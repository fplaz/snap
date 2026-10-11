#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output="$repo_root/.build/icon-validation"
mkdir -p "$output"
xcrun actool "$repo_root/Snap/Resources/AppIcon.icon" --compile "$output" \
    --output-format human-readable-text --notices --warnings \
    --output-partial-info-plist "$output/partial.plist" --app-icon AppIcon \
    --include-all-app-icons --enable-on-demand-resources NO --development-region en \
    --target-device mac --minimum-deployment-target 14.0 --platform macosx
[[ -s "$output/Assets.car" ]] || { echo 'Icon compiler did not produce Assets.car' >&2; exit 1; }
cp "$output/Assets.car" "$repo_root/Snap/Resources/Assets.car"
# Retain the existing ICNS artwork for older macOS versions.
