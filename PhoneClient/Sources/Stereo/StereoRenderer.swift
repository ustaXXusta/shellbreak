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
    private let bank: DecoderBank
    private let settings: StereoSettings
    private let cursor: CursorOverlay
    private let spritePipeline: MTLRenderPipelineState
    private let themePipeline: MTLRenderPipelineState
    private let blitPipeline: MTLRenderPipelineState
    private var themeTex: MTLTexture?
    private var themeScale: Float = 0.5
    private var frameEMA = 1.0 / 60, lastFrameT = CACurrentMediaTime(), lastScaleAdjust = CACurrentMediaTime()
    private let ar: ARSessionController
    private let cameraPipeline: MTLRenderPipelineState
    private let hud: HUDOverlay
    private var arYaw: Float = 0, arPitch: Float = 0
    private var wasLayout = false
    /// AR cursor placement for the current frame: world transform of the hand sprite, and u/v when over the panel.
    private var eyeTextures: [MTLTexture] = []
    private var eyeSize = (width: 0, height: 0)

    private let panelDistanceM: Float = 1.4
    private let screenMm = LensMath.iPhone13ProScreenMm

    init?(view: MTKView, bank: DecoderBank, settings: StereoSettings, cursor: CursorOverlay, ar: ARSessionController, hud: HUDOverlay) {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(), let lib = dev.makeDefaultLibrary() else { return nil }
        device = dev; queue = q; self.bank = bank; self.settings = settings; self.cursor = cursor; self.ar = ar; self.hud = hud
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
        guard let bl = pipe("quadVertex", "quadFragment", .bgra8Unorm) else { return nil }
        blitPipeline = bl
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

    // MARK: panels

    struct PanelRT {
        var id: String
        var streamId: Int
        var kind: PanelKind
        var orientation: PanelOrientation
        var world: simd_float4x4?
        var width: Float
        var aspect: Float
        var roll: Float = 0
        var afterId: String?
    }
    private var panels: [PanelRT] = []
    private var activeIdx = 0
    private var hoverIdx: Int?
    private var dragIdx: Int?
    private var pickerIdx: Int?
    private var changed: [String: Date] = [:]
    private var closeArm: (id: String, at: Date)?
    private var texRefs: [CVMetalTexture] = []

    // Magnets: joined panels keep sharing an edge (bent toward the viewer) while either one is moved, resized or tilted.
    struct Joint { var a: String; var b: String; var eA: Int; var slide: Float = 0 }      // B sits on A's edge eA (0 left, 1 right, 2 top, 3 bottom)
    private var joints: [Joint] = []
    private var magnetPending: (id: String, edge: Int, slide: Float)?
    private var hoverGroup: (joint: Int, edge: Int)?
    private var seamHover: Int?
    private var lastHead = SIMD3<Float>(0, 0, 0)
    private var lastJoinBend: Double = -1
    private var stickyIdx: Int?
    private func panelIndex(_ id: String) -> Int? { panels.firstIndex { $0.id == id } }
    private func size(_ p: PanelRT) -> SIMD2<Float> { SIMD2(p.width, p.width / max(p.aspect, 0.1)) }

    private func makeJoint(a: String, eA: Int, b: String, slide: Float = 0) {
        guard let ia = panelIndex(a), panelIndex(b) != nil, MagnetMath.isValid(eA), a != b else { hud.flash("Geçersiz seçim"); return }
        joints.removeAll { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }
        joints.append(Joint(a: a, b: b, eA: eA, slide: slide))
        enforceJoints(from: ia)
        settings.onMagnet?(MagnetJoin(panelA: a, edgeA: eA, panelB: b, edgeB: MagnetMath.opposite(eA), slide: Double(slide)))
        hud.flash("Mıknatıslandı")
    }

    /// Re-place every panel joined (directly or through others) to `leader`: flush edge to edge, then bent toward the head
    /// about the shared edge by the "magnet curvature" setting. Returns the panels that were visited.
    @discardableResult
    private func enforceJoints(from leader: Int) -> Set<Int> {
        var visited: Set<Int> = [leader]
        guard !joints.isEmpty else { return visited }
        let factor = Float(settings.calibration.joinBend)
        var queue = [leader]
        while !queue.isEmpty {
            let i = queue.removeFirst()
            guard let wi = panels[i].world else { continue }
            for j in joints {
                var other: Int?, iIsA = true
                if panels[i].id == j.a, let o = panelIndex(j.b) { other = o } else if panels[i].id == j.b, let o = panelIndex(j.a) { other = o; iIsA = false }
                guard let o = other, !visited.contains(o) else { continue }
                visited.insert(o); queue.append(o)
                let ia = iIsA ? i : o, ib = iIsA ? o : i
                let sa = size(panels[ia]), sb = size(panels[ib])
                guard let offAB = MagnetMath.centerOffset(aSize: sa, bSize: sb, edgeA: j.eA, slide: j.slide),
                      let hingeA = MagnetMath.hinge(aSize: sa, edgeA: j.eA, slide: j.slide) else { continue }
                let off = iIsA ? offAB : -offAB                                  // follower's centre in the leader's frame
                let hp = iIsA ? hingeA.point : hingeA.point - offAB              // shared-edge midpoint in the leader's frame
                var m = wi; m.columns.3 = wi * SIMD4(off.x, off.y, 0, 1)
                let pw = wi * SIMD4(hp.x, hp.y, 0, 1)
                let ax = wi * SIMD4(hingeA.axis, 0)
                let hingeP = SIMD3(pw.x, pw.y, pw.z), hingeAxis = SIMD3(ax.x, ax.y, ax.z)
                let toHead = lastHead - center(of: m)
                if simd_length(toHead) > 1e-3 {
                    let n = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
                    let ang = MagnetMath.bendAngle(normal: n, toHead: simd_normalize(toHead), axis: simd_normalize(hingeAxis), factor: factor)
                    m = MagnetMath.rotation(about: hingeP, axis: hingeAxis, angle: ang) * m
                }
                panels[o].world = m; panels[o].roll = panels[i].roll
                changed[panels[o].id] = Date()
            }
        }
        return visited
    }

    private func seamIndex(at point: SIMD3<Float>) -> Int? {
        for (k, j) in joints.enumerated() {
            guard let ia = panelIndex(j.a), let ib = panelIndex(j.b), let wa = panels[ia].world,
                  let seam = MagnetMath.seam(aSize: size(panels[ia]), bSize: size(panels[ib]), edgeA: j.eA, slide: j.slide) else { continue }
            let l = wa.inverse * SIMD4(point, 1)
            if seam.contains(l.x, l.y) && abs(l.z) < 0.3 { return k }
        }
        return nil
    }
    /// Merged-edge magnets of joined pairs (in A's frame): the magnet sits between the two ordinary magnets of that edge.
    private func groupMagnetList() -> [(joint: Int, ia: Int, gm: MagnetMath.GroupMagnet)] {
        var out: [(joint: Int, ia: Int, gm: MagnetMath.GroupMagnet)] = []
        for (k, j) in joints.enumerated() where j.slide == 0 {
            guard let ia = panelIndex(j.a), let ib = panelIndex(j.b) else { continue }
            for g in MagnetMath.groupMagnets(aSize: size(panels[ia]), bSize: size(panels[ib]), jointEdge: j.eA) { out.append((k, ia, g)) }
        }
        return out
    }
    private func groupMagnetHit(head: SIMD3<Float>, dir d: SIMD3<Float>) -> (joint: Int, ia: Int, gm: MagnetMath.GroupMagnet)? {
        for e in groupMagnetList() {
            guard let h = rayHit(e.ia, head: head, dir: d) else { continue }
            if e.gm.rect.contains(h.local.x, h.local.y) { return e }
        }
        return nil
    }
    private var handUV: (Double, Double)?

    private func syncScene() {
        guard let scene = settings.takeScene() else { return }
        var out: [PanelRT] = []
        for (i, info) in scene.enumerated() {
            if var p = panels.first(where: { $0.id == info.id }) {
                if info.orientation != p.orientation && info.kind == .virtual {
                    p.width = LayoutMath.clampedWidth(p.width / max(p.aspect, 0.1))   // new width = old height
                } else { p.width = LayoutMath.clampedWidth(Float(info.widthM)) }
                p.orientation = info.orientation; p.aspect = Float(info.aspect)
                out.append(p)
            } else {
                out.append(PanelRT(id: info.id, streamId: info.streamId, kind: info.kind, orientation: info.orientation, world: nil,
                                   width: LayoutMath.clampedWidth(Float(info.widthM)), aspect: Float(info.aspect),
                                   afterId: i > 0 ? scene[i - 1].id : nil))
            }
        }
        for p in panels where !out.contains(where: { $0.id == p.id }) { bank.remove(p.streamId) }
        let activeId = panels.indices.contains(activeIdx) ? panels[activeIdx].id : nil
        panels = out
        activeIdx = out.firstIndex(where: { $0.id == activeId }) ?? 0
        hoverIdx = nil; dragIdx = nil; pickerIdx = nil
        joints.removeAll { j in !out.contains { $0.id == j.a } || !out.contains { $0.id == j.b } }
        if let m = magnetPending, !out.contains(where: { $0.id == m.id }) { magnetPending = nil }
    }

    private func oriented(center: SIMD3<Float>, head: SIMD3<Float>, roll: Float) -> simd_float4x4 {
        let f = LayoutMath.facing(center: center, head: head)
        guard roll != 0 else { return f }
        let c = cos(roll), s = sin(roll)
        var r = matrix_identity_float4x4
        r.columns.0 = SIMD4(c, s, 0, 0); r.columns.1 = SIMD4(-s, c, 0, 0)
        return f * r
    }
    private func center(of m: simd_float4x4) -> SIMD3<Float> { SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z) }

    /// Panels without a pose are put in a row left → right (new ones go next to the panel before them).
    private func placePending(camera: simd_float4x4, force: Bool) {
        let head = center(of: camera)
        lastHead = head
        if force { for i in panels.indices { panels[i].world = nil } }
        for i in panels.indices where panels[i].world == nil {
            let ref = panels[i].afterId.flatMap { id in panels.first(where: { $0.id == id && $0.world != nil }) }
                ?? (i > 0 ? panels[0..<i].last(where: { $0.world != nil }) : nil)
            if let ref, let rw = ref.world {
                let rc = center(of: rw), o = LayoutMath.orbit(of: rc, around: head)
                let dYaw = -(ref.width / 2 + panels[i].width / 2 + 0.1) / max(o.radius, 0.5)
                panels[i].world = oriented(center: LayoutMath.moved(center: rc, head: head, dYaw: dYaw, dPitch: 0, dRadius: 0), head: head, roll: 0)
            } else {
                panels[i].world = oriented(center: center(of: Self.placePanel(camera: camera, distance: panelDistanceM)), head: head, roll: 0)
            }
            changed[panels[i].id] = Date()
        }
        if force {      // "re-centre" must not break magnets: each joined group is rebuilt around its first panel
            var done = Set<Int>()
            for i in panels.indices where !done.contains(i) { done.formUnion(enforceJoints(from: i)) }
        }
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

    private func videoTexture(_ streamId: Int) -> (MTLTexture, Float)? {
        guard let frame = bank.existing(streamId)?.latest, let cache else { return nil }
        let pb = frame.pixelBuffer
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        var tex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, w, h, 0, &tex)
        guard let tex, let mt = CVMetalTextureGetTexture(tex) else { return nil }
        texRefs.append(tex)
        return (mt, Float(w) / Float(h))
    }

    private func cameraTextures(_ frame: ARFrame?) -> (MTLTexture, MTLTexture, ARFrame)? {
        guard let frame, let cache else { return nil }
        let pb = frame.capturedImage
        func tex(_ plane: Int, _ fmt: MTLPixelFormat) -> MTLTexture? {
            var t: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, fmt, CVPixelBufferGetWidthOfPlane(pb, plane),
                                                      CVPixelBufferGetHeightOfPlane(pb, plane), plane, &t)
            if let t { texRefs.append(t) }
            return t.flatMap { CVMetalTextureGetTexture($0) }
        }
        guard let y = tex(0, .r8Unorm), let c = tex(1, .rg8Unorm) else { return nil }
        return (y, c, frame)
    }

    // MARK: keys

    /// Layout-mode keys apply to the active panel: orbit around the head, depth, size (spec 6.6). Shift = big step.
    private func applyCommands(camera: simd_float4x4, hasFrame: Bool) {
        let cmds = settings.takeCommands()
        guard hasFrame, !cmds.isEmpty else { return }
        let head = center(of: camera)
        for c in cmds {
            guard let name = LayoutCommandName(rawValue: c.command) else { continue }
            if name == .togglePassthrough { settings.passthrough.toggle(); hud.flash(settings.passthrough ? "Gerçek dünya" : "VR modu"); continue }
            if name == .bringFront { placePending(camera: camera, force: true); hud.flash("Önüme getir"); continue }
            guard panels.indices.contains(activeIdx), let world = panels[activeIdx].world else { continue }
            var ctr = center(of: world)
            let big: Float = c.shiftHeld ? 4 : 1
            let a: Float = 0.04 * big, d: Float = 0.1 * big, z: Float = c.shiftHeld ? 1.2 : 1.05
            switch name {
            case .moveLeft: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: a, dPitch: 0, dRadius: 0)
            case .moveRight: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: -a, dPitch: 0, dRadius: 0)
            case .moveUp: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: 0, dPitch: a, dRadius: 0)
            case .moveDown: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: 0, dPitch: -a, dRadius: 0)
            case .closer: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: 0, dPitch: 0, dRadius: -d); hud.flash("Yakın")
            case .farther: ctr = LayoutMath.moved(center: ctr, head: head, dYaw: 0, dPitch: 0, dRadius: d); hud.flash("Uzak")
            case .bigger: panels[activeIdx].width = LayoutMath.clampedWidth(panels[activeIdx].width * z); hud.flash(String(format: "Genişlik %.2f m", panels[activeIdx].width))
            case .smaller: panels[activeIdx].width = LayoutMath.clampedWidth(panels[activeIdx].width / z); hud.flash(String(format: "Genişlik %.2f m", panels[activeIdx].width))
            case .faceMe: hud.flash("Bana dön")
            default: break
            }
            panels[activeIdx].world = oriented(center: ctr, head: head, roll: panels[activeIdx].roll)
            changed[panels[activeIdx].id] = Date()
            enforceJoints(from: activeIdx)
        }
    }

    private func flushChanges() {
        for (id, t) in changed where Date().timeIntervalSince(t) > 0.3 {
            changed[id] = nil
            guard let p = panels.first(where: { $0.id == id }), let w = p.world else { continue }
            let m = (0..<4).flatMap { c in (0..<4).map { r in w[c][r] } }
            settings.onPanelChanged?(id, m, p.width)
        }
    }

    // MARK: AR cursor

    private enum Drag { case move, resize, tilt }
    private var drag: Drag?
    private var dragCorner = 3
    private var cursorGlyph: String?
    private var dragLocal = SIMD2<Float>(0, 0)       // handle point the hand stays pinned to while dragging
    private var hover: PanelRegion = .none
    private var handlesVisible = false
    private var pickerOpen: Bool { pickerIdx != nil }
    private var handModel: simd_float4x4?
    private var handHalf: Float = 0.05
    static let themeNames = ["Siyah", "Lav lambası", "Vice City", "Yağmur", "Güneşli", "Matrix", "Cyberpunk", "Steampunk", "Solarpunk", "Sword Art Online"]

    private struct RayHit { var idx: Int; var point: SIMD3<Float>; var local: SIMD2<Float>; var t: Float }

    private func rot3(_ m: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z), SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z), SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
    }

    private func rayHit(_ idx: Int, head: SIMD3<Float>, dir d: SIMD3<Float>) -> RayHit? {
        guard panels.indices.contains(idx), let w = panels[idx].world else { return nil }
        let n = SIMD3(w.columns.2.x, w.columns.2.y, w.columns.2.z), c = center(of: w)
        let denom = simd_dot(d, n)
        guard abs(denom) > 1e-4 else { return nil }
        let t = simd_dot(c - head, n) / denom
        guard t > 0.1 else { return nil }
        let p = head + d * t
        let l = w.inverse * SIMD4(p, 1)
        return RayHit(idx: idx, point: p, local: SIMD2(l.x, l.y), t: t)
    }

    /// The hovered panel is the nearest one whose picture the ray crosses, so overlapping toolbars of neighbours never
    /// compete. Once a panel is hovered it stays active while the cursor travels over its own handles (outside its picture).
    /// While a magnet join is armed every panel's handle area counts, so edge magnets of other panels can be reached.
    private func bestHit(head: SIMD3<Float>, dir d: SIMD3<Float>) -> RayHit? {
        var best: RayHit?
        for i in panels.indices {
            guard let h = rayHit(i, head: head, dir: d) else { continue }
            let p = panels[i]
            guard abs(h.local.x) <= p.width / 2, abs(h.local.y) <= p.width / max(p.aspect, 0.1) / 2 else { continue }
            if best == nil || h.t < best!.t { best = h }
        }
        if let b = best { stickyIdx = b.idx; return b }
        if let s = stickyIdx, panels.indices.contains(s), let h = rayHit(s, head: head, dir: d),
           PanelHandleGeometry.hoverArea(width: panels[s].width, aspect: panels[s].aspect).contains(h.local.x, h.local.y) { return h }
        if magnetPending != nil {
            for i in panels.indices {
                guard let h = rayHit(i, head: head, dir: d) else { continue }
                if PanelHandleGeometry.hoverArea(width: panels[i].width, aspect: panels[i].aspect).contains(h.local.x, h.local.y), best == nil || h.t < best!.t { best = h }
            }
            if let b = best { stickyIdx = b.idx; return b }
        }
        stickyIdx = nil
        return nil
    }

    private func updateARCursor(camera: simd_float4x4, hasFrame: Bool) {
        let layout = settings.layoutActive
        if layout != wasLayout { wasLayout = layout; arYaw = 0; arPitch = 0; drag = nil; dragIdx = nil }
        handModel = nil; handUV = nil; handlesVisible = false; hover = .none; hoverIdx = nil; cursorGlyph = nil; seamHover = nil; hoverGroup = nil
        guard layout, hasFrame, !panels.isEmpty else { pickerIdx = nil; _ = settings.takeInputs(); drag = nil; dragIdx = nil; return }
        let head = center(of: camera)
        let rot = rot3(camera)
        func dirNow() -> SIMD3<Float> { simd_normalize(rot * LayoutMath.direction(yaw: arYaw, pitch: arPitch)) }

        for i in settings.takeInputs() {
            switch i.kind {
            case "move":
                if let dr = drag, let di = dragIdx, panels.indices.contains(di) {
                    switch dr {
                    case .move:
                        if let w = panels[di].world {
                            let ctr = LayoutMath.moved(center: center(of: w), head: head, dYaw: -Float(i.dx) * 0.0022, dPitch: -Float(i.dy) * 0.0022, dRadius: 0)
                            panels[di].world = oriented(center: ctr, head: head, roll: panels[di].roll)
                        }
                    case .resize:
                        let sx: Float = (dragCorner == 1 || dragCorner == 3) ? 1 : -1, sy: Float = dragCorner >= 2 ? 1 : -1
                        panels[di].width = LayoutMath.clampedWidth(panels[di].width * (1 + (sx * Float(i.dx) + sy * Float(i.dy)) * 0.003))
                    case .tilt:
                        if let w = panels[di].world {
                            panels[di].roll += Float(i.dx) * 0.004
                            panels[di].world = oriented(center: center(of: w), head: head, roll: panels[di].roll)
                        }
                    }
                    changed[panels[di].id] = Date()
                    enforceJoints(from: di)
                } else {
                    arYaw = max(-0.6, min(0.6, arYaw - Float(i.dx) * 0.0022))
                    arPitch = max(-0.45, min(0.45, arPitch - Float(i.dy) * 0.0022))
                }
            case "down":
                guard drag == nil else { break }
                let hit = bestHit(head: head, dir: dirNow())
                var region: PanelRegion = .none
                if let h = hit {
                    let p = panels[h.idx]
                    region = PanelHandleGeometry.hit(x: h.local.x, y: h.local.y, width: p.width, aspect: p.aspect, pickerOpen: pickerIdx == h.idx)
                }
                // The picker stays open until a theme is chosen or something else is clicked.
                if case .theme = region { pickerIdx = hit?.idx } else { pickerIdx = nil }
                if let e = groupMagnetHit(head: head, dir: dirNow()) {   // merged-edge magnet of a stacked/side-by-side pair
                    activeIdx = e.ia
                    if let pend = magnetPending {
                        magnetPending = nil
                        if panels[e.ia].id != pend.id { makeJoint(a: pend.id, eA: pend.edge, b: panels[e.ia].id, slide: pend.slide) }
                        else { hud.flash("İptal") }
                    } else { magnetPending = (panels[e.ia].id, e.gm.edge, e.gm.slide); hud.flash("Şimdi yapıştırılacak ekrana tıkla") }
                    break
                }
                if let h = hit, let k = seamIndex(at: h.point) {      // X on the seam: break the magnet
                    joints.remove(at: k); hud.flash("Mıknatıs ayrıldı"); break
                }
                guard let h = hit else { if magnetPending != nil { magnetPending = nil; hud.flash("İptal") }; break }
                activeIdx = h.idx
                let p = panels[h.idx]
                if let pend = magnetPending {               // second click of a magnet join: any other screen attaches
                    if p.id != pend.id { magnetPending = nil; makeJoint(a: pend.id, eA: pend.edge, b: p.id, slide: pend.slide); break }
                    if case .magnet(let kk) = region, kk != pend.edge { magnetPending = (p.id, kk, 0); hud.flash("Kenar değişti"); break }
                    magnetPending = nil; hud.flash("İptal"); break
                }
                switch region {
                case .magnet(let k): magnetPending = (p.id, k, 0); hud.flash("Şimdi yapıştırılacak ekrana tıkla")
                case .content(let u, let v): settings.onEnterScreen?(p.id, u, v)
                case .moveBar: drag = .move; dragIdx = h.idx; dragLocal = PanelHandleGeometry.moveBar(width: p.width, aspect: p.aspect).center
                case .resizeCorner(let k):
                    drag = .resize; dragIdx = h.idx; dragCorner = k
                    dragLocal = PanelHandleGeometry.corners(width: p.width, aspect: p.aspect)[k].center
                case .tilt: drag = .tilt; dragIdx = h.idx; dragLocal = PanelHandleGeometry.buttons(width: p.width, aspect: p.aspect)[1].center
                case .rotate:
                    if p.kind == .mirror {
                        hud.flash("Ana ekran döndürülemez · dikey için + ile yeni ekran ekle")
                    } else {
                        settings.onRotate?(p.id, p.orientation == .landscape ? .portrait : .landscape)
                    }
                case .darken: settings.passthrough.toggle(); hud.flash(settings.passthrough ? "Gerçek dünya" : "Dünya karartıldı")
                case .theme: break
                case .themeChoice(let k):
                    if settings.passthrough { hud.flash("Önce 🌙 ile dünyayı karart") } else { settings.theme = k; hud.flash(Self.themeNames[k]) }
                case .add: settings.onAddDisplay?(p.id); hud.flash("Yeni ekran ekleniyor…")
                case .close:
                    if p.kind == .mirror { hud.flash("Ana ekran kapatılamaz") }
                    else if let a = closeArm, a.id == p.id, Date().timeIntervalSince(a.at) < 3 { closeArm = nil; settings.onRemoveDisplay?(p.id) }
                    else { closeArm = (p.id, Date()); hud.flash("Kapatmak için tekrar tıkla") }
                case .none: break
                }
            case "up": drag = nil; dragIdx = nil
            default: break
            }
        }

        // Where the hand goes this frame.
        var model: simd_float4x4
        var handHalfSize: Float = 0.045
        let d = dirNow()
        if drag == nil, let e = groupMagnetHit(head: head, dir: d) { hoverGroup = (e.joint, e.gm.edge) }
        if let dr = drag, let di = dragIdx, panels.indices.contains(di), let w = panels[di].world {
            model = w; model.columns.3 = w * SIMD4(dragLocal.x, dragLocal.y, 0.01, 1)
            handlesVisible = true; hoverIdx = di
            switch dr {
            case .move: hover = .moveBar
            case .resize: hover = .resizeCorner(dragCorner); cursorGlyph = (dragCorner == 0 || dragCorner == 3) ? "corner" : "corner2"
            case .tilt: hover = .tilt
            }
            handHalfSize = 0.0225 * 1.4
        } else if let h = bestHit(head: head, dir: d), let w = panels[h.idx].world {
            let p = panels[h.idx]
            let region = PanelHandleGeometry.hit(x: h.local.x, y: h.local.y, width: p.width, aspect: p.aspect, pickerOpen: pickerIdx == h.idx)
            hover = region; hoverIdx = h.idx; handlesVisible = true
            if case .theme = region { pickerIdx = h.idx }      // opens on hover
            if case .content(let u, let v) = region { handUV = (u, v) }
            if case .resizeCorner(let k) = region { cursorGlyph = (k == 0 || k == 3) ? "corner" : "corner2" }
            if drag == nil, let k = seamIndex(at: h.point) { seamHover = k; cursorGlyph = "close"; hover = .none }
            model = w; model.columns.3 = SIMD4(h.point + SIMD3(w.columns.2.x, w.columns.2.y, w.columns.2.z) * 0.012, 1)
            handHalfSize = 0.0225 * max(h.t, 0.8)
        } else {
            var m = camera; m.columns.3 = SIMD4(head + d * 2, 1)
            model = m; handHalfSize = 0.0225 * 2
        }
        if let pi = pickerIdx { handlesVisible = true; if hoverIdx == nil { hoverIdx = pi } }
        if cursorGlyph != nil { handHalfSize = 0.03 * max(1, handHalfSize / 0.045) }
        var off = matrix_identity_float4x4; off.columns.3 = SIMD4(0, cursorGlyph == nil ? -handHalfSize : 0, 0, 1)   // fingertip at the hit point
        handModel = model * off
        handHalf = handHalfSize
    }

    // MARK: frame

    func draw(in view: MTKView) {
        let cal = settings.calibration
        let ds = view.drawableSize
        guard ds.width > 0, let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        ensureEyeTextures(cal, drawable: ds)
        guard eyeTextures.count == 2 else { return }
        texRefs.removeAll(keepingCapacity: true)
        let frame = ar.latestFrame
        let camT = frame?.camera.transform ?? matrix_identity_float4x4
        syncScene()
        if frame != nil { lastHead = center(of: camT) }
        if frame != nil { placePending(camera: camT, force: settings.takeRecenter()) }
        if cal.joinBend != lastJoinBend {      // curvature slider moved: rebuild every joined group
            lastJoinBend = cal.joinBend
            var done = Set<Int>()
            for i in panels.indices where !done.contains(i) { done.formUnion(enforceJoints(from: i)) }
        }
        applyCommands(camera: camT, hasFrame: frame != nil)
        // Panel textures first so aspect ratios are current for hit testing.
        var tex: [Int: (MTLTexture, Float)] = [:]
        for i in panels.indices {
            if let t = videoTexture(panels[i].streamId) { tex[i] = t; panels[i].aspect = t.1 }
        }
        updateARCursor(camera: camT, hasFrame: frame != nil)
        flushChanges()
        let v4 = camT.inverse                      // world -> head (camera) space, full 6DoF
        let cameraTex = settings.passthrough ? cameraTextures(frame) : nil
        let ipd = Float(cal.lensSeparationMm) / 1000
        let aspectEye = Double(eyeSize.width) / Double(eyeSize.height)
        let proj = LensMath.perspective(verticalFovDegrees: cal.fovDegrees, aspect: aspectEye, near: 0.05, far: 50)
        let head = center(of: camT)
        let order = panels.indices.sorted { a, b in
            let da = panels[a].world.map { simd_length(center(of: $0) - head) } ?? 0
            let db = panels[b].world.map { simd_length(center(of: $0) - head) } ?? 0
            return da > db
        }
        let cur = cursor.snapshot
        let handlesPanel = dragIdx ?? pickerIdx ?? hoverIdx
        let refs = texRefs
        cb.addCompletedHandler { _ in _ = refs.count }

        // World theme: direction-only, so it is drawn ONCE per frame at reduced resolution and shared by both eyes.
        // The resolution adapts to the frame time so the heavy scenes never make head tracking stutter.
        let themeActive = cameraTex == nil && !cal.testPattern && settings.theme > 0
        let nowT = CACurrentMediaTime()
        frameEMA = frameEMA * 0.92 + min(nowT - lastFrameT, 0.1) * 0.08; lastFrameT = nowT
        if themeActive, nowT - lastScaleAdjust > 1.0 {
            lastScaleAdjust = nowT
            if frameEMA > 0.0215 { themeScale = max(0.25, themeScale - 0.06) } else if frameEMA < 0.0185 { themeScale = min(0.6, themeScale + 0.03) }
        }
        if themeActive {
            let tw = max(64, Int(Float(eyeSize.width) * themeScale)), th = max(64, Int(Float(eyeSize.height) * themeScale))
            if themeTex == nil || themeTex!.width != tw || themeTex!.height != th {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
                themeTex = device.makeTexture(descriptor: d)
            }
            if let tt = themeTex {
                let rp = MTLRenderPassDescriptor()
                rp.colorAttachments[0].texture = tt; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
                if let enc = cb.makeRenderCommandEncoder(descriptor: rp) {
                    struct TP { var right: SIMD4<Float>; var up: SIMD4<Float>; var back: SIMD4<Float>; var tanY: Float; var aspect: Float; var time: Float; var theme: Int32 }
                    var tp = TP(right: camT.columns.0, up: camT.columns.1, back: camT.columns.2,
                                tanY: Float(tan(cal.fovDegrees * .pi / 360)), aspect: Float(aspectEye),
                                time: Float(nowT.truncatingRemainder(dividingBy: 3600)), theme: Int32(settings.theme))
                    var sc = SIMD2<Float>(1, 1)
                    enc.setRenderPipelineState(themePipeline)
                    enc.setVertexBytes(&sc, length: 8, index: 0)
                    enc.setFragmentBytes(&tp, length: MemoryLayout<TP>.size, index: 0)
                    enc.setFragmentTexture(cursor.glyphAtlas, index: 0)
                    enc.setFragmentTexture(cursor.themeEnvironment(settings.theme), index: 1)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }
            }
        }

        for eye in 0..<2 {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = eyeTextures[eye]
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.01, blue: 0.012, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            var shift = simd_float4x4(1)
            shift.columns.3 = SIMD4(eye == 0 ? ipd / 2 : -ipd / 2, 0, 0, 1)
            struct U { var mvp: simd_float4x4; var halfSize: SIMD2<Float> }
            func sprite(_ model: simd_float4x4, _ half: SIMD2<Float>, _ t: MTLTexture) {
                var u = U(mvp: proj * shift * v4 * model, halfSize: half)
                enc.setRenderPipelineState(spritePipeline)
                enc.setVertexBytes(&u, length: MemoryLayout<U>.size, index: 0)
                enc.setFragmentTexture(t, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            if let (yT, cT, cf) = cameraTex, !cal.testPattern {
                let res = cf.camera.imageResolution, K = cf.camera.intrinsics
                let w = Float(res.width), h = Float(res.height), D: Float = 8
                let fx = K[0][0], fy = K[1][1], cx = K[2][0], cy = K[2][1]
                struct CU { var mvp: simd_float4x4; var xr: SIMD2<Float>; var yr: SIMD2<Float>; var z: Float }
                var cu = CU(mvp: proj * shift,
                            xr: SIMD2(-cx / fx * D, (w - cx) / fx * D), yr: SIMD2(-(h - cy) / fy * D, cy / fy * D), z: -D)
                enc.setRenderPipelineState(cameraPipeline)
                enc.setVertexBytes(&cu, length: MemoryLayout<CU>.size, index: 0)
                enc.setFragmentTexture(yT, index: 0); enc.setFragmentTexture(cT, index: 1)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            if themeActive, let tt = themeTex {
                var sc = SIMD2<Float>(1, 1)
                enc.setRenderPipelineState(blitPipeline)
                enc.setVertexBytes(&sc, length: 8, index: 0)
                enc.setFragmentTexture(tt, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            if cal.testPattern || tex.isEmpty {
                var asp = Float(aspectEye); var sc = SIMD2<Float>(1, 1)
                enc.setRenderPipelineState(testPipeline)
                enc.setVertexBytes(&sc, length: 8, index: 0)
                enc.setFragmentBytes(&asp, length: 4, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            } else {
                for i in order {
                    guard let (t, aspect) = tex[i], let model = panels[i].world else { continue }
                    let w = panels[i].width
                    var u = U(mvp: proj * shift * v4 * model, halfSize: SIMD2(w / 2, w / 2 / aspect))
                    enc.setRenderPipelineState(panelPipeline)
                    enc.setVertexBytes(&u, length: MemoryLayout<U>.size, index: 0)
                    enc.setFragmentTexture(t, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    if cur.visible, cur.panelId == panels[i].id, let ct = cur.texture {
                        let r = CursorLayout.spriteRect(u: cur.u, v: cur.v, hotspot: cur.hotspot, sizePt: cur.sizePt,
                                                        displayWidthPt: cur.displayWidthPt, aspect: Double(aspect), scale: 1.5)
                        let ph = w / aspect
                        var cm = model
                        cm.columns.3 = model * SIMD4(Float(r.center.x - 0.5) * w, Float(0.5 - r.center.y) * ph, 0.004, 1)
                        sprite(cm, SIMD2(Float(r.size.x) * w / 2, Float(r.size.y) * ph / 2), ct)
                    }
                }
            }
            if handlesVisible, let hi = handlesPanel, panels.indices.contains(hi), let model = panels[hi].world, let handles = cursor.handles {
                let w = panels[hi].width, asp = panels[hi].aspect
                func draw(_ r: LocalRect, _ key: String, hot: Bool) {
                    guard let t = handles.get(key, hot: hot) else { return }
                    var m = model; m.columns.3 = model * SIMD4(r.cx, r.cy, 0.006, 1)
                    let k: Float = hot ? 1.1 : 1
                    sprite(m, SIMD2(r.w / 2 * k, r.h / 2 * k), t)
                }
                draw(PanelHandleGeometry.moveBar(width: w, aspect: asp), "bar", hot: hover == .moveBar)
                let b = PanelHandleGeometry.buttons(width: w, aspect: asp)
                draw(b[0], "rotate", hot: hover == .rotate)
                draw(b[1], "tilt", hot: hover == .tilt)
                draw(b[2], "add", hot: hover == .add)
                draw(b[3], "close", hot: hover == .close || closeArm?.id == panels[hi].id)
                draw(b[4], "dark", hot: hover == .darken || !settings.passthrough)
                draw(b[5], "theme", hot: hover == .theme || pickerOpen)
                if pickerIdx == hi {
                    let c = PanelHandleGeometry.themeCircles(width: w, aspect: asp)
                    for (i, r) in c.enumerated() {
                        var sel = false; if case .themeChoice(let k) = hover { sel = k == i }
                        draw(r, "c\(i)", hot: sel || (!settings.passthrough && settings.theme == i))
                    }
                }
            }
            for (i, pnl) in panels.enumerated() where pnl.world != nil && (magnetPending != nil || (handlesVisible && handlesPanel == i)) {
                guard let model = pnl.world, let handles = cursor.handles else { continue }
                for (k, r) in PanelHandleGeometry.magnets(width: pnl.width, aspect: pnl.aspect).enumerated() {
                    let armed = magnetPending.map { $0.id == pnl.id && $0.edge == k } ?? false
                    let joined = joints.contains { ($0.a == pnl.id && $0.eA == k) || ($0.b == pnl.id && MagnetMath.opposite($0.eA) == k) }
                    var hot = false; if hoverIdx == i, case .magnet(let kk) = hover { hot = kk == k }
                    guard let t = handles.get(armed || joined ? "magnetOn" : "magnet", hot: hot) else { continue }
                    var m = model; m.columns.3 = model * SIMD4(r.cx, r.cy, 0.006, 1)
                    let sc: Float = hot ? 1.12 : 1
                    sprite(m, SIMD2(r.w / 2 * sc, r.h / 2 * sc), t)
                }
            }
            if let handles = cursor.handles {
                for e in groupMagnetList() {
                    guard let model = panels[e.ia].world,
                          let ib = panelIndex(joints[e.joint].b),
                          magnetPending != nil || handlesPanel == e.ia || handlesPanel == ib else { continue }
                    let armed = magnetPending.map { $0.id == panels[e.ia].id && $0.edge == e.gm.edge && $0.slide == e.gm.slide } ?? false
                    let hot = hoverGroup.map { $0.joint == e.joint && $0.edge == e.gm.edge } ?? false
                    guard let t = handles.get(armed ? "magnetOn" : "magnet", hot: hot || armed) else { continue }
                    var m = model; m.columns.3 = model * SIMD4(e.gm.rect.cx, e.gm.rect.cy, 0.006, 1)
                    sprite(m, SIMD2(e.gm.rect.w / 2 * (hot ? 1.12 : 1), e.gm.rect.h / 2 * (hot ? 1.12 : 1)), t)
                }
            }
            if let hm = handModel {
                if let g = cursorGlyph, let gt = cursor.handles?.get(g, hot: true) { sprite(hm, SIMD2(handHalf, handHalf), gt) }
                else if let ht = cursor.handTexture { sprite(hm, SIMD2(handHalf, handHalf), ht) }
            }
            if let (ht, hasp) = hud.current() {
                var place = simd_float4x4(1); place.columns.3 = SIMD4(0, -0.17, -0.9, 1)
                var hu = U(mvp: proj * shift * place, halfSize: SIMD2(0.07 * hasp, 0.07))
                enc.setRenderPipelineState(spritePipeline)
                enc.setVertexBytes(&hu, length: MemoryLayout<U>.size, index: 0)
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
