import XCTest
import simd
@testable import DesktopARShared

final class LayoutMathTests: XCTestCase {
    let head = SIMD3<Float>(0.2, 1.5, -0.1)

    func testOrbitRoundTrip() {
        let c = head + LayoutMath.direction(yaw: 0.4, pitch: 0.2) * 1.4
        let o = LayoutMath.orbit(of: c, around: head)
        XCTAssertEqual(o.yaw, 0.4, accuracy: 1e-4); XCTAssertEqual(o.pitch, 0.2, accuracy: 1e-4); XCTAssertEqual(o.radius, 1.4, accuracy: 1e-4)
    }
    func testMoveKeepsDistanceAndLeftIsPositiveYaw() {
        let c = head + SIMD3<Float>(0, 0, -1.4)
        let m = LayoutMath.moved(center: c, head: head, dYaw: 0.3, dPitch: 0, dRadius: 0)
        XCTAssertEqual(simd_distance(m, head), 1.4, accuracy: 1e-4)
        XCTAssertLessThan(m.x, head.x, "positive yaw turns left")
    }
    func testDistanceAndPitchClamp() {
        let c = head + SIMD3<Float>(0, 0, -1.4)
        XCTAssertEqual(simd_distance(LayoutMath.moved(center: c, head: head, dYaw: 0, dPitch: 0, dRadius: 99), head), 5, accuracy: 1e-4)
        XCTAssertEqual(simd_distance(LayoutMath.moved(center: c, head: head, dYaw: 0, dPitch: 0, dRadius: -99), head), 0.5, accuracy: 1e-4)
        let up = LayoutMath.moved(center: c, head: head, dYaw: 0, dPitch: 9, dRadius: 0)
        XCTAssertEqual(LayoutMath.orbit(of: up, around: head).pitch, 1.2, accuracy: 1e-4)
    }
    func testFacingPointsAtHead() {
        let c = head + LayoutMath.direction(yaw: 0.7, pitch: 0.3) * 2
        let t = LayoutMath.facing(center: c, head: head)
        let z = SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        XCTAssertEqual(simd_dot(z, simd_normalize(head - c)), 1, accuracy: 1e-4)
        XCTAssertEqual(t.columns.0.y, 0, accuracy: 1e-5, "panel x axis stays horizontal")
    }
    func testWidthClamp() { XCTAssertEqual(LayoutMath.clampedWidth(9), 4); XCTAssertEqual(LayoutMath.clampedWidth(0.1), 0.3) }
}
