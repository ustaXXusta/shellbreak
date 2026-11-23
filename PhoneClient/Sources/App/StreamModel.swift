import Foundation
import SwiftUI
import DesktopARShared

/// Glue: connection → decoder, latency watchdog, overlay stats.
@MainActor
final class StreamModel: ObservableObject {
    @Published var status = "Başlıyor…"
    @Published var latencyMs: Double = 0
    @Published var fps: Double = 0
    @Published var codec = "-"

    let connection = HostConnection()
    let settings = StereoSettings()
    let cursor = CursorOverlay()
    let ar = ARSessionController()
    let hud = HUDOverlay()
    @Published var stereo = true
    let decoder = VideoDecoder()
    private var lastIDR = Date.distantPast
    private var overSince: Date?
    private var fpsCount = 0
    private var fpsTick = Date()
    private var latencyAcc: [Double] = []

    func toggleStereo() { stereo.toggle(); settings.stereo = stereo }

    func start() {
        connection.onState = { [weak self] s in
            Task { @MainActor in
                self?.status = s
                if s == "Bağlı" { self?.hud.flash("Bağlı · Esc: düzen modu", seconds: 3) }
                if s.hasPrefix("Yeniden") { /* keep last frame on screen */ }
            }
        }
        connection.onMessage = { [weak self] msg in
            switch msg {
            case .calibration(let c): self?.settings.calibration = c
            case .scene(let sc): if let p = sc.panels.first { self?.settings.panelWidthM = Float(p.widthM) }
            case .mode(let m): self?.settings.passthrough = m.passthrough
            case .cursor(let c): self?.cursor.update(c)
            case .cursorImage(let i): self?.cursor.update(i)
            case .hud(let h) where h.text == "!recenter": self?.settings.requestRecenter()
            case .hud(let h): self?.hud.flash(h.text, seconds: 2.5)
            case .inputMode(let m):
                if m.mode == "layout" { self?.hud.setPersistent("DÜZEN MODU · Esc: ekran modu") }
                else { self?.hud.setPersistent(nil); self?.hud.flash("Ekran modu") }
            case .layoutCommand(let c): self?.settings.enqueue(c)
            default: break
            }
        }
        connection.onVideoPacket = { [weak self] p in self?.handle(p) }
        decoder.onDecoded = { [weak self] captureUs in self?.decoded(captureUs) }
        settings.onPanelChanged = { [weak self] t, w in
            self?.connection.send(.panelUpdate(PanelUpdate(panelId: "desktop-1", transform: t, widthM: Double(w), curvature: 0)))
        }
        ar.start()
        connection.start()
    }

    private nonisolated func handle(_ p: VideoPacket) {
        let off = connection.clockOffsetUs
        let age = ClockSync.ageMs(captureTimeUs: p.header.captureTimeUs, nowUs: HostConnection.nowUs(), offsetUs: off)
        if age > 300 && !p.header.flags.contains(.keyframe) {
            Task { @MainActor in self.watchdog(age: age) }
            return // drop stale frame
        }
        decoder.decode(annexB: p.payload, hevc: p.header.flags.contains(.hevc), captureTimeUs: p.header.captureTimeUs)
        Task { @MainActor in self.codec = p.header.flags.contains(.hevc) ? "HEVC" : "H.264" }
    }

    private nonisolated func decoded(_ captureUs: UInt64) {
        let age = ClockSync.ageMs(captureTimeUs: captureUs, nowUs: HostConnection.nowUs(), offsetUs: connection.clockOffsetUs)
        Task { @MainActor in
            self.latencyAcc.append(age); self.fpsCount += 1
            let now = Date()
            if now.timeIntervalSince(self.fpsTick) >= 0.5 {
                self.fps = Double(self.fpsCount) / now.timeIntervalSince(self.fpsTick)
                self.latencyMs = self.latencyAcc.reduce(0, +) / Double(self.latencyAcc.count)
                self.fpsCount = 0; self.latencyAcc = []; self.fpsTick = now
            }
            if age > 500 { if self.overSince == nil { self.overSince = now } } else { self.overSince = nil }
        }
    }

    private func watchdog(age: Double) {
        guard Date().timeIntervalSince(lastIDR) > 0.5 else { return }
        lastIDR = Date()
        connection.send(.requestIDR(RequestIDR(streamId: 0)))
    }
}
