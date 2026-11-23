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
    case moveBar, resizeCorner, rotate, add, close, darken, theme
    case themeChoice(Int)
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
    /// Rotate, Add, Close, Darken world, Theme — left to right above the panel.
    public static let buttonCount = 5
    public static func buttons(width: Float, aspect: Float) -> [LocalRect] {
        let h = heightM(width: width, aspect: aspect)
        let size: Float = 0.06, step = size * 1.3
        return (0..<buttonCount).map { i in LocalRect(cx: (Float(i) - Float(buttonCount - 1) / 2) * step, cy: h / 2 + 0.02 + size / 2, w: size, h: size) }
    }

    /// Theme colour circles in a row right above the theme button (index 0 = plain black).
    public static let themeCount = 9
    public static func themeCircles(width: Float, aspect: Float) -> [LocalRect] {
        let btn = buttons(width: width, aspect: aspect)[4]
        let d: Float = 0.05, step: Float = 0.062
        let y = btn.cy + btn.h / 2 + 0.008 + d / 2
        // Row ends at the theme button's right edge so it stays within reach of the panel's top-right.
        let right = btn.cx + btn.w / 2
        return (0..<themeCount).map { i in LocalRect(cx: right - d / 2 - Float(themeCount - 1 - i) * step, cy: y, w: d, h: d) }
    }

    /// Area in which the AR cursor sticks to the panel plane (panel plus handles).
    public static func hoverArea(width: Float, aspect: Float) -> LocalRect {
        let h = heightM(width: width, aspect: aspect)
        return LocalRect(cx: 0, cy: 0.06, w: width + 0.3, h: h + 0.5)
    }

    /// Corner wins over everything, then buttons, move bar (with 0.01 m slack), content.
    public static func hit(x: Float, y: Float, width: Float, aspect: Float, pickerOpen: Bool = false) -> PanelRegion {
        if pickerOpen {
            let c = themeCircles(width: width, aspect: aspect)
            for (i, r) in c.enumerated() where r.contains(x, y) { return .themeChoice(i) }
            let btn = buttons(width: width, aspect: aspect)[4]
            let top = c[0].cy + c[0].h / 2
            let strip = LocalRect(cx: (c[0].cx - c[0].w / 2 + btn.cx + btn.w / 2) / 2, cy: (btn.cy + top) / 2,
                                  w: (btn.cx + btn.w / 2) - (c[0].cx - c[0].w / 2), h: top - btn.cy)
            if strip.contains(x, y) { return .theme }
        }
        if resizeCorner(width: width, aspect: aspect).contains(x, y) { return .resizeCorner }
        let b = buttons(width: width, aspect: aspect)
        if b[0].contains(x, y) { return .rotate }
        if b[1].contains(x, y) { return .add }
        if b[2].contains(x, y) { return .close }
        if b[3].contains(x, y) { return .darken }
        if b[4].contains(x, y) { return .theme }
        var bar = moveBar(width: width, aspect: aspect); bar.h += 0.02
        if bar.contains(x, y) { return .moveBar }
        let h = heightM(width: width, aspect: aspect)
        if abs(x) <= width / 2, abs(y) <= h / 2 { return .content(u: Double(x / width + 0.5), v: Double(0.5 - y / h)) }
        return .none
    }
}
