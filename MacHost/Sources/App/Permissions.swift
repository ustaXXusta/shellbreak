import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

struct PermissionStatus {
    var screenRecording: Bool
    var accessibility: Bool
    var inputMonitoring: Bool

    static func current() -> PermissionStatus {
        PermissionStatus(screenRecording: CGPreflightScreenCaptureAccess(),
                         accessibility: AXIsProcessTrusted(),
                         inputMonitoring: CGPreflightListenEventAccess())
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
