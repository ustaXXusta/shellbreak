import Foundation
import simd

/// Where the cursor sprite sits on a panel, in panel uv units (origin top-left, u and v both 0…1).
public enum CursorLayout {
    /// - Parameters:
    ///   - u, v: hotspot position on the panel.
    ///   - hotspot, sizePt: cursor image hotspot and size in display points.
    ///   - displayWidthPt: captured display width in points.
    ///   - aspect: panel width / height.
    ///   - scale: visual enlargement (about the hotspot).
    public static func spriteRect(u: Double, v: Double, hotspot: SIMD2<Double>, sizePt: SIMD2<Double>,
                                  displayWidthPt: Double, aspect: Double, scale: Double = 1)
        -> (center: SIMD2<Double>, size: SIMD2<Double>) {
        let k = scale / displayWidthPt
        let size = SIMD2(sizePt.x * k, sizePt.y * k * aspect)
        let topLeft = SIMD2(u - hotspot.x * k, v - hotspot.y * k * aspect)
        return (topLeft + size / 2, size)
    }
}
