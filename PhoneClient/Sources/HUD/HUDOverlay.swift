import MetalKit
import UIKit

/// Short head-locked notices ("DÜZEN MODU", "Yakın", …) rendered from UIKit text into small textures.
final class HUDOverlay: @unchecked Sendable {
    private let lock = NSLock()
    private var persistent: String?
    private var transient: String?
    private var transientUntil = Date.distantPast
    private var cache: [String: (MTLTexture, Float)] = [:]
    private let loader: MTKTextureLoader?

    init() { loader = MTLCreateSystemDefaultDevice().map { MTKTextureLoader(device: $0) } }

    func setPersistent(_ text: String?) { lock.lock(); persistent = text; lock.unlock() }
    func flash(_ text: String, seconds: Double = 1.5) {
        lock.lock(); transient = text; transientUntil = Date().addingTimeInterval(seconds); lock.unlock()
    }

    /// Texture and width/height aspect of what should be on screen now, if anything.
    func current() -> (MTLTexture, Float)? {
        lock.lock()
        let text = Date() < transientUntil ? transient : persistent
        let hit = text.flatMap { cache[$0] }
        lock.unlock()
        guard let text else { return nil }
        if let hit { return hit }
        guard let loader else { return nil }
        let font = UIFont.systemFont(ofSize: 44, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 20
        let imgSize = CGSize(width: ceil(size.width) + pad * 2, height: ceil(size.height) + pad)
        let img = UIGraphicsImageRenderer(size: imgSize).image { _ in
            UIColor(white: 0, alpha: 0.65).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: imgSize), cornerRadius: imgSize.height / 2).fill()
            (text as NSString).draw(at: CGPoint(x: pad, y: pad / 2), withAttributes: attrs)
        }
        guard let cg = img.cgImage, let tex = try? loader.newTexture(cgImage: cg, options: [.SRGB: false]) else { return nil }
        let entry = (tex, Float(imgSize.width / imgSize.height))
        lock.lock(); cache[text] = entry; lock.unlock()
        return entry
    }
}
