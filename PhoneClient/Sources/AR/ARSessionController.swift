import ARKit
import simd

/// F4: ARKit world tracking at a 60 fps video format; keeps only the newest frame for the render thread.
final class ARSessionController: NSObject, ARSessionDelegate, @unchecked Sendable {
    let session = ARSession()
    private let lock = NSLock()
    private var _frame: ARFrame?

    var latestFrame: ARFrame? { lock.lock(); defer { lock.unlock() }; return _frame }

    func start() {
        let cfg = ARWorldTrackingConfiguration()
        cfg.planeDetection = [.horizontal, .vertical]
        // ARKit's default 30 fps format makes poses judder at 60 Hz: prefer a 60 fps format (≤ 1920 px wide to limit heat).
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats.filter { $0.framesPerSecond >= 60 }
        if let f = formats.filter({ $0.imageResolution.width <= 1920 }).max(by: { $0.imageResolution.width < $1.imageResolution.width }) ?? formats.first {
            cfg.videoFormat = f
        }
        session.delegate = self
        session.delegateQueue = DispatchQueue(label: "dev.desktopar.ar", qos: .userInteractive)
        session.run(cfg)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lock.lock(); _frame = frame; lock.unlock()
    }
}
