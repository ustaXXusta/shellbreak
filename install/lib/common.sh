#!/bin/bash
# Shared helpers for the Shellbreak one-click installers.
# macOS ships bash 3.2: no associative arrays, no ${var,,}, no mapfile.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$HOME/Library/Application Support/Shellbreak/tools"
BUILD_DIR="$HOME/Library/Caches/shellbreak-build"
LOG_DIR="$HOME/Library/Logs/Shellbreak"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# The project's own Apple team. Anyone else gets a unique bundle-ID suffix so signing does not clash.
DEFAULT_TEAM="43MZVFR7CG"
HOST_BUNDLE_BASE="dev.desktopar.host"
PHONE_BUNDLE_BASE="dev.desktopar.phone"

mkdir -p "$LOG_DIR" "$BUILD_DIR" "$TOOLS_DIR"
touch "$BUILD_DIR/.metadata_never_index"

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_RESET=""
fi

step()  { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
ok()    { printf '%s  ✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()  { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }
fail()  { printf '\n%s  ✗ %s%s\n' "$C_RED" "$*" "$C_RESET"; printf '%s    Full log: %s%s\n' "$C_DIM" "$LOG_FILE" "$C_RESET"; pause_and_exit 1; }

# Keep the Terminal window open when the script was double-clicked.
pause_and_exit() {
  local code="${1:-0}"
  if [ -t 0 ] && [ "${SHELLBREAK_NO_PAUSE:-0}" != "1" ]; then
    printf '\nPress Return to close this window...'
    read -r _ || true
  fi
  exit "$code"
}

banner() {
  printf '%s\n' "${C_BOLD}"
  printf '  ┌──────────────────────────────────────────┐\n'
  printf '  │  Shellbreak installer · %-17s│\n' "$1"
  printf '  └──────────────────────────────────────────┘\n'
  printf '%s' "${C_RESET}"
  info "Log file: $LOG_FILE"
}

# Run a command, send its output to the log, show only errors on failure.
run_logged() {
  local label="$1"; shift
  echo "\$ $*" >>"$LOG_FILE"
  if ! "$@" >>"$LOG_FILE" 2>&1; then
    echo
    grep -E "error:|fatal:|failed|requires a development team|No profiles|not registered" "$LOG_FILE" | tail -n 15 | sed 's/^/    /' || true
    fail "$label failed."
  fi
}

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------- checks

check_macos() {
  step "Checking macOS"
  [ "$(uname -s)" = "Darwin" ] || fail "This installer runs on macOS only. Windows is not supported yet (see README)."
  local ver major
  ver="$(sw_vers -productVersion)"
  major="${ver%%.*}"
  if [ "$major" -lt 14 ]; then
    fail "macOS $ver found. Shellbreak needs macOS 14 Sonoma or newer."
  fi
  ok "macOS $ver ($(uname -m))"
}

check_xcode() {
  step "Checking Xcode"
  if ! xcodebuild -version >/dev/null 2>&1; then
    warn "Full Xcode is required (the Command Line Tools alone are not enough)."
    info "Opening Xcode in the App Store. Install it, open it once, then run this installer again."
    open "macappstores://apps.apple.com/app/id497799835" || true
    fail "Xcode not found."
  fi
  local xv
  xv="$(xcodebuild -version | head -n1)"
  local xmajor
  xmajor="$(echo "$xv" | awk '{print $2}' | cut -d. -f1)"
  if [ "${xmajor:-0}" -lt 15 ]; then
    fail "$xv found. Xcode 15 or newer is required."
  fi
  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    warn "Xcode needs its first-launch setup (license + components). macOS will ask for your password."
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch
  fi
  ok "$xv"
}

ensure_xcodegen() {
  step "Checking XcodeGen"
  if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN="$(command -v xcodegen)"
  elif [ -x "$TOOLS_DIR/xcodegen/bin/xcodegen" ]; then
    XCODEGEN="$TOOLS_DIR/xcodegen/bin/xcodegen"
  elif command -v brew >/dev/null 2>&1; then
    info "Installing XcodeGen with Homebrew..."
    run_logged "brew install xcodegen" brew install xcodegen
    XCODEGEN="$(command -v xcodegen)"
  else
    info "Downloading XcodeGen (no Homebrew needed)..."
    local tmp
    tmp="$(mktemp -d)"
    run_logged "XcodeGen download" curl -fsSL -o "$tmp/xcodegen.zip" \
      "https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip"
    run_logged "XcodeGen unzip" unzip -q -o "$tmp/xcodegen.zip" -d "$TOOLS_DIR"
    rm -rf "$tmp"
    XCODEGEN="$TOOLS_DIR/xcodegen/bin/xcodegen"
    [ -x "$XCODEGEN" ] || fail "XcodeGen download did not contain $XCODEGEN."
  fi
  ok "XcodeGen $("$XCODEGEN" --version 2>/dev/null | tail -n1)"
}

generate_project() {
  step "Generating the Xcode project"
  (cd "$REPO_ROOT" && run_logged "xcodegen generate" "$XCODEGEN" generate)
  ok "DesktopAR.xcodeproj generated"
}

# ---------------------------------------------------------------- signing

# Sets TEAM_ID. Order: SHELLBREAK_TEAM env → Xcode account → Apple Development certificate in the keychain.
detect_team() {
  [ -n "${TEAM_DETECTED:-}" ] && return 0
  step "Finding your Apple developer team"
  TEAM_ID="${SHELLBREAK_TEAM:-}"

  if [ -z "$TEAM_ID" ]; then
    # Teams of the Apple IDs signed in to Xcode (key name differs between Xcode versions).
    local teams
    teams="$( { defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null; \
                defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null; } \
      | grep -Eo 'teamID = "?[A-Z0-9]{10}"?' | grep -Eo '[A-Z0-9]{10}' || true)"
    if printf '%s\n' "$teams" | grep -qx "$DEFAULT_TEAM"; then
      TEAM_ID="$DEFAULT_TEAM"   # the project owner's machine keeps the original bundle IDs
    else
      TEAM_ID="$(printf '%s\n' "$teams" | head -n1)"
    fi
  fi
  if [ -z "$TEAM_ID" ]; then
    # The OU field of an "Apple Development" certificate is the team ID.
    local tmpd f
    tmpd="$(mktemp -d)"
    security find-certificate -a -c "Apple Development" -p >"$tmpd/all.pem" 2>/dev/null || true
    if [ -s "$tmpd/all.pem" ]; then
      (cd "$tmpd" && split -p "-----BEGIN CERTIFICATE-----" all.pem cert_)
      for f in "$tmpd"/cert_*; do
        TEAM_ID="$(openssl x509 -noout -subject -in "$f" 2>/dev/null | grep -Eo 'OU ?= ?[A-Z0-9]{10}' | grep -Eo '[A-Z0-9]{10}' || true)"
        [ -n "$TEAM_ID" ] && break
      done
    fi
    rm -rf "$tmpd"
  fi
  if [ -z "$TEAM_ID" ]; then
    return 1
  fi
  TEAM_DETECTED=1
  ok "Team $TEAM_ID"
  if [ "$TEAM_ID" = "$DEFAULT_TEAM" ]; then
    HOST_BUNDLE_ID="$HOST_BUNDLE_BASE"
    PHONE_BUNDLE_ID="$PHONE_BUNDLE_BASE"
  else
    local suffix
    suffix="$(lowercase "$TEAM_ID")"
    HOST_BUNDLE_ID="$HOST_BUNDLE_BASE.$suffix"
    PHONE_BUNDLE_ID="$PHONE_BUNDLE_BASE.$suffix"
    info "Using your own bundle IDs: $HOST_BUNDLE_ID / $PHONE_BUNDLE_ID"
  fi
  return 0
}

explain_apple_id() {
  warn "No Apple ID is signed in to Xcode."
  info "1. Xcode opens now. Go to Xcode → Settings… → Accounts → + → Apple ID."
  info "   A free Apple ID is enough."
  info "2. Select your account → Manage Certificates… → + → Apple Development."
  info "3. Run this installer again."
  open -a Xcode || true
}
