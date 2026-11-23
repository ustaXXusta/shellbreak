import MetalKit
import ARKit
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
    private let ar: ARSessionController
    private let cameraPipeline: MTLRenderPipelineState
    private var panelWorld: simd_float4x4?
    private let hud: HUDOverlay
    private var changedAt: Date?
    private var eyeTextures: [MTLTexture] = []
    private var eyeSize = (width: 0, height: 0)

    private let panelDistanceM: Float = 1.4
    private let screenMm = LensMath.iPhone13ProScreenMm

    init?(view: MTKView, decoder: VideoDecoder, settings: StereoSettings, cursor: CursorOverlay, ar: ARSessionController, hud: HUDOverlay) {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(), let lib = dev.makeDefaultLibrary() else { return nil }
        device = dev; queue = q; self.decoder = decoder; self.settings = settings; self.cursor = cursor; self.ar = ar; self.hud = hud
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
        guard let cam = pipe("cameraVertex", "cameraFragment", .bgra8Unorm) else { return nil }
        cameraPipeline = cam
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

    /// Panel in front of the camera at its eye height, facing the user, fixed in world space.
    static func placePanel(camera: simd_float4x4, distance: Float) -> simd_float4x4 {
        let pos = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        var fwd = -SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
        fwd.y = 0
        fwd = simd_length(fwd) < 1e-3 ? SIMD3(0, 0, -1) : simd_normalize(fwd)
        let z = -fwd, up = SIMD3<Float>(0, 1, 0), x = simd_normalize(simd_cross(up, z))
        let c = pos + fwd * distance
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(up, 0), SIMD4(z, 0), SIMD4(c, 1)))
    }

    private func cameraTextures(_ frame: ARFrame?) -> (MTLTexture, MTLTexture, ARFrame)? {
        guard let frame, let cache else { return nil }
        let pb = frame.capturedImage
        func tex(_ plane: Int, _ fmt: MTLPixelFormat) -> MTLTexture? {
            var t: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, fmt, CVPixelBufferGetWidthOfPlane(pb, plane),
                                                      CVPixelBufferGetHeightOfPlane(pb, plane), plane, &t)
            return t.flatMap { CVMetalTextureGetTexture($0) }
        }
        guard let y = tex(0, .r8Unorm), let c = tex(1, .rg8Unorm) else { return nil }
        return (y, c, frame)
    }

    /// Layout-mode keys: orbit around the head, depth, size (spec 6.6). Shift = big step.
    private func applyCommands(camera: simd_float4x4, hasFrame: Bool) {
        let cmds = settings.takeCommands()
        if hasFrame, !cmds.isEmpty, var world = panelWorld {
            let head = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
            var center = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            for c in cmds {
                guard let name = LayoutCommandName(rawValue: c.command) else { continue }
                let big: Float = c.shiftHeld ? 4 : 1
                let a: Float = 0.04 * big, d: Float = 0.1 * big, z: Float = c.shiftHeld ? 1.2 : 1.05
                switch name {
                case .moveLeft: center = LayoutMath.moved(center: center, head: head, dYaw: a, dPitch: 0, dRadius: 0)
                case .moveRight: center = LayoutMath.moved(center: center, head: head, dYaw: -a, dPitch: 0, dRadius: 0)
                case .moveUp: center = LayoutMath.moved(center: center, head: head, dYaw: 0, dPitch: a, dRadius: 0)
                case .moveDown: center = LayoutMath.moved(center: center, head: head, dYaw: 0, dPitch: -a, dRadius: 0)
                case .closer: center = LayoutMath.moved(center: center, head: head, dYaw: 0, dPitch: 0, dRadius: -d); hud.flash("Yakın")
                case .farther: center = LayoutMath.moved(center: center, head: head, dYaw: 0, dPitch: 0, dRadius: d); hud.flash("Uzak")
                case .bigger: settings.panelWidthM = LayoutMath.clampedWidth(settings.panelWidthM * z); hud.flash(String(format: "Genişlik %.2f m", settings.panelWidthM))
                case .smaller: settings.panelWidthM = LayoutMath.clampedWidth(settings.panelWidthM / z); hud.flash(String(format: "Genişlik %.2f m", settings.panelWidthM))
                case .faceMe: hud.flash("Bana dön")
                case .bringFront:
                    world = Self.placePanel(camera: camera, distance: panelDistanceM)
                    center = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z); hud.flash("Önüme getir")
                case .togglePassthrough: settings.passthrough.toggle(); hud.flash(settings.passthrough ? "Gerçek dünya" : "VR modu")
                default: break
                }
            }
            panelWorld = LayoutMath.facing(center: center, head: head)
            changedAt = Date()
        }
        if let t = changedAt, Date().timeIntervalSince(t) > 0.3, let w = panelWorld {
            changedAt = nil
            let m = (0..<4).flatMap { c in (0..<4).map { r in w[c][r] } }
            settings.onPanelChanged?(m, settings.panelWidthM)
        }
    }

    func draw(in view: MTKView) {
        let cal = settings.calibration
        let ds = view.drawableSize
        guard ds.width > 0, let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        ensureEyeTextures(cal, drawable: ds)
        guard eyeTextures.count == 2 else { return }
        let frame = ar.latestFrame
        let camT = frame?.camera.transform ?? matrix_identity_float4x4
        if frame != nil, settings.takeRecenter() || panelWorld == nil {
            panelWorld = Self.placePanel(camera: camT, distance: panelDistanceM)
        }
        applyCommands(camera: camT, hasFrame: frame != nil)
        let panelWidthM = settings.panelWidthM
        let panelModel = panelWorld ?? { var m = matrix_identity_float4x4; m.columns.3 = SIMD4(0, 0, -panelDistanceM, 1); return m }()
        let v4 = camT.inverse                      // world -> head (camera) space, full 6DoF
        let video = videoTexture()
        let cameraTex = settings.passthrough ? cameraTextures(frame) : nil
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
            if let (yT, cT, cf) = cameraTex, !cal.testPattern {
                let res = cf.camera.imageResolution, K = cf.camera.intrinsics
                let w = Float(res.width), h = Float(res.height), D: Float = 8
                let fx = K[0][0], fy = K[1][1], cx = K[2][0], cy = K[2][1]
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                struct CU { var mvp: simd_float4x4; var xr: SIMD2<Float>; var yr: SIMD2<Float>; var z: Float }
                var cu = CU(mvp: proj * shift,
                            xr: SIMD2(-cx / fx * D, (w - cx) / fx * D), yr: SIMD2(-(h - cy) / fy * D, cy / fy * D), z: -D)
                enc.setRenderPipelineState(cameraPipeline)
                enc.setVertexBytes(&cu, length: MemoryLayout<CU>.size, index: 0)
                enc.setFragmentTexture(yT, index: 0); enc.setFragmentTexture(cT, index: 1)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            if cal.testPattern || video == nil {
                var asp = Float(aspectEye); var sc = SIMD2<Float>(1, 1)
                enc.setRenderPipelineState(testPipeline)
                enc.setVertexBytes(&sc, length: 8, index: 0)
                enc.setFragmentBytes(&asp, length: 4, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            } else if let (tex, aspect) = video {
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                let model = panelModel
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
                    cm = model * { var t = matrix_identity_float4x4; t.columns.3 = SIMD4(Float(r.center.x - 0.5) * panelWidthM, Float(0.5 - r.center.y) * ph, 0.004, 1); return t }()
                    var cu = U(mvp: proj * shift * v4 * cm, halfSize: SIMD2(Float(r.size.x) * panelWidthM / 2, Float(r.size.y) * ph / 2))
                    enc.setRenderPipelineState(spritePipeline)
                    enc.setVertexBytes(&cu, length: MemoryLayout<U>.size, index: 0)
                    enc.setFragmentTexture(ct, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
            if let (ht, hasp) = hud.current() {
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                var place = simd_float4x4(1); place.columns.3 = SIMD4(0, -0.17, -0.9, 1)
                struct HU { var mvp: simd_float4x4; var halfSize: SIMD2<Float> }
                var hu = HU(mvp: proj * shift * place, halfSize: SIMD2(0.07 * hasp, 0.07))
                enc.setRenderPipelineState(spritePipeline)
                enc.setVertexBytes(&hu, length: MemoryLayout<HU>.size, index: 0)
                enc.setFragmentTexture(ht, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
