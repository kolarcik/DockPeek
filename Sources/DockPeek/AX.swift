import AppKit
import ApplicationServices

/// Privátní (ale široce používané) API: vrátí CGWindowID pro AX okno.
/// Bez něj nejde spárovat AX okno (to umíme aktivovat) se snímkem ze ScreenCaptureKit.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func attr<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    func element(_ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    var children: [AXUIElement] { attr(kAXChildrenAttribute) ?? [] }
    var role: String? { attr(kAXRoleAttribute) }
    var subrole: String? { attr(kAXSubroleAttribute) }
    var title: String? { attr(kAXTitleAttribute) }

    var position: CGPoint? {
        guard let value = axValue(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value = axValue(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Rámec v AX souřadnicích (počátek vlevo nahoře primární obrazovky).
    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(self, action as CFString)
    }

    private func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

enum Geometry {
    /// Výška primární obrazovky (té s menu barem) – podle ní se převádí AX ↔ Cocoa souřadnice.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cocoa(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}

enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/dockpeek.log")
    static var enabled = ProcessInfo.processInfo.environment["DOCKPEEK_LOG"] != nil
        || CommandLine.arguments.contains("--log")

    static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message())\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
