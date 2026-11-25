# Shellbreak

**Floating Mac desktops in a cheap VR box.** Shellbreak streams every macOS desktop to an iPhone sitting in a lens-only VR headset. The iPhone shows your room through its rear camera and pins each desktop in the room as a big virtual screen, a bit like Vision Pro, using hardware you already own.

- Your main display plus as many extra virtual displays as you want, each shown as its own panel.
- Head tracking runs on the phone (ARKit), so turning your head never lags. Only the screen content goes over Wi-Fi.
- You control everything with the Mac's own keyboard and trackpad. You don't need controllers or hand tracking.
- Two lens-corrected eye views at 60 Hz, with passthrough or a virtual environment around the panels.

> Internally the project is called **DesktopAR** (bundle IDs `dev.desktopar.*`, Bonjour `_desktopar._tcp`). The app's name is **Shellbreak**.

---

## Contents

1. [Platform support](#platform-support)
2. [Requirements](#requirements)
3. [Installation](#installation)
   - [Option A: one-click installer (recommended)](#option-a-one-click-installer-recommended)
   - [Option B: prebuilt release (no Xcode on the Mac)](#option-b-prebuilt-release-no-xcode-on-the-mac)
   - [Option C: build manually](#option-c-build-manually)
4. [First-run setup](#first-run-setup)
5. [Using Shellbreak](#using-shellbreak)
6. [Troubleshooting](#troubleshooting)
7. [Updating and uninstalling](#updating-and-uninstalling)
8. [Development](#development)
9. [Project status](#project-status)

---

## Platform support

Shellbreak has two parts: a **host**, which captures and streams the desktops, and a **viewer**, the phone in the headset.

| Host (computer) | Viewer (phone) | Status | How to install |
| --- | --- | --- | --- |
| **Mac** | **iPhone** | ✅ Supported | `install/Install Shellbreak - Mac + iPhone.command` |
| Mac | Android | 🚧 Not available yet | No Android viewer exists yet (it needs an ARCore + Vulkan/GL port of the viewer) |
| Windows | iPhone | 🚧 Not available yet | No Windows host exists yet (it needs a DXGI capture + virtual display driver port). From a Windows PC you *can* sideload the iPhone app ([Option B](#option-b-prebuilt-release-no-xcode-on-the-mac)), but it still needs a Mac to stream from |
| Windows | Android | 🚧 Not available yet | Needs both ports above |

The host relies on macOS-only APIs (ScreenCaptureKit, VideoToolbox, virtual displays, Mission Control Spaces). The viewer relies on iOS-only APIs (ARKit, Metal). Ports are listed in [Project status](#project-status).

---

## Requirements

| | Minimum | Tested on |
| --- | --- | --- |
| **Mac** | macOS 14 Sonoma, Apple Silicon recommended | MacBook Pro M1 13", 8 GB |
| **Xcode** (Option A / C only) | Xcode 15, free from the App Store | Xcode 15–16 |
| **iPhone** | iOS 17, ARKit + Metal (iPhone XS or newer) | iPhone 13 Pro |
| **Apple ID** | A free Apple ID is enough | — |
| **Headset** | Any lens-only phone VR box ("Cardboard" style) that leaves the **rear camera uncovered** | — |
| **Network** | Mac and iPhone on the **same Wi-Fi** (5 GHz strongly preferred) | — |

---

## Installation

### Option A: one-click installer (recommended)

The installer builds Shellbreak from source on your Mac and installs it on the Mac and on the iPhone.

1. **Install Xcode** from the App Store, open it once and let it finish installing its components.
2. **Sign in to Xcode with your Apple ID**: *Xcode → Settings… → Accounts → + → Apple ID*. A free Apple ID works.
3. **Get the code**: either `git clone https://github.com/<you>/shellbreak.git`, or on GitHub use *Code → Download ZIP* and unzip it.
4. **Connect the iPhone** to the Mac with a cable, unlock it and tap **Trust This Computer**. You only need the cable the first time.
5. In Finder, open the `install` folder and **double-click** the installer you need:

| Installer | What it does |
| --- | --- |
| `Install Shellbreak - Mac + iPhone.command` | Everything: Mac app + iPhone app |
| `Install Shellbreak - Mac only.command` | Installs or updates only the Mac app |
| `Install Shellbreak - iPhone only.command` | Installs the iPhone app, or renews it after 7 days with a free Apple ID |
| `Uninstall Shellbreak.command` | Removes the Mac app, its build cache and its permissions |

> **"cannot be opened because it is from an unidentified developer"?** Right-click the `.command` file → **Open** → **Open**. macOS only asks once.
>
> **Nothing happens / "permission denied"?** The ZIP lost the executable bit. Open Terminal in the `install` folder and run `chmod +x *.command`.

**What the installer does, step by step:**

1. Checks macOS 14+ and Xcode 15+. If Xcode's first-launch setup is missing, it runs it (this asks for your password).
2. Installs **XcodeGen** with Homebrew. Without Homebrew, it downloads the official release into `~/Library/Application Support/Shellbreak/tools`.
3. Generates `DesktopAR.xcodeproj` from `project.yml`.
4. Finds your Apple team: first from Xcode's accounts, then from your *Apple Development* certificate. If your team isn't the project owner's, it uses unique bundle IDs (`dev.desktopar.host.<team>` / `dev.desktopar.phone.<team>`), so signing never clashes.
5. **Mac:** builds a Release build, quits any running copy, installs it to `/Applications/Shellbreak.app` (or `~/Applications` without admin rights) and starts it.
6. **iPhone:** finds the paired iPhone, checks iOS 17+ and Developer Mode, builds the app, installs it with `xcrun devicectl` and launches it.
7. Opens the Screen Recording page in System Settings and prints the remaining setup steps.

The full build output goes to `~/Library/Logs/Shellbreak/install-<date>.log`. On failure the installer shows only the relevant error lines.

<details>
<summary>Advanced: environment variables</summary>

| Variable | Effect |
| --- | --- |
| `SHELLBREAK_TEAM=ABCDE12345` | Use this Apple team instead of auto-detecting |
| `SHELLBREAK_NO_PAUSE=1` | Don't wait for Return at the end (for running from Terminal/CI) |
| `SHELLBREAK_NO_SETTINGS=1` | Don't open System Settings at the end |

Example: `SHELLBREAK_TEAM=ABCDE12345 "./install/Install Shellbreak - iPhone only.command"`
</details>

### Option B: prebuilt release (no Xcode on the Mac)

Every tagged version (`v*`) is built by GitHub Actions and attached to the **Releases** page:

| File | Use |
| --- | --- |
| `Shellbreak-macOS.dmg` | Mac app. Open it and drag **Shellbreak** to **Applications** |
| `Shellbreak-macOS.zip` | The same Mac app as a ZIP |
| `Shellbreak-iOS-unsigned.ipa` | iPhone app. It must be signed with your own Apple ID before installing |
| `SHA256SUMS.txt` | Checksums |

**Mac:** the release app is ad-hoc signed, so the first time you open it, right-click it in Applications → **Open** → **Open**. If macOS still refuses, run `xattr -dr com.apple.quarantine /Applications/Shellbreak.app`.

**iPhone (from a Mac or a Windows PC):**

1. Install [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). Both run on macOS and Windows; on Windows, install iTunes and iCloud from Apple's website (not the Microsoft Store) first.
2. Connect the iPhone with a cable and trust the computer.
3. Drag `Shellbreak-iOS-unsigned.ipa` into Sideloadly (or open it in AltStore), enter your Apple ID and start.
4. On the iPhone, trust your Apple ID (see [First-run setup](#first-run-setup) → iPhone).

With a free Apple ID the signature lasts **7 days**. After that, sideload it again (AltStore can refresh it automatically over Wi-Fi).

### Option C: build manually

```bash
brew install xcodegen
./scripts/bootstrap.sh                 # xcodegen generate + Shared unit tests
open DesktopAR.xcodeproj
```

In Xcode, set your team under *Signing & Capabilities* for both targets (and change the bundle IDs if signing complains). Then:

- **MacHost** scheme → *My Mac* → ▶︎ Run, or `./scripts/install_mac.sh` to install a Release build to `/Applications`.
- **PhoneClient** scheme → your iPhone → ▶︎ Run. It only runs on a real iPhone: the simulator has no camera or ARKit.

Don't edit the `.xcodeproj` by hand. Change `project.yml` and run `xcodegen generate` again.

---

## First-run setup

### Mac

1. Click the **Shellbreak icon in the menu bar** (top right). There is no Dock icon.
2. Grant the three permissions. Each **✗** row in the panel opens the right System Settings page:

   | Permission | Why |
   | --- | --- |
   | **Screen Recording** | Capture the desktops for streaming |
   | **Accessibility** | Move windows between desktops and warp the cursor |
   | **Input Monitoring** | Layout mode: read keyboard and trackpad while apps don't receive them |

3. After granting them, **quit Shellbreak from its menu and open it again**. macOS only applies some permissions after a restart. *İzinleri yenile* (Refresh permissions) updates the ticks.
4. Recommended: turn on the desktop-switch shortcuts: *System Settings → Keyboard → Keyboard Shortcuts… → Mission Control →* **Switch to Desktop 1 … 9** (⌃1 … ⌃9). Automatic Mission Control desktop mapping, which is still in development, will need them.

### iPhone

1. **Developer Mode** (iOS 16+): *Settings → Privacy & Security → Developer Mode → On*. The phone restarts; confirm **Turn On**. This option only appears after the phone has been connected to Xcode once.
2. **Trust the developer** (free Apple ID): *Settings → General → VPN & Device Management → your Apple ID → Trust*.
3. Open **Shellbreak** and allow **Camera** (passthrough view of the room) and **Local Network** (to find the Mac). If you denied Local Network by mistake, turn it back on under *Settings → Privacy & Security → Local Network → Shellbreak*.

### Headset

1. Make sure the box **does not cover the rear camera**. If it does, cut a small window so the camera and LiDAR can see.
2. Measure the distance between the two lens centres with a ruler. You'll enter it as *Lens arası (mm)* during calibration.

---

## Using Shellbreak

### 1. Connect

1. Put the Mac and the iPhone on the **same Wi-Fi network**.
2. Start Shellbreak on the Mac (menu-bar icon) and press **Yayını başlat** (Start streaming).
3. Open Shellbreak on the iPhone. It finds the Mac automatically over Bonjour and connects. The control panel then shows **Telefon bağlı** (Phone connected).
4. Without the headset, the phone shows a flat preview with live **latency / fps / codec** in the corner. Green means fine; red means over 300 ms.

### 2. Put on the headset

| Gesture on the iPhone screen | Action |
| --- | --- |
| **Double tap** | Switch between the flat preview and the **stereo headset view** (two round eye views) |
| **Triple tap** | Toggle **passthrough** (real room) ↔ **VR** (virtual environment) |

Switch to the stereo view, slide the phone into the box with the screen facing the lenses, and look around. Your desktops float in front of you.

### 3. Add screens

Panel **1** is your Mac's built-in display (mirrored). For more panels, press **Yeni ekran ekle** (Add display) in the control panel, **N** in layout mode, or the **+** button above a panel. Each one is a real virtual monitor: macOS sees it like an external display, so you can drag windows onto it. Remove one with **Kaldır** (Remove), **⌫⌫** or **×** twice.

### 4. Calibrate the lenses (once)

In the Mac control panel under **Gözlük kalibrasyonu** (headset calibration):

1. Turn on **Test deseni** (test pattern): every eye shows a grid and a cross.
2. Set **Lens arası (mm)** to the distance you measured, then fine-tune it until the two crosses **merge into one**.
3. Adjust **k1 / k2** (lens distortion) until the grid lines look **straight**, not curved.
4. Optional: **Dikey kayma** (vertical offset), **FOV**, **Renk sapması** (chromatic aberration), **Keskinlik** (sharpen) and **Supersample** (sharper but hotter).
5. Turn the test pattern off. **Görüşü ortala** re-centres the view; **Sıfırla** resets the calibration.

You can also calibrate from the headset: in layout mode press **K**, then use the arrow keys to pick a value and change it.

### 5. Two input modes

You only use the MacBook's keyboard and trackpad.

| Mode | What happens | How to get there |
| --- | --- | --- |
| **Screen mode** | Normal macOS: type and click inside the desktops. The headset draws the Mac cursor | At start, or **click inside a panel** / press **Enter** in layout mode |
| **Layout mode** | The Mac cursor freezes and an **AR cursor ring** moves freely around you. Apps receive no keys or clicks | Press the **exit key** (default **Esc**) |

Clicking inside a panel in layout mode returns to screen mode and puts the Mac cursor exactly where you clicked. Layout mode only switches on while the iPhone is connected, so you can never lose control of the Mac.

The **exit key** is set under **Çıkış tuşu** in the control panel:

| Setting | Behaviour |
| --- | --- |
| `Esc` (default) | One Esc switches. Apps never receive Esc while Shellbreak runs |
| `Esc Esc` | Press Esc twice within 350 ms. The first Esc still reaches the app |
| `⌃Esc` | Only Control+Esc switches |

⌘Esc and ⌥Esc are never intercepted.

### 6. Arranging panels (layout mode)

**Trackpad and mouse:**

| Action | Where | Result |
| --- | --- | --- |
| Click | Inside a panel | Back to screen mode at that point |
| Drag | Bar under the panel (or **⌥ + drag** anywhere on it) | Move the panel around you; it keeps facing you |
| Drag | Bottom-right corner | Resize (aspect ratio kept) |
| Pinch | Over a panel | Resize |
| Two-finger scroll | Over a panel | Move it closer / farther |
| Click | ⟳ button above the panel | Landscape ↔ portrait |
| Click | **+** button | New virtual display to the right |
| Click twice | **×** button | Remove that virtual display (the main display is only hidden) |

**Keyboard** (works on the Turkish Q layout too). Commands apply to the panel under the AR cursor:

| Key | Command |
| --- | --- |
| **R** | Toggle landscape / portrait |
| **H** / **V** | Landscape / portrait |
| **F** | Turn the panel to face me |
| **Arrows** | Move (hold ⇧ for big steps) |
| **+** / **−** (also `=`, `*`, keypad) | Bigger / smaller |
| **[** / **]** (also `,` / `.` and **Ğ** / **Ü**) | Closer / farther |
| **C** | Curvature on / off |
| **N** | New virtual display |
| **⌫** | Remove / hide panel (press twice to confirm) |
| **G** | Show hidden panels |
| **0** | Bring everything in front of me |
| **P** | Passthrough ↔ VR |
| **K** | Calibration mode |
| **Enter** | Back to screen mode |

Global shortcuts that also work in screen mode: **⌃⌥P** (passthrough) and **⌃⌥0** (bring everything in front).

Limits: panel width 0.3–4 m, distance 0.5–5 m. The **main display** (desktop 1, mirrored) can't be rotated; you'll see a notice. Virtual displays rotate for real (1920×1080 ↔ 1080×1920) within 1–2 s.

### 7. Control panel reference (Mac menu bar)

| Section | What it does |
| --- | --- |
| Permissions | ✓/✗ for Screen Recording, Accessibility, Input Monitoring. Click a ✗ to open its settings page |
| Status | Phone connected? Streaming? Which codec (HEVC, or H.264 as a fallback)? Last error |
| **Görüntü kalitesi** (image quality) | Higher = HiDPI virtual displays and bigger capture. Sharper, but heavier on the Mac and Wi-Fi |
| **Ekranlar** (displays) | One row per panel: orientation, resolution, remove. **Yeni ekran ekle** adds a virtual display (up to 6) |
| **Ekran düzeni** (display arrangement) | Arrange the displays like in System Settings |
| **Yayını başlat / durdur** | Start / stop streaming |
| **Panel genişliği** | Default panel width in metres |
| **Gerçek dünya (passthrough)** | Room view ↔ virtual environment |
| Debug | Dump the raw stream to `~/Desktop/stream.h265` (play it with `ffplay`) |
| **Quit** | Quits Shellbreak and removes its virtual displays |

### Tips for a good picture

- Use **5 GHz Wi-Fi** and keep the Mac close to the router. Target latency is 60–120 ms; there's a hard watchdog at 500 ms.
- Text gets sharper when a panel is **bigger or closer**. A lower resolution per display gives bigger text at the same panel size.
- For long sessions, plug the iPhone into a charger. The video still goes over Wi-Fi.
- If the phone gets hot, lower **Supersample** first, then switch to VR mode (it uses less power than passthrough).

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Installer: *"Xcode not found"* | Install Xcode from the App Store, open it once, then run the installer again |
| Installer: *"No Apple ID"* / *"requires a development team"* | Xcode → Settings → Accounts → add your Apple ID → *Manage Certificates* → **+** *Apple Development* |
| Installer: *"No ready iPhone found"* | Use a cable, unlock the phone, tap *Trust*, wait for Xcode to *prepare* the device (Xcode → Window → Devices and Simulators shows the progress) |
| Installer: *"Developer Mode is off"* | iPhone: Settings → Privacy & Security → Developer Mode → On |
| App on the iPhone won't open (*"Untrusted Developer"*) | Settings → General → VPN & Device Management → your Apple ID → Trust |
| App on the iPhone stopped opening after a week | Free Apple ID signatures last 7 days. Run `Install Shellbreak - iPhone only.command` again |
| iPhone never finds the Mac | Same Wi-Fi? Local Network allowed on the iPhone? Guest or public networks often block device-to-device traffic. A Mac firewall must allow Shellbreak (TCP ports **47801** control, **47802** video) |
| Black panels, or *"Hata"* in the control panel | Screen Recording permission is missing, or was dropped after a reinstall. Remove Shellbreak from the list in System Settings, add it back, restart the app |
| Permissions keep disappearing after updates | macOS ties them to the app's signature. Sign in to Xcode with an Apple ID so the installer signs with your team instead of ad-hoc |
| A virtual display is empty | Drag windows onto it like onto an external monitor (its position is set under **Ekran düzeni**) |
| Extra "ghost" monitors after a crash | Open and quit Shellbreak once, or log out and back in |
| Image judders when turning your head | Restart the iPhone app. Head tracking needs good light and a textured room for ARKit |
| Crosses don't merge / lines look bent | Recalibrate: lens distance first, then k1/k2 |
| Apps don't get the Esc key | That's the default single-Esc setting. Switch **Çıkış tuşu** to `Esc Esc` or `⌃Esc` |

Installer logs: `~/Library/Logs/Shellbreak/`. App logs: Console.app, filter subsystem `dev.desktopar.host` (Mac) or `dev.desktopar.phone` (iPhone).

---

## Updating and uninstalling

- **Update:** `git pull` (or download the new ZIP), then double-click the installer again. Builds are cached in `~/Library/Caches/shellbreak-build`, so updates are much faster than the first install.
- **Uninstall:** double-click `install/Uninstall Shellbreak.command`. It quits the app and removes `Shellbreak.app`, the build cache, the downloaded tools and the app's macOS permissions. On the iPhone, touch and hold the icon → **Remove App**.

---

## Development

```
.
├── MacHost/          macOS menu-bar host: capture, encode, virtual displays, input, server
├── PhoneClient/      iOS viewer: networking, decode, ARKit, stereo renderer, HUD
├── Shared/           Swift package with pure, unit-tested logic (protocol, geometry, input state machines…)
├── docs/             ARCHITECTURE.md · PROTOCOL.md · ROADMAP.md · THIRD_PARTY.md
├── install/          One-click installers (.command) + their shell library
├── scripts/          bootstrap.sh, install_mac.sh, icon generators
├── project.yml       XcodeGen spec — the .xcodeproj is generated, never committed
└── .github/workflows CI: tests, builds, DMG/IPA release on tags
```

| Task | Command |
| --- | --- |
| Generate project + run tests | `./scripts/bootstrap.sh` |
| Shared unit tests | `cd Shared && swift test` |
| Build the Mac host | `xcodebuild -scheme MacHost build` |
| Build the iPhone viewer | `xcodebuild -scheme PhoneClient -destination 'generic/platform=iOS' build` |
| Make a release | `git tag v0.1.0 && git push origin v0.1.0`, then GitHub Actions publishes the DMG, ZIP and IPA |

**How it works.** The built-in display is mirrored as panel 1; every extra panel is a virtual display created by the Mac (the goal is one per Mission Control desktop). Each display is captured at 60 fps, encoded with low-latency HEVC (H.264 fallback) and sent over TCP. A WebSocket channel carries control messages, the cursor, input and clock sync, and the Mac advertises itself over Bonjour. The iPhone decodes every stream into Metal textures, places them as world-locked panels using ARKit, and renders two lens-corrected eye views at 60 Hz. The render loop never waits for the network. Details are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/PROTOCOL.md`](docs/PROTOCOL.md).

**Private APIs.** The host uses `CGVirtualDisplay` (virtual monitors) and read-only SkyLight calls (desktop list). Both are resolved at runtime and fail soft, and none of them need SIP turned off. Because of these APIs, Shellbreak is distributed outside the Mac App Store.

---

## Project status

Shellbreak is a personal project in active development. Full checklist: [`docs/ROADMAP.md`](docs/ROADMAP.md).

- ✅ **Stage 1: pipeline.** Mac streamer, flat iPhone client, latency overlay and watchdog.
- ✅ **Stage 2 (mostly): headset.** Stereo rendering, lens distortion, ARKit passthrough, world-anchored panels, virtual displays with one stream each, world themes for VR mode.
- 🚧 **In progress:** automatic Mission Control desktop detection and moving windows onto their panels; polishing input modes and layout controls; sharpness module (automatic resolution ladder); saving panel positions between launches; a 30-minute endurance test.
- 🗺️ **Later:** Windows host, Android viewer.

Third-party credits (CC0 panoramas, shader techniques): [`docs/THIRD_PARTY.md`](docs/THIRD_PARTY.md).
# shellbreak
# shellbreak
