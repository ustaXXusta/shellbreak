import Foundation
import CoreGraphics
import simd

/// Magnet joins between panels, edge to edge. Edges (panel space, +Y up): 0 left, 1 right, 2 top, 3 bottom.
/// The panel clicked second always attaches with its opposite edge, centred on the first panel's edge.
public enum MagnetMath {
    public static func opposite(_ edge: Int) -> Int { edge ^ 1 }
    public static func isValid(_ edge: Int) -> Bool { (0..<4).contains(edge) }

    /// Centre of B in A's local frame (metres), B sitting flush against A's `edgeA`, centred on it.
    public static func centerOffset(aSize: SIMD2<Float>, bSize: SIMD2<Float>, edgeA: Int) -> SIMD2<Float>? {
        switch edgeA {
        case 0: return SIMD2(-(aSize.x + bSize.x) / 2, 0)
        case 1: return SIMD2((aSize.x + bSize.x) / 2, 0)
        case 2: return SIMD2(0, (aSize.y + bSize.y) / 2)
        case 3: return SIMD2(0, -(aSize.y + bSize.y) / 2)
        default: return nil
        }
    }

    /// Midpoint of the shared edge in A's local frame, and the hinge axis direction (unit, in A's local frame).
    public static func hinge(aSize: SIMD2<Float>, edgeA: Int) -> (point: SIMD2<Float>, axis: SIMD3<Float>)? {
        switch edgeA {
        case 0: return (SIMD2(-aSize.x / 2, 0), SIMD3(0, 1, 0))
        case 1: return (SIMD2(aSize.x / 2, 0), SIMD3(0, 1, 0))
        case 2: return (SIMD2(0, aSize.y / 2), SIMD3(1, 0, 0))
        case 3: return (SIMD2(0, -aSize.y / 2), SIMD3(1, 0, 0))
        default: return nil
        }
    }

    /// Thin rectangle along the shared edge in A's local frame (where the break "X" appears).
    public static func seam(aSize: SIMD2<Float>, bSize: SIMD2<Float>, edgeA: Int, thickness: Float = 0.16) -> LocalRect? {
        guard let off = centerOffset(aSize: aSize, bSize: bSize, edgeA: edgeA) else { return nil }
        switch edgeA {
        case 0, 1:
            let len = min(aSize.y, bSize.y)
            return LocalRect(cx: edgeA == 1 ? aSize.x / 2 : -aSize.x / 2, cy: off.y, w: thickness, h: len)
        default:
            let len = min(aSize.x, bSize.x)
            return LocalRect(cx: off.x, cy: edgeA == 2 ? aSize.y / 2 : -aSize.y / 2, w: len, h: thickness)
        }
    }

    /// Where B's display goes in macOS coordinates (y down) so it touches A's display on `edgeA`, centred.
    public static func displayOrigin(a: CGRect, bSize: CGSize, edgeA: Int) -> CGPoint? {
        switch edgeA {
        case 0: return CGPoint(x: a.minX - bSize.width, y: a.midY - bSize.height / 2)
        case 1: return CGPoint(x: a.maxX, y: a.midY - bSize.height / 2)
        case 2: return CGPoint(x: a.midX - bSize.width / 2, y: a.minY - bSize.height)
        case 3: return CGPoint(x: a.midX - bSize.width / 2, y: a.maxY)
        default: return nil
        }
    }

    /// Angle (radians) to rotate B about the hinge axis so it turns toward the viewer, scaled by `factor` and clamped.
    /// `normal` is B's face direction, `toHead` the direction from B's centre to the head, `axis` the unit hinge axis.
    public static func bendAngle(normal n: SIMD3<Float>, toHead d: SIMD3<Float>, axis h: SIMD3<Float>, factor: Float, limit: Float = 1.0) -> Float {
        let np = n - h * simd_dot(n, h), dp = d - h * simd_dot(d, h)
        guard simd_length(np) > 1e-4, simd_length(dp) > 1e-4 else { return 0 }
        let a = simd_normalize(np), b = simd_normalize(dp)
        let ang = atan2(simd_dot(simd_cross(a, b), h), simd_dot(a, b))
        return max(-limit, min(limit, ang * factor))
    }

    /// Rotation by `angle` about the line through `point` with direction `axis` (world space).
    public static func rotation(about point: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) -> simd_float4x4 {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
        var m = simd_float4x4(q)
        let t = point - m.act(point)
        m.columns.3 = SIMD4(t, 1)
        return m
    }
}

extension simd_float4x4 {
    fileprivate func act(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = self * SIMD4(p, 0); return SIMD3(r.x, r.y, r.z)
    }
}
