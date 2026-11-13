import AppKit

/// Vzhled panelu s náhledy (uložený v UserDefaults).
enum PreviewTheme: String, CaseIterable {
    case system, app, light, dark

    var title: String {
        switch self {
        case .system: "Podle systému"
        case .app: "Podle aplikace"
        case .light: "Světlý"
        case .dark: "Tmavý"
        }
    }

    /// Pevný vzhled; u `.app` se rozhoduje až podle snímků oken (viz PreviewController).
    var appearance: NSAppearance? {
        switch self {
        case .system, .app: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: PreviewTheme {
        get { UserDefaults.standard.string(forKey: "previewTheme").flatMap(PreviewTheme.init) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "previewTheme") }
    }
}

/// Odhad, zda je aplikace „tmavá“, podle průměrného jasu snímků jejích oken.
enum AppTone {
    /// Průměrný relativní jas obrázku (0 = černá, 1 = bílá).
    static func luminance(of image: CGImage) -> CGFloat {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.2126 * CGFloat(pixels[i]) + 0.7152 * CGFloat(pixels[i + 1]) + 0.0722 * CGFloat(pixels[i + 2])
        }
        return sum / CGFloat(side * side) / 255
    }

    /// nil = nemáme z čeho rozhodnout.
    static func isDark(_ images: [CGImage]) -> Bool? {
        guard !images.isEmpty else { return nil }
        let avg = images.map(luminance).reduce(0, +) / CGFloat(images.count)
        return avg < 0.45
    }

    static func appearance(isDark: Bool) -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

/// Zjistí, jestli má Dock otevřenou kontextovou nabídku (okno na úrovni pop-up menu).
/// Funguje bez ohledu na to, čím byla otevřena (pravé tlačítko, Ctrl+klik, podržení).
enum DockMenu {
    /// Na macOS 26 nabídku Docku kreslí samostatný proces „DockHelper“, dříve přímo Dock.
    private static let owners: Set<String> = ["Dock", "DockHelper"]

    static func isOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains {
            ($0[kCGWindowLayer as String] as? Int) == menuLevel
                && owners.contains($0[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}

/// Plovoucí panel, který nikdy nebere fokus aktivní aplikaci.
final class PreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu          // nad Dockem
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Jeden náhled okna: titulek nahoře, snímek pod ním, křížek pro zavření při najetí.
final class ThumbnailView: HoverView {
    static let titleHeight: CGFloat = 16
    static let inset: CGFloat = 6

    let info: WindowInfo
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeView = NSImageView()
    private let fallbackIcon: NSImage?

    init(frame: NSRect, info: WindowInfo, image: CGImage?, title: String, fallbackIcon: NSImage?) {
        self.info = info
        self.fallbackIcon = fallbackIcon
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8

        let inset = Self.inset, titleH = Self.titleHeight
        label.stringValue = title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: inset, y: frame.height - inset - titleH,
                             width: frame.width - 2 * inset - 18, height: titleH)

        imageView.frame = NSRect(x: inset, y: inset,
                                 width: frame.width - 2 * inset,
                                 height: frame.height - 3 * inset - titleH)
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        if info.isMinimized { imageView.alphaValue = 0.85 }

        closeView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Zavřít okno")
        closeView.contentTintColor = .secondaryLabelColor
        closeView.frame = NSRect(x: frame.width - inset - 16, y: frame.height - inset - titleH, width: 16, height: 16)
        closeView.isHidden = true

        addSubview(imageView)
        addSubview(label)
        addSubview(closeView)
        setImage(image)
        toolTip = title
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: CGImage?) {
        if let image {
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.image = NSImage(cgImage: image, size: .zero)
        } else {
            imageView.imageScaling = .scaleProportionallyDown
            imageView.image = fallbackIcon
        }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if !closeView.isHidden, closeView.frame.insetBy(dx: -4, dy: -4).contains(point) {
            onClose?()
        } else {
            onClick?()
        }
    }

    override func hoverChanged() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isHovering ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
        }
        closeView.isHidden = !isHovering
    }
}

/// Obsah panelu – rozmístí náhledy do řádky.
final class PreviewContentView: NSVisualEffectView {
    private(set) var thumbnails: [ThumbnailView] = []
    private(set) var mediaBar: MediaBarView?
    private let tint = NSView()

    static let padding: CGFloat = 8
    static let spacing: CGFloat = 6
    static let preferredImageHeight: CGFloat = 130
    static let cornerRadius: CGFloat = 12

