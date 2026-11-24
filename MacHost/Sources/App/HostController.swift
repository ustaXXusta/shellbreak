import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import DesktopARShared
import os

/// One panel as the Mac sees it (mirror of the built-in display, or a virtual display).
struct PanelModel: Identifiable, Equatable {
    var id: String
    var kind: PanelKind
    var streamId: Int
    var desktopIndex: Int
    var widthM: Double
    var aspect: Double
    var orientation: PanelOrientation = .landscape
    var displayID: CGDirectDisplayID
    var transform: [Float]?
    var info: PanelInfo {
        PanelInfo(id: id, kind: kind, streamId: streamId, desktopIndex: desktopIndex, widthM: widthM, aspect: aspect,
                  orientation: orientation, transform: transform)
    }
}

/// A macOS display as shown in the arrangement editor.
struct DisplayItem: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var name: String
    var bounds: CGRect
    var isMain: Bool
    var isPanel: Bool
    var key: String
    var excluded: Bool
}

/// Thread-safe streamId → pipeline lookup for callbacks that run off the main actor.
final class StreamRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [UInt8: PanelStream] = [:]
    func set(_ s: PanelStream) { lock.lock(); map[s.streamId] = s; lock.unlock() }
    func remove(_ id: UInt8) { lock.lock(); map[id] = nil; lock.unlock() }
    func get(_ id: UInt8) -> PanelStream? { lock.lock(); defer { lock.unlock() }; return map[id] }
    func all() -> [PanelStream] { lock.lock(); defer { lock.unlock() }; return Array(map.values) }
    func clear() { lock.lock(); map = [:]; lock.unlock() }
}

