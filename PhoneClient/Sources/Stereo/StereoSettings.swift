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
    private var _layoutActive = false
    private var _theme = UserDefaults.standard.integer(forKey: "theme.v1")
    private var _inputs: [ARInput] = []

    var calibration: Calibration {
        get { lock.lock(); defer { lock.unlock() }; return _calibration }
        set { lock.lock(); _calibration = newValue; lock.unlock() }
    }
    var stereo: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stereo }
        set { lock.lock(); _stereo = newValue; _recenter = true; lock.unlock() }
    }
    private var _scene: [PanelInfo]?
    /// Latest `scene` from the Mac; the render thread takes it once.
    func setScene(_ p: [PanelInfo]) { lock.lock(); _scene = p; lock.unlock() }
    func takeScene() -> [PanelInfo]? { lock.lock(); defer { lock.unlock() }; let s = _scene; _scene = nil; return s }
    var passthrough: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _passthrough }
        set { lock.lock(); _passthrough = newValue; lock.unlock() }
    }
    /// 0 = plain black, 1…8 = procedural world themes (only visible while the real world is darkened).
    var theme: Int {
        get { lock.lock(); defer { lock.unlock() }; return _theme }
        set { lock.lock(); _theme = max(0, min(8, newValue)); lock.unlock(); UserDefaults.standard.set(max(0, min(8, newValue)), forKey: "theme.v1") }
    }
    var layoutActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _layoutActive }
        set { lock.lock(); _layoutActive = newValue; _inputs = []; lock.unlock() }
    }
    func enqueue(_ i: ARInput) { lock.lock(); _inputs.append(i); if _inputs.count > 400 { _inputs.removeFirst() }; lock.unlock() }
    func takeInputs() -> [ARInput] { lock.lock(); defer { lock.unlock() }; let i = _inputs; _inputs = []; return i }
    var onAddDisplay: ((_ afterPanelId: String) -> Void)?
    var onEnterScreen: ((_ panelId: String, _ u: Double, _ v: Double) -> Void)?
    func enqueue(_ c: LayoutCommand) { lock.lock(); _commands.append(c); if _commands.count > 200 { _commands.removeFirst() }; lock.unlock() }
    func takeCommands() -> [LayoutCommand] { lock.lock(); defer { lock.unlock() }; let c = _commands; _commands = []; return c }
    /// Called after the user stops adjusting the panel (debounced).
    var onPanelChanged: ((_ panelId: String, _ transform: [Float], _ widthM: Float) -> Void)?
    var onMagnet: ((_ join: MagnetJoin) -> Void)?
    var onRotate: ((_ panelId: String, _ orientation: PanelOrientation) -> Void)?
    var onRemoveDisplay: ((_ panelId: String) -> Void)?
    func requestRecenter() { lock.lock(); _recenter = true; lock.unlock() }
    func takeRecenter() -> Bool { lock.lock(); defer { lock.unlock() }; let r = _recenter; _recenter = false; return r }
}
