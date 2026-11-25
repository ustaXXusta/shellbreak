#!/bin/bash
# One click: installs (or updates) only the Mac host. Double-click in Finder.
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/mac.sh"

banner "Mac only"
check_macos
check_xcode
ensure_xcodegen
generate_project
install_mac_host
explain_mac_permissions

step "Done"
pause_and_exit 0
