#!/bin/bash
# Builds the Shellbreak Mac host (MacHost scheme) and installs it to /Applications.
# Source after common.sh.

install_mac_host() {
  local sign_args=()
  if detect_team; then
    sign_args=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
    if [ "$TEAM_ID" != "$DEFAULT_TEAM" ]; then
      sign_args+=(PRODUCT_BUNDLE_IDENTIFIER="$HOST_BUNDLE_ID")
    fi
  else
    warn "No Apple ID in Xcode — the Mac app will be signed ad-hoc."
    info "It works, but macOS forgets its permissions after every reinstall."
    info "Add a free Apple ID in Xcode → Settings → Accounts to avoid that."
    sign_args=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  fi

  step "Building the Mac app (Release) — this takes 1–3 minutes the first time"
  (cd "$REPO_ROOT" && run_logged "Mac build" xcodebuild \
      -project DesktopAR.xcodeproj -scheme MacHost -configuration Release \
      -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
      "${sign_args[@]}" build)
  local built="$BUILD_DIR/Build/Products/Release/Shellbreak.app"
  [ -d "$built" ] || fail "Build finished but $built is missing."
  ok "Built Shellbreak.app"

  step "Installing"
  osascript -e 'tell application "Shellbreak" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Shellbreak >/dev/null 2>&1 || true

  local dest_dir="/Applications"
  if [ ! -w "$dest_dir" ]; then
    dest_dir="$HOME/Applications"
    mkdir -p "$dest_dir"
    warn "/Applications is not writable for this user — installing to $dest_dir"
  fi
  MAC_APP="$dest_dir/Shellbreak.app"
  rm -rf "$MAC_APP"
  ditto "$built" "$MAC_APP"
  xattr -dr com.apple.quarantine "$MAC_APP" >/dev/null 2>&1 || true
  ok "Installed $MAC_APP"

  step "Starting Shellbreak"
  open "$MAC_APP"
  ok "Shellbreak is running — look for its icon in the menu bar (top right)."
}

explain_mac_permissions() {
  step "One-time macOS setup"
  info "Shellbreak needs three permissions. Click its menu-bar icon: every ✗ row opens the right page."
  info "  • Screen Recording   — to stream your desktops"
  info "  • Accessibility      — to move windows and the cursor"
  info "  • Input Monitoring   — for layout mode (Esc) with keyboard + trackpad"
  info "After granting them, quit Shellbreak from its menu and open it again."
  info ""
  info "Recommended: enable the desktop-switch shortcuts (used by the upcoming desktop mapping):"
  info "  System Settings → Keyboard → Keyboard Shortcuts… → Mission Control →"
  info "  turn on \"Switch to Desktop 1 … 9\" (⌃1 … ⌃9)."
  if [ "${SHELLBREAK_NO_SETTINGS:-0}" != "1" ]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" >/dev/null 2>&1 || true
  fi
}
