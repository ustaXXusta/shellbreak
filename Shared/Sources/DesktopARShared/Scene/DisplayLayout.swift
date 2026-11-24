import Foundation
import CoreGraphics
import simd

/// Pure geometry for arranging macOS displays like physical monitors (rects in global display points).
public enum DisplayLayout {
    /// `ignored` displays (eye toggled off) are never snap targets but are still avoided so nothing overlaps.
    /// Place `moving` against the nearest edge of another display. It may slide freely along that edge
    /// (only the shared side is forced), snapping to flush/centre alignment when close, and never overlaps any display.
    public static func snapped(moving: CGRect, others: [CGRect], ignored: [CGRect] = []) -> CGRect? {
        if others.isEmpty && ignored.isEmpty { return moving }
        if others.isEmpty { return moving }
        let blockers = others + ignored
        var best: CGRect?
        var bestDist = CGFloat.greatestFiniteMagnitude
        let slack: CGFloat = 8, snapRange: CGFloat = 60
        func consider(_ c: CGRect) {
            guard !blockers.contains(where: { $0.intersects(c.insetBy(dx: 1, dy: 1)) }) else { return }
            let d = hypot(c.minX - moving.minX, c.minY - moving.minY)
            if d < bestDist { bestDist = d; best = c }
        }
        func aligned(_ v: CGFloat, _ marks: [CGFloat]) -> CGFloat {
            var out = v
            for m in marks where abs(m - v) < snapRange { out = m }
            return out
        }
        for o in others {
            for x in [o.maxX, o.minX - moving.width] {
                let lo = o.minY - moving.height + slack, hi = o.maxY - slack
                let y = aligned(min(max(moving.minY, lo), hi), [o.minY, o.maxY - moving.height, o.midY - moving.height / 2])
                consider(CGRect(x: x, y: y, width: moving.width, height: moving.height))
            }
            for y in [o.maxY, o.minY - moving.height] {
                let lo = o.minX - moving.width + slack, hi = o.maxX - slack
                let x = aligned(min(max(moving.minX, lo), hi), [o.minX, o.maxX - moving.width, o.midX - moving.width / 2])
                consider(CGRect(x: x, y: y, width: moving.width, height: moving.height))
            }
        }
        return best
    }

    private static func touches(_ a: CGRect, _ b: CGRect) -> Bool {
        let h = abs(a.maxX - b.minX) < 1 || abs(b.maxX - a.minX) < 1
        let v = abs(a.maxY - b.minY) < 1 || abs(b.maxY - a.minY) < 1
        let ovY = min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0
        let ovX = min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0
        return (h && ovY) || (v && ovX)
    }

    /// Contiguous left → right row in the given order, translated so the item at `anchor` sits at origin (0, 0)
    /// (the main display always keeps that origin). Heights are top-aligned.
    public static func row(sizes: [CGSize], anchor: Int) -> [CGPoint] {
        var x: CGFloat = 0
        var origins: [CGPoint] = []
        for s in sizes { origins.append(CGPoint(x: x, y: 0)); x += s.width }
        guard origins.indices.contains(anchor) else { return origins }
        let dx = origins[anchor].x
        return origins.map { CGPoint(x: $0.x - dx, y: 0) }
    }

    /// Order panels left → right by their position along `right` (a world-space axis) relative to the first panel.
    public static func orderLeftToRight(positions: [SIMD3<Float>], right: SIMD3<Float>) -> [Int] {
        guard let p0 = positions.first else { return [] }
        return positions.indices.sorted { a, b in
            let sa = simd_dot(positions[a] - p0, right), sb = simd_dot(positions[b] - p0, right)
            return sa == sb ? a < b : sa < sb
        }
    }
}
