#!/bin/bash
# One click: installs (or re-signs after 7 days) only the iPhone app. Double-click in Finder.
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/iphone.sh"

banner "iPhone only"
check_macos
check_xcode
ensure_xcodegen
generate_project
install_iphone_app

step "Done"
pause_and_exit 0
