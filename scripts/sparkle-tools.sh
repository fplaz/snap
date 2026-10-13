#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/.build/distribution/derived-data"
bin="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$bin/generate_appcast" ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    xcodebuild -resolvePackageDependencies -project "$repo_root/Snap.xcodeproj" \
        -scheme Snap -derivedDataPath "$derived_data" >&2
fi
printf '%s\n' "$bin"
