import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Model

@MainActor
final class OnboardingModel: ObservableObject {
    struct PlayerRow: Identifiable {
        let player: MediaPlayer
        var permission: MediaPlayer.Permission
        var id: String { player.bundleID }
    }

    @Published var accessibility = Permissions.accessibility
    @Published var screenRecording = Permissions.screenRecording
    /// Uživatel klikl na „Povolit“ u nahrávání obrazovky – macOS pak chce restart aplikace.
    @Published var screenRequested = false
    @Published var players: [PlayerRow] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var theme = PreviewTheme.current
    @Published var loginError: String?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var requiredDone: Bool { accessibility && screenRecording }

    func refresh() {
        accessibility = Permissions.accessibility
        screenRecording = Permissions.screenRecording
        let installed = MediaPlayer.supported.filter(\.isInstalled)
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = installed.map { PlayerRow(player: $0, permission: $0.automationPermission(ask: false)) }
            DispatchQueue.main.async { self.players = rows }
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            Permissions.openSettings("Privacy_Accessibility")
        }
    }

    func requestScreenRecording() {
        screenRequested = true
        // CGRequestScreenCaptureAccess() vrací false i ve chvíli, kdy dotaz právě ukázal,
        // a dotaz ukáže jen jednou. Poprvé tedy jen dotaz, při dalším kliknutí Nastavení.
        let key = "screenCaptureRequested"
        if UserDefaults.standard.bool(forKey: key) {
            Permissions.openSettings("Privacy_ScreenCapture")
        } else {
            UserDefaults.standard.set(true, forKey: key)
            CGRequestScreenCaptureAccess()
        }
    }

    func requestAutomation(_ player: MediaPlayer) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty {
            // Povolení jde vyžádat jen u běžící aplikace – spusť ji na pozadí.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        _ = player.automationPermission(ask: true)
                        DispatchQueue.main.async { self.refresh() }
                    }
                }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = player.automationPermission(ask: true)
            DispatchQueue.main.async {
                if result == .denied { Permissions.openSettings("Privacy_Automation") }
                self.refresh()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setTheme(_ theme: PreviewTheme) {
        PreviewTheme.current = theme
        self.theme = theme
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Cesta jako samostatný argument – žádné skládání shellového příkazu z textu.
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$1\"", "sh", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Views

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.bottom, 22)

            VStack(spacing: 10) {
                SectionTitle("Potřebná oprávnění")
                accessibilityRow
                screenRecordingRow
                if !model.players.isEmpty {
                    SectionTitle("Ovládání přehrávačů (volitelné)")
                        .padding(.top, 8)
                    ForEach(model.players) { row in playerRow(row) }
                }

                SectionTitle("Předvolby").padding(.top, 8)
                preferences
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 18)
            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityRow: some View {
        PermissionRow(
            symbol: "hand.point.up.left.fill", tint: .blue,
            title: "Zpřístupnění",
            detail: "Pozná, nad kterou ikonou v Docku je myš, a umí přepnout na vybrané okno.",
            granted: model.accessibility,
            action: { model.requestAccessibility() })
    }

    private var screenRecordingRow: some View {
        let waiting = model.screenRequested && !model.screenRecording
        let restart: (String, () -> Void)? = waiting ? ("Restartovat DockPeek", { OnboardingModel.relaunch() }) : nil
        return PermissionRow(
            symbol: "rectangle.dashed.badge.record", tint: .purple,
            title: "Nahrávání obrazovky",
            detail: "Vytváří náhledy oken. Snímky zůstávají jen v paměti a nikam se neodesílají.",
            granted: model.screenRecording,
            action: { model.requestScreenRecording() },
            note: waiting ? "Po zapnutí v Nastavení je potřeba DockPeek restartovat." : nil,
            extraButton: restart)
    }

    private func playerRow(_ row: OnboardingModel.PlayerRow) -> some View {
        let tint: Color = row.player.bundleID == "com.spotify.client" ? .green : .pink
        return PermissionRow(
            symbol: "music.note", tint: tint,
            title: row.player.name,
            detail: playerDetail(row.permission),
            granted: row.permission == .granted,
            denied: row.permission == .denied,
            action: { model.requestAutomation(row.player) })
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Text("Vítejte v DockPeek")
                .font(.system(size: 22, weight: .bold))
            Text("Najeďte myší na aplikaci v Docku a uvidíte náhledy všech jejích oken.\nNež začnete, povolte prosím pár věcí.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spouštět DockPeek po přihlášení")
                Spacer()
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if let error = model.loginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Vzhled náhledů")
                Picker("", selection: Binding(get: { model.theme }, set: { model.setTheme($0) })) {
                    ForEach(PreviewTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var footer: some View {
        HStack {
            if !model.requiredDone {
                Label("Bez potřebných oprávnění DockPeek nebude fungovat.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else {
                Label("Vše připraveno – vyzkoušejte to v Docku.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
            Spacer()
            Button(model.requiredDone ? "Hotovo" : "Dokončit později", action: onFinish)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private func playerDetail(_ permission: MediaPlayer.Permission) -> String {
        switch permission {
        case .denied: "Zamítnuto – povolte v Nastavení › Soukromí › Automatizace."
        case .notRunning: "Ovládání přehrávání přímo z náhledu. Pro povolení se aplikace na chvíli spustí."
        default: "Ovládání přehrávání (play/pauza, další skladba) přímo z náhledu."
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let granted: Bool
    var denied = false
    let action: () -> Void
    var note: String? = nil
    var extraButton: (String, () -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tint.gradient)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)

            if granted {
                Label("Povoleno", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else if let extraButton {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Otevřít Nastavení", action: action).controlSize(.small)
                    Button(extraButton.0, action: extraButton.1)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button(denied ? "Otevřít Nastavení" : "Povolit", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Window

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    private var model: OnboardingModel?
    var onClose: (() -> Void)?

    static var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: doneKey) || !Permissions.accessibility || !Permissions.screenRecording
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "DockPeek – průvodce nastavením"
        self.init(window: window)
        window.delegate = self

        let model = OnboardingModel()
        self.model = model
        let view = OnboardingView(model: model) { [weak self] in self?.finish() }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
    }

    func present() {
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
