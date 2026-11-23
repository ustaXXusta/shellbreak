import Foundation
import CoreGraphics
import os

/// Wraps the private CGVirtualDisplay API. Virtual displays vanish when the owning object is released
/// or the process exits, so every exit path only has to drop its references.
final class VirtualDisplay {
    let displayID: CGDirectDisplayID
    private let display: CGVirtualDisplay
    private(set) var width: Int
    private(set) var height: Int

    fileprivate init(display: CGVirtualDisplay, width: Int, height: Int) {
        self.display = display; self.displayID = display.displayID; self.width = width; self.height = height
    }

    /// Switch the display mode (landscape ↔ portrait).
    func setMode(width w: Int, height h: Int) -> Bool {
        let s = CGVirtualDisplaySettings()
        s.hiDPI = 0
        s.modes = [CGVirtualDisplayMode(width: UInt32(w), height: UInt32(h), refreshRate: 60)]
        guard display.apply(s) else { return false }
        width = w; height = h
        return true
    }
}

final class VirtualDisplayManager {
    private static let log = Logger(subsystem: "dev.desktopar.host", category: "displays")
    nonisolated(unsafe) private static var serial: UInt32 = 100

    static func create(name: String, width: Int, height: Int) -> VirtualDisplay? {
        let d = CGVirtualDisplayDescriptor()
        d.name = name
        d.maxPixelsWide = 3840; d.maxPixelsHigh = 3840   // any preset in either orientation
        d.sizeInMillimeters = CGSize(width: 508, height: 286)
        d.productID = 0x5342; d.vendorID = 0x5342
        serial += 1; d.serialNum = serial
        d.queue = DispatchQueue.main
        let vd = CGVirtualDisplay(descriptor: d)
        let s = CGVirtualDisplaySettings()
        s.hiDPI = 0
        s.modes = [CGVirtualDisplayMode(width: UInt32(width), height: UInt32(height), refreshRate: 60)]
        guard vd.apply(s), vd.displayID != 0 else { log.error("virtual display apply failed"); return nil }
        log.info("virtual display \(vd.displayID) \(width)x\(height)")
        return VirtualDisplay(display: vd, width: width, height: height)
    }

    /// Put `displayID` directly to the right of every other active display (macOS cursor then flows left → right).
    static func arrangeRight(_ displayID: CGDirectDisplayID) {
        var n: UInt32 = 0; CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n)); CGGetActiveDisplayList(n, &ids, &n)
        let right = ids.filter { $0 != displayID }.map { CGDisplayBounds($0).maxX }.max() ?? 0
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return }
        CGConfigureDisplayOrigin(cfg, displayID, Int32(right), 0)
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
}
