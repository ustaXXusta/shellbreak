import Foundation

/// Rectangle in panel-local metres (panel centred at the origin, +X right, +Y up).
public struct LocalRect: Equatable {
    public var cx: Float, cy: Float, w: Float, h: Float
    public init(cx: Float, cy: Float, w: Float, h: Float) { self.cx = cx; self.cy = cy; self.w = w; self.h = h }
    public var center: SIMD2<Float> { SIMD2(cx, cy) }
    public func contains(_ x: Float, _ y: Float) -> Bool { abs(x - cx) <= w / 2 && abs(y - cy) <= h / 2 }
}

public enum PanelRegion: Equatable {
    case none
    case content(u: Double, v: Double)
    case moveBar, resizeCorner, rotate, add, close
}

/// Handle layout shared by rendering and hit testing (spec 6.4).
public enum PanelHandleGeometry {
    public static func heightM(width: Float, aspect: Float) -> Float { width / aspect }

    public static func moveBar(width: Float, aspect: Float) -> LocalRect {
        let h = heightM(width: width, aspect: aspect)
        let bw = max(0.15, min(0.6, width * 0.35))
        return LocalRect(cx: 0, cy: -h / 2 - 0.02 - 0.0175, w: bw, h: 0.035)
    }
    public static func resizeCorner(width: Float, aspect: Float) -> LocalRect {
        LocalRect(cx: width / 2, cy: -heightM(width: width, aspect: aspect) / 2, w: 0.08, h: 0.08)
    }
    /// Rotate, Add, Close — left to right above the panel.
    public static func buttons(width: Float, aspect: Float) -> [LocalRect] {
        let h = heightM(width: width, aspect: aspect)
        let size: Float = 0.06, step = size * 1.3
        return (0..<3).map { i in LocalRect(cx: (Float(i) - 1) * step, cy: h / 2 + 0.02 + size / 2, w: size, h: size) }
    }

    /// Area in which the AR cursor sticks to the panel plane (panel plus handles).
    public static func hoverArea(width: Float, aspect: Float) -> LocalRect {
        let h = heightM(width: width, aspect: aspect)
        return LocalRect(cx: 0, cy: 0, w: width + 0.3, h: h + 0.35)
    }

    /// Corner wins over everything, then buttons, move bar (with 0.01 m slack), content.
    public static func hit(x: Float, y: Float, width: Float, aspect: Float) -> PanelRegion {
        if resizeCorner(width: width, aspect: aspect).contains(x, y) { return .resizeCorner }
        let b = buttons(width: width, aspect: aspect)
        if b[0].contains(x, y) { return .rotate }
        if b[1].contains(x, y) { return .add }
        if b[2].contains(x, y) { return .close }
        var bar = moveBar(width: width, aspect: aspect); bar.h += 0.02
        if bar.contains(x, y) { return .moveBar }
        let h = heightM(width: width, aspect: aspect)
        if abs(x) <= width / 2, abs(y) <= h / 2 { return .content(u: Double(x / width + 0.5), v: Double(0.5 - y / h)) }
        return .none
    }
}
