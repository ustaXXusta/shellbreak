import XCTest
import simd
@testable import DesktopARShared

final class DisplayLayoutTests: XCTestCase {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSnapToRightEdge() {
        let moving = CGRect(x: 1500, y: 40, width: 1920, height: 1080)
        let s = DisplayLayout.snapped(moving: moving, others: [main])
        XCTAssertEqual(s?.minX, 1440)
    }
    func testSnapNeverOverlaps() {
        let moving = CGRect(x: 200, y: 100, width: 1920, height: 1080)   // dropped on top of main
        let s = DisplayLayout.snapped(moving: moving, others: [main])
        XCTAssertNotNil(s)
        XCTAssertFalse(s!.intersects(main.insetBy(dx: 1, dy: 1)))
    }
    func testSnapLeftOfMainAllowsNegativeX() {
        let moving = CGRect(x: -2000, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(DisplayLayout.snapped(moving: moving, others: [main])?.maxX, 0)
    }
    func testRowKeepsAnchorAtOrigin() {
        let o = DisplayLayout.row(sizes: [CGSize(width: 1920, height: 1080), CGSize(width: 1440, height: 900), CGSize(width: 1080, height: 1920)], anchor: 1)
        XCTAssertEqual(o[1], .zero)
        XCTAssertEqual(o[0].x, -1920)
        XCTAssertEqual(o[2].x, 1440)
    }
    func testOrderLeftToRight() {
        let p: [SIMD3<Float>] = [SIMD3(0, 0, -1.4), SIMD3(1.5, 0, -1.4), SIMD3(-1.5, 0, -1.4)]
        XCTAssertEqual(DisplayLayout.orderLeftToRight(positions: p, right: SIMD3(1, 0, 0)), [2, 0, 1])
    }
}
