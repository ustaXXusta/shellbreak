import Foundation

public enum PanelKind: String, Codable, Equatable { case mirror, virtual }
public enum PanelOrientation: String, Codable, Equatable { case landscape, portrait }
public enum QualityLevel: String, Codable, Equatable, CaseIterable { case l1, l2, l3, l4 }

public struct PanelInfo: Codable, Equatable {
    public var id: String
    public var kind: PanelKind
    public var streamId: Int
    public var desktopIndex: Int
    public var widthM: Double
    public var aspect: Double
    public var orientation: PanelOrientation
    public var curvature: Double
    public var visible: Bool
    public var level: QualityLevel
    public var transform: [Float]?
    public init(id: String, kind: PanelKind, streamId: Int, desktopIndex: Int, widthM: Double, aspect: Double,
                orientation: PanelOrientation = .landscape, curvature: Double = 0, visible: Bool = true,
                level: QualityLevel = .l2, transform: [Float]? = nil) {
        self.id = id; self.kind = kind; self.streamId = streamId; self.desktopIndex = desktopIndex
        self.widthM = widthM; self.aspect = aspect; self.orientation = orientation
        self.curvature = curvature; self.visible = visible; self.level = level; self.transform = transform
    }
}

public struct Hello: Codable, Equatable {
    public var role: String; public var version: Int; public var device: String
    public var screenWidth: Int; public var screenHeight: Int
    public init(role: String = "phone", version: Int = ProtocolConstants.version, device: String, screenWidth: Int, screenHeight: Int) {
        self.role = role; self.version = version; self.device = device
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}
public struct Ping: Codable, Equatable { public var t0: Int64; public init(t0: Int64) { self.t0 = t0 } }
public struct Pong: Codable, Equatable {
    public var t0: Int64; public var t1: Int64
    public init(t0: Int64, t1: Int64) { self.t0 = t0; self.t1 = t1 }
}
public struct SceneMessage: Codable, Equatable {
    public var revision: Int; public var panels: [PanelInfo]
    public init(revision: Int, panels: [PanelInfo]) { self.revision = revision; self.panels = panels }
}
public struct StartupScan: Codable, Equatable {
    public var desktops: Int; public var step: Int; public var status: String; public var message: String
    public init(desktops: Int, step: Int, status: String, message: String) {
        self.desktops = desktops; self.step = step; self.status = status; self.message = message
    }
}
public struct PanelUpdate: Codable, Equatable {
    public var panelId: String; public var transform: [Float]; public var widthM: Double; public var curvature: Double
    public init(panelId: String, transform: [Float], widthM: Double, curvature: Double) {
        self.panelId = panelId; self.transform = transform; self.widthM = widthM; self.curvature = curvature
    }
}
public struct AddDisplay: Codable, Equatable { public var afterPanelId: String; public init(afterPanelId: String) { self.afterPanelId = afterPanelId } }
public struct RemoveDisplay: Codable, Equatable { public var panelId: String; public init(panelId: String) { self.panelId = panelId } }
public struct Rotate: Codable, Equatable {
    public var panelId: String; public var orientation: PanelOrientation
    public init(panelId: String, orientation: PanelOrientation) { self.panelId = panelId; self.orientation = orientation }
}
public struct QualityRequest: Codable, Equatable {
    public var panelId: String; public var level: QualityLevel
    public init(panelId: String, level: QualityLevel) { self.panelId = panelId; self.level = level }
}
public struct RequestIDR: Codable, Equatable { public var streamId: Int; public init(streamId: Int) { self.streamId = streamId } }
public struct InputMode: Codable, Equatable { public var mode: String; public init(mode: String) { self.mode = mode } }
public struct ARInput: Codable, Equatable {
    public var kind: String; public var dx: Double; public var dy: Double
    public var scrollY: Double; public var magnification: Double
    public var optionHeld: Bool; public var shiftHeld: Bool
    public init(kind: String, dx: Double = 0, dy: Double = 0, scrollY: Double = 0, magnification: Double = 0,
                optionHeld: Bool = false, shiftHeld: Bool = false) {
        self.kind = kind; self.dx = dx; self.dy = dy; self.scrollY = scrollY
        self.magnification = magnification; self.optionHeld = optionHeld; self.shiftHeld = shiftHeld
    }
}
public struct LayoutCommand: Codable, Equatable {
    public var command: String; public var shiftHeld: Bool
    public init(command: String, shiftHeld: Bool = false) { self.command = command; self.shiftHeld = shiftHeld }
}
public struct EnterScreen: Codable, Equatable {
    public var panelId: String; public var u: Double; public var v: Double
    public init(panelId: String, u: Double, v: Double) { self.panelId = panelId; self.u = u; self.v = v }
}
/// Two panels were joined with magnets: panel B sits against edge `edgeA` of panel A, on B's opposite edge
/// (edges: 0 left, 1 right, 2 top, 3 bottom).
public struct MagnetJoin: Codable, Equatable {
    public var panelA: String; public var edgeA: Int; public var panelB: String; public var edgeB: Int
    public init(panelA: String, edgeA: Int, panelB: String, edgeB: Int) {
        self.panelA = panelA; self.edgeA = edgeA; self.panelB = panelB; self.edgeB = edgeB
    }
}
public struct CursorState: Codable, Equatable {
    public var panelId: String; public var u: Double; public var v: Double; public var visible: Bool; public var imageId: Int
    public init(panelId: String, u: Double, v: Double, visible: Bool, imageId: Int) {
        self.panelId = panelId; self.u = u; self.v = v; self.visible = visible; self.imageId = imageId
    }
}
public struct CursorImage: Codable, Equatable {
    public var imageId: Int; public var pngBase64: String
    public var hotspotX: Double; public var hotspotY: Double; public var widthPt: Double; public var heightPt: Double
    /// Width of the captured display in points; lets the phone size the cursor relative to the panel (optional on the wire).
    public var displayWidthPt: Double?
    public init(imageId: Int, pngBase64: String, hotspotX: Double, hotspotY: Double, widthPt: Double, heightPt: Double,
                displayWidthPt: Double? = nil) {
        self.imageId = imageId; self.pngBase64 = pngBase64; self.hotspotX = hotspotX
        self.hotspotY = hotspotY; self.widthPt = widthPt; self.heightPt = heightPt; self.displayWidthPt = displayWidthPt
    }
}
public struct GazeFocus: Codable, Equatable { public var panelId: String; public init(panelId: String) { self.panelId = panelId } }
public struct Calibration: Codable, Equatable {
    public var lensSeparationMm: Double, screenToLensMm: Double, verticalOffsetMm: Double
    public var k1: Double, k2: Double, fovDegrees: Double, chromaticAberration: Double, sharpen: Double, supersample: Double
    /// Show the grid + centre-cross test pattern instead of the video (optional on the wire, default false).
    public var testPattern: Bool
    /// How strongly magnet-joined screens bend toward the viewer, 0 (flat) … 1 (fully facing). Optional on the wire.
    public var joinBend: Double
    public init(lensSeparationMm: Double = 63, screenToLensMm: Double = 39, verticalOffsetMm: Double = 0,
                k1: Double = 0.34, k2: Double = 0.55, fovDegrees: Double = 90,
                chromaticAberration: Double = 0.008, sharpen: Double = 0.3, supersample: Double = 1.25,
                testPattern: Bool = false, joinBend: Double = 0.7) {
        self.lensSeparationMm = lensSeparationMm; self.screenToLensMm = screenToLensMm
        self.verticalOffsetMm = verticalOffsetMm; self.k1 = k1; self.k2 = k2; self.fovDegrees = fovDegrees
        self.chromaticAberration = chromaticAberration; self.sharpen = sharpen; self.supersample = supersample
        self.testPattern = testPattern; self.joinBend = joinBend
    }
    private enum CodingKeys: String, CodingKey {
        case lensSeparationMm, screenToLensMm, verticalOffsetMm, k1, k2, fovDegrees, chromaticAberration, sharpen, supersample, testPattern, joinBend
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lensSeparationMm = try c.decode(Double.self, forKey: .lensSeparationMm)
        screenToLensMm = try c.decode(Double.self, forKey: .screenToLensMm)
        verticalOffsetMm = try c.decode(Double.self, forKey: .verticalOffsetMm)
        k1 = try c.decode(Double.self, forKey: .k1); k2 = try c.decode(Double.self, forKey: .k2)
        fovDegrees = try c.decode(Double.self, forKey: .fovDegrees)
        chromaticAberration = try c.decode(Double.self, forKey: .chromaticAberration)
        sharpen = try c.decode(Double.self, forKey: .sharpen); supersample = try c.decode(Double.self, forKey: .supersample)
        testPattern = try c.decodeIfPresent(Bool.self, forKey: .testPattern) ?? false
        joinBend = try c.decodeIfPresent(Double.self, forKey: .joinBend) ?? 0.7
    }
}
public struct ModeMessage: Codable, Equatable { public var passthrough: Bool; public init(passthrough: Bool) { self.passthrough = passthrough } }
public struct HUD: Codable, Equatable { public var text: String; public init(text: String) { self.text = text } }
public struct Stats: Codable, Equatable {
    public var fps: Double; public var latencyMs: Double; public var lossPct: Double; public var thermal: String; public var battery: Double
    public init(fps: Double, latencyMs: Double, lossPct: Double, thermal: String, battery: Double) {
        self.fps = fps; self.latencyMs = latencyMs; self.lossPct = lossPct; self.thermal = thermal; self.battery = battery
    }
}

/// All control messages; JSON with a snake_case `type` discriminator. Unknown types decode to `.unknown`.
public enum ControlMessage: Equatable {
    case hello(Hello), ping(Ping), pong(Pong), scene(SceneMessage), startupScan(StartupScan)
    case panelUpdate(PanelUpdate), addDisplay(AddDisplay), removeDisplay(RemoveDisplay), unhideAll
    case rotate(Rotate), qualityRequest(QualityRequest), requestIDR(RequestIDR)
    case inputMode(InputMode), arInput(ARInput), layoutCommand(LayoutCommand), enterScreen(EnterScreen), magnet(MagnetJoin)
    case cursor(CursorState), cursorImage(CursorImage), gazeFocus(GazeFocus)
    case calibration(Calibration), mode(ModeMessage), hud(HUD), stats(Stats)
    case unknown(String)

