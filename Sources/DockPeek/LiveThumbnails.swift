import AppKit

/// Průběžně obnovované náhledy: dokud je panel otevřený, každá 3 s se pořídí
/// nový snímek viditelných oken (jednorázové snímky přes ScreenCaptureKit, žádný stream).
///
/// Aplikace, která své okno nekreslí (je celé zakryté a šetří výkon),
/// může vrátit poslední známý obsah.
final class LiveThumbnails {
    /// Nový snímek okna (volá se na hlavním vlákně).
    var onFrame: ((CGWindowID, CGImage) -> Void)?

    /// Kolik oken se nejvýš obnovuje najednou.
    static let maxWindows = 8
    /// Jak často se snímky obnovují.
    static let refreshInterval: TimeInterval = 3

    private var ids: [CGWindowID] = []
    private var timer: Timer?
    /// Snímání zrovna běží – další kolo se přeskočí, aby se požadavky nehromadily.
    private var capturing = false
    /// Zvyšuje se při každém start/stop – výsledek starého kola se zahodí.
    private var token = 0

    var isRunning: Bool { timer != nil }

    func start(ids: [CGWindowID]) {
        stop()
        self.ids = Array(ids.prefix(Self.maxWindows))
        guard !self.ids.isEmpty else { return }
        // První snímek pořizuje controller hned při zobrazení, tady až další kola.
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        token += 1
        timer?.invalidate()
        timer = nil
        ids = []
        capturing = false
    }

    private func refresh() {
        guard !capturing, !ids.isEmpty else { return }
        capturing = true
        let myToken = token
        let wanted = ids
        Task { @MainActor [weak self] in
            let images = await Thumbnailer.capture(ids: wanted)
            guard let self, myToken == self.token else { return }
            self.capturing = false
            for (id, image) in images { self.onFrame?(id, image) }
        }
    }
}
