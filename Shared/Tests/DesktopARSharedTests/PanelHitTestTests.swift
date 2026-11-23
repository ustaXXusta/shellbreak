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
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0.98, y: -0.48, width: w, aspect: a), .resizeCorner(3))
        XCTAssertEqual(PanelHandleGeometry.hit(x: -0.98, y: 0.48, width: w, aspect: a), .resizeCorner(0))
        XCTAssertEqual(PanelHandleGeometry.hit(x: 0.98, y: 0.48, width: w, aspect: a), .resizeCorner(1))
        XCTAssertEqual(PanelHandleGeometry.hit(x: -0.98, y: -0.48, width: w, aspect: a), .resizeCorner(2))
    }
    func testButtonsAbove() {
        let b = PanelHandleGeometry.buttons(width: w, aspect: a)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[0].cx, y: b[0].cy, width: w, aspect: a), .rotate)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[1].cx, y: b[1].cy, width: w, aspect: a), .tilt)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[2].cx, y: b[2].cy, width: w, aspect: a), .add)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[3].cx, y: b[3].cy, width: w, aspect: a), .close)
    }
    func testDarkenAndThemePicker() {
        let b = PanelHandleGeometry.buttons(width: w, aspect: a)
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[4].cx, y: b[4].cy, width: w, aspect: a), .darken)
        XCTAssertEqual(PanelHandleGeometry.hit(x: b[5].cx, y: b[5].cy, width: w, aspect: a), .theme)
        let c = PanelHandleGeometry.themeCircles(width: w, aspect: a)
        XCTAssertEqual(c.count, PanelHandleGeometry.themeCount)
        XCTAssertEqual(PanelHandleGeometry.hit(x: c[3].cx, y: c[3].cy, width: w, aspect: a, pickerOpen: true), .themeChoice(3))
        // Circles are only live while the picker is open.
        XCTAssertNotEqual(PanelHandleGeometry.hit(x: c[3].cx, y: c[3].cy, width: w, aspect: a), .themeChoice(3))
        // Gap between button and circles keeps the picker open.
        let btn = b[5]
        XCTAssertEqual(PanelHandleGeometry.hit(x: btn.cx, y: btn.cy + btn.h / 2 + 0.004, width: w, aspect: a, pickerOpen: true), .theme)
    }
    func testMagnetsOnEdges() {
        let m = PanelHandleGeometry.magnets(width: w, aspect: a)
        XCTAssertEqual(m.count, 4)
        for (i, r) in m.enumerated() { XCTAssertEqual(PanelHandleGeometry.hit(x: r.cx, y: r.cy, width: w, aspect: a), .magnet(i)) }
    }
    func testOutside() {
        XCTAssertEqual(PanelHandleGeometry.hit(x: 5, y: 5, width: w, aspect: a), .none)
    }
}
