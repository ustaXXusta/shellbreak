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
    case moveBar, rotate, tilt, add, close, darken, theme
    /// 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
    case resizeCorner(Int)
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
    /// The four resize corners (0.1 m squares centred on the panel corners): TL, TR, BL, BR.
    public static func corners(width: Float, aspect: Float) -> [LocalRect] {
        let hw = width / 2, hh = heightM(width: width, aspect: aspect) / 2
        return [(-hw, hh), (hw, hh), (-hw, -hh), (hw, -hh)].map { LocalRect(cx: $0.0, cy: $0.1, w: 0.1, h: 0.1) }
    }
    /// Rotate, Tilt, Add, Close, Darken world, Theme — left to right above the panel.
    public static let buttonCount = 6
    public static func buttons(width: Float, aspect: Float) -> [LocalRect] {
        let h = heightM(width: width, aspect: aspect)
        let size: Float = 0.06, step = size * 1.3
        return (0..<buttonCount).map { i in LocalRect(cx: (Float(i) - Float(buttonCount - 1) / 2) * step, cy: h / 2 + 0.02 + size / 2, w: size, h: size) }
    }

    /// Theme colour circles in a row right above the theme button (index 0 = plain black).
    public static let themeCount = 9
    public static func themeCircles(width: Float, aspect: Float) -> [LocalRect] {
        let btn = buttons(width: width, aspect: aspect)[5]
        let d: Float = 0.05, step: Float = 0.062
        let y = btn.cy + btn.h / 2 + 0.008 + d / 2
        // Row ends at the theme button's right edge so it stays within reach of the panel's top-right.
        let right = btn.cx + btn.w / 2
        return (0..<themeCount).map { i in LocalRect(cx: right - d / 2 - Float(themeCount - 1 - i) * step, cy: y, w: d, h: d) }
    }

    /// Area in which the AR cursor sticks to the panel plane (panel plus handles).
    public static func hoverArea(width: Float, aspect: Float) -> LocalRect {
        let h = heightM(width: width, aspect: aspect)
        var minX = -(width + 0.3) / 2, maxX = (width + 0.3) / 2
        let minY = -(h + 0.3) / 2 - 0.1
        var maxY = h / 2 + 0.3
        for c in themeCircles(width: width, aspect: aspect) { minX = min(minX, c.cx - c.w / 2 - 0.05); maxX = max(maxX, c.cx + c.w / 2 + 0.05); maxY = max(maxY, c.cy + c.h / 2 + 0.05) }
        return LocalRect(cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, w: maxX - minX, h: maxY - minY)
    }

    /// Corner wins over everything, then buttons, move bar (with 0.01 m slack), content.
    public static func hit(x: Float, y: Float, width: Float, aspect: Float, pickerOpen: Bool = false) -> PanelRegion {
        if pickerOpen {
            let c = themeCircles(width: width, aspect: aspect)
            for (i, r) in c.enumerated() where r.contains(x, y) { return .themeChoice(i) }
            let btn = buttons(width: width, aspect: aspect)[5]
            let top = c[0].cy + c[0].h / 2
            let strip = LocalRect(cx: (c[0].cx - c[0].w / 2 + btn.cx + btn.w / 2) / 2, cy: (btn.cy + top) / 2,
                                  w: (btn.cx + btn.w / 2) - (c[0].cx - c[0].w / 2), h: top - btn.cy)
            if strip.contains(x, y) { return .theme }
        }
        for (i, r) in corners(width: width, aspect: aspect).enumerated() where r.contains(x, y) { return .resizeCorner(i) }
        let b = buttons(width: width, aspect: aspect)
        if b[0].contains(x, y) { return .rotate }
        if b[1].contains(x, y) { return .tilt }
        if b[2].contains(x, y) { return .add }
        if b[3].contains(x, y) { return .close }
        if b[4].contains(x, y) { return .darken }
        if b[5].contains(x, y) { return .theme }
        var bar = moveBar(width: width, aspect: aspect); bar.h += 0.02
        if bar.contains(x, y) { return .moveBar }
        let h = heightM(width: width, aspect: aspect)
        if abs(x) <= width / 2, abs(y) <= h / 2 { return .content(u: Double(x / width + 0.5), v: Double(0.5 - y / h)) }
        return .none
    }
}
