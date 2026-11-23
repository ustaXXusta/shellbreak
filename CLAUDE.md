# DesktopAR

> Detailed docs: docs/ARCHITECTURE.md, docs/PROTOCOL.md, docs/ROADMAP.md. Keep them in sync.

## 0. Instructions for Claude Code

You are building **DesktopAR** from scratch for Mehmet. It is a personal, non-commercial project — no budget, store or business concerns; focus only on the technical work.

- Talk to the user in **Turkish**. Code, comments, commit messages and repo docs in **English**.
- This file is the specification. When you create the repo, split it into `CLAUDE.md` (sections 0, 1, 12, 13), `docs/ARCHITECTURE.md` (sections 2–9), `docs/PROTOCOL.md` (section 10) and `docs/ROADMAP.md` (section 14). Keep them in sync afterwards.
- Work phase by phase (section 14). Every phase ends in a **gate**: stop, tell the user in Turkish exactly what to test on the real devices and what to look for, and wait for the result before starting the next stage.
- Put every piece of logic that can be pure (protocol, framing, geometry, hit testing, state machines, quality ladder, clock sync) in the `Shared` Swift package and unit-test it. Run `cd Shared && swift test` after every Shared change; build both app schemes after every app change.
- Never hand-edit the `.xcodeproj`; edit `project.yml` and run `xcodegen generate`.
- Do not change the product rules in section 1.3 without asking the user.
- At the end of each phase: tick the roadmap boxes, commit, and give a short Turkish summary (what changed, what to test, what to watch for).

---

## 1. What we are building

### 1.1 Summary

A Vision Pro–style "floating desktops" setup from hardware the user already owns. The Mac streams each of its desktops as low-latency video. The iPhone sits in a very old lens-only VR box, shows the room through its rear camera (passthrough), draws each desktop as a panel fixed in the room, splits its screen into two lens-corrected eye views (classic side-by-side Cardboard look: two round images on black) and renders at 60 Hz. Head tracking is local on the phone (ARKit), so network latency never affects head motion; only screen content has latency.

### 1.2 Hardware and environment

| Item | Detail |
| --- | --- |
| Host | MacBook Pro M1, 13", 8 GB RAM, built-in display 2560×1600 (16:10), macOS 14+ |
| Viewer | iPhone 13 Pro (A15, 2532×1170 @ 120 Hz, LiDAR, triple rear camera), iOS 17+ |
| Headset | Two lenses + a phone slot. No button, no QR code, no sensors. The rear camera must not be covered |
| Link | Same room, same Wi-Fi router (prefer 5 GHz). No cable |
| Input | Only the MacBook's own keyboard and trackpad. No hand tracking, no gaze clicking |
| Usual setup | 2 desktops (the number is always read at launch, never assumed) |

### 1.3 Product rules (decided by the user)

1. **Desktops are discovered, never hard-coded.** At launch the Mac reads how many desktops (Spaces) Mission Control has. Desktop 1 = the built-in display, mirrored. Desktop 2…N = one virtual display each; that desktop's windows are moved onto it. 2 desktops → 2 panels, 5 → 5. On quit, windows are moved back to their original desktops.
2. **Two input modes**, keyboard + trackpad only:
   - **Screen mode:** normal macOS. The cursor moves only inside the displays. Only the exit key is intercepted.
   - **Layout mode:** entered with **Esc**. The macOS cursor is hidden and frozen; all mouse and keyboard events are swallowed and drive an AR cursor that moves freely around the user, so panels can be moved, resized, rotated, added and removed. **Clicking inside a panel** (or Enter) returns to screen mode with the macOS cursor placed exactly at the clicked point.
   - The exit key is configurable: single Esc (default), double Esc (the first Esc still reaches the app), ⌃Esc. Single Esc means apps never receive Esc while DesktopAR runs — show this in the settings.
3. **Panels are world-locked.** They change only in layout mode and keep their place across launches.
4. **Rotation:** landscape ↔ portrait per panel. Real rotation for virtual displays (display mode swap). The mirrored built-in display cannot be rotated in v1 — show a HUD notice instead.
5. **The cursor is always visible in the headset.** Screen mode: the iPhone draws the macOS cursor itself (position + cursor image from the Mac, not baked into video). Layout mode: an AR cursor ring.
6. **Sharpness module:** enlarging or approaching a panel makes it sharper, never blurrier (resolution ladder L1–L4).

