import AppKit
import ApplicationServices

/// Jedna ikona v Docku.
struct DockItem: Equatable {
    let element: AXUIElement
    let title: String
    let bundleURL: URL?
    let isApplication: Bool
    /// Rámec ikony v Cocoa souřadnicích.
    let frame: CGRect

    init?(_ element: AXUIElement) {
        guard let axFrame = element.frame else { return nil }
        self.element = element
        self.title = element.title ?? ""
        self.bundleURL = element.attr("AXURL") as URL?
        self.isApplication = element.subrole == "AXApplicationDockItem"
        self.frame = Geometry.cocoa(fromAX: axFrame)
    }

    static func == (lhs: DockItem, rhs: DockItem) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    /// Běžící aplikace, které ikona patří (nil = aplikace neběží).
    var runningApp: NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let path = bundleURL?.resolvingSymlinksInPath().path {
            if let app = apps.first(where: { $0.bundleURL?.resolvingSymlinksInPath().path == path }) {
                return app
            }
        }
        return apps.first { $0.activationPolicy == .regular && $0.localizedName == title }
    }
}

/// Hlídá, nad kterou ikonou Docku je myš.
///
/// Dock při najetí myší „vybere“ položku ve svém AXListu a pošle notifikaci
/// kAXSelectedChildrenChangedNotification – na tu se tu přihlašujeme.
final class DockObserver {
    private var observer: AXObserver?
    private var list: AXUIElement?
    private let onChange: (DockItem?) -> Void

    init(onChange: @escaping (DockItem?) -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        stop()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            Log.write("Dock neběží")
            return false
        }
        let pid = dock.processIdentifier
        let dockApp = AXUIElementCreateApplication(pid)
        guard let list = dockApp.children.first(where: { $0.role == kAXListRole }) else {
            Log.write("V Docku jsem nenašel AXList (chybí oprávnění Zpřístupnění?)")
            return false
        }

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<DockObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.selectionChanged()
        }
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else {
            Log.write("AXObserverCreate selhal")
            return false
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(newObserver, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard err == .success else {
            Log.write("AXObserverAddNotification selhal: \(err.rawValue)")
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        self.observer = newObserver
        self.list = list
        Log.write("Sleduji Dock (pid \(pid))")
        return true
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        list = nil
    }

    var isRunning: Bool { observer != nil }

    /// Položka, nad kterou je právě myš (nebo nil).
    func currentItem() -> DockItem? {
        guard let list,
              let selected: [AXUIElement] = list.attr(kAXSelectedChildrenAttribute),
              let first = selected.first else { return nil }
        return DockItem(first)
    }

    /// Všechny položky Docku (pro diagnostiku).
    func allItems() -> [DockItem] {
        list?.children.compactMap(DockItem.init) ?? []
    }

    private func selectionChanged() {
        let item = currentItem()
        Log.write("Dock hover: \(item.map { "\($0.title) app=\($0.isApplication) frame=\($0.frame)" } ?? "nic")")
        onChange(item)
    }
}
