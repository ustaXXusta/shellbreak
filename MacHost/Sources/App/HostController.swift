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
    @Published var panelWidthM: Double = {
        let v = UserDefaults.standard.double(forKey: "panelWidthM"); return v > 0 ? v : 2.0
    }() { didSet { UserDefaults.standard.set(panelWidthM, forKey: "panelWidthM"); if !suppressScene { sendScene() } } }
    private var sceneRevision = 0
    private var suppressScene = false
    private func applyPhonePanelWidth(_ w: Double) {
        suppressScene = true; panelWidthM = w; suppressScene = false
    }
    func sendScene() {
        sceneRevision += 1
        server.send(.scene(SceneMessage(revision: sceneRevision, panels: [
            PanelInfo(id: "desktop-1", kind: .mirror, streamId: 0, desktopIndex: 1, widthM: panelWidthM, aspect: 1.6)])))
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

    private let capture = DisplayCapture()
    private var encoder: VideoEncoder?
    private let server = HostServer()
    private var cursorStreamer: CursorStreamer?
    private let inputController = InputModeController()
    @Published var inputMode: InputModeState = .screen
    @Published var exitKeyStyle: ExitKeyStyle = ExitKeyStyle(rawValue: UserDefaults.standard.string(forKey: "exitKeyStyle") ?? "") ?? .singleEsc {
        didSet { UserDefaults.standard.set(exitKeyStyle.rawValue, forKey: "exitKeyStyle"); inputController.style = exitKeyStyle }
    }
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
            server.onConnectionChange = { [weak self] up in
                Task { @MainActor in
                    self?.phoneConnected = up
                    self?.inputController.phoneConnected = up
                    if !up { self?.inputController.forceScreen() }   // never leave the Mac in layout mode without a headset
                }
            }
            server.onNeedKeyframe = { [weak enc] _ in enc?.requestKeyframe() }
            server.onMessage = { [weak self] msg in
                switch msg {
                case .addDisplay, .removeDisplay, .rotate: self?.server.send(.hud(HUD(text: "Bu özellik F5'te geliyor")))
                default: break
                }
                if case .enterScreen(let e) = msg { self?.inputController.enterScreen(u: e.u, v: e.v) }
                if case .panelUpdate(let u) = msg { Task { @MainActor in self?.applyPhonePanelWidth(u.widthM) } }
                if case .hello = msg { Task { @MainActor in
                    guard let self else { return }
                    self.server.send(.calibration(self.calibration))
                    self.sendScene()
                    self.server.send(.mode(ModeMessage(passthrough: self.passthrough)))
                    self.cursorStreamer?.resend()
                } }
            }
            try server.start()
            capture.onFrame = { [weak enc] pb in enc?.encode(pb) }
            try await capture.start(displayID: id, width: w, height: h)
            encoder = enc
            let cs = CursorStreamer(displayID: id) { [weak self] m in self?.server.send(m) }
            cs.start(); cursorStreamer = cs
            inputController.send = { [weak self] m in self?.server.send(m) }
            inputController.onModeChange = { [weak self] m in Task { @MainActor in self?.inputMode = m } }
            inputController.style = exitKeyStyle
            if !inputController.start() { lastError = "Esc/düzen modu için Accessibility + Input Monitoring izni gerekli" }
            codecName = enc.isHEVC ? "HEVC" : "H.264"
            streaming = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("start failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        inputController.stop()
        cursorStreamer?.stop(); cursorStreamer = nil
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
