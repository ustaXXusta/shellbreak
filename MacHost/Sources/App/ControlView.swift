import SwiftUI
import DesktopARShared

/// The Shellbreak control panel: shown in the menu-bar popover and in a window on the virtual display.
struct ControlView: View {
    @ObservedObject var host: HostController
    var scrollable = false

    var body: some View {
        if scrollable { ScrollView { content }.frame(minWidth: 360, minHeight: 520) } else { content }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shellbreak (protocol v\(ProtocolConstants.version))").font(.headline)
                Divider()
                permissionRow("Screen Recording", host.permissions.screenRecording, "Privacy_ScreenCapture")
                permissionRow("Accessibility", host.permissions.accessibility, "Privacy_Accessibility")
                permissionRow("Input Monitoring", host.permissions.inputMonitoring, "Privacy_ListenEvent")
                Button("İzinleri yenile") { host.refreshPermissions() }
                Divider()
                Text(host.phoneConnected ? "Telefon bağlı" : "Telefon bağlı değil")
                Text(host.streaming ? "Yayın: \(host.codecName)" : "Yayın kapalı")
                if let e = host.lastError { Text("Hata: \(e)") }
                Divider()
                Text("Ekranlar").font(.headline)
                ForEach(host.panels) { p in
                    HStack {
                        Text(p.kind == .mirror ? "1 · Ana ekran (yansıtma)" : "\(p.desktopIndex) · Sanal ekran")
                        Spacer()
                        if p.kind == .virtual { Button("Kaldır") { Task { await host.removeVirtual(p.id) } } }
                    }
                }
                Text("Ekran düzeni").font(.headline)
                DisplayArrangementView(host: host)
                Button("Yeni ekran ekle") { Task { await host.addVirtual() } }.disabled(!host.streaming)
                Button(host.streaming ? "Yayını durdur" : "Yayını başlat") {
                    Task { if host.streaming { await host.stop() } else { await host.start() } }
                }
                Toggle("Debug: ~/Desktop/stream.h265", isOn: $host.dumpToDesktop)
                Divider()
                Picker("Çıkış tuşu", selection: $host.exitKeyStyle) {
                    Text("Esc").tag(ExitKeyStyle.singleEsc); Text("Esc Esc").tag(ExitKeyStyle.doubleEsc); Text("⌃Esc").tag(ExitKeyStyle.ctrlEsc)
                }
                if host.exitKeyStyle == .singleEsc { Text("Esc artık uygulamalara ulaşmaz").font(.caption).foregroundStyle(.secondary) }
                Text(host.inputMode == .layout ? "DÜZEN MODU (Esc/Enter: ekran modu)" : "Ekran modu").font(.caption)
                slider("Panel genişliği (m)", $host.panelWidthM, 0.5...4, "%.2f")
                Text("Gözlük kalibrasyonu").font(.headline)
                Toggle("Gerçek dünya (passthrough)", isOn: $host.passthrough)
                Toggle("Test deseni (ızgara + artı)", isOn: $host.calibration.testPattern)
                slider("Lens arası (mm)", $host.calibration.lensSeparationMm, 20...75, "%.1f")
                slider("Dikey kayma (mm)", $host.calibration.verticalOffsetMm, -15...15, "%.1f")
                slider("k1", $host.calibration.k1, 0...1, "%.2f")
                slider("k2", $host.calibration.k2, 0...1.5, "%.2f")
                slider("FOV (°)", $host.calibration.fovDegrees, 50...120, "%.0f")
                slider("Renk sapması", $host.calibration.chromaticAberration, 0...0.03, "%.3f")
                slider("Keskinlik", $host.calibration.sharpen, 0...1, "%.2f")
                slider("Supersample", $host.calibration.supersample, 0.75...1.75, "%.2f")
                HStack {
                    Button("Görüşü ortala") { host.recenterPhone() }
                    Button("Sıfırla") { host.resetCalibration() }
                }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(title): \(String(format: fmt, value.wrappedValue))").font(.caption)
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, _ ok: Bool, _ pane: String) -> some View {
        Button("\(ok ? "✓" : "✗") \(name)") { if !ok { PermissionStatus.openSettings(pane) } }
    }
}
