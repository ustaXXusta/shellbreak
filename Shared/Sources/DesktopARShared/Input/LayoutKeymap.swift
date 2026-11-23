import Foundation

public enum LayoutCommandName: String, Equatable, Sendable, CaseIterable {
    case moveLeft = "move_left", moveRight = "move_right", moveUp = "move_up", moveDown = "move_down"
    case closer, farther, bigger, smaller
    case toggleOrientation = "toggle_orientation", landscape, portrait, faceMe = "face_me"
    case toggleCurvature = "toggle_curvature", newDisplay = "new_display", removePanel = "remove_panel"
    case unhideAll = "unhide_all", bringFront = "bring_front", togglePassthrough = "toggle_passthrough"
    case calibration
}

/// Maps a layout-mode key to a command. Letters and symbols are matched by the produced character
/// (layout-aware, works with the Turkish Q keyboard); arrows, delete and keypad by key code.
public enum LayoutKeymap {
    public static func command(keyCode: UInt16, characters: String) -> LayoutCommandName? {
        switch keyCode {
        case 123: return .moveLeft
        case 124: return .moveRight
        case 126: return .moveUp
        case 125: return .moveDown
        case 51, 117: return .removePanel          // delete / forward delete
        case 69, 24: return .bigger                // keypad + , =
        case 78, 27: return .smaller               // keypad − , −
        case 67: return .bigger                    // keypad *
        default: break
        }
        switch characters.lowercased() {
        case "r": return .toggleOrientation
        case "h": return .landscape
        case "v": return .portrait
        case "f": return .faceMe
        case "+", "=", "*": return .bigger
        case "-", "_": return .smaller
        case "[", ",", "ğ": return .closer
        case "]", ".", "ü": return .farther
        case "c", "ç": return .toggleCurvature
        case "n": return .newDisplay
        case "g": return .unhideAll
        case "0": return .bringFront
        case "p": return .togglePassthrough
        case "k": return .calibration
        default: return nil
        }
    }
}