    /// Roztažitelná maska se zaoblenými rohy pro NSVisualEffectView.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    init(windows: [WindowInfo],
         images: [CGWindowID: CGImage],
         appName: String,
         icon: NSImage?,
         maxWidth: CGFloat,
         media: MediaInfo? = nil,
         onMedia: ((MediaCommand) -> Void)? = nil,
         onClick: @escaping (WindowInfo) -> Void,
         onClose: @escaping (WindowInfo) -> Void) {
        let pad = Self.padding, spacing = Self.spacing, inset = ThumbnailView.inset
        let n = CGFloat(windows.count)

        func imageWidths(_ height: CGFloat) -> [CGFloat] {
            windows.map { min(max(height * $0.aspect, height * 0.75), height * 2.2) }
        }

        var imageHeight = Self.preferredImageHeight
        var widths = imageWidths(imageHeight)
        let chrome = 2 * pad + spacing * max(0, n - 1) + 2 * inset * n
        let total = widths.reduce(0, +) + chrome
        if n > 0, total > maxWidth {
            imageHeight *= max(0.25, (maxWidth - chrome) / widths.reduce(0, +))
            widths = imageWidths(imageHeight)
        }
        let thumbHeight = n > 0 ? imageHeight + 3 * inset + ThumbnailView.titleHeight : 0
        let thumbsWidth = widths.reduce(0, +) + chrome - 2 * pad
        let mediaHeight = media.map(MediaBarView.height(for:)) ?? 0
        let contentWidth = max(thumbsWidth, media != nil ? 300 : 0)
        let gap = (n > 0 && media != nil) ? spacing : 0
        let size = NSSize(width: contentWidth + 2 * pad, height: thumbHeight + gap + mediaHeight + 2 * pad)

        super.init(frame: NSRect(origin: .zero, size: size))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        // Zaoblení musí jít přes maskImage – materiál „behindWindow“ ignoruje
        // cornerRadius vrstvy a jinak by v rozích prosvítal hranatý podklad okna.
        maskImage = Self.roundedMask(radius: Self.cornerRadius)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        // Tónovací vrstva – průsvitný materiál sám o sobě nad světlou plochou moc neztmavne.
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.cornerRadius = Self.cornerRadius
        tint.layer?.cornerCurve = .continuous
        addSubview(tint)
        updateColors()

        // Přehrávač dole (blíž k Docku), náhledy nad ním, vycentrované.
        if let media {
            let bar = MediaBarView(frame: NSRect(x: pad, y: pad, width: contentWidth, height: mediaHeight),
                                   info: media, onCommand: { onMedia?($0) })
            addSubview(bar)
            mediaBar = bar
        }
        let thumbsY = pad + mediaHeight + gap
        var x = pad + (contentWidth - thumbsWidth) / 2
        for (window, imageWidth) in zip(windows, widths) {
            let frame = NSRect(x: x, y: thumbsY, width: imageWidth + 2 * inset, height: thumbHeight)
            let title = window.title.isEmpty ? appName : window.title
            let thumb = ThumbnailView(frame: frame,
                                      info: window,
                                      image: window.id.flatMap { images[$0] },
                                      title: title,
                                      fallbackIcon: icon)
            thumb.onClick = { onClick(window) }
            thumb.onClose = { onClose(window) }
            addSubview(thumb)
            thumbnails.append(thumb)
            x += frame.width + spacing
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        tint.layer?.backgroundColor = isDark
            ? NSColor(white: 0.08, alpha: 0.72).cgColor
            : NSColor(white: 1.0, alpha: 0.45).cgColor
        layer?.borderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.18).cgColor
            : NSColor(white: 0.0, alpha: 0.12).cgColor
    }

    func update(images: [CGWindowID: CGImage]) {
        for thumb in thumbnails {
            if let id = thumb.info.id, let image = images[id] { thumb.setImage(image) }
        }
    }
}

/// Řídí, kdy a kde se panel ukáže a kdy zmizí.
final class PreviewController {
    weak var dockObserver: DockObserver?

