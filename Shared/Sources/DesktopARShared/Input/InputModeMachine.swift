import Foundation

public enum InputModeState: String, Equatable, Sendable { case screen, layout }
public enum ExitKeyStyle: String, Codable, Equatable, Sendable { case singleEsc, doubleEsc, ctrlEsc }

public struct KeyEvent: Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool, option: Bool, control: Bool, shift: Bool
    public var isRepeat: Bool
    public var time: Double
    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false,
                shift: Bool = false, isRepeat: Bool = false, time: Double = 0) {
        self.keyCode = keyCode; self.command = command; self.option = option; self.control = control
        self.shift = shift; self.isRepeat = isRepeat; self.time = time
    }
    public static let escKeyCode: UInt16 = 53
}

public enum InputAction: Equatable, Sendable {
    /// Let the event reach the app.
    case pass
    /// Drop the event.
    case swallow
    case enterLayout
    case enterScreen
    /// Layout mode: the key is swallowed and should be mapped by `LayoutKeymap`.
    case layoutKey
}

/// Pure state machine for screen ↔ layout mode switching (key-down events only).
public struct InputModeMachine: Sendable {
    public private(set) var mode: InputModeState = .screen
    public var style: ExitKeyStyle
    public var doubleEscWindow: Double = 0.35
    private var firstEscTime: Double?

    public init(style: ExitKeyStyle = .singleEsc) { self.style = style }

    public mutating func forceScreen() { mode = .screen; firstEscTime = nil }

    public mutating func handleKeyDown(_ e: KeyEvent) -> InputAction {
        let isEsc = e.keyCode == KeyEvent.escKeyCode
        let isReturn = e.keyCode == 36 || e.keyCode == 76
        switch mode {
        case .screen:
            guard isEsc, !e.isRepeat, !e.command, !e.option else { return .pass }   // ⌘Esc / ⌥Esc (Force Quit) never intercepted
            switch style {
            case .singleEsc:
                if e.control || e.shift { return .pass }
                mode = .layout; return .enterLayout
            case .ctrlEsc:
                guard e.control else { return .pass }
                mode = .layout; return .enterLayout
            case .doubleEsc:
                if e.control { return .pass }
                if let t = firstEscTime, e.time - t <= doubleEscWindow {
                    firstEscTime = nil; mode = .layout; return .enterLayout
                }
                firstEscTime = e.time
                return .pass                                                      // first Esc still reaches the app
            }
        case .layout:
            if isEsc || isReturn {
                if e.isRepeat { return .swallow }
                mode = .screen; firstEscTime = nil; return .enterScreen
            }
            return .layoutKey
        }
    }
}
