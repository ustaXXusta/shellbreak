import MetalKit
import UIKit
import DesktopARShared

/// Screen-mode cursor sprite state (position + image from the Mac), shared with the render thread.
final class CursorOverlay: @unchecked Sendable {
    struct Snapshot {
        var u = 0.5, v = 0.5, visible = false, panelId = "desktop-1"
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

    /// Glass-style handle sprites ("bar", "corner", "rotate", "add", "close", "dark", "theme", "c0"…"c8"), each with a ".hot" variant.
    struct Handles {
        var tex: [String: MTLTexture]
        func get(_ key: String, hot: Bool) -> MTLTexture? { tex[hot ? key + ".hot" : key] }
    }
    private(set) lazy var handles: Handles? = {
        guard let loader else { return nil }
        var out: [String: MTLTexture] = [:]
        func put(_ key: String, _ build: (Bool) -> UIImage) {
            for hot in [false, true] {
                guard let d = build(hot).pngData(), let t = try? loader.newTexture(data: d, options: [.SRGB: false]) else { continue }
                out[hot ? key + ".hot" : key] = t
            }
        }
        let sq = CGSize(width: 160, height: 160)
        put("bar") { Self.glass(size: CGSize(width: 480, height: 72), symbol: nil, hot: $0, radiusFactor: 0.5, grabber: true) }
        put("corner") { Self.glass(size: sq, symbol: "arrow.up.left.and.arrow.down.right", hot: $0) }
        put("rotate") { Self.glass(size: sq, symbol: "rotate.right", hot: $0) }
        put("add") { Self.glass(size: sq, symbol: "plus", hot: $0) }
        put("close") { Self.glass(size: sq, symbol: "xmark", hot: $0) }
        put("dark") { Self.glass(size: sq, symbol: "moon.fill", hot: $0) }
        put("theme") { Self.glass(size: sq, symbol: "paintpalette.fill", hot: $0) }
        let colors: [UIColor?] = [nil, UIColor(red: 0.95, green: 0.15, blue: 0.1, alpha: 1), UIColor(red: 1, green: 0.25, blue: 0.65, alpha: 1),
                                  UIColor(red: 0.35, green: 0.5, blue: 0.75, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1),
                                  UIColor(red: 0.0, green: 0.85, blue: 0.25, alpha: 1), UIColor(red: 0.1, green: 0.9, blue: 1, alpha: 1),
                                  UIColor(red: 0.78, green: 0.5, blue: 0.2, alpha: 1), UIColor(red: 0.55, green: 0.85, blue: 0.25, alpha: 1)]
        for (i, c) in colors.enumerated() { put("c\(i)") { Self.glassDot(size: sq, color: c, hot: $0) } }
        return out.count >= 2 * (7 + colors.count) ? Handles(tex: out) : nil
    }()

    private static func glass(size: CGSize, symbol: String?, hot: Bool, radiusFactor: CGFloat = 0.34, grabber: Bool = false) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { r in
            let c = r.cgContext
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * radiusFactor)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: UIColor(white: 0, alpha: 0.45).cgColor)
            UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: hot ? 0.82 : 0.62).setFill(); path.fill()
            c.restoreGState()
            c.saveGState(); path.addClip()
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor(white: 1, alpha: hot ? 0.42 : 0.30).cgColor, UIColor(white: 1, alpha: 0.03).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            c.restoreGState()
            UIColor(white: 1, alpha: hot ? 0.95 : 0.5).setStroke(); path.lineWidth = hot ? 3 : 2; path.stroke()
            let hl = UIBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.12, dy: 3).applying(.identity), cornerRadius: rect.height * 0.2)
            UIColor(white: 1, alpha: 0.0).setStroke(); hl.stroke()
            if grabber {
                let gw = rect.width * 0.28, gh: CGFloat = 8
                UIColor(white: 1, alpha: hot ? 0.95 : 0.7).setFill()
                UIBezierPath(roundedRect: CGRect(x: rect.midX - gw / 2, y: rect.midY - gh / 2, width: gw, height: gh), cornerRadius: gh / 2).fill()
            }
            if let symbol, let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size.height * 0.42, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                c.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor(white: 0, alpha: 0.5).cgColor)
                img.draw(at: CGPoint(x: (size.width - img.size.width) / 2, y: (size.height - img.size.height) / 2))
            }
        }
    }

    private static func glassDot(size: CGSize, color: UIColor?, hot: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { r in
            let c = r.cgContext
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: UIColor(white: 0, alpha: 0.5).cgColor)
            (color ?? UIColor(white: 0.04, alpha: 1)).setFill(); UIBezierPath(ovalIn: rect).fill()
            c.restoreGState()
            c.saveGState(); UIBezierPath(ovalIn: rect).addClip()
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0.0).cgColor, UIColor(white: 0, alpha: 0.25).cgColor] as CFArray,
                               locations: [0, 0.55, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            c.restoreGState()
            UIColor(white: 1, alpha: hot ? 1 : 0.7).setStroke()
            let ring = UIBezierPath(ovalIn: rect); ring.lineWidth = hot ? 7 : 3.5; ring.stroke()
            if color == nil, let img = UIImage(systemName: "circle.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: size.height * 0.34, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                img.draw(at: CGPoint(x: (size.width - img.size.width) / 2, y: (size.height - img.size.height) / 2))
            }
        }
    }

    var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return snap }

    func update(_ c: CursorState) {
        lock.lock(); snap.u = c.u; snap.v = c.v; snap.visible = c.visible; snap.panelId = c.panelId; lock.unlock()
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
