import MetalKit
import QuartzCore
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
    private let themePipeline: MTLRenderPipelineState
    private let ar: ARSessionController
    private let cameraPipeline: MTLRenderPipelineState
    private var panelWorld: simd_float4x4?
    private let hud: HUDOverlay
    private var changedAt: Date?
    private var arYaw: Float = 0, arPitch: Float = 0
    private var wasLayout = false
    /// AR cursor placement for the current frame: world transform of the hand sprite, and u/v when over the panel.
    private var handModel: simd_float4x4?
    private var handUV: (Double, Double)?
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
        guard let th = pipe("quadVertex", "themeFragment", .bgra8Unorm) else { return nil }
        themePipeline = th
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
            panelWorld = oriented(center: center, head: head)
            changedAt = Date()
        }
        if let t = changedAt, Date().timeIntervalSince(t) > 0.3, let w = panelWorld {
            changedAt = nil
            let m = (0..<4).flatMap { c in (0..<4).map { r in w[c][r] } }
            settings.onPanelChanged?(m, settings.panelWidthM)
        }
    }

    private enum Drag { case move, resize }
    private var drag: Drag?
    private var dragLocal = SIMD2<Float>(0, 0)       // handle point the hand stays pinned to while dragging
    private var hover: PanelRegion = .none
    private var handlesVisible = false
    private var pickerOpen = false
    private var panelRoll: Float = 0
    private func oriented(center: SIMD3<Float>, head: SIMD3<Float>) -> simd_float4x4 {
        let f = LayoutMath.facing(center: center, head: head)
        guard panelRoll != 0 else { return f }
        let c = cos(panelRoll), s = sin(panelRoll)
        var r = matrix_identity_float4x4
        r.columns.0 = SIMD4(c, s, 0, 0); r.columns.1 = SIMD4(-s, c, 0, 0)
        return f * r
    }
    static let themeNames = ["Siyah", "Lav lambası", "Vice City", "Yağmur", "Güneşli", "Matrix", "Cyberpunk", "Steampunk", "Solarpunk"]

    /// Layout-mode mouse: steer a head-relative ray, hit-test it against the panel and its handles,
    /// drag the move bar / resize corner, click content → enter screen mode there.
    private func updateARCursor(camera: simd_float4x4, hasFrame: Bool, aspect: Float) {
        let layout = settings.layoutActive
        if layout != wasLayout { wasLayout = layout; arYaw = 0; arPitch = 0; drag = nil }
        handModel = nil; handUV = nil; handlesVisible = false; hover = .none
        guard layout, hasFrame, var panel = panelWorld else { pickerOpen = false; _ = settings.takeInputs(); drag = nil; return }
        let head = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        let width = settings.panelWidthM
        let inputs = settings.takeInputs()
        // Resolve what is under the ray first (using the ray before this frame's movement while dragging).
        func rayHit() -> (point: SIMD3<Float>, local: SIMD2<Float>, t: Float, d: SIMD3<Float>)? {
            let rot = simd_float3x3(SIMD3(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z),
                                    SIMD3(camera.columns.1.x, camera.columns.1.y, camera.columns.1.z),
                                    SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z))
            let d = simd_normalize(rot * LayoutMath.direction(yaw: arYaw, pitch: arPitch))
            let n = SIMD3(panel.columns.2.x, panel.columns.2.y, panel.columns.2.z)
            let c = SIMD3(panel.columns.3.x, panel.columns.3.y, panel.columns.3.z)
            let denom = simd_dot(d, n)
            guard abs(denom) > 1e-4 else { return nil }
            let t = simd_dot(c - head, n) / denom
            guard t > 0.1 else { return nil }
            let p = head + d * t
            let l = panel.inverse * SIMD4(p, 1)
            return (p, SIMD2(l.x, l.y), t, d)
        }
        for i in inputs {
            switch i.kind {
            case "move":
                if let dr = drag {
                    var center = SIMD3(panel.columns.3.x, panel.columns.3.y, panel.columns.3.z)
                    switch dr {
                    case .move:
                        center = LayoutMath.moved(center: center, head: head, dYaw: -Float(i.dx) * 0.0022, dPitch: -Float(i.dy) * 0.0022, dRadius: 0)
                        panel = oriented(center: center, head: head)
                        panelWorld = panel
                    case .resize:
                        settings.panelWidthM = LayoutMath.clampedWidth(settings.panelWidthM * (1 + Float(i.dx + i.dy) * 0.003))
                    }
                    changedAt = Date()
                } else {
                    arYaw = max(-0.6, min(0.6, arYaw - Float(i.dx) * 0.0022))
                    arPitch = max(-0.45, min(0.45, arPitch - Float(i.dy) * 0.0022))
                }
            case "down":
                if drag == nil {
                    let hit = rayHit()
                    let region = hit.map { PanelHandleGeometry.hit(x: $0.local.x, y: $0.local.y, width: settings.panelWidthM, aspect: aspect, pickerOpen: pickerOpen) } ?? .none
                    // The picker stays open until a theme is chosen or something else is clicked.
                    switch region { case .theme: break; case .themeChoice: pickerOpen = false; default: pickerOpen = false }
                    switch region {
                    case .content(let u, let v): settings.onEnterScreen?(u, v)
                    case .moveBar: drag = .move; dragLocal = PanelHandleGeometry.moveBar(width: settings.panelWidthM, aspect: aspect).center
                    case .resizeCorner: drag = .resize; dragLocal = PanelHandleGeometry.resizeCorner(width: settings.panelWidthM, aspect: aspect).center
                    case .rotate:
                        panelRoll = panelRoll == 0 ? .pi / 2 : 0
                        panelWorld = oriented(center: SIMD3(panel.columns.3.x, panel.columns.3.y, panel.columns.3.z), head: head)
                        panel = panelWorld ?? panel; changedAt = Date()
                        hud.flash(panelRoll == 0 ? "Yatay" : "Dikey")
                    case .darken: settings.passthrough.toggle(); hud.flash(settings.passthrough ? "Gerçek dünya" : "Dünya karartıldı")
                    case .theme: break
                    case .themeChoice(let i):
                        if settings.passthrough { hud.flash("Önce 🌙 ile dünyayı karart") }
                        else { settings.theme = i; hud.flash(Self.themeNames[i]) }
                    case .add: settings.onAddDisplay?(); hud.flash("Yeni ekran isteği gönderildi")
                    case .close: hud.flash("Kapatma F5'te geliyor")
                    case .none: break
                    }
                }
            case "up": drag = nil
            default: break
            }
        }
        let w = settings.panelWidthM
        var handHalfSize: Float = 0.045
        var model: simd_float4x4
        if let dr = drag {
            // Pinned to the grabbed handle while the panel moves under the mouse.
            _ = dr
            let p = panel * SIMD4(dragLocal.x, dragLocal.y, 0.01, 1)
            model = panel; model.columns.3 = p
            handlesVisible = true; hover = dr == .move ? .moveBar : .resizeCorner
            handHalfSize = 0.0225 * 1.4
        } else if let h = rayHit() {
            let region = PanelHandleGeometry.hit(x: h.local.x, y: h.local.y, width: w, aspect: aspect, pickerOpen: pickerOpen)
            if region == .theme { pickerOpen = true }
            let area = PanelHandleGeometry.hoverArea(width: w, aspect: aspect)
            if area.contains(h.local.x, h.local.y) {
                hover = region; handlesVisible = true
                if case .content(let u, let v) = region { handUV = (u, v) }
                model = panel; model.columns.3 = SIMD4(h.point + SIMD3(panel.columns.2.x, panel.columns.2.y, panel.columns.2.z) * 0.012, 1)
                handHalfSize = 0.0225 * max(h.t, 0.8)
            } else {
                model = camera; model.columns.3 = SIMD4(h.point, 1); handHalfSize = 0.0225 * max(h.t, 0.8)
            }
        } else {
            var m = camera
            let rot = simd_float3x3(SIMD3(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z),
                                    SIMD3(camera.columns.1.x, camera.columns.1.y, camera.columns.1.z),
                                    SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z))
            m.columns.3 = SIMD4(head + simd_normalize(rot * LayoutMath.direction(yaw: arYaw, pitch: arPitch)) * 2, 1)
            model = m; handHalfSize = 0.0225 * 2
        }
        var off = matrix_identity_float4x4; off.columns.3 = SIMD4(0, -handHalfSize, 0, 1)   // fingertip at the hit point
        if pickerOpen { handlesVisible = true }
        handModel = model * off
        handHalf = handHalfSize
    }
    private var handHalf: Float = 0.05

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
        updateARCursor(camera: camT, hasFrame: frame != nil, aspect: video?.1 ?? 1.6)
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
            if cameraTex == nil, !cal.testPattern, settings.theme > 0 {
                struct TP { var right: SIMD4<Float>; var up: SIMD4<Float>; var back: SIMD4<Float>; var tanY: Float; var aspect: Float; var time: Float; var theme: Int32 }
                var tp = TP(right: camT.columns.0, up: camT.columns.1, back: camT.columns.2,
                            tanY: Float(tan(cal.fovDegrees * .pi / 360)), aspect: Float(aspectEye),
                            time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 3600)), theme: Int32(settings.theme))
                var sc = SIMD2<Float>(1, 1)
                enc.setRenderPipelineState(themePipeline)
                enc.setVertexBytes(&sc, length: 8, index: 0)
                enc.setFragmentBytes(&tp, length: MemoryLayout<TP>.size, index: 0)
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
            if handlesVisible, let video, let handles = cursor.handles {
                let w = panelWidthM, asp = video.1
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                struct HC { var mvp: simd_float4x4; var halfSize: SIMD2<Float> }
                func draw(_ r: LocalRect, _ key: String, hot: Bool) {
                    guard let tex = handles.get(key, hot: hot) else { return }
                    var m = panelModel; m.columns.3 = panelModel * SIMD4(r.cx, r.cy, 0.006, 1)
                    let k: Float = hot ? 1.1 : 1
                    var hc = HC(mvp: proj * shift * v4 * m, halfSize: SIMD2(r.w / 2 * k, r.h / 2 * k))
                    enc.setRenderPipelineState(spritePipeline)
                    enc.setVertexBytes(&hc, length: MemoryLayout<HC>.size, index: 0)
                    enc.setFragmentTexture(tex, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                draw(PanelHandleGeometry.moveBar(width: w, aspect: asp), "bar", hot: hover == .moveBar)
                draw(PanelHandleGeometry.resizeCorner(width: w, aspect: asp), "corner", hot: hover == .resizeCorner)
                let b = PanelHandleGeometry.buttons(width: w, aspect: asp)
                draw(b[0], "rotate", hot: hover == .rotate)
                draw(b[1], "add", hot: hover == .add)
                draw(b[2], "close", hot: hover == .close)
                draw(b[3], "dark", hot: hover == .darken || !settings.passthrough)
                draw(b[4], "theme", hot: hover == .theme || pickerOpen)
                if pickerOpen {
                    let c = PanelHandleGeometry.themeCircles(width: w, aspect: asp)
                    for (i, r) in c.enumerated() {
                        var sel = false; if case .themeChoice(let k) = hover { sel = k == i }
                        draw(r, "c\(i)", hot: sel || (!settings.passthrough && settings.theme == i))
                    }
                }
            }
            if let hm = handModel, let ht = cursor.handTexture {
                var shift = simd_float4x4(1)
                shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
                struct HC { var mvp: simd_float4x4; var halfSize: SIMD2<Float> }
                var hc = HC(mvp: proj * shift * v4 * hm, halfSize: SIMD2(handHalf, handHalf))
                enc.setRenderPipelineState(spritePipeline)
                enc.setVertexBytes(&hc, length: MemoryLayout<HC>.size, index: 0)
                enc.setFragmentTexture(ht, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
