#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
beta_root="$repo_root/.build/distribution"
products="$beta_root/products"
staging="$beta_root/image"
output="$beta_root/dist"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Reuse a fixed certificate across releases; never silently fall back to ad-hoc signing.
identity="${SNAP_SIGNING_IDENTITY:-Snap Local Distribution}"
security find-certificate -c "$identity" >/dev/null || {
    echo 'Run bash scripts/setup-local-signing.sh first.' >&2; exit 1;
}

mkdir -p "$output"
tools="$beta_root/dmg-tools"
if [[ ! -x "$tools/bin/dmgbuild" ]]; then
    python3 -m venv "$tools"
    "$tools/bin/python" -m pip install 'dmgbuild==1.6.5'
fi
bash "$repo_root/scripts/build-app-icon.sh"
xcodebuild -project Snap.xcodeproj -scheme Snap -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$beta_root/derived-data" \
    CONFIGURATION_BUILD_DIR="$products" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM= \
    build > "$beta_root/build.log" 2>&1

app="$products/Snap.app"
# Validate the public OAuth configuration before creating an installer.
client_id="$(/usr/libexec/PlistBuddy -c 'Print :GIDClientID' "$app/Contents/Info.plist")"
[[ "$client_id" == *.apps.googleusercontent.com ]] || { echo 'Configure Configuration/Google.local.xcconfig first.' >&2; exit 1; }
[[ ! -d "$app/Contents/Frameworks" ]] || { echo 'Embedded frameworks need an explicit nested-code signing step.' >&2; exit 1; }
"$lsregister" -u "$app" || true
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app" "$staging/Snap.app"
# These unsigned build products must never compete with the signed development app.
rm -rf "$app"
rm -f "$staging/Snap.app/Contents/embedded.provisionprofile"
codesign --force --sign "$identity" --options runtime --timestamp=none "$staging/Snap.app"
codesign --verify --deep --strict "$staging/Snap.app"
architectures="$(lipo -archs "$staging/Snap.app/Contents/MacOS/Snap")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    echo "Expected a universal app; found: $architectures" >&2; exit 1;
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staging/Snap.app/Contents/Info.plist")"
dmg="$output/Snap-$version.dmg"
background="$beta_root/installer-background.tiff"
xcrun swift "$repo_root/scripts/dmg-background.swift" "$background" "$version"
"$tools/bin/dmgbuild" -s "$repo_root/scripts/dmg-settings.py" \
    -D "app=$staging/Snap.app" -D "background=$background" "Snap" "$dmg"
hdiutil verify "$dmg"
check_mount="$(mktemp -d "$beta_root/verify.XXXXXX")"
cleanup_verification() {
    hdiutil detach "$check_mount" >/dev/null 2>&1 || true
    rmdir "$check_mount" 2>/dev/null || true
}
trap cleanup_verification EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$check_mount" "$dmg" >/dev/null
codesign --verify --deep --strict "$check_mount/Snap.app"
cleanup_verification
trap - EXIT
(cd "$output" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
# Keep only the installer, avoiding another discoverable app bundle with the same ID.
"$lsregister" -u "$staging/Snap.app" || true
rm -rf "$staging"
echo "Download ready: $dmg"
echo 'Not notarized. First launch requires per-app approval in Privacy & Security.'
