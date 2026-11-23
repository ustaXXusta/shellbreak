import SwiftUI
import MetalKit
import DesktopARShared

@main
struct PhoneClientApp: App {
    @StateObject private var model = StreamModel()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                MetalVideoView(decoder: model.decoder).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.status)
                    Text(String(format: "%.0f ms · %.0f fps · %@", model.latencyMs, model.fps, model.codec))
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(model.latencyMs > 300 ? .red : .green)
                .padding(8)
            }
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

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: FlatRenderer? }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.colorPixelFormat = .bgra8Unorm
        context.coordinator.renderer = FlatRenderer(view: v, decoder: decoder)
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