    private let panel = PreviewPanel()
    private var content: PreviewContentView?
    private var currentItem: DockItem?
    private var currentApp: NSRunningApplication?
    private var currentWindows: [WindowInfo] = []
    private var currentMedia: MediaInfo?
    private var mediaCache: [String: MediaInfo] = [:]
    private var trackingTicks = 0
    /// Nad touto ikonou uživatel otevřel nabídku – dokud z ní myš neodjede, panel neukazuj.
    private var suppressedItem: DockItem?
    private var imageCache: [CGWindowID: CGImage] = [:]
    /// Naposledy zjištěný tón aplikace (bundle ID → tmavá?), aby panel neblikal při dalším najetí.
    private var appTone: [String: Bool] = [:]
    private var pendingShow: DispatchWorkItem?
    private var trackingTimer: Timer?
    private var generation = 0
    /// Od kdy je myš mimo panel i bezpečnou zónu (krátké vyjetí se toleruje).
    private var outsideSince: Date?
    /// Jak dlouho smí být myš mimo, než panel zmizí.
    private let outsideGrace: TimeInterval = 0.3
    /// Prodleva přepnutí na sousední ikonu, když myš míří k panelu (bezpečná zóna).
    /// Přepne se jen tehdy, když se myš na sousední ikoně opravdu zastaví.
    private let switchDelayInZone: TimeInterval = 0.25
    /// Prodleva přepnutí mimo zónu – i tady jen při zastavení, ne při průjezdu.
    private let switchDelay: TimeInterval = 0.12

    /// Prodleva před prvním zobrazením (aby panel neblikal při přejíždění přes Dock).
    var showDelay: TimeInterval = 0.18

