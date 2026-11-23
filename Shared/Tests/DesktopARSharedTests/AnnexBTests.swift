import XCTest
@testable import DesktopARShared

final class AnnexBTests: XCTestCase {
    let sps = Data([0x67, 1, 2]), pps = Data([0x68, 3]), idr = Data([0x65, 4, 5, 6]), p = Data([0x41, 7])

    func testSplitJoinRoundTrip() {
        let joined = AnnexB.join([sps, pps, idr])
        XCTAssertEqual(AnnexB.split(joined), [sps, pps, idr])
    }

    func testThreeByteStartCodes() {
        let d = Data([0, 0, 1, 0x67, 1, 0, 0, 1, 0x68, 2])
        XCTAssertEqual(AnnexB.split(d), [Data([0x67, 1]), Data([0x68, 2])])
    }

    func testLengthPrefixConversion() {
        let annexb = AnnexB.join([idr, p])
        let lp = AnnexB.toLengthPrefixed(annexb)
        XCTAssertEqual([UInt8](lp.prefix(4)), [0, 0, 0, 4])
        XCTAssertEqual(AnnexB.fromLengthPrefixed(lp), annexb)
    }

    func testParameterSetDetectionH264() {
        XCTAssertTrue(AnnexB.hasParameterSets(AnnexB.join([sps, pps, idr]), codec: .h264))
        XCTAssertFalse(AnnexB.hasParameterSets(AnnexB.join([p]), codec: .h264))
        XCTAssertTrue(AnnexB.isKeyframe(idr, codec: .h264))
    }

    func testParameterSetDetectionHEVC() {
        let vps = Data([0x40, 1]), hsps = Data([0x42, 1]), hpps = Data([0x44, 1]), hidr = Data([0x26, 1])
        XCTAssertTrue([vps, hsps, hpps].allSatisfy { AnnexB.isParameterSet($0, codec: .hevc) })
        XCTAssertTrue(AnnexB.isKeyframe(hidr, codec: .hevc))
        XCTAssertFalse(AnnexB.isKeyframe(Data([0x02, 1]), codec: .hevc))
    }
}
