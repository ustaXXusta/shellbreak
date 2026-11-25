#!/bin/bash
# One click: installs the Mac host and the iPhone app. Double-click in Finder.
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/mac.sh"
source "$(dirname "$0")/lib/iphone.sh"

banner "Mac + iPhone"
check_macos
check_xcode
ensure_xcodegen
generate_project
install_mac_host
install_iphone_app
explain_mac_permissions

step "Done"
info "Put the iPhone in the headset and keep it on the same Wi-Fi as this Mac."
info "Usage guide: README.md → \"Using Shellbreak\"."
pause_and_exit 0