    public var typeName: String {
        switch self {
        case .hello: "hello"; case .ping: "ping"; case .pong: "pong"; case .scene: "scene"
        case .startupScan: "startup_scan"; case .panelUpdate: "panel_update"; case .addDisplay: "add_display"
        case .removeDisplay: "remove_display"; case .unhideAll: "unhide_all"; case .rotate: "rotate"
        case .qualityRequest: "quality_request"; case .requestIDR: "request_idr"; case .inputMode: "input_mode"
        case .arInput: "ar_input"; case .layoutCommand: "layout_command"; case .enterScreen: "enter_screen"; case .magnet: "magnet"
        case .cursor: "cursor"; case .cursorImage: "cursor_image"; case .gazeFocus: "gaze_focus"
        case .calibration: "calibration"; case .mode: "mode"; case .hud: "hud"; case .stats: "stats"
        case .unknown(let t): t
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
    public static func decode(_ data: Data) throws -> ControlMessage {
        try JSONDecoder().decode(ControlMessage.self, from: data)
    }
}

extension ControlMessage: Codable {
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let t = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        func p<T: Decodable>(_ type: T.Type) throws -> T { try T(from: decoder) }
        switch t {
        case "hello": self = .hello(try p(Hello.self))
        case "ping": self = .ping(try p(Ping.self))
        case "pong": self = .pong(try p(Pong.self))
        case "scene": self = .scene(try p(SceneMessage.self))
        case "startup_scan": self = .startupScan(try p(StartupScan.self))
        case "panel_update": self = .panelUpdate(try p(PanelUpdate.self))
        case "add_display": self = .addDisplay(try p(AddDisplay.self))
        case "remove_display": self = .removeDisplay(try p(RemoveDisplay.self))
        case "unhide_all": self = .unhideAll
        case "rotate": self = .rotate(try p(Rotate.self))
        case "quality_request": self = .qualityRequest(try p(QualityRequest.self))
        case "request_idr": self = .requestIDR(try p(RequestIDR.self))
        case "input_mode": self = .inputMode(try p(InputMode.self))
        case "ar_input": self = .arInput(try p(ARInput.self))
        case "layout_command": self = .layoutCommand(try p(LayoutCommand.self))
        case "enter_screen": self = .enterScreen(try p(EnterScreen.self))
        case "magnet": self = .magnet(try p(MagnetJoin.self))
        case "cursor": self = .cursor(try p(CursorState.self))
        case "cursor_image": self = .cursorImage(try p(CursorImage.self))
        case "gaze_focus": self = .gazeFocus(try p(GazeFocus.self))
        case "calibration": self = .calibration(try p(Calibration.self))
        case "mode": self = .mode(try p(ModeMessage.self))
        case "hud": self = .hud(try p(HUD.self))
        case "stats": self = .stats(try p(Stats.self))
        default: self = .unknown(t)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .hello(let m): try m.encode(to: encoder)
        case .ping(let m): try m.encode(to: encoder)
        case .pong(let m): try m.encode(to: encoder)
        case .scene(let m): try m.encode(to: encoder)
        case .startupScan(let m): try m.encode(to: encoder)
        case .panelUpdate(let m): try m.encode(to: encoder)
        case .addDisplay(let m): try m.encode(to: encoder)
        case .removeDisplay(let m): try m.encode(to: encoder)
        case .unhideAll, .unknown: break
        case .rotate(let m): try m.encode(to: encoder)
        case .qualityRequest(let m): try m.encode(to: encoder)
        case .requestIDR(let m): try m.encode(to: encoder)
        case .inputMode(let m): try m.encode(to: encoder)
        case .arInput(let m): try m.encode(to: encoder)
        case .layoutCommand(let m): try m.encode(to: encoder)
        case .enterScreen(let m): try m.encode(to: encoder)
        case .magnet(let m): try m.encode(to: encoder)
        case .cursor(let m): try m.encode(to: encoder)
        case .cursorImage(let m): try m.encode(to: encoder)
        case .gazeFocus(let m): try m.encode(to: encoder)
        case .calibration(let m): try m.encode(to: encoder)
        case .mode(let m): try m.encode(to: encoder)
        case .hud(let m): try m.encode(to: encoder)
        case .stats(let m): try m.encode(to: encoder)
        }
    }
}
