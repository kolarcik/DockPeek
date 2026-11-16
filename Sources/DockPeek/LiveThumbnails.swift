import AppKit
import CoreImage
import ScreenCaptureKit

/// Živé náhledy: dokud je panel otevřený, každé viditelné okno má vlastní
/// SCStream s nízkou snímkovou frekvencí a náhled se průběžně obnovuje.
///
/// Stream posílá nový snímek jen tehdy, když se obsah okna změní, takže klidná okna
/// nic nestojí. Aplikace, která své okno nekreslí (je celé zakryté a šetří výkon),
/// nový snímek nepošle – tam zůstane poslední známý obsah.
final class LiveThumbnails: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Nový snímek okna (volá se na hlavním vlákně).
    var onFrame: ((CGWindowID, CGImage) -> Void)?

    /// Kolik oken se nejvýš streamuje najednou.
    static let maxStreams = 8
    /// Nejvýš 5 snímků za sekundu na okno.
    static let frameInterval = CMTime(value: 1, timescale: 5)

    private var streams: [CGWindowID: SCStream] = [:]
    private var windowForStream: [ObjectIdentifier: CGWindowID] = [:]
    private let queue = DispatchQueue(label: "DockPeek.live", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Zvyšuje se při každém start/stop – zpožděné spuštění starého požadavku se zahodí.
    private var token = 0

    var isRunning: Bool { !streams.isEmpty }

    func start(ids: [CGWindowID]) {
        stop()
        let wanted = Array(ids.prefix(Self.maxStreams))
        guard !wanted.isEmpty else { return }
        token += 1
        let myToken = token
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  myToken == self.token else { return }
            for id in wanted {
                guard let window = content.windows.first(where: { $0.windowID == id }) else { continue }
                self.startStream(for: window)
            }
            Log.write("Živé náhledy: \(self.streams.count) oken")
        }
    }

    func stop() {
        token += 1
        for stream in streams.values {
            stream.stopCapture { _ in }
        }
        streams.removeAll()
        windowForStream.removeAll()
    }

    private func startStream(for window: SCWindow) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let pointSize = window.frame.size
        let scale = min(CGFloat(filter.pointPixelScale),
                        Thumbnailer.maxPixelSize / max(pointSize.width, pointSize.height, 1))
        config.width = max(2, Int(pointSize.width * scale))
        config.height = max(2, Int(pointSize.height * scale))
        config.minimumFrameInterval = Self.frameInterval
        config.queueDepth = 3
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            Log.write("Živý náhled okna \(window.windowID) nejde spustit: \(error)")
            return
        }
        streams[window.windowID] = stream
        windowForStream[ObjectIdentifier(stream)] = window.windowID
        let myToken = token
        stream.startCapture { [weak self] error in
            guard let error else { return }
            Log.write("Živý náhled okna \(window.windowID) selhal: \(error)")
            DispatchQueue.main.async {
                guard let self, myToken == self.token else { return }
                self.streams[window.windowID] = nil
                self.windowForStream[ObjectIdentifier(stream)] = nil
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              Self.isCompleteFrame(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let key = ObjectIdentifier(stream)
        DispatchQueue.main.async { [weak self] in
            guard let self, let id = self.windowForStream[key] else { return }
            self.onFrame?(id, image)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let key = ObjectIdentifier(stream)
        DispatchQueue.main.async { [weak self] in
            guard let self, let id = self.windowForStream[key] else { return }
            self.streams[id] = nil
            self.windowForStream[key] = nil
        }
    }

    /// Jen úplné snímky – stream posílá i stavové „nic se nezměnilo“ (idle) bez obrazu.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
