import Foundation
import CoreGraphics

/// Full list of display modes (including the scaled HiDPI ones System Settings offers) through CoreGraphics' private
/// `CGS*` functions, resolved with dlsym so a missing symbol only disables the feature. No SIP changes needed.
/// The public `CGDisplayCopyAllDisplayModes` hides the HiDPI modes on current macOS, so it cannot offer smaller text sizes.
struct SystemDisplayMode: Equatable, Identifiable {
    var number: Int32
    var width: Int
    var height: Int
    var density: Float            // 2 = HiDPI (backing is twice as large)
    var id: Int32 { number }
    var label: String { "\(width) × \(height)" + (density >= 2 ? " (HiDPI)" : "") }
    var backingWidth: Int { Int(Float(width) * density) }
    var backingHeight: Int { Int(Float(height) * density) }
}

enum SystemDisplayModes {
    private typealias GetCount = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias GetDesc = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> CGError
    private typealias Configure = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> CGError

    private static func sym<T>(_ name: String, as: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(p, to: T.self)
    }

    /// Layout of `CGSDisplayMode` (212 bytes): modeNumber@0, flags@4, width@8, height@12, depth@16, … density@208.
    static func list(_ display: CGDirectDisplayID) -> [SystemDisplayMode] {
        guard let count = sym("CGSGetNumberOfDisplayModes", as: GetCount.self),
              let desc = sym("CGSGetDisplayModeDescriptionOfLength", as: GetDesc.self) else { return [] }
        var n: Int32 = 0
        guard count(display, &n) == .success, n > 0 else { return [] }
        var out: [SystemDisplayMode] = []
        let buf = UnsafeMutableRawPointer.allocate(byteCount: 212, alignment: 8); defer { buf.deallocate() }
        for i in 0..<n {
            memset(buf, 0, 212)
            guard desc(display, i, buf, 212) == .success else { continue }
            let w = Int(buf.load(fromByteOffset: 8, as: UInt32.self)), h = Int(buf.load(fromByteOffset: 12, as: UInt32.self))
            let dens = buf.load(fromByteOffset: 208, as: Float.self)
            guard w > 0, h > 0 else { continue }
            out.append(SystemDisplayMode(number: buf.load(fromByteOffset: 0, as: Int32.self), width: w, height: h, density: dens > 0 ? dens : 1))
        }
        return out.sorted { ($0.width, $0.density) < ($1.width, $1.density) }
    }

    static func current(_ display: CGDirectDisplayID) -> SystemDisplayMode? {
        guard let m = CGDisplayCopyDisplayMode(display) else { return nil }
        let dens = Float(m.pixelWidth) / Float(max(m.width, 1))
        return list(display).first { $0.width == m.width && $0.height == m.height && abs($0.density - dens) < 0.1 }
    }

    @discardableResult
    static func set(_ display: CGDirectDisplayID, mode: SystemDisplayMode) -> Bool {
        guard let configure = sym("CGSConfigureDisplayMode", as: Configure.self) else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        guard configure(cfg, display, mode.number) == .success else { CGCancelDisplayConfiguration(cfg); return false }
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }
}
