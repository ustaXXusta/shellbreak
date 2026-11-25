#!/bin/bash
# Builds the Shellbreak iPhone app (PhoneClient scheme) and installs it on a connected iPhone.
# Source after common.sh. Needs Xcode 15+ (xcrun devicectl).

DEVICES_JSON="$BUILD_DIR/devices.json"

json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }

# Sets DEVICE_ID (devicectl identifier), DEVICE_UDID, DEVICE_NAME. Returns 1 if no usable iPhone.
find_iphone() {
  rm -f "$DEVICES_JSON"
  xcrun devicectl list devices --json-output "$DEVICES_JSON" >>"$LOG_FILE" 2>&1 || return 1
  DEVICE_ID=""; DEVICE_UDID=""; DEVICE_NAME=""; DEVICE_OS=""; DEVICE_DEVMODE=""
  local i=0 platform pairing tunnel kind best=-1
  while :; do
    platform="$(json_get "$DEVICES_JSON" "result.devices.$i.hardwareProperties.platform")"
    [ -n "$platform" ] || break
    kind="$(json_get "$DEVICES_JSON" "result.devices.$i.hardwareProperties.deviceType")"
    pairing="$(json_get "$DEVICES_JSON" "result.devices.$i.connectionProperties.pairingState")"
    tunnel="$(json_get "$DEVICES_JSON" "result.devices.$i.connectionProperties.tunnelState")"
    if [ "$platform" = "iOS" ] && [ "$kind" = "iPhone" ] && [ "$pairing" = "paired" ] && [ "$tunnel" != "unavailable" ]; then
      best=$i
      [ "$tunnel" = "connected" ] && break
    fi
    i=$((i + 1))
  done
  [ "$best" -ge 0 ] || return 1
  DEVICE_ID="$(json_get "$DEVICES_JSON" "result.devices.$best.identifier")"
  DEVICE_UDID="$(json_get "$DEVICES_JSON" "result.devices.$best.hardwareProperties.udid")"
  DEVICE_NAME="$(json_get "$DEVICES_JSON" "result.devices.$best.deviceProperties.name")"
  DEVICE_OS="$(json_get "$DEVICES_JSON" "result.devices.$best.deviceProperties.osVersionNumber")"
  DEVICE_DEVMODE="$(json_get "$DEVICES_JSON" "result.devices.$best.deviceProperties.developerModeStatus")"
  [ -n "$DEVICE_ID" ] && [ -n "$DEVICE_UDID" ]
}

wait_for_iphone() {
  step "Looking for your iPhone"
  local tries=0
  until find_iphone; do
    tries=$((tries + 1))
    warn "No ready iPhone found."
    info "1. Connect the iPhone to this Mac with a cable (only needed the first time)."
    info "2. Unlock it and tap \"Trust This Computer\" if asked."
    info "3. If Xcode asks to \"prepare\" the device, let it finish."
    if [ "$tries" -ge 5 ] || [ ! -t 0 ]; then
      fail "Still no iPhone after $tries tries."
    fi
    printf '\n    Press Return to look again (or Ctrl-C to cancel)... '
    read -r _ || true
  done
  ok "$DEVICE_NAME (iOS ${DEVICE_OS:-?})"

  local major="${DEVICE_OS%%.*}"
  if [ -n "$major" ] && [ "$major" -lt 17 ] 2>/dev/null; then
    fail "Shellbreak needs iOS 17 or newer on the iPhone."
  fi
  if [ "$DEVICE_DEVMODE" = "disabled" ]; then
    warn "Developer Mode is off on the iPhone."
    info "On the iPhone: Settings → Privacy & Security → Developer Mode → On → Restart → Turn On."
    if [ -t 0 ]; then
      printf '\n    Press Return when Developer Mode is on... '
      read -r _ || true
      find_iphone || fail "iPhone disappeared after the restart. Reconnect it and run the installer again."
    fi
  fi
}

install_iphone_app() {
  if ! detect_team; then
    explain_apple_id
    fail "An Apple ID is required to install apps on an iPhone."
  fi
  wait_for_iphone

  local id_args=()
  if [ "$TEAM_ID" != "$DEFAULT_TEAM" ]; then
    id_args=(PRODUCT_BUNDLE_IDENTIFIER="$PHONE_BUNDLE_ID")
  else
    PHONE_BUNDLE_ID="$PHONE_BUNDLE_BASE"
  fi

  step "Building the iPhone app — this takes 2–5 minutes the first time"
  (cd "$REPO_ROOT" && run_logged "iPhone build" xcodebuild \
      -project DesktopAR.xcodeproj -scheme PhoneClient -configuration Release \
      -destination "id=$DEVICE_UDID" -derivedDataPath "$BUILD_DIR" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
      ${id_args[@]+"${id_args[@]}"} build)
  local built="$BUILD_DIR/Build/Products/Release-iphoneos/Shellbreak.app"
  [ -d "$built" ] || fail "Build finished but $built is missing."
  ok "Built Shellbreak.app for iPhone"

  step "Installing on $DEVICE_NAME"
  run_logged "Install on iPhone" xcrun devicectl device install app --device "$DEVICE_ID" "$built"
  ok "Installed"

  step "Launching on the iPhone"
  if xcrun devicectl device process launch --device "$DEVICE_ID" "$PHONE_BUNDLE_ID" >>"$LOG_FILE" 2>&1; then
    ok "Shellbreak is open on the iPhone. Allow Camera and Local Network when it asks."
  else
    warn "Installed, but iOS did not let it start yet. This is normal with a free Apple ID:"
    info "On the iPhone: Settings → General → VPN & Device Management →"
    info "tap your Apple ID under \"Developer App\" → Trust. Then open Shellbreak."
  fi
  info "With a free Apple ID the app stops opening after 7 days — just run this installer again."
}
