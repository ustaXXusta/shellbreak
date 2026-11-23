import MetalKit
import CoreVideo
import simd
import DesktopARShared

/// F3: renders the video panel world-fixed into two eye textures, then distorts both into the screen halves.
final class StereoRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let panelPipeline: MTLRenderPipelineState
    private let testPipeline: MTLRenderPipelineState
    private let distortPipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?
    private let decoder: VideoDecoder
    private let settings: StereoSettings
    private let cursor: CursorOverlay
    private let spritePipeline: MTLRenderPipelineState
    private let head = HeadPose()
    private var eyeTextures: [MTLTexture] = []
    private var eyeSize = (width: 0, height: 0)
    private var framesSeen = 0

    private let panelWidthM: Float = 1.3
    private let panelDistanceM: Float = 1.4
    private let screenMm = LensMath.iPhone13ProScreenMm

    init?(view: MTKView, decoder: VideoDecoder, settings: StereoSettings, cursor: CursorOverlay) {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(), let lib = dev.makeDefaultLibrary() else { return nil }
        device = dev; queue = q; self.decoder = decoder; self.settings = settings; self.cursor = cursor
        func pipe(_ v: String, _ f: String, _ fmt: MTLPixelFormat) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v); d.fragmentFunction = lib.makeFunction(name: f)
            d.colorAttachments[0].pixelFormat = fmt
            return try? dev.makeRenderPipelineState(descriptor: d)
        }
        guard let a = pipe("panelVertex", "quadFragment", .bgra8Unorm),
              let b = pipe("quadVertex", "testFragment", .bgra8Unorm),
              let c = pipe("quadVertex", "distortFragment", view.colorPixelFormat) else { return nil }
        let sd = MTLRenderPipelineDescriptor()
        sd.vertexFunction = lib.makeFunction(name: "panelVertex"); sd.fragmentFunction = lib.makeFunction(name: "spriteFragment")
        let ca = sd.colorAttachments[0]!
        ca.pixelFormat = .bgra8Unorm; ca.isBlendingEnabled = true
        ca.sourceRGBBlendFactor = .one; ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.sourceAlphaBlendFactor = .one; ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let sp = try? dev.makeRenderPipelineState(descriptor: sd) else { return nil }
        spritePipeline = sp
        panelPipeline = a; testPipeline = b; distortPipeline = c
        CVMetalTextureCacheCreate(nil, nil, dev, nil, &cache)
        super.init()
        view.device = dev
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func ensureEyeTextures(_ cal: Calibration, drawable: CGSize) {
        let t = LensMath.eyeTargetSize(screenWidthPx: Int(drawable.width), screenHeightPx: Int(drawable.height), supersample: cal.supersample)
        if t.width == eyeSize.width && t.height == eyeSize.height && eyeTextures.count == 2 { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: t.width, height: t.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        eyeTextures = (0..<2).compactMap { _ in device.makeTexture(descriptor: d) }
        eyeSize = t
    }

    private func videoTexture() -> (MTLTexture, Float)? {
        guard let frame = decoder.latest, let cache else { return nil }
        let pb = frame.pixelBuffer
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        var tex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, w, h, 0, &tex)
        guard let tex, let mt = CVMetalTextureGetTexture(tex) else { return nil }
        return (mt, Float(w) / Float(h))
    }

    func draw(in view: MTKView) {
        let cal = settings.calibration
        let ds = view.drawableSize
        guard ds.width > 0, let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        ensureEyeTextures(cal, drawable: ds)
        guard eyeTextures.count == 2 else { return }
        if decoder.latest != nil { framesSeen += 1 }
        head.invert = settings.invertHead
        if settings.takeRecenter() || framesSeen == 90 { head.recenter() }

        let video = videoTexture()
        let rot = head.viewRotation()
        var v4 = simd_float4x4(1)
        v4.columns.0 = SIMD4(rot.columns.0, 0); v4.columns.1 = SIMD4(rot.columns.1, 0); v4.columns.2 = SIMD4(rot.columns.2, 0)
        let ipd = Float(cal.lensSeparationMm) / 1000
        let aspectEye = Double(eyeSize.width) / Double(eyeSize.height)
        let proj = LensMath.perspective(verticalFovDegrees: cal.fovDegrees, aspect: aspectEye, near: 0.05, far: 50)

        for eye in 0..<2 {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = eyeTextures[eye]
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.01, blue: 0.012, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            if cal.testPattern || video == nil {
                var asp = Float(aspectEye); var sc = SIMD2<Float>(1, 1)
                enc.setRenderPipelineState(testPipeline)
                enc.setVertexBytes(&sc, length: 8, index: 0)
                enc.setFragmentBytes(&asp, length: 4, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            } else if let (tex, aspect) = video {
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                var model = simd_float4x4(1)
                model.columns.3 = SIMD4(0, 0, -panelDistanceM, 1)
                struct U { var mvp: simd_float4x4; var halfSize: SIMD2<Float> }
                var u = U(mvp: proj * shift * v4 * model, halfSize: SIMD2(panelWidthM / 2, panelWidthM / 2 / aspect))
                enc.setRenderPipelineState(panelPipeline)
                enc.setVertexBytes(&u, length: MemoryLayout<U>.size, index: 0)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                let c = cursor.snapshot
                if c.visible, let ct = c.texture {
                    let r = CursorLayout.spriteRect(u: c.u, v: c.v, hotspot: c.hotspot, sizePt: c.sizePt,
                                                    displayWidthPt: c.displayWidthPt, aspect: Double(aspect), scale: 1.5)
                    let ph = panelWidthM / aspect
                    var cm = model
                    cm.columns.3 = SIMD4(Float(r.center.x - 0.5) * panelWidthM, Float(0.5 - r.center.y) * ph, -panelDistanceM + 0.004, 1)
                    var cu = U(mvp: proj * shift * v4 * cm, halfSize: SIMD2(Float(r.size.x) * panelWidthM / 2, Float(r.size.y) * ph / 2))
                    enc.setRenderPipelineState(spritePipeline)
                    enc.setVertexBytes(&cu, length: MemoryLayout<U>.size, index: 0)
                    enc.setFragmentTexture(ct, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
            enc.endEncoding()
        }

        guard let rpd = view.currentRenderPassDescriptor, let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(distortPipeline)
        let half = ds.width / 2
        for eye in 0..<2 {
            enc.setViewport(MTLViewport(originX: Double(eye) * half, originY: 0, width: half, height: ds.height, znear: 0, zfar: 1))
            let lc = LensMath.lensCenter(separationMm: cal.lensSeparationMm, verticalOffsetMm: cal.verticalOffsetMm,
                                         screenWidthMm: screenMm.width, screenHeightMm: screenMm.height, eye: eye == 0 ? .left : .right)
            struct P { var lensCenter: SIMD2<Float>; var aspect: Float; var k1: Float; var k2: Float; var chroma: Float
                       var sharpen: Float; var maskRadius: Float; var texel: SIMD2<Float> }
            var p = P(lensCenter: SIMD2(Float(lc.x), Float(lc.y)), aspect: Float(half / ds.height), k1: Float(cal.k1), k2: Float(cal.k2),
                      chroma: Float(cal.chromaticAberration), sharpen: Float(cal.sharpen), maskRadius: 1.0,
                      texel: SIMD2(1 / Float(eyeSize.width), 1 / Float(eyeSize.height)))
            var sc = SIMD2<Float>(1, 1)
            enc.setVertexBytes(&sc, length: 8, index: 0)
            enc.setFragmentBytes(&p, length: MemoryLayout<P>.size, index: 0)
            enc.setFragmentTexture(eyeTextures[eye], index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
