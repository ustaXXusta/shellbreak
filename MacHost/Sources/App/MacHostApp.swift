import SwiftUI
import DesktopARShared

@main
struct MacHostApp: App {
    @StateObject private var host = HostController()

    var body: some Scene {
        MenuBarExtra {
            ControlView(host: host)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in host.shutdownSync() }
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
