import AppKit
import ScreenCaptureKit

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func openSettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var dockObserver: DockObserver?
    private let controller = PreviewController()
    private var retryTimer: Timer?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--dump") {
            Task { await Diagnostics.dump(); NSApp.terminate(nil) }
            return
        }
        setupStatusItem()
        if OnboardingWindowController.needsOnboarding || CommandLine.arguments.contains("--onboarding") {
            showOnboarding()
        }
        if CommandLine.arguments.contains("--about") { showAbout() }
        startObservingDock()

        // Když se Dock restartuje (killall Dock, změna nastavení), napoj se znovu.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" {
                self?.controller.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.startObservingDock() }
            }
        }
    }

    /// Zkouší se napojit na Dock, dokud uživatel nepovolí Zpřístupnění.
    private func startObservingDock() {
        retryTimer?.invalidate()
        if tryStart() { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] t in
            if self?.tryStart() == true { t.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func tryStart() -> Bool {
        guard Permissions.accessibility else { return false }
        let observer = DockObserver { [weak self] item in self?.controller.dockHoverChanged(item) }
        guard observer.start() else { return false }
        dockObserver = observer
        controller.dockObserver = observer
        return true
    }

    @objc func showAbout() {
        AboutWindowController.shared.present()
    }

    @objc func showOnboarding() {
        if onboarding == nil {
            let controller = OnboardingWindowController()
            controller.onClose = { [weak self] in self?.onboarding = nil }
            onboarding = controller
        }
        onboarding?.present()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "DockPeek", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let about = NSMenuItem(title: "O aplikaci DockPeek", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let ax = NSMenuItem(title: "Zpřístupnění: \(Permissions.accessibility ? "povoleno ✓" : "chybí – klikni a povol")",
                            action: #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)

        let sr = NSMenuItem(title: "Nahrávání obrazovky: \(Permissions.screenRecording ? "povoleno ✓" : "chybí – klikni a povol")",
                            action: #selector(openScreenRecording), keyEquivalent: "")
        sr.target = self
        menu.addItem(sr)

        let dock = NSMenuItem(title: "Dock: \(dockObserver?.isRunning == true ? "sleduji ✓" : "nepřipojeno")",
                              action: nil, keyEquivalent: "")
        dock.isEnabled = false
        menu.addItem(dock)

        let guide = NSMenuItem(title: "Průvodce nastavením…", action: #selector(showOnboarding), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        menu.addItem(.separator())
        let themeItem = NSMenuItem(title: "Vzhled náhledů", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in PreviewTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = theme == PreviewTheme.current ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Ukončit DockPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let theme = PreviewTheme(rawValue: raw) {
            PreviewTheme.current = theme
        }
    }

    @objc private func openAccessibility() { Permissions.openSettings("Privacy_Accessibility") }
    @objc private func openScreenRecording() { Permissions.openSettings("Privacy_ScreenCapture") }
}

/// `open build/DockPeek.app --args --dump` → vypíše stav do /tmp/dockpeek-dump.txt
enum Diagnostics {
    static func dump() async {
        var out = "Zpřístupnění: \(Permissions.accessibility), Nahrávání obrazovky: \(Permissions.screenRecording)\n"
        let observer = DockObserver { _ in }
        out += "Dock připojen: \(observer.start())\n\nPoložky Docku:\n"
        for item in observer.allItems() {
            let app = item.runningApp
            out += "- \(item.title) app=\(item.isApplication) běží=\(app != nil) frame=\(item.frame)\n"
            if let app, item.isApplication {
                let windows = WindowProvider.windows(for: app)
                for w in windows {
                    out += "    okno id=\(w.id.map(String.init) ?? "?") min=\(w.isMinimized) size=\(w.size) '\(w.title)'\n"
                }
                let images = await Thumbnailer.capture(ids: windows.compactMap(\.id))
                if !windows.isEmpty { out += "    snímků: \(images.count)/\(windows.count)\n" }
            }
        }
        try? out.write(toFile: "/tmp/dockpeek-dump.txt", atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
