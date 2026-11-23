import Foundation

/// offset = t1 − (t0 + t2)/2 (Mac clock minus phone clock, µs); median of the last 8 samples.
public struct ClockSync {
    public private(set) var samples: [Int64] = []
    public init() {}

    public static func offset(t0: Int64, t1: Int64, t2: Int64) -> Int64 { t1 - (t0 + t2) / 2 }

    public mutating func addSample(t0: Int64, t1: Int64, t2: Int64) {
        samples.append(Self.offset(t0: t0, t1: t1, t2: t2))
        if samples.count > 8 { samples.removeFirst() }
    }

    public var offsetUs: Int64 {
        guard !samples.isEmpty else { return 0 }
        let s = samples.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Content age in ms: local now − (captureTime − offset).
    public func latencyMs(captureTimeUs: UInt64, nowUs: Int64) -> Double {
        Double(nowUs - (Int64(captureTimeUs) - offsetUs)) / 1000
    }
}

extension ClockSync {
    /// Static variant for callers holding only the offset.
    public static func ageMs(captureTimeUs: UInt64, nowUs: Int64, offsetUs: Int64) -> Double {
        Double(nowUs - (Int64(captureTimeUs) - offsetUs)) / 1000
    }
}
