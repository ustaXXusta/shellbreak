import XCTest
@testable import DesktopARShared

final class InputModeMachineTests: XCTestCase {
    private func esc(_ t: Double = 0, control: Bool = false, command: Bool = false, option: Bool = false, rep: Bool = false) -> KeyEvent {
        KeyEvent(keyCode: 53, command: command, option: option, control: control, isRepeat: rep, time: t)
    }

    func testSingleEscEntersAndLeavesLayout() {
        var m = InputModeMachine()
        XCTAssertEqual(m.handleKeyDown(esc()), .enterLayout); XCTAssertEqual(m.mode, .layout)
        XCTAssertEqual(m.handleKeyDown(esc()), .enterScreen); XCTAssertEqual(m.mode, .screen)
    }
    func testCommandAndOptionEscNeverIntercepted() {
        var m = InputModeMachine()
        XCTAssertEqual(m.handleKeyDown(esc(command: true)), .pass)
        XCTAssertEqual(m.handleKeyDown(esc(option: true)), .pass)
        XCTAssertEqual(m.mode, .screen)
    }
    func testRepeatsNeverSwitch() {
        var m = InputModeMachine()
        XCTAssertEqual(m.handleKeyDown(esc(rep: true)), .pass); XCTAssertEqual(m.mode, .screen)
        _ = m.handleKeyDown(esc())
        XCTAssertEqual(m.handleKeyDown(esc(rep: true)), .swallow); XCTAssertEqual(m.mode, .layout)
    }
    func testDoubleEscWindow() {
        var m = InputModeMachine(style: .doubleEsc)
        XCTAssertEqual(m.handleKeyDown(esc(0)), .pass)
        XCTAssertEqual(m.handleKeyDown(esc(0.2)), .enterLayout)
        m.forceScreen()
        XCTAssertEqual(m.handleKeyDown(esc(10)), .pass)
        XCTAssertEqual(m.handleKeyDown(esc(10.5)), .pass, "outside the 350 ms window it is a new first Esc")
        XCTAssertEqual(m.mode, .screen)
    }
    func testCtrlEscStyle() {
        var m = InputModeMachine(style: .ctrlEsc)
        XCTAssertEqual(m.handleKeyDown(esc()), .pass)
        XCTAssertEqual(m.handleKeyDown(esc(control: true)), .enterLayout)
    }
    func testLayoutModeKeysAndEnter() {
        var m = InputModeMachine()
        _ = m.handleKeyDown(esc())
        XCTAssertEqual(m.handleKeyDown(KeyEvent(keyCode: 123)), .layoutKey)
        XCTAssertEqual(m.handleKeyDown(KeyEvent(keyCode: 36)), .enterScreen)
    }
    func testOtherKeysPassInScreenMode() {
        var m = InputModeMachine()
        XCTAssertEqual(m.handleKeyDown(KeyEvent(keyCode: 0)), .pass)
    }
}
