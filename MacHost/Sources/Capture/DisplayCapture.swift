import Foundation
import ScreenCaptureKit
import CoreMedia
import os

/// One SCStream per panel. Delivers IOSurface-backed pixel buffers without copies.
final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "capture")
    private let queue = DispatchQueue(label: "dev.desktopar.capture", qos: .userInteractive)
    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int = 60) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "DisplayCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Display \(displayID) not found"])
        }
        // Own windows stay in the capture: the control panel is meant to be usable from the virtual display.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.showsCursor = false
        cfg.queueDepth = 3
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        log.info("capture started \(width)x\(height)@\(fps)")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("capture stopped: \(error.localizedDescription)")
    }
}
