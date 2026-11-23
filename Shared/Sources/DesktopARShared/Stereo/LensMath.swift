import Foundation
import simd

public enum Eye: Int, Sendable { case left = 0, right = 1 }

/// Pure lens / stereo math shared by the phone renderer (the Metal shaders mirror these formulas).
public enum LensMath {
    /// iPhone 13 Pro panel size (2532×1170 @ 460 ppi).
    public static let iPhone13ProScreenMm = (width: 139.8, height: 63.4)

    /// Lens axis position inside one eye's half-screen viewport, in normalized [-1, 1] coordinates (x right, y up).
    /// Each eye owns half the screen, so the viewport centre sits at ±width/4 from the screen centre.
    public static func lensCenter(separationMm: Double, verticalOffsetMm: Double,
                                  screenWidthMm: Double, screenHeightMm: Double, eye: Eye) -> SIMD2<Double> {
        let quarter = screenWidthMm / 4
        let lensX = (eye == .left ? -1.0 : 1.0) * separationMm / 2
        let viewportX = (eye == .left ? -1.0 : 1.0) * quarter
        return SIMD2((lensX - viewportX) / quarter, verticalOffsetMm / (screenHeightMm / 2))
    }

    /// Barrel pre-distortion factor: r' = r · (1 + k1·r² + k2·r⁴); returns the bracketed factor.
    public static func radialScale(r2: Double, k1: Double, k2: Double) -> Double {
        1 + k1 * r2 + k2 * r2 * r2
    }

    /// Per-channel radial scale used for chromatic correction (red slightly smaller, blue slightly larger).
    public static func channelScales(chromatic: Double) -> SIMD3<Double> {
        SIMD3(1 - chromatic, 1, 1 + chromatic)
    }

    /// Right-handed perspective projection (view looks along −Z), vertical field of view in degrees, Metal depth 0…1.
    public static func perspective(verticalFovDegrees: Double, aspect: Double, near: Double, far: Double) -> simd_float4x4 {
        let f = 1 / tan(verticalFovDegrees * .pi / 360)
        let a = Float(f / aspect), b = Float(f)
        let z = Float(far / (near - far)), w = Float(near * far / (near - far))
        return simd_float4x4(columns: (SIMD4(a, 0, 0, 0), SIMD4(0, b, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, w, 0)))
    }

    /// Pixel size of one eye's render target for a given screen size and supersampling.
    public static func eyeTargetSize(screenWidthPx: Int, screenHeightPx: Int, supersample: Double) -> (width: Int, height: Int) {
        let s = max(0.5, min(2.0, supersample))
        return (max(16, Int(Double(screenWidthPx / 2) * s)), max(16, Int(Double(screenHeightPx) * s)))
    }
}
