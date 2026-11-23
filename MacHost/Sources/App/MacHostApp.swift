import SwiftUI
import DesktopARShared

@main
struct MacHostApp: App {
    @StateObject private var host = HostController()

    var body: some Scene {
        MenuBarExtra("DesktopAR", systemImage: "display.2") {
            Text("DesktopAR Host (protocol v\(ProtocolConstants.version))")
            Divider()
            permissionRow("Screen Recording", host.permissions.screenRecording, "Privacy_ScreenCapture")
            permissionRow("Accessibility", host.permissions.accessibility, "Privacy_Accessibility")
            permissionRow("Input Monitoring", host.permissions.inputMonitoring, "Privacy_ListenEvent")
            Button("İzinleri yenile") { host.refreshPermissions() }
            Divider()
            Text(host.phoneConnected ? "Telefon bağlı" : "Telefon bağlı değil")
            Text(host.streaming ? "Yayın: \(host.codecName)" : "Yayın kapalı")
            if let e = host.lastError { Text("Hata: \(e)") }
            Button(host.streaming ? "Yayını durdur" : "Yayını başlat") {
                Task { if host.streaming { await host.stop() } else { await host.start() } }
            }
            Toggle("Debug: ~/Desktop/stream.h265", isOn: $host.dumpToDesktop)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, _ ok: Bool, _ pane: String) -> some View {
        Button("\(ok ? "✓" : "✗") \(name)") { if !ok { PermissionStatus.openSettings(pane) } }
    }
}