@MainActor
final class HostController: ObservableObject {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "host")
    @Published var permissions = PermissionStatus.current()
    @Published var phoneConnected = false
    @Published var streaming = false
    @Published var codecName = "-"
    @Published var dumpToDesktop = false { didSet { updateDump() } }
    @Published var lastError: String?
    @Published var panels: [PanelModel] = []
    @Published var displays: [DisplayItem] = []
    /// Physical monitors the user switched off in the arrangement editor (eye): never snapped to or moved by us.
    @Published var excludedKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "excludedDisplays") ?? [])
    @Published var panelWidthM: Double = {
        let v = UserDefaults.standard.double(forKey: "panelWidthM"); return v > 0 ? v : 2.0
    }() { didSet {
        UserDefaults.standard.set(panelWidthM, forKey: "panelWidthM")
        if let i = panels.firstIndex(where: { $0.kind == .mirror }) { panels[i].widthM = panelWidthM }
        if !suppressScene { sendScene() }
    } }
    private var sceneRevision = 0
    private var suppressScene = false
    private var virtuals: [String: VirtualDisplay] = [:]
    private let registry = StreamRegistry()
    private var controlWindow: NSWindow?
    private let maxVirtualDisplays = 5

    func sendScene() {
        sceneRevision += 1
        server.send(.scene(SceneMessage(revision: sceneRevision, panels: panels.map(\.info))))
    }

    private func applyPhoneUpdate(_ u: PanelUpdate) {
        guard let i = panels.firstIndex(where: { $0.id == u.panelId }) else { return }
        panels[i].transform = u.transform; panels[i].widthM = u.widthM
        if panels[i].kind == .mirror { suppressScene = true; panelWidthM = u.widthM; suppressScene = false }
    }

    @Published var passthrough = true { didSet { server.send(.mode(ModeMessage(passthrough: passthrough))) } }
    @Published var calibration: Calibration = HostController.loadCalibration() {
        didSet { saveCalibration(); server.send(.calibration(calibration)) }
    }

    private static let calibrationKey = "calibration.v1"
    private static func loadCalibration() -> Calibration {
        guard let d = UserDefaults.standard.data(forKey: calibrationKey),
              let c = try? JSONDecoder().decode(Calibration.self, from: d) else { return Calibration() }
        return c
    }
    private func saveCalibration() {
        if let d = try? JSONEncoder().encode(calibration) { UserDefaults.standard.set(d, forKey: Self.calibrationKey) }
    }
    func recenterPhone() { server.send(.hud(HUD(text: "!recenter"))) }
    func resetCalibration() { calibration = Calibration() }

    private let server = HostServer()
    private var cursorStreamer: CursorStreamer?
    private let inputController = InputModeController()
    @Published var inputMode: InputModeState = .screen
    @Published var exitKeyStyle: ExitKeyStyle = ExitKeyStyle(rawValue: UserDefaults.standard.string(forKey: "exitKeyStyle") ?? "") ?? .singleEsc {
        didSet { UserDefaults.standard.set(exitKeyStyle.rawValue, forKey: "exitKeyStyle"); inputController.style = exitKeyStyle }
    }
    nonisolated(unsafe) private var dumpHandle: FileHandle?
    nonisolated private let dumpLock = NSLock()

    /// Streaming starts on launch (turn off with `defaults write dev.desktopar.host autoStart -bool false`).
    init() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if UserDefaults.standard.object(forKey: "autoStart") as? Bool ?? true { await self?.start() }
        }
    }

    func refreshPermissions() { permissions = PermissionStatus.current() }

    private func hud(_ text: String) { server.send(.hud(HUD(text: text))) }

    private func attach(_ stream: PanelStream) {
        let sid = stream.streamId
        stream.onFrame = { [weak self] f in
            guard let self else { return }
            self.server.sendVideo(streamId: sid, frame: f)
            if sid == 0 { self.dump(f) }
        }
        registry.set(stream)
    }

    func start() async {
        refreshPermissions()
        if !permissions.screenRecording { _ = CGRequestScreenCaptureAccess(); lastError = "Screen Recording izni gerekli"; return }
        do {
            let id = CGMainDisplayID()
            let mirror = PanelStream(streamId: 0, displayID: id, width: 1920, height: 1200)
            attach(mirror)
            server.onConnectionChange = { [weak self] up in
                Task { @MainActor in
                    self?.phoneConnected = up
                    self?.inputController.phoneConnected = up
                    if !up { self?.inputController.forceScreen() }   // never leave the Mac in layout mode without a headset
                }
            }
            server.onNeedKeyframe = { [weak self] sid in self?.registry.get(sid)?.requestKeyframe() }
            server.onMessage = { [weak self] msg in Task { @MainActor in self?.handle(msg) } }
            try server.start()
            try await mirror.start()
            panels = [PanelModel(id: "desktop-1", kind: .mirror, streamId: 0, desktopIndex: 1, widthM: panelWidthM, aspect: 1.6, displayID: id)]
            let cs = CursorStreamer(displays: { [weak self] in
                MainActor.assumeIsolated { (self?.panels ?? []).map { ($0.id, $0.displayID) } }
            }, send: { [weak self] m in self?.server.send(m) })
            cs.start(); cursorStreamer = cs
            inputController.send = { [weak self] m in self?.server.send(m) }
            inputController.onModeChange = { [weak self] m in Task { @MainActor in self?.inputMode = m } }
            inputController.style = exitKeyStyle
            if !inputController.start() { lastError = "Esc/düzen modu için Accessibility + Input Monitoring izni gerekli" }
            codecName = mirror.isHEVC ? "HEVC" : "H.264"
            streaming = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("start failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ msg: ControlMessage) {
        switch msg {
        case .hello:
            server.send(.calibration(calibration))
            sendScene()
            server.send(.mode(ModeMessage(passthrough: passthrough)))
            cursorStreamer?.resend()
            for s in registry.all() { s.requestKeyframe() }
        case .panelUpdate(let u): applyPhoneUpdate(u)
        case .enterScreen(let e):
            let d = panels.first(where: { $0.id == e.panelId })?.displayID ?? CGMainDisplayID()
            inputController.enterScreen(u: e.u, v: e.v, displayID: d)
        case .magnet(let m): applyMagnet(m)
        case .addDisplay: Task { await addVirtual() }
        case .removeDisplay(let r): Task { await removeVirtual(r.panelId) }
        case .rotate(let r): Task { await rotate(r.panelId, r.orientation) }
        default: break
        }
    }

    // MARK: display arrangement (macOS layout = how the monitors stand in the room)

    func refreshDisplays() {
        var n: UInt32 = 0; CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n)); CGGetActiveDisplayList(n, &ids, &n)
        let next = ids.map { id -> DisplayItem in
            let panel = panels.first { $0.displayID == id }
            let name = panel.map { $0.kind == .mirror ? "Ana ekran" : "Ekran \($0.desktopIndex)" } ?? (CGDisplayIsBuiltin(id) != 0 ? "Dahili" : "Harici")
            let key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
            return DisplayItem(id: id, name: name, bounds: CGDisplayBounds(id), isMain: id == CGMainDisplayID(), isPanel: panel != nil,
                               key: key, excluded: panel == nil && excludedKeys.contains(key))
        }
        if next != displays { displays = next }
    }

    func toggleExcluded(_ id: CGDirectDisplayID) {
        guard let d = displays.first(where: { $0.id == id }), !d.isPanel else { return }
        if excludedKeys.contains(d.key) { excludedKeys.remove(d.key) } else { excludedKeys.insert(d.key) }
        UserDefaults.standard.set(Array(excludedKeys), forKey: "excludedDisplays")
        refreshDisplays()
    }

    private func applyOrigins(_ origins: [CGDirectDisplayID: CGPoint]) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return }
        for (id, o) in origins { CGConfigureDisplayOrigin(cfg, id, Int32(o.x.rounded()), Int32(o.y.rounded())) }
        CGCompleteDisplayConfiguration(cfg, .forSession)
        refreshDisplays()
    }

    /// Drop a display at `rect` (global points); it snaps to touch another display without overlapping.
    func moveDisplay(_ id: CGDirectDisplayID, to rect: CGRect) {
        guard id != CGMainDisplayID() else { return }
        let others = displays.filter { $0.id != id && !$0.excluded }.map(\.bounds)
        let ignored = displays.filter { $0.id != id && $0.excluded }.map(\.bounds)
        guard let r = DisplayLayout.snapped(moving: rect, others: others, ignored: ignored) else { return }
        applyOrigins([id: r.origin])
    }

    /// Panels side by side in the order they stand in the room (left → right); other monitors go underneath.
    func arrangeRow() {
        refreshDisplays()
        guard !panels.isEmpty else { return }
        let positions: [SIMD3<Float>]? = panels.allSatisfy({ $0.transform?.count == 16 }) ? panels.map { p in
            let t = p.transform ?? []; return SIMD3(t[12], t[13], t[14])
        } : nil
        var order = Array(panels.indices)
        if let positions, let t0 = panels.first?.transform {
            order = DisplayLayout.orderLeftToRight(positions: positions, right: SIMD3(t0[0], t0[1], t0[2]))
        }
        let ordered = order.map { panels[$0] }
        let sizes = ordered.map { CGDisplayBounds($0.displayID).size }
        let anchor = ordered.firstIndex { $0.displayID == CGMainDisplayID() } ?? 0
        let o = DisplayLayout.row(sizes: sizes, anchor: anchor)
        var origins: [CGDirectDisplayID: CGPoint] = [:]
        for (i, p) in ordered.enumerated() { origins[p.displayID] = o[i] }
        var x: CGFloat = 0
        let below = sizes.map(\.height).max() ?? 900
        for d in displays where !d.isPanel && !d.excluded { origins[d.id] = CGPoint(x: x, y: below); x += d.bounds.width }
        applyOrigins(origins)
        hud("Ekranlar odadaki sıraya göre dizildi")
    }

    // MARK: magnets: joined panels become joined macOS displays

    private func applyMagnet(_ m: MagnetJoin) {
        refreshDisplays()
        guard MagnetMath.isValid(m.edgeA),
              let pa = panels.first(where: { $0.id == m.panelA }), let pb = panels.first(where: { $0.id == m.panelB }),
              let da = displays.first(where: { $0.id == pa.displayID }), let db = displays.first(where: { $0.id == pb.displayID }) else { return }
        // The main display cannot move, so when B is main, A is the one that moves against it.
        let moveB = !db.isMain
        let base = moveB ? da : db, mover = moveB ? db : da
        let edge = moveB ? m.edgeA : MagnetMath.opposite(m.edgeA)
        let basePanel = moveB ? pa : pb
        let slidePts = CGFloat(moveB ? m.slide : -m.slide) * base.bounds.width / CGFloat(max(basePanel.widthM, 0.1))
        guard let origin = MagnetMath.displayOrigin(a: base.bounds, bSize: mover.bounds.size, edgeA: edge, slidePoints: slidePts) else { return }
        var origins: [CGDirectDisplayID: CGPoint] = [mover.id: origin]
        let rect = CGRect(origin: origin, size: mover.bounds.size)
        var next = max(displays.map { $0.bounds.maxX }.max() ?? 0, rect.maxX)
        for d in displays where d.id != mover.id && d.id != base.id && !d.isMain && d.bounds.intersects(rect.insetBy(dx: 1, dy: 1)) {
            origins[d.id] = CGPoint(x: next, y: d.bounds.minY); next += d.bounds.width   // make room for other monitors
        }
        applyOrigins(origins)
        hud("Ekranlar yapıştırıldı")
    }

    // MARK: resolution / scale

    func resolutionOptions(for p: PanelModel) -> [CGSize] {
        if p.kind == .virtual { return DisplayResolutions.presets(portrait: p.orientation == .portrait) }
        let opts = ["kCGDisplayShouldListDuplicateModes" as CFString: false, "kCGDisplayShowDuplicateLowResolutionModes" as CFString: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(p.displayID, opts) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
        var seen = Set<String>(), out: [CGSize] = []
        for m in modes.sorted(by: { $0.width < $1.width }) where seen.insert("\(m.width)x\(m.height)").inserted {
            out.append(CGSize(width: m.width, height: m.height))
        }
        return out
    }

    func currentResolution(_ p: PanelModel) -> CGSize {
        if p.kind == .virtual, let vd = virtuals[p.id] { return CGSize(width: vd.width, height: vd.height) }
        return CGDisplayBounds(p.displayID).size
    }

    func setResolution(_ id: String, _ size: CGSize) async {
        guard let i = panels.firstIndex(where: { $0.id == id }) else { return }
        let w = Int(size.width), h = Int(size.height)
        if panels[i].kind == .virtual {
            guard let vd = virtuals[id], let s = registry.get(UInt8(panels[i].streamId)), vd.setMode(width: w, height: h) else { hud("Çözünürlük değişmedi"); return }
            do { try await s.restart(width: w, height: h) } catch { lastError = error.localizedDescription; return }
            panels[i].orientation = h > w ? .portrait : .landscape
            panels[i].aspect = Double(w) / Double(h)
            sendScene()
        } else {
            let did = panels[i].displayID
            let opts = ["kCGDisplayShouldListDuplicateModes" as CFString: false, "kCGDisplayShowDuplicateLowResolutionModes" as CFString: true] as CFDictionary
            let all = (CGDisplayCopyAllDisplayModes(did, opts) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() && $0.width == w && $0.height == h }
            guard let mode = all.max(by: { $0.pixelWidth < $1.pixelWidth }) else { return }
            var cfg: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return }
            CGConfigureDisplayWithDisplayMode(cfg, did, mode, nil)
            CGCompleteDisplayConfiguration(cfg, .forSession)
        }
        refreshDisplays()
        hud("\(w)×\(h)")
    }

    func setOrientation(_ id: String, _ o: PanelOrientation) async { await rotate(id, o) }

    // MARK: identify

    private var identifyWindows: [NSWindow] = []

    /// Shows each display's name in its bottom-right corner for two seconds.
    func identifyDisplays() {
        identifyWindows.forEach { $0.close() }
        identifyWindows = []
        refreshDisplays()
        for d in displays {
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.id }) else { continue }
            let label = d.name
            let size = NSSize(width: 360, height: 120)
            let frame = NSRect(x: screen.frame.maxX - size.width - 40, y: screen.frame.minY + 40, width: size.width, height: size.height)
            let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.level = .screenSaver; w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false; w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.contentView = NSHostingView(rootView: Text(label)
                .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: size.width, height: size.height)
                .background(RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.78)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.5), lineWidth: 2)))
            w.orderFrontRegardless()
            identifyWindows.append(w)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.identifyWindows.forEach { $0.close() }; self?.identifyWindows = []
        }
    }

    // MARK: virtual displays

    func addVirtual() async {
        guard streaming else { return }
        guard virtuals.count < maxVirtualDisplays else { hud("En fazla \(maxVirtualDisplays) sanal ekran"); return }
        let index = (panels.map(\.desktopIndex).max() ?? 1) + 1
        let sid = UInt8(index - 1)
        hud("Yeni ekran oluşturuluyor…")
        guard let vd = VirtualDisplayManager.create(name: "Shellbreak \(index)", width: 1920, height: 1080) else {
            hud("Sanal ekran açılamadı"); lastError = "Sanal ekran oluşturulamadı"; return
        }
        VirtualDisplayManager.arrangeRight(vd.displayID)
        let stream = PanelStream(streamId: sid, displayID: vd.displayID, width: 1920, height: 1080)
        attach(stream)
        do { try await stream.start() } catch {
            registry.remove(sid); hud("Yayın başlatılamadı"); lastError = error.localizedDescription; return
        }
        let id = "desktop-\(index)"
        virtuals[id] = vd
        panels.append(PanelModel(id: id, kind: .virtual, streamId: Int(sid), desktopIndex: index, widthM: 1.6, aspect: 16.0 / 9.0, displayID: vd.displayID))
        sendScene()
        hud("Ekran \(index) eklendi")
        showControlWindow(on: vd.displayID)
        refreshDisplays()
    }

    func removeVirtual(_ id: String) async {
        guard let p = panels.first(where: { $0.id == id }), p.kind == .virtual else { hud("Ana ekran kaldırılamaz"); return }
        let sid = UInt8(p.streamId)
        if let s = registry.get(sid) { await s.stop() }
        registry.remove(sid)
        panels.removeAll { $0.id == id }
        virtuals[id] = nil          // dropping the last reference destroys the display; macOS moves its windows away
        if virtuals.isEmpty { controlWindow?.close(); controlWindow = nil }
        else if let d = virtuals.values.first?.displayID { showControlWindow(on: d) }
        sendScene()
        refreshDisplays()
        hud("Ekran \(p.desktopIndex) kaldırıldı")
    }

    fileprivate func rotate(_ id: String, _ o: PanelOrientation) async {
        guard let i = panels.firstIndex(where: { $0.id == id }) else { return }
        guard panels[i].kind == .virtual, let vd = virtuals[id], let s = registry.get(UInt8(panels[i].streamId)) else {
            hud("Ana ekran döndürülemez"); return
        }
        let cur = CGSize(width: vd.width, height: vd.height)
        let (w, h) = (o == .portrait) == (cur.height > cur.width) ? (Int(cur.width), Int(cur.height)) : (Int(cur.height), Int(cur.width))
        guard vd.setMode(width: w, height: h) else { hud("Döndürülemedi"); return }
        do { try await s.restart(width: w, height: h) } catch { lastError = error.localizedDescription; return }
        panels[i].orientation = o; panels[i].aspect = Double(w) / Double(h)
        sendScene()
        hud(o == .landscape ? "Yatay" : "Dikey")
    }

    /// The control panel as a normal window on a virtual display, so the headset can operate it with the cursor.
    private func showControlWindow(on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }) else { return }
        let size = NSSize(width: 380, height: min(760, screen.visibleFrame.height - 60))
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        if controlWindow == nil {
            let w = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.titled, .resizable, .miniaturizable, .closable],
                             backing: .buffered, defer: false)
            w.title = "Shellbreak Kontrol"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ControlView(host: self, scrollable: true))
            controlWindow = w
        }
        controlWindow?.setFrame(NSRect(origin: origin, size: size), display: true)
        controlWindow?.orderFrontRegardless()
    }

    func stop() async {
        inputController.stop()
        cursorStreamer?.stop(); cursorStreamer = nil
        controlWindow?.close(); controlWindow = nil
        for s in registry.all() { await s.stop() }
        registry.clear()
        virtuals.removeAll()        // destroys every virtual display
        panels = []
        server.stop()
        streaming = false
    }

    /// Called on app termination so no ghost monitors survive.
    func shutdownSync() {
        controlWindow?.close(); virtuals.removeAll()
    }

    private func updateDump() {
        dumpLock.lock(); defer { dumpLock.unlock() }
        if dumpToDesktop {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/stream.h265")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            dumpHandle = try? FileHandle(forWritingTo: url)
        } else { try? dumpHandle?.close(); dumpHandle = nil }
    }

    nonisolated private func dump(_ f: EncodedFrame) {
        dumpLock.lock(); defer { dumpLock.unlock() }
        try? dumpHandle?.write(contentsOf: f.annexB)
    }
}
