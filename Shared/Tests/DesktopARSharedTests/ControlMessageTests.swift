import XCTest
@testable import DesktopARShared

final class ControlMessageTests: XCTestCase {
    func allMessages() -> [ControlMessage] {
        let panel = PanelInfo(id: "desktop-2", kind: .virtual, streamId: 1, desktopIndex: 2, widthM: 1.3,
                              aspect: 1.7778, curvature: 0.2, transform: Array(repeating: 1, count: 16))
        return [
            .hello(Hello(device: "iPhone14,2", screenWidth: 2532, screenHeight: 1170)),
            .ping(Ping(t0: 1_764_000_000_000_000)), .pong(Pong(t0: 1, t1: 2)),
            .scene(SceneMessage(revision: 12, panels: [panel, PanelInfo(id: "desktop-1", kind: .mirror, streamId: 0, desktopIndex: 1, widthM: 1.1, aspect: 1.6)])),
            .startupScan(StartupScan(desktops: 2, step: 1, status: "moving_windows", message: "Masaüstü 2/2")),
            .panelUpdate(PanelUpdate(panelId: "desktop-2", transform: Array(repeating: 0.5, count: 16), widthM: 1.6, curvature: 0.2)),
            .addDisplay(AddDisplay(afterPanelId: "desktop-2")), .removeDisplay(RemoveDisplay(panelId: "desktop-3")),
            .unhideAll, .rotate(Rotate(panelId: "desktop-2", orientation: .portrait)),
            .qualityRequest(QualityRequest(panelId: "desktop-2", level: .l3)), .requestIDR(RequestIDR(streamId: 1)),
            .inputMode(InputMode(mode: "layout")), .arInput(ARInput(kind: "move", dx: 3.5, dy: -1)),
            .layoutCommand(LayoutCommand(command: "toggle_orientation")),
            .enterScreen(EnterScreen(panelId: "desktop-2", u: 0.4, v: 0.7)),
            .cursor(CursorState(panelId: "desktop-1", u: 0.51, v: 0.33, visible: true, imageId: 7)),
            .cursorImage(CursorImage(imageId: 7, pngBase64: "AAAA", hotspotX: 4, hotspotY: 4, widthPt: 32, heightPt: 32)),
            .gazeFocus(GazeFocus(panelId: "desktop-2")), .calibration(Calibration()),
            .mode(ModeMessage(passthrough: true)), .hud(HUD(text: "Ana ekran döndürülemez")),
            .stats(Stats(fps: 59.8, latencyMs: 54, lossPct: 0.2, thermal: "nominal", battery: 0.78)),
        ]
    }

    func testRoundTripAll() throws {
        for m in allMessages() {
            XCTAssertEqual(try ControlMessage.decode(try m.encoded()), m, m.typeName)
        }
    }

    func testTypeFieldAndCamelCase() throws {
        let json = try JSONSerialization.jsonObject(with: ControlMessage.startupScan(
            StartupScan(desktops: 2, step: 1, status: "done", message: "x")).encoded()) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "startup_scan")
        XCTAssertNotNil(json?["desktops"])
        let cal = try JSONSerialization.jsonObject(with: ControlMessage.calibration(Calibration()).encoded()) as? [String: Any]
        XCTAssertNotNil(cal?["lensSeparationMm"]); XCTAssertNotNil(cal?["chromaticAberration"])
    }

    func testUnknownTypeIgnored() throws {
        let m = try ControlMessage.decode(Data(#"{"type":"future_thing","x":1}"#.utf8))
        XCTAssertEqual(m, .unknown("future_thing"))
    }

    func testSpecSceneJSONDecodes() throws {
        let s = #"{"type":"scene","revision":12,"panels":[{"id":"desktop-1","kind":"mirror","streamId":0,"desktopIndex":1,"widthM":1.1,"aspect":1.6,"orientation":"landscape","curvature":0,"visible":true,"level":"l2","transform":null}]}"#
        guard case .scene(let sc) = try ControlMessage.decode(Data(s.utf8)) else { return XCTFail() }
        XCTAssertNil(sc.panels[0].transform)
    }
}
