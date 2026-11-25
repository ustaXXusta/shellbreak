#!/bin/bash
# Removes the Mac app, its build cache and installer logs. The iPhone app is removed like any other app.
source "$(dirname "$0")/lib/common.sh"

banner "Uninstall"
step "Quitting Shellbreak"
osascript -e 'tell application "Shellbreak" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Shellbreak >/dev/null 2>&1 || true

step "Removing files"
for p in "/Applications/Shellbreak.app" "$HOME/Applications/Shellbreak.app" "$BUILD_DIR" "$HOME/Library/Application Support/Shellbreak"; do
  if [ -e "$p" ]; then rm -rf "$p" && ok "Removed $p"; fi
done
if tccutil reset All dev.desktopar.host >/dev/null 2>&1; then ok "Reset macOS permissions for Shellbreak"; fi
info "On the iPhone: touch and hold the Shellbreak icon → Remove App."
info "Installer logs stay in $LOG_DIR (delete that folder if you like)."
pause_and_exit 0
