import AppKit
import CoreGraphics
import DesktopARShared
import os

/// Screen mode: streams the macOS cursor position (≤ 120 Hz, only on change) and its image (on change)
/// so the phone draws the cursor itself instead of baking it into the video.
@MainActor
final class CursorStreamer {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "cursor")
    private var timer: DispatchSourceTimer?
    private let send: (ControlMessage) -> Void
    private var lastState: CursorState?
    private var lastImage: CursorImage?
    private var lastHash = 0
    private var imageId = 0
    private var tick = 0
    /// Current panel → display mapping (first entry is the mirror).
    private let displays: () -> [(panelId: String, displayID: CGDirectDisplayID)]
    private var lastPanelId = "desktop-1"

    init(displays: @escaping () -> [(panelId: String, displayID: CGDirectDisplayID)], send: @escaping (ControlMessage) -> Void) {
        self.displays = displays; self.send = send
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.poll() } }
        t.resume(); timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    /// Re-send everything (a phone just connected).
    func resend() {
        if let i = lastImage { send(.cursorImage(i)) }
        if let s = lastState { send(.cursor(s)) }
    }

    private func poll() {
        tick += 1
        if tick % 12 == 1 { refreshImage() }
        guard let loc = CGEvent(source: nil)?.location else { return }
        let list = displays()
        let hit = list.first { CGDisplayBounds($0.displayID).contains(loc) }
        let inside = hit != nil
        if let hit { lastPanelId = hit.panelId }
        let b = CGDisplayBounds((hit ?? list.first(where: { $0.panelId == lastPanelId }) ?? list.first)?.displayID ?? CGMainDisplayID())
        let u = min(max((loc.x - b.minX) / b.width, 0), 1), v = min(max((loc.y - b.minY) / b.height, 0), 1)
        let s = CursorState(panelId: lastPanelId, u: u, v: v, visible: inside, imageId: imageId)
        if s != lastState { lastState = s; send(.cursor(s)) }
    }

    private func refreshImage() {
        guard let c = NSCursor.currentSystem, let tiff = c.image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        let h = png.hashValue
        guard h != lastHash else { return }
        lastHash = h; imageId += 1
        let img = CursorImage(imageId: imageId, pngBase64: png.base64EncodedString(),
                              hotspotX: c.hotSpot.x, hotspotY: c.hotSpot.y,
                              widthPt: c.image.size.width, heightPt: c.image.size.height,
                              displayWidthPt: CGDisplayBounds(CGMainDisplayID()).width)
        lastImage = img
        send(.cursorImage(img))
    }
}
