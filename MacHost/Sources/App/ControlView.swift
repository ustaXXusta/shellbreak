import SwiftUI
import DesktopARShared

/// The Shellbreak control panel: shown in the menu-bar popover and in a window on the virtual display.
struct ControlView: View {
    @ObservedObject var host: HostController
    var scrollable = false

    var body: some View {
        // Always scrollable: the panel is taller than a laptop screen once the display editor is included.
        let h = min(720, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        ScrollView(.vertical, showsIndicators: true) { content }
            .frame(width: 340, height: scrollable ? nil : h)
            .frame(minHeight: scrollable ? 400 : nil)
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.kind == .mirror ? "1 · Ana ekran (yansıtma)" : "\(p.desktopIndex) · Sanal ekran").font(.subheadline.bold())
                            Spacer()
                            if p.kind == .virtual { Button("Kaldır") { Task { await host.removeVirtual(p.id) } } }
                        }
                        if p.kind == .virtual {
                            Picker("Yön", selection: Binding(get: { p.orientation }, set: { o in Task { await host.setOrientation(p.id, o) } })) {
                                Text("Yatay").tag(PanelOrientation.landscape); Text("Dikey").tag(PanelOrientation.portrait)
                            }.pickerStyle(.segmented)
                        }
                        ResolutionPicker(host: host, panel: p)
                    }
                    .padding(.vertical, 2)
                }
                Button("Yeni ekran ekle") { Task { await host.addVirtual() } }.disabled(!host.streaming)
                Divider()
                Text("Ekran düzeni").font(.headline)
                DisplayArrangementView(host: host)
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
                slider("Magnetli ekran eğriliği", $host.calibration.joinBend, 0...1, "%.2f")
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
            .frame(width: 316, alignment: .leading)
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

/// Resolution list for one panel: portrait displays list portrait sizes, landscape ones landscape sizes.
/// A lower resolution makes text and windows bigger at the same panel size.
struct ResolutionPicker: View {
    @ObservedObject var host: HostController
    let panel: PanelModel
    private func key(_ s: CGSize) -> String { "\(Int(s.width))x\(Int(s.height))" }
    var body: some View {
        let options = host.resolutionOptions(for: panel)
        let cur = host.currentResolution(panel)
        let all = options.contains(where: { key($0) == key(cur) }) ? options : [cur] + options
        Picker("Çözünürlük", selection: Binding(get: { key(cur) }, set: { k in
            if let n = all.first(where: { key($0) == k }) { Task { await host.setResolution(panel.id, n) } }
        })) {
            ForEach(all.map(key), id: \.self) { k in Text(k.replacingOccurrences(of: "x", with: " × ")).tag(k) }
        }
        .font(.caption)
    }
}
