import Foundation
import CoreGraphics

/// Resolution choices for virtual displays: landscape list for landscape displays, swapped list for portrait ones.
public enum DisplayResolutions {
    public static let landscape: [CGSize] = [
        CGSize(width: 640, height: 360), CGSize(width: 800, height: 450), CGSize(width: 960, height: 540), CGSize(width: 1024, height: 576),
        CGSize(width: 1152, height: 648), CGSize(width: 1280, height: 720), CGSize(width: 1366, height: 768), CGSize(width: 1440, height: 810),
        CGSize(width: 1600, height: 900), CGSize(width: 1760, height: 990), CGSize(width: 1920, height: 1080), CGSize(width: 2048, height: 1152),
        CGSize(width: 2304, height: 1296), CGSize(width: 2560, height: 1440), CGSize(width: 2880, height: 1620), CGSize(width: 3200, height: 1800),
        CGSize(width: 3840, height: 2160),
    ]
    public static func presets(portrait: Bool) -> [CGSize] {
        portrait ? landscape.map { CGSize(width: $0.height, height: $0.width) } : landscape
    }
    /// Encoder bitrate that grows with the pixel count (15 Mbps at 1080p, capped at 40).
    public static func bitrate(width: Int, height: Int) -> Int {
        min(40_000_000, max(6_000_000, Int(15_000_000 * Double(width * height) / (1920.0 * 1080.0))))
    }
}
