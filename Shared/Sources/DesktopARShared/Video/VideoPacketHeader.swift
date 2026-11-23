import Foundation

/// 18-byte big-endian header preceding every video payload (see docs/PROTOCOL.md).
public struct VideoPacketHeader: Equatable {
    public static let size = 18
    public static let maxPayload: UInt32 = 16 * 1024 * 1024

    public struct Flags: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let keyframe = Flags(rawValue: 1 << 0)
        public static let hevc = Flags(rawValue: 1 << 1)
        public static let hasParameterSets = Flags(rawValue: 1 << 2)
        public static let highQualityRefresh = Flags(rawValue: 1 << 3)
    }

    public var streamId: UInt8
    public var flags: Flags
    public var frameId: UInt32
    public var captureTimeUs: UInt64
    public var payloadLength: UInt32

    public init(streamId: UInt8, flags: Flags, frameId: UInt32, captureTimeUs: UInt64, payloadLength: UInt32) {
        self.streamId = streamId
        self.flags = flags
        self.frameId = frameId
        self.captureTimeUs = captureTimeUs
        self.payloadLength = payloadLength
    }

    public func encoded() -> Data {
        var d = Data(capacity: Self.size)
        d.append(streamId)
        d.append(flags.rawValue)
        withUnsafeBytes(of: frameId.bigEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: captureTimeUs.bigEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: payloadLength.bigEndian) { d.append(contentsOf: $0) }
        return d
    }

    /// Returns nil if fewer than 18 bytes or the payload length exceeds the limit.
    public static func decode(_ data: Data) -> VideoPacketHeader? {
        guard data.count >= size else { return nil }
        let b = [UInt8](data.prefix(size))
        func be<T: FixedWidthInteger>(_ off: Int, _ type: T.Type) -> T {
            var v: T = 0
            for i in 0..<MemoryLayout<T>.size { v = (v << 8) | T(b[off + i]) }
            return v
        }
        let len = be(14, UInt32.self)
        guard len <= maxPayload else { return nil }
        return VideoPacketHeader(streamId: b[0], flags: Flags(rawValue: b[1]),
                                 frameId: be(2, UInt32.self), captureTimeUs: be(6, UInt64.self),
                                 payloadLength: len)
    }
}
