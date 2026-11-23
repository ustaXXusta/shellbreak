import Foundation
import CoreGraphics
import SwiftUI
import DesktopARShared
import os

@MainActor
final class HostController: ObservableObject {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "host")
    @Published var permissions = PermissionStatus.current()
    @Published var phoneConnected = false
    @Published var streaming = false
    @Published var codecName = "-"
    @Published var dumpToDesktop = false { didSet { updateDump() } }
    @Published var lastError: String?

    private let capture = DisplayCapture()
    private var encoder: VideoEncoder?
    private let server = HostServer()
    nonisolated(unsafe) private var dumpHandle: FileHandle?
    nonisolated private let dumpLock = NSLock()

    func refreshPermissions() { permissions = PermissionStatus.current() }

    func start() async {
        refreshPermissions()
        if !permissions.screenRecording { _ = CGRequestScreenCaptureAccess(); lastError = "Screen Recording izni gerekli"; return }
        do {
            let id = CGMainDisplayID()
            let w = 1920, h = 1200
            let enc = VideoEncoder(width: w, height: h)
            try enc.start()
            enc.onFrame = { [weak self] f in
                guard let self else { return }
                self.server.sendVideo(streamId: 0, frame: f)
                self.dump(f)
            }
            server.onConnectionChange = { [weak self] up in Task { @MainActor in self?.phoneConnected = up } }
            server.onNeedKeyframe = { [weak enc] _ in enc?.requestKeyframe() }
            try server.start()
            capture.onFrame = { [weak enc] pb in enc?.encode(pb) }
            try await capture.start(displayID: id, width: w, height: h)
            encoder = enc
            codecName = enc.isHEVC ? "HEVC" : "H.264"
            streaming = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("start failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        await capture.stop()
        encoder?.stop(); encoder = nil
        server.stop()
        streaming = false
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
