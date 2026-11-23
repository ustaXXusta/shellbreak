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
    /// Layout mode needs a headset to show it; without a phone the exit key is passed through untouched.
    var phoneConnected: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _phoneConnected }
        set { lock.lock(); _phoneConnected = newValue; lock.unlock() }
    }
    private var _phoneConnected = false
    private var pendingDX = 0.0, pendingDY = 0.0
    private var flushTimer: DispatchSourceTimer?

    /// Click inside a panel: put the macOS cursor at the clicked point and leave layout mode.
    func enterScreen(u: Double, v: Double, displayID: CGDirectDisplayID = CGMainDisplayID()) {
        let b = CGDisplayBounds(displayID)
        CGWarpMouseCursorPosition(CGPoint(x: b.minX + max(0, min(1, u)) * (b.width - 1), y: b.minY + max(0, min(1, v)) * (b.height - 1)))
        forceScreen()
    }

    private func startFlush() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(8))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock(); let dx = self.pendingDX, dy = self.pendingDY; self.pendingDX = 0; self.pendingDY = 0; self.lock.unlock()
            if dx != 0 || dy != 0 { self.send?(.arInput(ARInput(kind: "move", dx: dx, dy: dy))) }
        }
        flushTimer = t; t.resume()
    }
    private func stopFlush() { flushTimer?.cancel(); flushTimer = nil }
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
        startFlush()
        send?(.inputMode(InputMode(mode: "layout")))
        onModeChange?(.layout)
    }

    private func leaveLayout(notify: Bool) {
        stopFlush()
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
            case .enterLayout:
                if !phoneConnected {
                    lock.lock(); machine.forceScreen(); lock.unlock()
                    return Unmanaged.passUnretained(event)
                }
                enterLayout(); return nil
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
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard mode == .layout else { return Unmanaged.passUnretained(event) }
            lock.lock()
            pendingDX += event.getDoubleValueField(.mouseEventDeltaX); pendingDY += event.getDoubleValueField(.mouseEventDeltaY)
            lock.unlock()
            return nil
        case .leftMouseDown, .leftMouseUp:
            guard mode == .layout else { return Unmanaged.passUnretained(event) }
            send?(.arInput(ARInput(kind: type == .leftMouseDown ? "down" : "up", optionHeld: event.flags.contains(.maskAlternate))))
            return nil
        default:
            return mode == .layout ? nil : Unmanaged.passUnretained(event)   // other mouse + scroll swallowed in layout mode
        }
    }
}
