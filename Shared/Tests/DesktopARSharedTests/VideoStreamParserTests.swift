import XCTest
@testable import DesktopARShared

final class VideoStreamParserTests: XCTestCase {
    func packet(_ id: UInt32, _ payload: [UInt8]) -> Data {
        VideoPacketHeader(streamId: 0, flags: [], frameId: id, captureTimeUs: 0, payloadLength: UInt32(payload.count)).encoded() + Data(payload)
    }

    func testSplitAcrossReads() throws {
        var p = VideoStreamParser()
        let d = packet(1, [1, 2, 3, 4, 5])
        var out: [VideoPacket] = []
        for byte in d { out += try p.feed(Data([byte])) }
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].payload, Data([1, 2, 3, 4, 5]))
    }

    func testMergedPackets() throws {
        var p = VideoStreamParser()
        let out = try p.feed(packet(1, [9]) + packet(2, []) + packet(3, [7, 7]))
        XCTAssertEqual(out.map { $0.header.frameId }, [1, 2, 3])
    }

    func testOversizedFails() {
        var p = VideoStreamParser()
        let bad = VideoPacketHeader(streamId: 0, flags: [], frameId: 0, captureTimeUs: 0, payloadLength: VideoPacketHeader.maxPayload + 1).encoded()
        XCTAssertThrowsError(try p.feed(bad))
        XCTAssertTrue(p.failed)
    }
}