### 1.4 Hard requirements

| Requirement | Target | Acceptable |
| --- | --- | --- |
| Panel resolution | 1920×1080 | Ladder raises it for big/close panels |
| Video frame rate | 60 fps | Down to 30 fps under heavy load (focused panel last) |
| Content latency (change on Mac → visible in headset) | 60–120 ms | Hard ceiling 500 ms, enforced by a watchdog |
| iPhone render loop | Always 60 Hz | Never waits for video frames |
| Calibration / resolution / rotation switch | — | 1–2 s hitch is acceptable |

Realistic quality: each eye gets ~1266×1170 px, roughly 12–14 px/degree. Readability depends on panel size and the sharpness module.

---

## 12. Private APIs and known gotchas

| API | Used for | If it breaks |
| --- | --- | --- |
| `CGVirtualDisplay*` (CoreGraphics, private) | Virtual monitors for desktops 2…N, rotation | Keep the mirror panel working; manual count; later window-mode capture |
| `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows` (SkyLight, via `dlsym`) | Reading the desktop list and window → desktop map (read-only) | Manual desktop count in the control panel, empty virtual displays |

Never use private APIs that need SIP disabled. Resolve SkyLight symbols at runtime and fail soft.

Gotchas:
- Non-visible Spaces are not rendered → cannot be captured (reason for virtual displays).
- Moving windows to a desktop requires switching to it first; "Switch to Desktop 1…9" shortcuts (⌃1…⌃9, System Settings → Keyboard → Keyboard Shortcuts → Mission Control) must be enabled.
- A fully transparent `NSWindow` gets no mouse events (use alpha ≥ 0.01 if one is ever needed).
- HEVC low-latency session may fail with −12902 → H.264 fallback.
- ARKit's default 30 fps video format makes poses judder at 60 Hz → pick a 60 fps format.
- Without `NSLocalNetworkUsageDescription` + `NSBonjourServices`, iOS discovery fails silently.
- Rebuilding the Mac app with a new signature can silently drop Screen Recording / Accessibility / Input Monitoring permissions → remove and re-add the app in System Settings.
- Single-Esc exit steals Esc from apps — the setting exists; keep the default unless the user changes it.
- Virtual displays must be destroyed on every exit path (normal quit, crash signals), or ghost monitors remain until logout.

---

## 13. Engineering conventions

- Swift 5.9+, Swift 5 language mode. Mark cross-thread types `@unchecked Sendable` only when a lock or serial queue justifies it.
- One primary type per file, named after it (small payload structs of one message family may share a file). No force-unwraps outside tests; `fatalError` only for programmer errors.
- Hot paths (capture callback, encode output, decode output, render loop) avoid per-frame allocations and never block on the network.
- Zero-copy: IOSurface-backed `CVPixelBuffer` → `CVMetalTextureCache`. Never route frames through `CGImage`/`UIImage`.
- Logging with `os.Logger`, subsystems `dev.desktopar.host` / `dev.desktopar.phone`.
- Threading: Mac capture callbacks on per-stream serial queues → encoder callback → server send queue; control handling on the main actor; event tap on its own run-loop thread. Phone: ARKit delegate queue, decoder callback queue → lock-protected latest-frame slot, rendering on the MTKView thread, networking on its own queue; interaction state only touched on the render thread (incoming messages are queued into it).
- Build commands: `./scripts/bootstrap.sh`; `cd Shared && swift test`; `xcodebuild -scheme MacHost build`; `xcodebuild -scheme PhoneClient -destination 'generic/platform=iOS' build`. The phone app runs only on the physical iPhone (no ARKit/camera in the simulator).

**Unit tests required in Shared** (minimum): video header encode/decode; stream parser with split, merged and oversized packets; Annex-B split/join/length-prefix conversion and parameter-set detection; every control message round-trip + JSON field names; arc layout symmetry and order; orbit keeps distance and facing; distance clamping; rotation preserves area; hit-test regions (content u/v, bar, corner priority, buttons, nearest panel); input-mode machine (single Esc, double Esc window, ⌃Esc, ⌘/⌥Esc ignored, repeats ignored, enterScreen); layout keymap (letters, Turkish Ğ/Ü/Ç, arrows, keypad); quality ladder selection and governor debounce/manipulation; clock sync median and latency.

---

