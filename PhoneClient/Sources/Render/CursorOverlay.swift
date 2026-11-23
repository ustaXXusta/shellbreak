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
