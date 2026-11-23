import SwiftUI
import DesktopARShared

@main
struct MacHostApp: App {
    var body: some Scene {
        MenuBarExtra("DesktopAR", systemImage: "display.2") {
            Text("DesktopAR Host (protocol v\(ProtocolConstants.version))")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
