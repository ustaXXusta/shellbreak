import AppKit
import CoreGraphics
import DesktopARShared
import os

/// Screen ↔ layout mode via a session-level CGEventTap on its own run-loop thread.
/// Screen mode: only the exit key is intercepted. Layout mode: the macOS cursor is hidden and frozen,
/// all keyboard and mouse events are swallowed, and keys are mapped to `layout_command` for the phone.
final class InputModeController: @unchecked Sendable {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "input")
    private let lock = NSLock()
    private var machine = InputModeMachine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var cursorHidden = false

    var send: ((ControlMessage) -> Void)?
    var onModeChange: ((InputModeState) -> Void)?

    var style: ExitKeyStyle {
        get { lock.lock(); defer { lock.unlock() }; return machine.style }
        set { lock.lock(); machine.style = newValue; lock.unlock() }
    }

    private static let mouseTypes: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
        .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ]

    /// Returns false when the tap cannot be created (Accessibility / Input Monitoring missing).
    func start() -> Bool {
        var mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        for t in Self.mouseTypes { mask |= 1 << t.rawValue }
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<InputModeController>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: cb,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("event tap could not be created")
            return false
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        source = src
        let th = Thread { [weak self] in
            guard let self, let src = self.source else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        th.name = "dev.desktopar.eventtap"; th.qualityOfService = .userInteractive
        thread = th; th.start()
        return true
    }

    func stop() {
        forceScreen()
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let rl = runLoop { CFRunLoopStop(rl) }
        tap = nil; source = nil; thread = nil; runLoop = nil
    }

    /// Leave layout mode without a click (phone disconnected, streaming stopped, quit).
    func forceScreen() {
        lock.lock()
        let was = machine.mode == .layout
        machine.forceScreen()
        lock.unlock()
        if was { leaveLayout(notify: true) }
    }

    private func enterLayout() {
        if !cursorHidden { CGDisplayHideCursor(CGMainDisplayID()); cursorHidden = true }
        CGAssociateMouseAndMouseCursorPosition(0)
        send?(.inputMode(InputMode(mode: "layout")))
        onModeChange?(.layout)
    }

    private func leaveLayout(notify: Bool) {
        CGAssociateMouseAndMouseCursorPosition(1)
        if cursorHidden { CGDisplayShowCursor(CGMainDisplayID()); cursorHidden = false }
        if notify {
            send?(.inputMode(InputMode(mode: "screen")))
            onModeChange?(.screen)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        lock.lock(); let mode = machine.mode; lock.unlock()

        switch type {
        case .keyDown:
            let f = event.flags
            let key = KeyEvent(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                               command: f.contains(.maskCommand), option: f.contains(.maskAlternate),
                               control: f.contains(.maskControl), shift: f.contains(.maskShift),
                               isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                               time: ProcessInfo.processInfo.systemUptime)
            lock.lock(); let action = machine.handleKeyDown(key); lock.unlock()
            switch action {
            case .pass: return Unmanaged.passUnretained(event)
            case .swallow: return nil
            case .enterLayout: enterLayout(); return nil
            case .enterScreen: leaveLayout(notify: true); return nil
            case .layoutKey:
                var len = 0; var buf = [UniChar](repeating: 0, count: 4)
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
                let chars = String(utf16CodeUnits: buf, count: len)
                if let cmd = LayoutKeymap.command(keyCode: key.keyCode, characters: chars) {
                    send?(.layoutCommand(LayoutCommand(command: cmd.rawValue, shiftHeld: key.shift)))
                }
                return nil
            }
        case .keyUp:
            return mode == .layout ? nil : Unmanaged.passUnretained(event)
        default:
            return mode == .layout ? nil : Unmanaged.passUnretained(event)   // mouse + scroll swallowed in layout mode
        }
    }
}
