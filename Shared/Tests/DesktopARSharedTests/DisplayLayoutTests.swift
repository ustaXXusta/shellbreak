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
    func testFreeSlideAlongSharedEdge() {
        // A portrait display dropped left of a vertical stack keeps its own vertical offset (no forced alignment).
        let top = CGRect(x: 0, y: 0, width: 1920, height: 1080), bottom = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let moving = CGRect(x: -1200, y: 400, width: 1080, height: 1920)
        let s = DisplayLayout.snapped(moving: moving, others: [top, bottom])
        XCTAssertEqual(s?.maxX, 0)
        XCTAssertEqual(s?.minY, 400)
    }
    func testStackedPairLeftSideIsValid() {
        let top = CGRect(x: 0, y: 0, width: 1920, height: 1080), bottom = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let s = DisplayLayout.snapped(moving: CGRect(x: -100, y: 200, width: 1080, height: 1920), others: [top, bottom])
        XCTAssertNotNil(s)
        XCTAssertFalse(s!.intersects(top.insetBy(dx: 1, dy: 1)) || s!.intersects(bottom.insetBy(dx: 1, dy: 1)))
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

final class DisplayResolutionsTests: XCTestCase {
    func testPortraitListIsSwapped() {
        let l = DisplayResolutions.presets(portrait: false), p = DisplayResolutions.presets(portrait: true)
        XCTAssertEqual(l.count, p.count)
        XCTAssertTrue(l.allSatisfy { $0.width > $0.height })
        XCTAssertTrue(p.allSatisfy { $0.width < $0.height })
        XCTAssertTrue(p.contains(CGSize(width: 1080, height: 1920)))
    }
    func testBitrateScalesAndCaps() {
        XCTAssertEqual(DisplayResolutions.bitrate(width: 1920, height: 1080), 15_000_000)
        XCTAssertEqual(DisplayResolutions.bitrate(width: 3840, height: 2160), 40_000_000)
        XCTAssertEqual(DisplayResolutions.bitrate(width: 1280, height: 720), 6_666_666)
    }
}
