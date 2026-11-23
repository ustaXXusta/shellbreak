import Foundation
import CoreGraphics

/// One panel's capture → encode pipeline for a single display.
final class PanelStream: @unchecked Sendable {
    let streamId: UInt8
    let displayID: CGDirectDisplayID
    private let capture = DisplayCapture()
    private(set) var encoder: VideoEncoder
    private(set) var width: Int
    private(set) var height: Int
    var onFrame: ((EncodedFrame) -> Void)?

    init(streamId: UInt8, displayID: CGDirectDisplayID, width: Int, height: Int) {
        self.streamId = streamId; self.displayID = displayID; self.width = width; self.height = height
        encoder = VideoEncoder(width: width, height: height)
    }

    var isHEVC: Bool { encoder.isHEVC }
    func requestKeyframe() { encoder.requestKeyframe() }

    func start() async throws {
        try encoder.start()
        encoder.onFrame = { [weak self] f in self?.onFrame?(f) }
        capture.onFrame = { [weak self] pb in self?.encoder.encode(pb) }
        // A fresh virtual display needs a moment before ScreenCaptureKit lists it.
        var lastError: Error?
        for _ in 0..<8 {
            do { try await capture.start(displayID: displayID, width: width, height: height); return }
            catch { lastError = error; try? await Task.sleep(nanoseconds: 400_000_000) }
        }
        throw lastError ?? NSError(domain: "PanelStream", code: 1)
    }

    func stop() async {
        await capture.stop()
        encoder.stop()
    }

    /// New output size (portrait/landscape swap): restart capture and encoder.
    func restart(width w: Int, height h: Int) async throws {
        await stop()
        width = w; height = h
        let cb = onFrame
        encoder = VideoEncoder(width: w, height: h)
        onFrame = cb
        try await start()
    }
}
