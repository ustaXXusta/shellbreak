import Foundation
import DesktopARShared

/// Thread-safe settings shared between the UI/network side and the render thread.
final class StereoSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var _calibration = Calibration()
    private var _stereo = true
    private var _recenter = true
    private var _invert = false

    var calibration: Calibration {
        get { lock.lock(); defer { lock.unlock() }; return _calibration }
        set { lock.lock(); _calibration = newValue; lock.unlock() }
    }
    var stereo: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stereo }
        set { lock.lock(); _stereo = newValue; _recenter = true; lock.unlock() }
    }
    var invertHead: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _invert }
        set { lock.lock(); _invert = newValue; lock.unlock() }
    }
    func requestRecenter() { lock.lock(); _recenter = true; lock.unlock() }
    func takeRecenter() -> Bool { lock.lock(); defer { lock.unlock() }; let r = _recenter; _recenter = false; return r }
}
