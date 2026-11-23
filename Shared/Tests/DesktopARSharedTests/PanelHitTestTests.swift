import XCTest
@testable import DesktopARShared

final class PanelHitTestTests: XCTestCase {
    let w: Float = 2, a: Float = 2   // 2 m wide, 1 m tall

    func testContentUV() {
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0, y: 0, width: w, aspect: a), .content(u: 0.5, v: 0.5))
        XCTAssertEqual(PanelHandleGeometry.hit(x: -0.5, y: 0.25, width: w, aspect: a), .content(u: 0.25, v: 0.25))
    }
    func testBarBelowPanel() {
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0, y: -0.5 - 0.02 - 0.0175, width: w, aspect: a), .moveBar)
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0.9, y: -0.5 - 0.04, width: w, aspect: a), .none)
    }
    func testCornerWinsOverContent() {
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0.98, y: -0.48, width: w, aspect: a), .resizeCorner)
    }
    func testButtonsAbove() {
        let b = PanelHandleGeometry.buttons(width: w, aspect: a)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[0].cx, y: b[0].cy, width: w, aspect: a), .rotate)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[1].cx, y: b[1].cy, width: w, aspect: a), .add)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[2].cx, y: b[2].cy, width: w, aspect: a), .close)
    }
    func testOutside() {
        XCTAssertEqual(PanelHandleGeometry.hit(x: 5, y: 5, width: w, aspect: a), .none)
    }
}
