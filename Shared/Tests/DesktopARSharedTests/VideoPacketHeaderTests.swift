import XCTest
@testable import DesktopARShared

final class VideoPacketHeaderTests: XCTestCase {
    func testRoundTrip() {
        let h = VideoPacketHeader(streamId: 3, flags: [.keyframe, .hevc], frameId: 0xAABBCCDD,
                                  captureTimeUs: 1_764_000_000_000_000, payloadLength: 1234)
        let d = h.encoded()
        XCTAssertEqual(d.count, 18)
        XCTAssertEqual(VideoPacketHeader.decode(d), h)
    }

    func testBigEndianLayout() {
        let h = VideoPacketHeader(streamId: 1, flags: [.keyframe], frameId: 1, captureTimeUs: 2, payloadLength: 3)
        XCTAssertEqual([UInt8](h.encoded()), [1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 3])
    }

    func testRejectsShortAndOversized() {
        XCTAssertNil(VideoPacketHeader.decode(Data(count: 17)))
        let big = VideoPacketHeader(streamId: 0, flags: [], frameId: 0, captureTimeUs: 0,
                                    payloadLength: VideoPacketHeader.maxPayload + 1)
        XCTAssertNil(VideoPacketHeader.decode(big.encoded()))
    }
}
