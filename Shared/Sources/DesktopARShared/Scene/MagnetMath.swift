import Foundation
import CoreGraphics
import simd

/// Magnet joins between panels, edge to edge. Edges (panel space, +Y up): 0 left, 1 right, 2 top, 3 bottom.
/// The panel clicked second always attaches with its opposite edge, centred on the first panel's edge.
public enum MagnetMath {
    public static func opposite(_ edge: Int) -> Int { edge ^ 1 }
    public static func isValid(_ edge: Int) -> Bool { (0..<4).contains(edge) }

    /// Centre of B in A's local frame (metres), B sitting flush against A's `edgeA`; centred on the edge unless `slide`
    /// moves it along the edge.
    public static func centerOffset(aSize: SIMD2<Float>, bSize: SIMD2<Float>, edgeA: Int, slide: Float = 0) -> SIMD2<Float>? {
        switch edgeA {
        case 0: return SIMD2(-(aSize.x + bSize.x) / 2, slide)
        case 1: return SIMD2((aSize.x + bSize.x) / 2, slide)
        case 2: return SIMD2(slide, (aSize.y + bSize.y) / 2)
        case 3: return SIMD2(slide, -(aSize.y + bSize.y) / 2)
        default: return nil
        }
    }

    /// Midpoint of the shared edge in A's local frame, and the hinge axis direction (unit, in A's local frame).
    public static func hinge(aSize: SIMD2<Float>, edgeA: Int, slide: Float = 0) -> (point: SIMD2<Float>, axis: SIMD3<Float>)? {
        switch edgeA {
        case 0: return (SIMD2(-aSize.x / 2, slide), SIMD3(0, 1, 0))
        case 1: return (SIMD2(aSize.x / 2, slide), SIMD3(0, 1, 0))
        case 2: return (SIMD2(slide, aSize.y / 2), SIMD3(1, 0, 0))
        case 3: return (SIMD2(slide, -aSize.y / 2), SIMD3(1, 0, 0))
        default: return nil
        }
    }

    /// Thin rectangle along the shared edge in A's local frame (where the break "X" appears).
    public static func seam(aSize: SIMD2<Float>, bSize: SIMD2<Float>, edgeA: Int, slide: Float = 0, thickness: Float = 0.16) -> LocalRect? {
        guard centerOffset(aSize: aSize, bSize: bSize, edgeA: edgeA) != nil else { return nil }
        switch edgeA {
        case 0, 1:
            let lo = max(-aSize.y / 2, slide - bSize.y / 2), hi = min(aSize.y / 2, slide + bSize.y / 2)
            guard hi > lo else { return nil }
            return LocalRect(cx: edgeA == 1 ? aSize.x / 2 : -aSize.x / 2, cy: (lo + hi) / 2, w: thickness, h: hi - lo)
        default:
            let lo = max(-aSize.x / 2, slide - bSize.x / 2), hi = min(aSize.x / 2, slide + bSize.x / 2)
            guard hi > lo else { return nil }
            return LocalRect(cx: (lo + hi) / 2, cy: edgeA == 2 ? aSize.y / 2 : -aSize.y / 2, w: hi - lo, h: thickness)
        }
    }

    /// A merged-edge magnet: for a pair joined across `jointEdge` whose perpendicular sides line up (same width for a
    /// stacked pair, same height for a side-by-side pair), the two collinear sides count as one edge.
    public struct GroupMagnet: Equatable { public var edge: Int; public var slide: Float; public var rect: LocalRect }
    public static func groupMagnets(aSize: SIMD2<Float>, bSize: SIMD2<Float>, jointEdge: Int) -> [GroupMagnet] {
        let tol: Float = 0.02
        switch jointEdge {
        case 2, 3:   // B above / below A → left and right sides merge
            guard abs(aSize.x - bSize.x) < tol else { return [] }
            let s = (jointEdge == 2 ? 1 : -1) * bSize.y / 2
            return [GroupMagnet(edge: 0, slide: s, rect: LocalRect(cx: -(aSize.x / 2 + 0.09), cy: s, w: 0.07, h: 0.07)),
                    GroupMagnet(edge: 1, slide: s, rect: LocalRect(cx: aSize.x / 2 + 0.09, cy: s, w: 0.07, h: 0.07))]
        case 0, 1:   // B left / right of A → top and bottom sides merge
            guard abs(aSize.y - bSize.y) < tol else { return [] }
            let s = (jointEdge == 1 ? 1 : -1) * bSize.x / 2
            return [GroupMagnet(edge: 2, slide: s, rect: LocalRect(cx: s, cy: aSize.y / 2 + 0.2, w: 0.07, h: 0.07)),
                    GroupMagnet(edge: 3, slide: s, rect: LocalRect(cx: s, cy: -(aSize.y / 2 + 0.15), w: 0.07, h: 0.07))]
        default: return []
        }
    }

    /// Where B's display goes in macOS coordinates (y down) so it touches A's display on `edgeA`, centred
    /// (`slidePoints` shifts it along the edge in display points; positive = up / right in the room's frame).
    public static func displayOrigin(a: CGRect, bSize: CGSize, edgeA: Int, slidePoints: CGFloat = 0) -> CGPoint? {
        switch edgeA {
        case 0: return CGPoint(x: a.minX - bSize.width, y: a.midY - bSize.height / 2 - slidePoints)
        case 1: return CGPoint(x: a.maxX, y: a.midY - bSize.height / 2 - slidePoints)
        case 2: return CGPoint(x: a.midX - bSize.width / 2 + slidePoints, y: a.minY - bSize.height)
        case 3: return CGPoint(x: a.midX - bSize.width / 2 + slidePoints, y: a.maxY)
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
