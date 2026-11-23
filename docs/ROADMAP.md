# Roadmap

## Roadmap

Legend: **[S]** Shared · **[M]** MacHost · **[P]** PhoneClient · **[U]** needs the user (hardware or settings). Do not start a stage before the previous gate passes on the real devices.

### Stage 1 — Pipeline

**F0 · Preparation**
- [x] [M][P][S] Create the repo (section 3), `project.yml`, `bootstrap.sh`, docs split from this file; both schemes build and launch; `swift test` green
- [ ] [U] Phone fits the box; rear wide camera + LiDAR uncovered (cut a window if needed)
- [ ] [U] Measure lens centre distance and screen-to-lens distance → calibration defaults
- [ ] [U] Enable "Switch to Desktop 1…9" shortcuts
- [ ] [U] Try DeskPad: how many virtual displays the M1 opens without problems

**F1 · Mac streamer**
- [x] [S] Video header, stream parser, Annex-B helpers, control messages, clock sync (+ tests)
- [x] [M] Menu-bar app + permission checklist
- [x] [M] `DisplayCapture` of the built-in display, 60 fps, `showsCursor = false`
- [x] [M] `VideoEncoder`: HEVC low-latency, H.264 fallback, Annex-B with inline parameter sets
- [x] [M] `HostServer`: Bonjour + WebSocket control + TCP video, back-pressure
- [x] [M] Debug dump to `~/Desktop/stream.h265`, verify with `ffplay`

**F2 · Flat iPhone client**
- [x] [P] `HostConnection`: discover, connect both channels, `hello`, `ping`/`pong`, auto-reconnect
- [x] [P] `VideoDecoder` → Metal texture → full-screen quad
- [x] [P] Latency overlay + 300/500 ms watchdog
- [x] [U] Glass-to-glass latency: photograph a ms counter on both screens, 10 samples

**Gate 1:** Mac screen smooth on the iPhone; measured latency < 500 ms (target 60–120 ms).

### Stage 2 — Screens in the headset

**F3 · Stereo + lenses**
- [x] [P] Two eye textures, per-eye projection, IPD
- [x] [P] Distortion pass: barrel, chromatic correction, circular mask, sharpen
- [x] [P][M] Test pattern; live calibration from the Mac control panel
- [x] [P] Panel fixed in rotation with CoreMotion (sanity check before ARKit)
- [ ] [U] Calibrate until the grid is straight and the crosses fuse

**F4 · ARKit passthrough**
- [x] [P] World tracking, 60 fps video format, plane detection
- [x] [P] Camera background scaled from intrinsics, same pose as the panels
- [x] [P] World-anchored panel; passthrough ↔ VR mode

**F5 · All desktops**
- [ ] [S] Panel/scene model, layout math (+ tests)
- [ ] [M] `DesktopScanner` (SkyLight via `dlsym`, fail soft) + manual override
- [ ] [M] `VirtualDisplayManager`: create, destroy, change mode; cleanup on quit and crash
- [ ] [M] `WindowMover.distribute` / `restore` with `startup_scan` progress
- [ ] [M] `DisplayArranger`: macOS display order = panel order
- [ ] [M][P] One capture/encoder/decoder per panel, `scene`, default arc layout
- [ ] [M] Frame-rate policy

**Gate 2:** every Mission Control desktop (count read at launch) appears as a world-locked panel at 60 fps without judder; quitting restores windows to their desktops.

### Stage 3 — v1

**F6 · Input modes and layout controls**
- [ ] [S] `InputModeMachine`, `LayoutKeymap`, `ARCursor`, `PanelHitTest`, `PanelHandleGeometry` (+ tests)
- [ ] [M] `InputModeController`: event tap, exit-key styles, hide/freeze cursor, `enter_screen` warp
- [ ] [M] `CursorStreamer`: `cursor` ≤ 120 Hz, `cursor_image` on change
- [ ] [P] Screen-mode cursor sprite; layout-mode AR cursor; highlight + handles
- [ ] [P] Interaction: move (bar or ⌥-drag), resize corner, pinch, scroll distance, click → `enter_screen`
- [ ] [P][M] Layout keys (section 6.6) + HUD
- [ ] [M] Rotation of virtual displays; mirror → HUD notice
- [ ] [P][M] Add / remove / unhide

**F7 · Sharpness module**
- [ ] [S] Quality ladder + governor (+ tests)
- [ ] [P] `PanelPixelMeter` → `quality_request`
- [ ] [M] `QualityController`: ladder, bitrate scaling, keyframe
- [ ] [M] Idle high-quality refresh (300 ms)
- [ ] [P] Supersampling, mipmaps for small panels, sharpen strength in calibration
- [ ] [M][P] HEVC 4:4:4 test; measure the M1's total pixel budget

**F8 · Persistence and robustness**
- [ ] [P] `ARWorldMap` save/load, relocalisation, re-anchor fallback after 10 s
- [ ] [P][M] Reconnect keeps the last frame + HUD
- [ ] [P] Thermal steps
- [ ] [M] Full control panel: layout preview, stats, exit-key setting
- [ ] [U] 30-minute endurance test with all desktops

**Gate 3 (v1):** desktops discovered at launch, controlled with keyboard + trackpad only, same positions after relaunch, 30 minutes stable.

### Test checklist for the user (per gate)

- **Latency:** ms counter photo method, 10 samples, Wi-Fi.
- **Endurance:** 30 min, all desktops; log fps, thermal state, battery, dropped frames.
- **Persistence:** quit and relaunch; panels within a few cm of their old place?
- **Modes:** Esc enters layout mode instantly; click inside a panel puts the macOS cursor exactly there; apps receive no clicks or keys in layout mode.
- **Rotation:** virtual display turns portrait within 2 s, windows re-laid out; mirror shows the notice.
- **Sharpness:** enlarge a panel → level switch ≤ 2 s, no black frame, text visibly sharper.
- **Readability:** 12/14/16 pt text at panel widths of 40°, 55°, 70° → keep the most comfortable as default.
- **Calibration:** straight grid, single fused cross.

---

