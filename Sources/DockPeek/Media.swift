import AppKit

/// Co právě hraje.
struct MediaInfo: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    /// Identifikace obalu (URL nebo ID skladby) – pro cache a porovnání.
    var artworkKey: String
    var artwork: NSImage?
    /// Pozice a délka skladby v sekundách (délka 0 = neznámá).
    var position: Double = 0
    var duration: Double = 0
    /// Kdy byla pozice změřena – mezi dotazy se dopočítává lokálně.
    var measuredAt = Date()

    /// Aktuální odhad pozice (při přehrávání plyne čas od posledního měření).
    var estimatedPosition: Double {
        let p = isPlaying ? position + Date().timeIntervalSince(measuredAt) : position
        return duration > 0 ? min(p, duration) : p
    }

    /// Porovnává jen to, co mění vzhled lišty – pozice se aktualizuje bez překreslení.
    static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
            && lhs.artworkKey == rhs.artworkKey && (lhs.artwork == nil) == (rhs.artwork == nil)
            && (lhs.duration > 0) == (rhs.duration > 0)
    }
}

enum MediaCommand: Equatable {
    case previous, playPause, next
    /// Posun na pozici v sekundách.
    case seek(Double)

    var appleScriptVerb: String {
        switch self {
        case .previous: "previous track"
        case .playPause: "playpause"
        case .next: "next track"
        case .seek(let seconds): String(format: "set player position to %.2f", seconds)
        }
    }
}

/// Přehrávač ovládaný přes AppleScript.
///
/// Systémové „Now Playing“ (privátní MediaRemote) je od macOS 15.4 pro běžné aplikace
/// zavřené, proto se mluví přímo s aplikacemi, které mají AppleScript slovník.
/// Při prvním použití se macOS zeptá na povolení „DockPeek chce ovládat Spotify“.
struct MediaPlayer {
    enum ArtworkSource { case url, rawData }

    let bundleID: String
    let name: String
    let artworkSource: ArtworkSource
    /// Spotify vrací délku skladby v milisekundách, Hudba v sekundách.
    let durationInMilliseconds: Bool

    static let supported: [MediaPlayer] = [
        MediaPlayer(bundleID: "com.spotify.client", name: "Spotify", artworkSource: .url, durationInMilliseconds: true),
        MediaPlayer(bundleID: "com.apple.Music", name: "Hudba", artworkSource: .rawData, durationInMilliseconds: false),
    ]

