import Foundation
import simd

/// Panel placement math around the head (section 7). World: Y up, user looks along −Z at yaw 0, positive yaw turns left.
public enum LayoutMath {
    public static let minDistance: Float = 0.5, maxDistance: Float = 5
    public static let minWidth: Float = 0.3, maxWidth: Float = 4
    public static let maxPitch: Float = 1.2

    public struct Orbit: Equatable { public var yaw: Float, pitch: Float, radius: Float }

    public static func direction(yaw: Float, pitch: Float) -> SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    public static func orbit(of center: SIMD3<Float>, around head: SIMD3<Float>) -> Orbit {
        let d = center - head
        let r = max(simd_length(d), 1e-4)
        return Orbit(yaw: atan2(-d.x, -d.z), pitch: asin(max(-1, min(1, d.y / r))), radius: r)
    }

    public static func position(_ o: Orbit, around head: SIMD3<Float>) -> SIMD3<Float> {
        head + direction(yaw: o.yaw, pitch: o.pitch) * o.radius
    }

    /// Move around the head by yaw/pitch deltas and change the radius; pitch and distance are clamped.
    public static func moved(center: SIMD3<Float>, head: SIMD3<Float>, dYaw: Float, dPitch: Float, dRadius: Float) -> SIMD3<Float> {
        var o = orbit(of: center, around: head)
        o.yaw += dYaw
        o.pitch = max(-maxPitch, min(maxPitch, o.pitch + dPitch))
        o.radius = max(minDistance, min(maxDistance, o.radius + dRadius))
        return position(o, around: head)
    }

    /// Panel transform at `center` facing `head` (face +Z toward the head, vertical tilt toward it).
    public static func facing(center: SIMD3<Float>, head: SIMD3<Float>) -> simd_float4x4 {
        var z = head - center
        z = simd_length(z) < 1e-4 ? SIMD3(0, 0, 1) : simd_normalize(z)
        var x = simd_cross(SIMD3<Float>(0, 1, 0), z)
        x = simd_length(x) < 1e-4 ? SIMD3(1, 0, 0) : simd_normalize(x)
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(center, 1)))
    }

    public static func clampedWidth(_ w: Float) -> Float { max(minWidth, min(maxWidth, w)) }
}
