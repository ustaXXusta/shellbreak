import XCTest
@testable import DesktopARShared

final class LayoutKeymapTests: XCTestCase {
    func testArrows() {
        XCTAssertEqual(LayoutKeymap.command(keyCode: 123, characters: ""), .moveLeft)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 124, characters: ""), .moveRight)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 126, characters: ""), .moveUp)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 125, characters: ""), .moveDown)
    }
    func testLettersByCharacter() {
        XCTAssertEqual(LayoutKeymap.command(keyCode: 15, characters: "r"), .toggleOrientation)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 15, characters: "R"), .toggleOrientation)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 3, characters: "f"), .faceMe)
    }
    func testTurkishKeys() {
        XCTAssertEqual(LayoutKeymap.command(keyCode: 33, characters: "ğ"), .closer)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 30, characters: "ü"), .farther)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 41, characters: "ç"), .toggleCurvature)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 33, characters: "["), .closer)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 30, characters: "]"), .farther)
    }
    func testKeypadAndSize() {
        XCTAssertEqual(LayoutKeymap.command(keyCode: 69, characters: "+"), .bigger)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 78, characters: "-"), .smaller)
        XCTAssertEqual(LayoutKeymap.command(keyCode: 51, characters: ""), .removePanel)
        XCTAssertNil(LayoutKeymap.command(keyCode: 0, characters: "q"))
    }
}
