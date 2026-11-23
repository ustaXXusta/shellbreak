import XCTest
import simd
@testable import DesktopARShared

final class MagnetMathTests: XCTestCase {
    let a = SIMD2<Float>(2, 1), b = SIMD2<Float>(1, 1)

    func testRightAdjacencyTopAligned() {
        // A top-right meets B top-left → B to the right, tops level.
        let o = MagnetMath.centerOffset(aSize: a, bSize: b, cornerA: 1, cornerB: 0)
        XCTAssertEqual(o, SIMD2(1.5, 0))
        XCTAssertEqual(MagnetMath.relation(cornerA: 1, cornerB: 0), .rightOf)
    }
    func testAboveRightAligned() {
        // A top-right meets B bottom-right → B above, right edges level.
        let o = MagnetMath.centerOffset(aSize: a, bSize: b, cornerA: 1, cornerB: 3)
        XCTAssertEqual(o, SIMD2(0.5, 1.0))
        XCTAssertEqual(MagnetMath.relation(cornerA: 1, cornerB: 3), .above)
    }
    func testDiagonalBecomesHorizontal() {
        XCTAssertEqual(MagnetMath.normalizedCornerB(cornerA: 1, cornerB: 2), 0)   // TR + BL → TR + TL
        XCTAssertEqual(MagnetMath.relation(cornerA: 1, cornerB: 2), .rightOf)
    }
    func testSameCornerInvalid() {
        XCTAssertNil(MagnetMath.centerOffset(aSize: a, bSize: b, cornerA: 1, cornerB: 1))
    }
    func testSeamLiesOnSharedEdge() {
        let s = MagnetMath.seam(aSize: a, bSize: SIMD2(1, 2), cornerA: 1, cornerB: 0)
        XCTAssertEqual(s?.cx, 1)
        XCTAssertEqual(s?.h, 1)        // overlap of A (1 tall) and B (2 tall)
    }
    func testDisplayOriginRightTop() {
        let r = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1080, height: 1920), cornerA: 1, cornerB: 0), CGPoint(x: 1920, y: 0))
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1080, height: 1920), cornerA: 3, cornerB: 2), CGPoint(x: 1920, y: 1080 - 1920))
    }
    func testDisplayOriginAbove() {
        let r = CGRect(x: 100, y: 500, width: 1920, height: 1080)
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1920, height: 1080), cornerA: 0, cornerB: 2), CGPoint(x: 100, y: -580))
    }
}
