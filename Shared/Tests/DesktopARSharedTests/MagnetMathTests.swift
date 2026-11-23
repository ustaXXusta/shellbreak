import XCTest
import simd
@testable import DesktopARShared

final class MagnetMathTests: XCTestCase {
    let a = SIMD2<Float>(2, 1), b = SIMD2<Float>(1, 1)

    func testOffsets() {
        XCTAssertEqual(MagnetMath.centerOffset(aSize: a, bSize: b, edgeA: 1), SIMD2(1.5, 0))
        XCTAssertEqual(MagnetMath.centerOffset(aSize: a, bSize: b, edgeA: 0), SIMD2(-1.5, 0))
        XCTAssertEqual(MagnetMath.centerOffset(aSize: a, bSize: b, edgeA: 2), SIMD2(0, 1))
        XCTAssertEqual(MagnetMath.centerOffset(aSize: a, bSize: b, edgeA: 3), SIMD2(0, -1))
        XCTAssertNil(MagnetMath.centerOffset(aSize: a, bSize: b, edgeA: 9))
    }
    func testOppositeEdges() {
        XCTAssertEqual([0, 1, 2, 3].map(MagnetMath.opposite), [1, 0, 3, 2])
    }
    func testSeamOnSharedEdge() {
        let s = MagnetMath.seam(aSize: a, bSize: SIMD2(1, 3), edgeA: 1)
        XCTAssertEqual(s?.cx, 1)
        XCTAssertEqual(s?.h, 1)      // the shorter of the two sides
    }
    func testDisplayOriginCentred() {
        let r = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1080, height: 1920), edgeA: 1), CGPoint(x: 1920, y: 540 - 960))
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1920, height: 1080), edgeA: 2), CGPoint(x: 0, y: -1080))
        XCTAssertEqual(MagnetMath.displayOrigin(a: r, bSize: CGSize(width: 1920, height: 1080), edgeA: 3), CGPoint(x: 0, y: 1080))
    }
    func testBendTurnsTowardHead() {
        // Panel faces +Z; head is above and in front → rotate about +X by -45° (top leans toward the head).
        let ang = MagnetMath.bendAngle(normal: SIMD3(0, 0, 1), toHead: simd_normalize(SIMD3(0, 1, 1)), axis: SIMD3(1, 0, 0), factor: 1)
        XCTAssertEqual(ang, -.pi / 4, accuracy: 1e-4)
        XCTAssertEqual(MagnetMath.bendAngle(normal: SIMD3(0, 0, 1), toHead: SIMD3(0, 1, 1), axis: SIMD3(1, 0, 0), factor: 0), 0)
    }
    func testRotationAboutHingeKeepsHingePoint() {
        let p = SIMD3<Float>(1, 2, 3)
        let m = MagnetMath.rotation(about: p, axis: SIMD3(1, 0, 0), angle: 0.7)
        let r = m * SIMD4(p, 1)
        XCTAssertEqual(r.x, p.x, accuracy: 1e-5); XCTAssertEqual(r.y, p.y, accuracy: 1e-5); XCTAssertEqual(r.z, p.z, accuracy: 1e-5)
    }
}
