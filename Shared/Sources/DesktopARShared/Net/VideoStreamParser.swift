import Foundation

public struct VideoPacket: Equatable {
    public var header: VideoPacketHeader
    public var payload: Data
}

/// Reassembles video packets from arbitrary TCP chunking. After `.failed` the connection must be reset.
public struct VideoStreamParser {
    public enum ParseError: Error, Equatable { case oversizedPayload }
    private var buffer = Data()
    public private(set) var failed = false
    public init() {}

    public mutating func feed(_ data: Data) throws -> [VideoPacket] {
        guard !failed else { throw ParseError.oversizedPayload }
        buffer.append(data)
        var out: [VideoPacket] = []
        while buffer.count >= VideoPacketHeader.size {
            let base = buffer.startIndex
            let lenBytes = buffer[(base + 14)..<(base + 18)]
            let len = lenBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if len > VideoPacketHeader.maxPayload { failed = true; buffer.removeAll(); throw ParseError.oversizedPayload }
            let total = VideoPacketHeader.size + Int(len)
            guard buffer.count >= total, let h = VideoPacketHeader.decode(buffer) else { break }
            out.append(VideoPacket(header: h, payload: Data(buffer[(base + VideoPacketHeader.size)..<(base + total)])))
            buffer = Data(buffer.dropFirst(total))
        }
        return out
    }
}
