import Foundation
import CoreGraphics
import simd

/// Pure geometry for arranging macOS displays like physical monitors (rects in global display points).
public enum DisplayLayout {
    /// Snap `moving` so one of its edges touches an edge of another display (nearest valid spot), keeping them adjacent
    /// and never overlapping. Returns nil when no overlap-free position exists.
    public static func snapped(moving: CGRect, others: [CGRect]) -> CGRect? {
        var best = moving
        var bestDist = CGFloat.greatestFiniteMagnitude
        var candidates: [CGRect] = [moving]
        for o in others {
            // Horizontal adjacency (left/right of o), vertical offset kept or aligned to o's top/bottom.
            for x in [o.maxX, o.minX - moving.width] {
                for y in [moving.minY, o.minY, o.maxY - moving.height] {
                    candidates.append(CGRect(x: x, y: y, width: moving.width, height: moving.height))
                }
            }
            // Vertical adjacency (above/below o).
            for y in [o.maxY, o.minY - moving.height] {
                for x in [moving.minX, o.minX, o.maxX - moving.width] {
                    candidates.append(CGRect(x: x, y: y, width: moving.width, height: moving.height))
                }
            }
        }
        for c in candidates where !others.contains(where: { $0.intersects(c.insetBy(dx: 1, dy: 1)) }) {
            let dist = hypot(c.minX - moving.minX, c.minY - moving.minY)
            let touching = others.isEmpty || others.contains { touches($0, c) }
            guard touching else { continue }
            if dist < bestDist { bestDist = dist; best = c }
        }
        return bestDist == .greatestFiniteMagnitude ? nil : best
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
