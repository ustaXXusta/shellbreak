import CoreMotion
import simd

/// F3 sanity-check head tracking from CoreMotion (replaced by ARKit in F4).
/// Produces a world→view rotation for landscape-right, Y-up world, −Z forward.
final class HeadPose {
    private let motion = CMMotionManager()
    private var yawOffset: Float = 0
    private let lock = NSLock()
    /// If head motion turns out mirrored on the device, flipping this transposes the attitude.
    var invert = false

    init() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    private func base() -> simd_float3x3 {
        guard let m = motion.deviceMotion?.attitude.rotationMatrix else { return matrix_identity_float3x3 }
        var rm = simd_float3x3(rows: [SIMD3(Float(m.m11), Float(m.m12), Float(m.m13)),
                                      SIMD3(Float(m.m21), Float(m.m22), Float(m.m23)),
                                      SIMD3(Float(m.m31), Float(m.m32), Float(m.m33))])
        if invert { rm = rm.transpose }
        let p = simd_float3x3(rows: [SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)])   // device → landscape-right view
        let c = simd_float3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)])   // Y-up world → Z-up reference
        return p * rm * c
    }

    private static func rotY(_ a: Float) -> simd_float3x3 {
        let s = sin(a), c = cos(a)
        return simd_float3x3(rows: [SIMD3(c, 0, s), SIMD3(0, 1, 0), SIMD3(-s, 0, c)])
    }

    /// World→view rotation including the recentre yaw.
    func viewRotation() -> simd_float3x3 {
        lock.lock(); defer { lock.unlock() }
        return base() * Self.rotY(yawOffset)
    }

    /// Make the current heading the world's forward (−Z).
    func recenter() {
        lock.lock(); defer { lock.unlock() }
        let f = base().transpose * SIMD3<Float>(0, 0, -1)
        yawOffset = atan2(-f.x, -f.z)
    }
}
