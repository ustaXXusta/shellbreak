import SwiftUI
import MetalKit
import DesktopARShared

@main
struct PhoneClientApp: App {
    @StateObject private var model = StreamModel()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                MetalVideoView(decoder: model.decoder, settings: model.settings, cursor: model.cursor, ar: model.ar, hud: model.hud, stereo: model.stereo).ignoresSafeArea()
                if !model.stereo { VStack(alignment: .leading, spacing: 2) {
                    Text(model.status)
                    Text(String(format: "%.0f ms · %.0f fps · %@", model.latencyMs, model.fps, model.codec))
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(model.latencyMs > 300 ? .red : .green)
                .padding(8) }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 3) { model.settings.passthrough.toggle() }
            .onTapGesture(count: 2) { model.toggleStereo() }
            .background(Color.black)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                model.start()
            }
        }
    }
}

struct MetalVideoView: UIViewRepresentable {
    let decoder: VideoDecoder
    let settings: StereoSettings
    let cursor: CursorOverlay
    let ar: ARSessionController
    let hud: HUDOverlay
    let stereo: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var flat: FlatRenderer?; var stereo: StereoRenderer? }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.colorPixelFormat = .bgra8Unorm
        context.coordinator.flat = FlatRenderer(view: v, decoder: decoder, cursor: cursor)
        context.coordinator.stereo = StereoRenderer(view: v, decoder: decoder, settings: settings, cursor: cursor, ar: ar, hud: hud)
        v.delegate = stereo ? context.coordinator.stereo : context.coordinator.flat
        return v
    }
    func updateUIView(_ v: MTKView, context: Context) {
        v.delegate = stereo ? context.coordinator.stereo : context.coordinator.flat
    }
}
