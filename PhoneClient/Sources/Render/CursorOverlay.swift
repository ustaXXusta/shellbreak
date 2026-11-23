import MetalKit
import UIKit
import DesktopARShared

/// Screen-mode cursor sprite state (position + image from the Mac), shared with the render thread.
final class CursorOverlay: @unchecked Sendable {
    struct Snapshot {
        var u = 0.5, v = 0.5, visible = false
        var texture: MTLTexture?
        var hotspot = SIMD2<Double>(1, 1), sizePt = SIMD2<Double>(12, 19), displayWidthPt = 1440.0
    }
    private let lock = NSLock()
    private var snap = Snapshot()
    private var loader: MTKTextureLoader?
    private var currentImageId = -1

    init() {
        if let dev = MTLCreateSystemDefaultDevice() {
            loader = MTKTextureLoader(device: dev)
            if let tex = fallbackArrow() { snap.texture = tex }
        }
    }

    /// Layout-mode AR cursor: a pointing hand (fingertip at the top centre), so it differs from the macOS arrow.
    private(set) lazy var handTexture: MTLTexture? = {
        let font = UIFont.systemFont(ofSize: 110)
        let text = "👆" as NSString
        let size = text.size(withAttributes: [.font: font])
        let img = UIGraphicsImageRenderer(size: size).image { _ in text.draw(at: .zero, withAttributes: [.font: font]) }
        guard let data = img.pngData() else { return nil }
        return try? loader?.newTexture(data: data, options: [.SRGB: false])
    }()

    struct Handles { var bar, corner, rotate, add, close, dark, theme: MTLTexture; var circles: [MTLTexture] }
    /// Flat handle sprites drawn around a hovered panel in layout mode.
    private(set) lazy var handles: Handles? = {
        func glyph(_ text: String, size: CGSize, bg: UIColor) -> MTLTexture? {
            let img = UIGraphicsImageRenderer(size: size).image { _ in
                bg.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(size.width, size.height) / 2.5).fill()
                guard !text.isEmpty else { return }
                let font = UIFont.systemFont(ofSize: size.height * 0.7, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let t = text as NSString, ts = t.size(withAttributes: attrs)
                t.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
            }
            guard let d = img.pngData() else { return nil }
            return try? loader?.newTexture(data: d, options: [.SRGB: false])
        }
        let sq = CGSize(width: 96, height: 96)
        guard let bar = glyph("", size: CGSize(width: 320, height: 48), bg: UIColor(white: 0.9, alpha: 0.85)),
              let corner = glyph("⤡", size: sq, bg: UIColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.9)),
              let rot = glyph("↻", size: sq, bg: UIColor(white: 0.25, alpha: 0.9)),
              let add = glyph("+", size: sq, bg: UIColor(red: 0.15, green: 0.6, blue: 0.3, alpha: 0.9)),
              let close = glyph("×", size: sq, bg: UIColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 0.9)) else { return nil }
        guard let dark = glyph("🌙", size: sq, bg: UIColor(white: 0.12, alpha: 0.92)),
              let theme = glyph("🎨", size: sq, bg: UIColor(white: 0.25, alpha: 0.92)) else { return nil }
        let colors: [UIColor] = [.black, UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1), UIColor(red: 1, green: 0.25, blue: 0.65, alpha: 1),
                                 UIColor(red: 0.3, green: 0.42, blue: 0.6, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1),
                                 UIColor(red: 0.0, green: 0.8, blue: 0.2, alpha: 1), UIColor(red: 0.1, green: 0.9, blue: 1, alpha: 1),
                                 UIColor(red: 0.72, green: 0.45, blue: 0.2, alpha: 1), UIColor(red: 0.55, green: 0.85, blue: 0.25, alpha: 1)]
        let circles: [MTLTexture] = colors.compactMap { c in
            let sz = CGSize(width: 96, height: 96)
            let img = UIGraphicsImageRenderer(size: sz).image { _ in
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(origin: .zero, size: sz)).fill()
                c.setFill(); UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 80, height: 80)).fill()
            }
            guard let d = img.pngData() else { return nil }
            return try? loader?.newTexture(data: d, options: [.SRGB: false])
        }
        guard circles.count == colors.count else { return nil }
        return Handles(bar: bar, corner: corner, rotate: rot, add: add, close: close, dark: dark, theme: theme, circles: circles)
    }()

    var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return snap }

    func update(_ c: CursorState) {
        lock.lock(); snap.u = c.u; snap.v = c.v; snap.visible = c.visible; lock.unlock()
    }

    func update(_ img: CursorImage) {
        guard let data = Data(base64Encoded: img.pngBase64), let loader else { return }
        let opts: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
        loader.newTexture(data: data, options: opts) { [weak self] tex, _ in
            guard let self, let tex else { return }
            self.lock.lock()
            self.snap.texture = tex
            self.snap.hotspot = SIMD2(img.hotspotX, img.hotspotY)
            self.snap.sizePt = SIMD2(max(img.widthPt, 1), max(img.heightPt, 1))
            if let w = img.displayWidthPt, w > 0 { self.snap.displayWidthPt = w }
            self.lock.unlock()
        }
    }

    private func fallbackArrow() -> MTLTexture? {
        let size = CGSize(width: 24, height: 38)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 2, y: 30)); p.addLine(to: CGPoint(x: 9, y: 24))
            p.addLine(to: CGPoint(x: 14, y: 36)); p.addLine(to: CGPoint(x: 19, y: 34)); p.addLine(to: CGPoint(x: 14, y: 22))
            p.addLine(to: CGPoint(x: 23, y: 22)); p.close()
            UIColor.black.setStroke(); UIColor.white.setFill(); p.lineWidth = 2; p.fill(); p.stroke()
        }
        guard let data = img.pngData() else { return nil }
        return try? loader?.newTexture(data: data, options: [.SRGB: false])
    }
}