    func dockHoverChanged(_ item: DockItem?) {
        pendingShow?.cancel()

        if let suppressed = suppressedItem {
            if item == suppressed { return }
            suppressedItem = nil      // myš odjela jinam – znovu normálně
        }
        guard let item else { return }  // myš opustila Dock – rozhodne trackingTimer
        // Spodní okraj panelu leží nad zvětšenými ikonami Docku a Dock o panelu neví –
        // dál hlásí najetí na ikonu pod ním. Dokud je myš v panelu, nic nepřepínej.
        if isMouseInPanel { return }
        // Myš cestou k panelu šikmo přejíždí přes sousední ikony – v bezpečné zóně
        // nereaguj hned, jinak by panel přeskočil na jinou aplikaci nebo zmizel.
        let inZone = panel.isVisible && isInSafeZone(NSEvent.mouseLocation)
        guard item.isApplication, let app = item.runningApp else {
            // složka, koš, neběžící aplikace…
            if panel.isVisible && !inZone { hide() }
            return
        }
        if panel.isVisible, item == currentItem { return }

        let delay = panel.isVisible ? (inZone ? switchDelayInZone : switchDelay) : showDelay
        let work = DispatchWorkItem { [weak self] in
            self?.pendingShow = nil
            self?.show(item: item, app: app)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(item: DockItem, app: NSRunningApplication) {
        // Pokud mezitím myš odjela jinam, nic neukazuj.
        guard let now = dockObserver?.currentItem(), now == item else { return }
        if DockMenu.isOpen() { suppressedItem = item; return }
        if item != currentItem, isMouseInPanel { return }

        let windows = WindowProvider.windows(for: app)
        let player = MediaPlayer.forApp(app)
        Log.write("Zobrazuji \(app.localizedName ?? "?"): \(windows.count) oken\(player != nil ? ", přehrávač" : "")")
        guard !windows.isEmpty || player != nil else { hide(); return }

        generation += 1
        let gen = generation
        currentItem = item
        currentApp = app
        currentWindows = windows
        currentMedia = player.flatMap { mediaCache[$0.bundleID] }
        panel.appearance = initialAppearance(for: app, windows: windows)

        // Bez oken a bez známé skladby počkej na odpověď přehrávače.
        if !windows.isEmpty || currentMedia != nil { render() }

        if !windows.isEmpty {
            let ids = windows.compactMap(\.id)
            Task { @MainActor [weak self] in
                let images = await Thumbnailer.capture(ids: ids)
                guard let self, gen == self.generation else { return }
                // Cache drž jen pro okna, která ještě existují (jinak by rostla donekonečna).
                if self.imageCache.count > 60 {
                    let live = Set(self.currentWindows.compactMap(\.id))
                    self.imageCache = self.imageCache.filter { live.contains($0.key) }
                }
                self.imageCache.merge(images) { $1 }
                self.content?.update(images: images)
                self.applyAppTone(app: app, images: Array(images.values))
            }
        }
        if let player { refreshMedia(player, generation: gen) }
    }

    /// Zjistí, co hraje, a pokud se něco změnilo, překreslí panel.
    private func refreshMedia(_ player: MediaPlayer, generation gen: Int) {
        player.fetch { [weak self] info in
            Log.write("Přehrávač \(player.bundleID): \(info.map { "\($0.isPlaying ? "hraje" : "pauza") \($0.title) – \($0.artist), obal: \($0.artwork != nil)" } ?? "nic")")
            guard let self, gen == self.generation else { return }
            if let info { self.mediaCache[player.bundleID] = info } else { self.mediaCache[player.bundleID] = nil }
            if let info, info == self.currentMedia, self.panel.isVisible {
                // Mění se jen pozice – posuň posuvník bez překreslení panelu.
                self.currentMedia = info
                self.content?.mediaBar?.sync(with: info)
                return
            }
            if info == nil, self.currentMedia == nil, self.panel.isVisible { return }
            self.currentMedia = info
            if self.currentWindows.isEmpty && info == nil { self.hide(); return }
            // Panel jen s přehrávačem ukaž, jen pokud je myš pořád u ikony.
            if !self.panel.isVisible, let item = self.currentItem,
               self.dockObserver?.currentItem() != item { return }
            self.render()
        }
    }

    /// Postaví obsah panelu z aktuálního stavu (okna + přehrávač) a ukáže ho.
    private func render() {
        guard let item = currentItem, let app = currentApp else { return }
        let player = MediaPlayer.forApp(app)
        let screen = Geometry.screen(containing: item.frame) ?? NSScreen.main!
        let view = PreviewContentView(
            windows: currentWindows,
            images: imageCache,
            appName: app.localizedName ?? "",
            icon: app.icon,
            maxWidth: screen.visibleFrame.width - 40,
            media: currentMedia,
            onMedia: { [weak self] command in
                guard let self, let player else { return }
                let gen = self.generation
                // Okamžitá odezva tlačítka play/pause, skutečný stav se dočte vzápětí.
                if command == .playPause, var media = self.currentMedia {
                    media.isPlaying.toggle()
                    self.currentMedia = media
                    self.content?.mediaBar?.sync(with: media)
                }
                player.send(command) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.refreshMedia(player, generation: gen)
                    }
                }
            },
            onClick: { [weak self] window in
                WindowActivator.focus(window, of: app)
                self?.hide()
            },
            onClose: { [weak self] window in
                WindowActivator.close(window)
                // Chvilku počkej, než aplikace okno opravdu zavře, a překresli.
                // Myš je teď v panelu (ne v Docku), proto jen znovu načti okna – show() by
                // vyžadovalo najetí na ikonu a panel by zůstal viset se zastaralým obsahem.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard let self, self.currentItem == item else { return }
                    self.reloadWindows()
                }
            })
        content = view
        // Velikost zjisti předem – přiřazení contentView zmenší view na (zatím nulový) rámec okna.
        let size = view.frame.size
        panel.setFrame(frameFor(size: size, item: item.frame, screen: screen), display: false)
        panel.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        startTracking()
    }

    /// Znovu načte okna aktuální aplikace (po zavření okna z panelu).
    private func reloadWindows() {
        guard let app = currentApp else { return }
        currentWindows = WindowProvider.windows(for: app)
        if currentWindows.isEmpty && currentMedia == nil { hide(); return }
        render()
    }

    private func initialAppearance(for app: NSRunningApplication, windows: [WindowInfo]) -> NSAppearance? {
        let theme = PreviewTheme.current
        guard theme == .app else { return theme.appearance }
        if let key = app.bundleIdentifier, let dark = appTone[key] {
            return AppTone.appearance(isDark: dark)
        }
        let cached = windows.compactMap { $0.id.flatMap { imageCache[$0] } }
        return AppTone.isDark(cached).flatMap(AppTone.appearance) // nic v cache → zatím podle systému
    }

    private func applyAppTone(app: NSRunningApplication, images: [CGImage]) {
        guard PreviewTheme.current == .app, let dark = AppTone.isDark(images) else { return }
        if let key = app.bundleIdentifier { appTone[key] = dark }
        let appearance = AppTone.appearance(isDark: dark)
        if panel.appearance?.name != appearance?.name {
            panel.appearance = appearance
        }
        Log.write("Tón \(app.localizedName ?? "?"): \(dark ? "tmavý" : "světlý")")
    }

    func hide() {
        pendingShow?.cancel()
        generation += 1
        trackingTimer?.invalidate()
        trackingTimer = nil
        currentItem = nil
        currentApp = nil
        currentWindows = []
        currentMedia = nil
        trackingTicks = 0
        outsideSince = nil
        panel.orderOut(nil)
    }

    // MARK: - Pozice

    private enum DockEdge { case bottom, left, right }

    private func edge(of item: CGRect, on screen: NSScreen) -> DockEdge {
        let s = screen.frame
        let bottom = item.minY - s.minY
        let left = item.minX - s.minX
        let right = s.maxX - item.maxX
        if bottom <= left && bottom <= right { return .bottom }
        return left < right ? .left : .right
    }

    private func frameFor(size: NSSize, item: CGRect, screen: NSScreen) -> NSRect {
        // Záporná mezera: panel zasáhne do průhledného okraje rámečku ikony a zakryje
        // tak celý systémový popisek s názvem aplikace (Dock ho kreslí těsně nad ikonou
        // a z jiné aplikace ho skrýt nejde).
        let gap: CGFloat = -4
        let visible = screen.visibleFrame
        var origin: NSPoint
        switch edge(of: item, on: screen) {
        case .bottom:
            origin = NSPoint(x: item.midX - size.width / 2, y: item.maxY + gap)
        case .left:
            origin = NSPoint(x: item.maxX + gap, y: item.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: item.minX - gap - size.width, y: item.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.frame.minY), visible.maxY - size.height - 8)
        return NSRect(origin: origin, size: size)
    }

    // MARK: - Skrývání

    private func startTracking() {
        guard trackingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkMouse() }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func checkMouse() {
        guard panel.isVisible, let item = currentItem else { return }
        // Během tažení posuvníkem panel nikdy neschovávej (myš může vyjet mimo).
        if content?.mediaBar?.isScrubbing == true { return }
        if DockMenu.isOpen() {
            Log.write("Dock: otevřená nabídka – skrývám panel")
            suppressedItem = item
            hide()
            return
        }
        // Každé ~2 s obnov přehrávač (skladba mohla skončit sama).
        trackingTicks += 1
        if trackingTicks % 20 == 0, let app = currentApp, let player = MediaPlayer.forApp(app) {
            refreshMedia(player, generation: generation)
        }
        let mouse = NSEvent.mouseLocation
        // Myš sjela z panelu rovnou na jinou ikonu: Dock ji hlásil už dřív (když byla myš
        // v panelu a hlášení se ignorovalo) a znovu ji neohlásí – naplánuj přepnutí sám.
        if pendingShow == nil, !isMouseInPanel, let hovered = dockObserver?.currentItem(),
           hovered.isApplication, hovered != item {
            dockHoverChanged(hovered)
        }
        if panel.frame.insetBy(dx: -8, dy: -8).contains(mouse) || isInSafeZone(mouse) {
            outsideSince = nil
            return
        }
        // Myš je nad jinou aplikací v Docku – přepnutí řeší dockHoverChanged.
        if let hovered = dockObserver?.currentItem(), hovered.isApplication {
            outsideSince = nil
            return
        }
        // Krátké vyjetí mimo (nepřesný šikmý pohyb) ještě panel neschová.
        let since = outsideSince ?? Date()
        outsideSince = since
        if Date().timeIntervalSince(since) >= outsideGrace { hide() }
    }

    private var isMouseInPanel: Bool {
        panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    /// Je bod v panelu nebo v bezpečné zóně mezi ikonou a panelem?
    private func isInSafeZone(_ point: CGPoint) -> Bool {
        guard let item = currentItem else { return false }
        return item.frame.contains(point) || safeZone(item: item.frame).contains(point)
    }

    /// Bezpečná zóna, přes kterou myš přejíždí od ikony do panelu: celý pás mezi
    /// panelem a okrajem obrazovky v šířce panelu. Pokrývá šikmý i obloukový pohyb
    /// ke krajním náhledům, i když myš cestou přejede po Docku přes sousední ikony.
    /// Strana Docku se určuje stejně jako při umísťování panelu – panel ikonu
    /// mírně překrývá, takže ji nejde odvodit z jejich vzájemné polohy.
    private func safeZone(item: CGRect) -> CGPath {
        let p = panel.frame
        let slack: CGFloat = 48
        guard let screen = Geometry.screen(containing: item) else { return CGMutablePath() }
        let s = screen.frame
        let rect: CGRect
        switch edge(of: item, on: screen) {
        case .bottom:
            let x0 = min(p.minX, item.minX) - slack, x1 = max(p.maxX, item.maxX) + slack
            rect = CGRect(x: x0, y: s.minY, width: x1 - x0, height: p.minY - s.minY + 2)
        case .left:
            let y0 = min(p.minY, item.minY) - slack, y1 = max(p.maxY, item.maxY) + slack
            rect = CGRect(x: s.minX, y: y0, width: p.minX - s.minX + 2, height: y1 - y0)
        case .right:
            let y0 = min(p.minY, item.minY) - slack, y1 = max(p.maxY, item.maxY) + slack
            rect = CGRect(x: p.maxX - 2, y: y0, width: s.maxX - p.maxX + 2, height: y1 - y0)
        }
        return CGPath(rect: rect, transform: nil)
    }
}
