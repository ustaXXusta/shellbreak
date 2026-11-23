#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || { echo "Homebrew is required to install XcodeGen"; exit 1; }
  brew install xcodegen
fi
xcodegen generate
(cd Shared && swift test)
