# Protocol

## 10. Protocol (v1)

### 10.1 Channels

| Channel | Transport | Port | Direction | Content |
| --- | --- | --- | --- | --- |
| Discovery | Bonjour `_desktopar._tcp` | — | Mac advertises | TXT `v=1`, `video=47802` |
| Control | WebSocket text frames, JSON | 47801 | both | control messages |
| Video | raw TCP, binary | 47802 | Mac → iPhone | header + Annex-B payload |

One phone at a time. Unknown control message types are ignored (forward compatibility).

### 10.2 Video packet

Big-endian 18-byte header followed by `payloadLength` bytes.

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 1 | streamId | One stream per panel (0…7) |
| 1 | 1 | flags | bit0 keyframe · bit1 HEVC (0 = H.264) · bit2 payload starts with parameter sets · bit3 high-quality idle refresh |
| 2 | 4 | frameId | Monotonic per stream |
| 6 | 8 | captureTimeUs | Mac wall clock, µs since 1970 |
| 14 | 4 | payloadLength | ≤ 16 MiB, otherwise reset the connection |

Payload: Annex-B NAL units with 4-byte start codes; keyframes include parameter sets inline so a decoder can start on any keyframe. The phone's stream parser must handle packets split across or merged within TCP reads.

**Back-pressure (Mac):** at most 2 unsent frames per stream; when exceeded, drop non-keyframes until the next keyframe and force one. Never let a queue grow.

**Latency watchdog (iPhone):** age = local now − (captureTime − clock offset). Over 300 ms → drop queued frames, `request_idr`. Over 500 ms for 2 s → `quality_request` one level lower for that panel.

**Clock sync:** the phone sends `ping {t0}` every 2 s, the Mac answers `pong {t0, t1}`; offset = t1 − (t0 + t2)/2, median of the last 8 samples.

### 10.3 Control messages

JSON objects with a snake_case `type` and camelCase fields.

```json
{ "type": "hello", "role": "phone", "version": 1, "device": "iPhone14,2", "screenWidth": 2532, "screenHeight": 1170 }
{ "type": "ping", "t0": 1764000000000000 }
{ "type": "pong", "t0": 1764000000000000, "t1": 1764000000004200 }

{ "type": "scene", "revision": 12, "panels": [
  { "id": "desktop-1", "kind": "mirror", "streamId": 0, "desktopIndex": 1, "widthM": 1.1, "aspect": 1.6,
    "orientation": "landscape", "curvature": 0, "visible": true, "level": "l2", "transform": null },
  { "id": "desktop-2", "kind": "virtual", "streamId": 1, "desktopIndex": 2, "widthM": 1.3, "aspect": 1.7778,
    "orientation": "landscape", "curvature": 0.2, "visible": true, "level": "l2", "transform": [16 floats] }
] }
{ "type": "startup_scan", "desktops": 2, "step": 1, "status": "moving_windows", "message": "Masaüstü 2/2" }

{ "type": "panel_update", "panelId": "desktop-2", "transform": [16 floats], "widthM": 1.6, "curvature": 0.2 }
{ "type": "add_display", "afterPanelId": "desktop-2" }
{ "type": "remove_display", "panelId": "desktop-3" }
{ "type": "unhide_all" }
{ "type": "rotate", "panelId": "desktop-2", "orientation": "portrait" }
{ "type": "quality_request", "panelId": "desktop-2", "level": "l3" }
{ "type": "request_idr", "streamId": 1 }

{ "type": "input_mode", "mode": "layout" }
{ "type": "ar_input", "kind": "move", "dx": 3.5, "dy": -1.0, "scrollY": 0, "magnification": 0, "optionHeld": false, "shiftHeld": false }
{ "type": "layout_command", "command": "toggle_orientation", "shiftHeld": false }
{ "type": "enter_screen", "panelId": "desktop-2", "u": 0.4, "v": 0.7 }
{ "type": "cursor", "panelId": "desktop-1", "u": 0.51, "v": 0.33, "visible": true, "imageId": 7 }
{ "type": "cursor_image", "imageId": 7, "pngBase64": "…", "hotspotX": 4, "hotspotY": 4, "widthPt": 32, "heightPt": 32 }
{ "type": "gaze_focus", "panelId": "desktop-2" }

{ "type": "calibration", "lensSeparationMm": 63, "screenToLensMm": 39, "verticalOffsetMm": 0, "k1": 0.34, "k2": 0.55,
  "fovDegrees": 90, "chromaticAberration": 0.008, "sharpen": 0.3, "supersample": 1.25 }
{ "type": "mode", "passthrough": true }
{ "type": "hud", "text": "Ana ekran döndürülemez" }
{ "type": "stats", "fps": 59.8, "latencyMs": 54, "lossPct": 0.2, "thermal": "nominal", "battery": 0.78 }
```

| Message | Direction | Meaning |
| --- | --- | --- |
| hello, ping | phone → Mac | Session start, clock sync |
| pong | Mac → phone | Clock sync |
| scene | Mac → phone | Full panel list after every change; `transform` null until placed (phone then uses the arc layout and reports back) |
| startup_scan | Mac → phone | Desktop scan progress: `reading`, `creating_displays`, `moving_windows`, `done`, `failed` |
| panel_update | phone → Mac | Panel moved/resized; Mac stores and rebroadcasts |
| add_display / remove_display / unhide_all / rotate | phone → Mac | Panel lifecycle (the phone knows which panel is hovered) |
| quality_request, request_idr | phone → Mac | Sharpness module, watchdog |
| input_mode | Mac → phone | Mode changed |
| ar_input | Mac → phone | Raw layout-mode mouse/trackpad: kinds `move`, `down`, `up`, `scroll`, `magnify` |
| layout_command | Mac → phone | Layout-mode key, already mapped |
| enter_screen | phone → Mac | Click inside a panel: warp the cursor, switch to screen mode |
| cursor, cursor_image | Mac → phone | Screen-mode cursor |
| gaze_focus | phone → Mac | Panel nearest to the view centre (frame-rate priority) |
| calibration, mode | both | Settings; the Mac persists them |
| hud | Mac → phone | Text notice |
| stats | phone → Mac | Shown in the control panel; drives adaptive bitrate |

Every message must exist as a Codable type in Shared (`ControlMessage` enum with a `type` discriminator) and have a round-trip unit test.

---

