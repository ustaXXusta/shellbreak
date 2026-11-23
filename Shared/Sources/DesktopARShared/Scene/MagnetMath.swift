import Foundation
import CoreGraphics
import simd

/// Magnet joins between panels. Corner indices (panel space, +Y up): 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
public enum MagnetMath {
    public enum Relation: Equatable { case rightOf, leftOf, above, below }   // where B sits relative to A

    public static func sign(_ corner: Int) -> (x: Float, y: Float) { (corner % 2 == 1 ? 1 : -1, corner < 2 ? 1 : -1) }
    public static func corner(sx: Float, sy: Float) -> Int { (sy > 0 ? 0 : 2) + (sx > 0 ? 1 : 0) }

    /// B's corner is normalised so the two panels share an edge: diagonal picks keep A's top/bottom side;
    /// the same corner on both panels is not a valid join.
    public static func normalizedCornerB(cornerA: Int, cornerB: Int) -> Int? {
        let a = sign(cornerA), b = sign(cornerB)
        if a.x == b.x && a.y == b.y { return nil }
        if a.x != b.x && a.y != b.y { return corner(sx: b.x, sy: a.y) }
        return cornerB
    }

    public static func relation(cornerA: Int, cornerB: Int) -> Relation? {
        guard let nb = normalizedCornerB(cornerA: cornerA, cornerB: cornerB) else { return nil }
        let a = sign(cornerA), b = sign(nb)
        if a.x != b.x { return a.x > 0 ? .rightOf : .leftOf }
        return a.y > 0 ? .above : .below
    }

    /// Centre of B in A's local frame (metres) so that B's corner meets A's corner and the panels share an edge.
    public static func centerOffset(aSize: SIMD2<Float>, bSize: SIMD2<Float>, cornerA: Int, cornerB: Int) -> SIMD2<Float>? {
        guard let nb = normalizedCornerB(cornerA: cornerA, cornerB: cornerB) else { return nil }
        let a = sign(cornerA), b = sign(nb)
        let pa = SIMD2(a.x * aSize.x / 2, a.y * aSize.y / 2), pb = SIMD2(b.x * bSize.x / 2, b.y * bSize.y / 2)
        return pa - pb
    }

    /// Seam between a joined pair in A's local frame (a thin rectangle along the shared edge).
    public static func seam(aSize: SIMD2<Float>, bSize: SIMD2<Float>, cornerA: Int, cornerB: Int, thickness: Float = 0.12) -> LocalRect? {
        guard let off = centerOffset(aSize: aSize, bSize: bSize, cornerA: cornerA, cornerB: cornerB),
              let rel = relation(cornerA: cornerA, cornerB: cornerB) else { return nil }
        let aMin = SIMD2(-aSize.x / 2, -aSize.y / 2), aMax = SIMD2(aSize.x / 2, aSize.y / 2)
        let bMin = off - bSize / 2, bMax = off + bSize / 2
        switch rel {
        case .rightOf, .leftOf:
            let lo = max(aMin.y, bMin.y), hi = min(aMax.y, bMax.y)
            guard hi > lo else { return nil }
            return LocalRect(cx: rel == .rightOf ? aMax.x : aMin.x, cy: (lo + hi) / 2, w: thickness, h: hi - lo)
        case .above, .below:
            let lo = max(aMin.x, bMin.x), hi = min(aMax.x, bMax.x)
            guard hi > lo else { return nil }
            return LocalRect(cx: (lo + hi) / 2, cy: rel == .above ? aMax.y : aMin.y, w: hi - lo, h: thickness)
        }
    }

    /// Where B's display goes in macOS coordinates (y down) so it touches A's display the same way.
    public static func displayOrigin(a: CGRect, bSize: CGSize, cornerA: Int, cornerB: Int) -> CGPoint? {
        guard let rel = relation(cornerA: cornerA, cornerB: cornerB) else { return nil }
        let top = sign(cornerA).y > 0, right = sign(cornerA).x > 0
        switch rel {
        case .rightOf: return CGPoint(x: a.maxX, y: top ? a.minY : a.maxY - bSize.height)
        case .leftOf: return CGPoint(x: a.minX - bSize.width, y: top ? a.minY : a.maxY - bSize.height)
        case .above: return CGPoint(x: right ? a.maxX - bSize.width : a.minX, y: a.minY - bSize.height)
        case .below: return CGPoint(x: right ? a.maxX - bSize.width : a.minX, y: a.maxY)
        }
    }
}
