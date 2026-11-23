import MetalKit
import DesktopARShared
import CoreVideo

/// F2 flat renderer: draws the newest decoded frame aspect-fit. Never waits for video.
final class FlatRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?
    private let decoder: VideoDecoder
    private let cursor: CursorOverlay
    private let spritePipeline: MTLRenderPipelineState

    init?(view: MTKView, decoder: VideoDecoder, cursor: CursorOverlay) {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(),
              let lib = dev.makeDefaultLibrary() else { return nil }
        device = dev; queue = q; self.decoder = decoder; self.cursor = cursor
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "quadVertex")
        d.fragmentFunction = lib.makeFunction(name: "quadFragment")
        d.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let p = try? dev.makeRenderPipelineState(descriptor: d) else { return nil }
        pipeline = p
        let sd = MTLRenderPipelineDescriptor()
        sd.vertexFunction = lib.makeFunction(name: "spriteVertex"); sd.fragmentFunction = lib.makeFunction(name: "spriteFragment")
        let ca = sd.colorAttachments[0]!
        ca.pixelFormat = view.colorPixelFormat; ca.isBlendingEnabled = true
        ca.sourceRGBBlendFactor = .one; ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.sourceAlphaBlendFactor = .one; ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let sp = try? dev.makeRenderPipelineState(descriptor: sd) else { return nil }
        spritePipeline = sp
        CVMetalTextureCacheCreate(nil, nil, dev, nil, &cache)
        super.init()
        view.device = dev
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        if let frame = decoder.latest, let cache {
            let pb = frame.pixelBuffer
            var tex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm,
                                                      CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &tex)
            if let tex, let mt = CVMetalTextureGetTexture(tex) {
                let va = Float(CVPixelBufferGetWidth(pb)) / Float(CVPixelBufferGetHeight(pb))
                let da = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
                var scale = va > da ? SIMD2<Float>(1, da / va) : SIMD2<Float>(va / da, 1)
                enc.setRenderPipelineState(pipeline)
                enc.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
                enc.setFragmentTexture(mt, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                let c = cursor.snapshot
                if c.visible, let ct = c.texture {
                    let r = CursorLayout.spriteRect(u: c.u, v: c.v, hotspot: c.hotspot, sizePt: c.sizePt,
                                                    displayWidthPt: c.displayWidthPt, aspect: Double(va), scale: 1.5)
                    struct SU { var center: SIMD2<Float>; var half: SIMD2<Float> }
                    var su = SU(center: SIMD2(Float(r.center.x * 2 - 1) * scale.x, Float(1 - r.center.y * 2) * scale.y),
                                half: SIMD2(Float(r.size.x) * scale.x, Float(r.size.y) * scale.y))
                    enc.setRenderPipelineState(spritePipeline)
                    enc.setVertexBytes(&su, length: MemoryLayout<SU>.size, index: 0)
                    enc.setFragmentTexture(ct, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
