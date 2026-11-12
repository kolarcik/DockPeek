import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowInfo {
    let element: AXUIElement
    let id: CGWindowID?
    let title: String
    let isMinimized: Bool
    let size: CGSize

    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 1.6 }
}

enum WindowProvider {
    /// Okna aplikace z Accessibility API (včetně minimalizovaných, v aktuální ploše).
    static func windows(for app: NSRunningApplication) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Zamrzlá aplikace nesmí zablokovat celé DockPeek.
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        let elements: [AXUIElement] = axApp.attr(kAXWindowsAttribute) ?? []
        return elements.compactMap { window in
            let subrole = window.subrole
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            let size = window.size ?? .zero
            guard size.width >= 60, size.height >= 40 else { return nil }
            let minimized: Bool = window.attr(kAXMinimizedAttribute) ?? false
            return WindowInfo(element: window,
                              id: window.windowID,
                              title: window.title ?? "",
                              isMinimized: minimized,
                              size: size)
        }
    }
}

enum WindowActivator {
    static func focus(_ window: WindowInfo, of app: NSRunningApplication) {
        if window.isMinimized {
            window.element.set(kAXMinimizedAttribute, false as CFBoolean)
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        axApp.set(kAXFrontmostAttribute, true as CFBoolean)
        window.element.set(kAXMainAttribute, true as CFBoolean)
        window.element.perform(kAXRaiseAction)
        app.activate()
        // Některé aplikace (Electron, Java) potřebují raise ještě jednou až po aktivaci.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.element.perform(kAXRaiseAction)
        }
    }

    static func close(_ window: WindowInfo) {
        window.element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
    }
}

enum Thumbnailer {
    /// Nejdelší strana náhledu v pixelech.
    static let maxPixelSize: CGFloat = 640

    static func capture(ids: [CGWindowID]) async -> [CGWindowID: CGImage] {
        // Bez CGPreflightScreenCaptureAccess(): na macOS 15+ umí vracet false,
        // i když ScreenCaptureKit snímat smí. Chybějící oprávnění ohlásí SCK chybou.
        guard !ids.isEmpty else { return [:] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Log.write("SCShareableContent selhal: \(error)")
            return [:]
        }
        let windows = ids.compactMap { id in content.windows.first { $0.windowID == id } }

        return await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for window in windows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let pointSize = window.frame.size
                    let pixelScale = CGFloat(filter.pointPixelScale)
                    let scale = min(pixelScale, maxPixelSize / max(pointSize.width, pointSize.height, 1))
                    config.width = max(1, Int(pointSize.width * scale))
                    config.height = max(1, Int(pointSize.height * scale))
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    do {
                        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        return (window.windowID, image)
                    } catch {
                        Log.write("Snímek okna \(window.windowID) selhal: \(error)")
                        return (window.windowID, nil)
                    }
                }
            }
            var result: [CGWindowID: CGImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }
    }
}