    enum Permission { case granted, denied, notDetermined, notRunning, notInstalled }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// Stav povolení „Automatizace“ pro tento přehrávač. S `ask: true` se macOS zeptá
    /// uživatele (blokuje – volat mimo hlavní vlákno). Přehrávač musí běžet.
    func automationPermission(ask: Bool) -> Permission {
        guard isInstalled else { return .notInstalled }
        var target = AEAddressDesc()
        let data = Array(bundleID.utf8)
        let created = data.withUnsafeBytes {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, data.count, &target)
        }
        guard created == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notDetermined
        }
    }

    static func forApp(_ app: NSRunningApplication) -> MediaPlayer? {
        supported.first { $0.bundleID == app.bundleIdentifier }
    }

    /// AppleScript běží mimo hlavní vlákno, ale vždy jen jeden najednou.
    private static let queue = DispatchQueue(label: "DockPeek.media")
    private static var artworkCache: [String: NSImage] = [:]   // jen na `queue`
    /// Stahování obalů běží zvlášť, aby pomalá síť nezdržovala play/pauza/posun.
    private static var artworkLoading: Set<String> = []          // jen na `queue`

    /// AppleScript `tell application id` by neběžící přehrávač spustil – proto vždy nejdřív ověř.
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    func fetch(completion: @escaping (MediaInfo?) -> Void) {
        Self.queue.async {
            let info = isRunning ? fetchSync() : nil
            DispatchQueue.main.async { completion(info) }
        }
    }

    func send(_ command: MediaCommand, completion: @escaping () -> Void) {
        Self.queue.async {
            if isRunning {
                _ = Self.run("tell application id \"\(bundleID)\" to \(command.appleScriptVerb)")
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func fetchSync() -> MediaInfo? {
        let artworkExpr = artworkSource == .url ? "(artwork url of t)" : "\"\""
        // Čísla jako celé milisekundy – desetinná čárka/tečka v textu závisí na jazyku systému.
        let durationExpr = durationInMilliseconds
            ? "(duration of t)"
            : "(round ((duration of t) * 1000) rounding down)"
        let source = """
        tell application id "\(bundleID)"
            set pState to player state as string
            if pState is "stopped" then return "stopped"
            set t to current track
            set posMs to round ((player position) * 1000) rounding down
            set durMs to \(durationExpr)
            return pState & linefeed & (name of t) & linefeed & (artist of t) & linefeed & \(artworkExpr) & linefeed & (id of t as string) & linefeed & (posMs as string) & linefeed & (durMs as string)
        end tell
        """
        let measuredAt = Date()
        guard let text = Self.run(source)?.stringValue, text != "stopped" else { return nil }
        let parts = text.components(separatedBy: "\n")
        guard parts.count >= 5 else { return nil }

        func seconds(_ index: Int) -> Double {
            guard parts.count > index, let ms = Double(parts[index]) else { return 0 }
            return ms / 1000
        }
        let artworkKey = parts[3].isEmpty ? parts[4] : parts[3]
        return MediaInfo(title: parts[1],
                         artist: parts[2],
                         isPlaying: parts[0] == "playing",
                         artworkKey: artworkKey,
                         artwork: artwork(key: artworkKey, url: parts[3]),
                         position: seconds(5),
                         duration: seconds(6),
                         measuredAt: measuredAt)
    }

    private func artwork(key: String, url: String) -> NSImage? {
        if let cached = Self.artworkCache[key] { return cached }
        var image: NSImage?
        switch artworkSource {
        case .url:
            // Stáhni na pozadí; obal se objeví při dalším obnovení (do ~2 s).
            guard let u = URL(string: url), !Self.artworkLoading.contains(key) else { return nil }
            Self.artworkLoading.insert(key)
            var request = URLRequest(url: u)
            request.timeoutInterval = 10
            URLSession.shared.dataTask(with: request) { data, _, _ in
                let downloaded = data.flatMap(NSImage.init(data:))
                Self.queue.async {
                    Self.artworkLoading.remove(key)
                    if let downloaded { Self.store(downloaded, key: key) }
                }
            }.resume()
            return nil
        case .rawData:
            let script = "tell application id \"\(bundleID)\" to get raw data of artwork 1 of current track"
            if let data = Self.run(script)?.data, !data.isEmpty { image = NSImage(data: data) }
        }
        if let image { Self.store(image, key: key) }
        return image
    }

    private static func store(_ image: NSImage, key: String) {
        if artworkCache.count > 50 { artworkCache.removeAll() }
        artworkCache[key] = image
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.write("AppleScript chyba: \(error[NSAppleScript.errorNumber] ?? "?") \(error[NSAppleScript.errorMessage] ?? "")")
            return nil
        }
        return result
    }
}

/// Malé tlačítko se SF Symbolem – funguje i v neaktivním panelu.
final class SymbolButton: HoverView {
    var onClick: (() -> Void)?
    private let imageView = NSImageView()
    private let pointSize: CGFloat

    init(frame: NSRect, symbol: String, pointSize: CGFloat, description: String) {
        self.pointSize = pointSize
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        imageView.frame = bounds
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        setSymbol(symbol, description: description)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ symbol: String, description: String) {
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        toolTip = description
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func hoverChanged() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isHovering ? NSColor.labelColor.withAlphaComponent(0.15).cgColor : nil
        }
    }
}

/// Tenký posuvník průběhu skladby (vlastní view – NSSlider v neaktivním panelu nereaguje na první klik).
final class ProgressScrubber: HoverView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    /// Během tažení (pro průběžné zobrazení času).
    var onScrub: ((CGFloat) -> Void)?
    /// Po puštění myši.
    var onSeek: ((CGFloat) -> Void)?
    private(set) var isDragging = false
    private let inset: CGFloat = 5

    override func hoverChanged() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let active = isHovering || isDragging
        let height: CGFloat = active ? 5 : 3
        let track = NSRect(x: inset, y: (bounds.height - height) / 2, width: bounds.width - 2 * inset, height: height)
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()

        var filled = track
        filled.size.width = track.width * fraction
        (active ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.75)).setFill()
        NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()

        if active {
            let knob: CGFloat = 11
            let rect = NSRect(x: filled.maxX - knob / 2, y: (bounds.height - knob) / 2, width: knob, height: knob)
            NSColor.white.setFill()
            let path = NSBezierPath(ovalIn: rect)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 2
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) { update(with: event) }

    override func mouseUp(with event: NSEvent) {
        update(with: event)
        isDragging = false
        needsDisplay = true
        onSeek?(fraction)
    }

    private func update(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        fraction = min(1, max(0, (x - inset) / max(1, bounds.width - 2 * inset)))
        onScrub?(fraction)
    }
}

/// Lišta přehrávače: obal, název, interpret, tlačítka a posuvník průběhu.
final class MediaBarView: NSView {
    static func height(for info: MediaInfo) -> CGFloat { info.duration > 0 ? 82 : 60 }

