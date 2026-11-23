import SwiftUI
import DesktopARShared

/// Mini "Displays → Arrange" editor: drag the monitors to where they stand in the room;
/// macOS then moves the mouse and windows across their shared edges like physical monitors.
struct DisplayArrangementView: View {
    @ObservedObject var host: HostController
    @State private var drag: [CGDirectDisplayID: CGSize] = [:]
    private let canvas = CGSize(width: 320, height: 150)
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var union: CGRect { host.displays.map(\.bounds).reduce(CGRect.null) { $0.union($1) } }
    private var scale: CGFloat {
        let u = union.insetBy(dx: -600, dy: -300)
        guard !u.isNull, u.width > 0 else { return 0.05 }
        return min(canvas.width / u.width, canvas.height / u.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25))
                ForEach(host.displays) { d in
                    let u = union.insetBy(dx: -600, dy: -300)
                    let off = drag[d.id] ?? .zero
                    RoundedRectangle(cornerRadius: 4)
                        .fill(d.isPanel ? Color.accentColor.opacity(0.55) : Color.gray.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(d.isMain ? 0.9 : 0.4), lineWidth: d.isMain ? 2 : 1))
                        .overlay(Text(d.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white))
                        .frame(width: d.bounds.width * scale, height: d.bounds.height * scale)
                        .offset(x: (d.bounds.minX - u.minX) * scale + off.width, y: (d.bounds.minY - u.minY) * scale + off.height)
                        .gesture(DragGesture()
                            .onChanged { v in if !d.isMain { drag[d.id] = v.translation } }
                            .onEnded { v in
                                drag[d.id] = nil
                                guard !d.isMain else { return }
                                host.moveDisplay(d.id, to: d.bounds.offsetBy(dx: v.translation.width / scale, dy: v.translation.height / scale))
                            })
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            HStack {
                Button("Odadaki sıraya diz") { host.arrangeRow() }
                Button("Yenile") { host.refreshDisplays() }
            }
            Text("Ekranları sürükle: kenarları birleşince fare ve pencereler bir ekrandan diğerine geçer.").font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { host.refreshDisplays() }
        .onReceive(timer) { _ in host.refreshDisplays() }
    }
}
