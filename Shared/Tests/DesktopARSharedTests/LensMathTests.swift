import XCTest
import simd
@testable import DesktopARShared

final class LensMathTests: XCTestCase {
    private let s = LensMath.iPhone13ProScreenMm

    func testLensCentersAreMirrored() {
        let l = LensMath.lensCenter(separationMm: 63, verticalOffsetMm: 5, screenWidthMm: s.width, screenHeightMm: s.height, eye: .left)
        let r = LensMath.lensCenter(separationMm: 63, verticalOffsetMm: 5, screenWidthMm: s.width, screenHeightMm: s.height, eye: .right)
        XCTAssertEqual(l.x, -r.x, accuracy: 1e-9)
        XCTAssertEqual(l.y, r.y, accuracy: 1e-9)
        XCTAssertGreaterThan(l.x, 0, "63 mm < half-screen pitch, so the left lens sits right of its viewport centre")
        XCTAssertGreaterThan(l.y, 0)
    }

    func testLensCenterMatchesViewportCentreAtHalfScreenPitch() {
        let c = LensMath.lensCenter(separationMm: s.width / 2, verticalOffsetMm: 0, screenWidthMm: s.width, screenHeightMm: s.height, eye: .left)
        XCTAssertEqual(c.x, 0, accuracy: 1e-9)
    }

    func testRadialScale() {
        XCTAssertEqual(LensMath.radialScale(r2: 0, k1: 0.34, k2: 0.55), 1, accuracy: 1e-12)
        XCTAssertEqual(LensMath.radialScale(r2: 1, k1: 0.34, k2: 0.55), 1.89, accuracy: 1e-12)
        var prev = 0.0
        for i in 0...10 { let r = Double(i) / 10; let v = r * LensMath.radialScale(r2: r * r, k1: 0.34, k2: 0.55); XCTAssertGreaterThanOrEqual(v, prev); prev = v }
    }

    func testChannelScales() {
        let c = LensMath.channelScales(chromatic: 0.01)
        XCTAssertEqual(c.x, 0.99, accuracy: 1e-12); XCTAssertEqual(c.y, 1); XCTAssertEqual(c.z, 1.01, accuracy: 1e-12)
    }

    func testPerspectiveMapsFrustumEdges() {
        let p = LensMath.perspective(verticalFovDegrees: 90, aspect: 1, near: 0.1, far: 100)
        let top = p * SIMD4<Float>(0, 1, -1, 1)          // 45° up at distance 1
        XCTAssertEqual(top.y / top.w, 1, accuracy: 1e-5)
        let near = p * SIMD4<Float>(0, 0, -0.1, 1), far = p * SIMD4<Float>(0, 0, -100, 1)
        XCTAssertEqual(near.z / near.w, 0, accuracy: 1e-4)
        XCTAssertEqual(far.z / far.w, 1, accuracy: 1e-4)
    }

    func testEyeTargetSize() {
        let t = LensMath.eyeTargetSize(screenWidthPx: 2532, screenHeightPx: 1170, supersample: 1.25)
        XCTAssertEqual(t.width, 1582); XCTAssertEqual(t.height, 1462)
        XCTAssertEqual(LensMath.eyeTargetSize(screenWidthPx: 2532, screenHeightPx: 1170, supersample: 9).height, 2340)
    }
}
