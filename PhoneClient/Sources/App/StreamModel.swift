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
    let decoder = VideoDecoder()
    private var lastIDR = Date.distantPast
    private var overSince: Date?
    private var fpsCount = 0
    private var fpsTick = Date()
    private var latencyAcc: [Double] = []

    func start() {
        connection.onState = { [weak self] s in
            Task { @MainActor in
                self?.status = s
                if s.hasPrefix("Yeniden") { /* keep last frame on screen */ }
            }
        }
        connection.onVideoPacket = { [weak self] p in self?.handle(p) }
        decoder.onDecoded = { [weak self] captureUs in self?.decoded(captureUs) }
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
