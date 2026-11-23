import Foundation
import DesktopARShared

/// Thread-safe settings shared between the UI/network side and the render thread.
final class StereoSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var _calibration = Calibration()
    private var _stereo = true
    private var _recenter = true
    private var _passthrough = true
    private var _commands: [LayoutCommand] = []
    private var _panelWidth: Float = 2.0
    private var _layoutActive = false
    private var _inputs: [ARInput] = []

    var calibration: Calibration {
        get { lock.lock(); defer { lock.unlock() }; return _calibration }
        set { lock.lock(); _calibration = newValue; lock.unlock() }
    }
    var stereo: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stereo }
        set { lock.lock(); _stereo = newValue; _recenter = true; lock.unlock() }
    }
    var panelWidthM: Float {
        get { lock.lock(); defer { lock.unlock() }; return _panelWidth }
        set { lock.lock(); _panelWidth = max(0.3, min(4, newValue)); lock.unlock() }
    }
    var passthrough: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _passthrough }
        set { lock.lock(); _passthrough = newValue; lock.unlock() }
    }
    var layoutActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _layoutActive }
        set { lock.lock(); _layoutActive = newValue; _inputs = []; lock.unlock() }
    }
    func enqueue(_ i: ARInput) { lock.lock(); _inputs.append(i); if _inputs.count > 400 { _inputs.removeFirst() }; lock.unlock() }
    func takeInputs() -> [ARInput] { lock.lock(); defer { lock.unlock() }; let i = _inputs; _inputs = []; return i }
    var onAddDisplay: (() -> Void)?
    var onEnterScreen: ((_ u: Double, _ v: Double) -> Void)?
    func enqueue(_ c: LayoutCommand) { lock.lock(); _commands.append(c); if _commands.count > 200 { _commands.removeFirst() }; lock.unlock() }
    func takeCommands() -> [LayoutCommand] { lock.lock(); defer { lock.unlock() }; let c = _commands; _commands = []; return c }
    /// Called after the user stops adjusting the panel (debounced).
    var onPanelChanged: ((_ transform: [Float], _ widthM: Float) -> Void)?
    func requestRecenter() { lock.lock(); _recenter = true; lock.unlock() }
    func takeRecenter() -> Bool { lock.lock(); defer { lock.unlock() }; let r = _recenter; _recenter = false; return r }
}
