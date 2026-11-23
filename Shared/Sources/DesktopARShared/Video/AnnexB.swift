import Foundation

public enum AnnexB {
    public static let startCode: [UInt8] = [0, 0, 0, 1]

    /// Splits an Annex-B stream (3- or 4-byte start codes) into NAL units without start codes.
    public static func split(_ data: Data) -> [Data] {
        let b = [UInt8](data)
        var starts: [(pos: Int, len: Int)] = []
        var i = 0
        while i + 2 < b.count {
            if b[i] == 0, b[i + 1] == 0 {
                if b[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if b[i + 2] == 0, i + 3 < b.count, b[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        var nals: [Data] = []
        for (n, s) in starts.enumerated() {
            let begin = s.pos + s.len
            let end = n + 1 < starts.count ? starts[n + 1].pos : b.count
            if end > begin { nals.append(Data(b[begin..<end])) }
        }
        return nals
    }

    public static func join(_ nals: [Data]) -> Data {
        var d = Data()
        for n in nals { d.append(contentsOf: startCode); d.append(n) }
        return d
    }

    /// Annex-B → 4-byte big-endian length-prefixed NALs (what VideoToolbox expects).
    public static func toLengthPrefixed(_ data: Data) -> Data {
        var d = Data()
        for n in split(data) {
            withUnsafeBytes(of: UInt32(n.count).bigEndian) { d.append(contentsOf: $0) }
            d.append(n)
        }
        return d
    }

    public static func fromLengthPrefixed(_ data: Data) -> Data {
        let b = [UInt8](data)
        var nals: [Data] = []
        var i = 0
        while i + 4 <= b.count {
            let n = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            i += 4
            guard n >= 0, i + n <= b.count else { break }
            nals.append(Data(b[i..<(i + n)])); i += n
        }
        return join(nals)
    }

    public enum Codec { case h264, hevc }

    public static func nalType(_ nal: Data, codec: Codec) -> Int? {
        guard let f = nal.first else { return nil }
        return codec == .h264 ? Int(f & 0x1F) : Int((f >> 1) & 0x3F)
    }

    public static func isParameterSet(_ nal: Data, codec: Codec) -> Bool {
        guard let t = nalType(nal, codec: codec) else { return false }
        return codec == .h264 ? (t == 7 || t == 8) : (t >= 32 && t <= 34)
    }

    public static func isKeyframe(_ nal: Data, codec: Codec) -> Bool {
        guard let t = nalType(nal, codec: codec) else { return false }
        return codec == .h264 ? t == 5 : (t >= 16 && t <= 21)
    }

    public static func hasParameterSets(_ data: Data, codec: Codec) -> Bool {
        split(data).contains { isParameterSet($0, codec: codec) }
    }
}