    private var info: MediaInfo
    private var scrubber: ProgressScrubber?
    private var playButton: SymbolButton?
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    /// Uživatel právě táhne posuvníkem (panel se nesmí schovat).
    var isScrubbing: Bool { scrubber?.isDragging == true }

    init(frame: NSRect, info: MediaInfo, onCommand: @escaping (MediaCommand) -> Void) {
        self.info = info
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8

        let hasProgress = info.duration > 0
        // Horní část (obal, texty, tlačítka) – 60 bodů; pod ní řádek s posuvníkem.
        let topY: CGFloat = hasProgress ? frame.height - 60 : 0
        let topHeight: CGFloat = 60

        let art = NSImageView(frame: NSRect(x: 8, y: topY + (topHeight - 44) / 2, width: 44, height: 44))
        art.wantsLayer = true
        art.layer?.cornerRadius = 6
        art.layer?.masksToBounds = true
        art.imageScaling = info.artwork != nil ? .scaleProportionallyUpOrDown : .scaleNone
        art.image = info.artwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
        art.contentTintColor = .secondaryLabelColor
        addSubview(art)

        // Tlačítka zprava doleva
        let size: CGFloat = 30
        let y = topY + (topHeight - size) / 2
        var x = frame.width - 8 - size
        let buttons: [(MediaCommand, String, String, CGFloat)] = [
            (.next, "forward.fill", "Další", 13),
            (.playPause, info.isPlaying ? "pause.fill" : "play.fill", info.isPlaying ? "Pozastavit" : "Přehrát", 16),
            (.previous, "backward.fill", "Předchozí", 13),
        ]
        for (command, symbol, description, pointSize) in buttons {
            let button = SymbolButton(frame: NSRect(x: x, y: y, width: size, height: size),
                                      symbol: symbol, pointSize: pointSize, description: description)
            button.onClick = { onCommand(command) }
            addSubview(button)
            if command == .playPause { playButton = button }
            x -= size + 2
        }

        let textX: CGFloat = 60
        let textWidth = max(40, x + size - 6 - textX)
        let title = NSTextField(labelWithString: info.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: textX, y: topY + topHeight / 2 + 1, width: textWidth, height: 16)
        addSubview(title)

        let artist = NSTextField(labelWithString: info.artist)
        artist.font = .systemFont(ofSize: 11)
        artist.textColor = .secondaryLabelColor
        artist.lineBreakMode = .byTruncatingTail
        artist.frame = NSRect(x: textX, y: topY + topHeight / 2 - 16, width: textWidth, height: 15)
        addSubview(artist)

        if hasProgress {
            let rowY: CGFloat = 6, rowH: CGFloat = 18, labelW: CGFloat = 40
            for (label, alignment) in [(elapsedLabel, NSTextAlignment.right), (remainingLabel, .left)] {
                label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                label.textColor = .secondaryLabelColor
                label.alignment = alignment
                addSubview(label)
            }
            elapsedLabel.frame = NSRect(x: 4, y: rowY + 2, width: labelW, height: 14)
            remainingLabel.frame = NSRect(x: frame.width - 4 - labelW, y: rowY + 2, width: labelW, height: 14)

            let scrubber = ProgressScrubber(frame: NSRect(x: 4 + labelW + 2, y: rowY,
                                                          width: frame.width - 2 * (4 + labelW + 2), height: rowH))
            scrubber.onScrub = { [weak self] fraction in
                guard let self else { return }
                self.showTimes(position: Double(fraction) * self.info.duration)
            }
            scrubber.onSeek = { [weak self] fraction in
                guard let self else { return }
                let target = Double(fraction) * self.info.duration
                self.info.position = target
                self.info.measuredAt = Date()
                onCommand(.seek(target))
            }
            addSubview(scrubber)
            self.scrubber = scrubber
            tick()
        }

        toolTip = "\(info.title) – \(info.artist)"
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Novější údaje o pozici a stavu přehrávání (bez překreslení celé lišty).
    func sync(with newInfo: MediaInfo) {
        if newInfo.isPlaying != info.isPlaying {
            info.isPlaying = newInfo.isPlaying
            playButton?.setSymbol(info.isPlaying ? "pause.fill" : "play.fill",
                                  description: info.isPlaying ? "Pozastavit" : "Přehrát")
        }
        guard !isScrubbing else { return }
        info.position = newInfo.position
        info.measuredAt = newInfo.measuredAt
        tick()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil, scrubber != nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let scrubber, !scrubber.isDragging, info.duration > 0 else { return }
        let position = info.estimatedPosition
        scrubber.fraction = CGFloat(position / info.duration)
        showTimes(position: position)
    }

    private func showTimes(position: Double) {
        elapsedLabel.stringValue = Self.format(position)
        remainingLabel.stringValue = "-" + Self.format(max(0, info.duration - position))
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        }
    }
}
