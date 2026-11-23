import XCTest
@testable import DesktopARShared

final class ClockSyncTests: XCTestCase {
    func testOffsetFormula() {
        // phone clock is 1000 µs behind the Mac, 200 µs round trip
        XCTAssertEqual(ClockSync.offset(t0: 0, t1: 1100, t2: 200), 1000)
    }

    func testMedianIgnoresOutliers() {
        var c = ClockSync()
        for o in [1000, 1000, 1000, 50_000, 1000] as [Int64] { c.addSample(t0: 0, t1: o, t2: 0) }
        XCTAssertEqual(c.offsetUs, 1000)
    }

    func testKeepsLastEight() {
        var c = ClockSync()
        for i in 0..<20 { c.addSample(t0: 0, t1: Int64(i), t2: 0) }
        XCTAssertEqual(c.samples.count, 8)
    }

    func testLatency() {
        var c = ClockSync()
        c.addSample(t0: 0, t1: 1000, t2: 0) // offset 1000
        // captured at Mac 10_000 → phone time 9_000; now 59_000 → 50 ms
        XCTAssertEqual(c.latencyMs(captureTimeUs: 10_000, nowUs: 59_000), 50, accuracy: 0.001)
    }
}
