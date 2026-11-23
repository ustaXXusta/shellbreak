import XCTest
@testable import DesktopARShared

final class CursorLayoutTests: XCTestCase {
    func testHotspotStaysOnTarget() {
        let r = CursorLayout.spriteRect(u: 0.5, v: 0.5, hotspot: SIMD2(4, 4), sizePt: SIMD2(32, 32), displayWidthPt: 1600, aspect: 1.6)
        // hotspot position = topLeft + hotspot*k
        let k = 1.0 / 1600
        let topLeft = r.center - r.size / 2
        XCTAssertEqual(topLeft.x + 4 * k, 0.5, accuracy: 1e-12)
        XCTAssertEqual(topLeft.y + 4 * k * 1.6, 0.5, accuracy: 1e-12)
    }
    func testSquareInPoints() {
        let r = CursorLayout.spriteRect(u: 0, v: 0, hotspot: SIMD2(0, 0), sizePt: SIMD2(16, 16), displayWidthPt: 1600, aspect: 1.6)
        XCTAssertEqual(r.size.y / r.size.x, 1.6, accuracy: 1e-12) // equal pt extents = 1.6× taller in v units on a 16:10 panel
    }
    func testScaleKeepsHotspotFixed() {
        let a = CursorLayout.spriteRect(u: 0.3, v: 0.7, hotspot: SIMD2(2, 3), sizePt: SIMD2(20, 30), displayWidthPt: 1000, aspect: 1.6, scale: 2)
        let tl = a.center - a.size / 2
        XCTAssertEqual(tl.x + 2 * 2 / 1000, 0.3, accuracy: 1e-12)
    }
}
