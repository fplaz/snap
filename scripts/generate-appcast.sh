#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
download_url="${1:?Usage: bash scripts/generate-appcast.sh https://HOST/downloads/ [release-notes.html]}"
[[ "$download_url" == https://* ]] || { echo 'Downloads must use HTTPS.' >&2; exit 1; }
[[ "$download_url" != *'/releases/latest/'* ]] || {
    echo 'The feed must point to a specific release, not the latest-release redirect.' >&2; exit 1;
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Snap/Info.plist)"
dmg="$repo_root/.build/distribution/dist/Snap-$version.dmg"
[[ -f "$dmg" ]] || { echo 'Build the DMG first.' >&2; exit 1; }
bin="$(bash "$repo_root/scripts/sparkle-tools.sh")"
archives="$repo_root/.build/distribution/updates"
mkdir -p "$archives"
temporary="$(mktemp -d)"
trap 'hdiutil detach "$temporary" >/dev/null 2>&1 || true; rmdir "$temporary" 2>/dev/null || true' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$temporary" "$dmg" >/dev/null
plist="$temporary/Snap.app/Contents/Info.plist"
public_key="$("$bin/generate_keys" --account cl.fplaz.snap -p)"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" == "$public_key" ]] || {
    echo 'The app public key does not match the signing key in your Keychain.' >&2; exit 1;
}
python3 - "$plist" <<'PY'
import plistlib, sys
from urllib.parse import urlsplit
with open(sys.argv[1], 'rb') as file:
    feed = urlsplit(plistlib.load(file).get('SUFeedURL', ''))
if feed.scheme != 'https' or not feed.hostname or not feed.path.endswith('.xml'):
    sys.exit('Configure an HTTPS XML feed URL before publishing updates.')
PY
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
python3 - "$archives/appcast.xml" "$build" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

feed, build = Path(sys.argv[1]), sys.argv[2]
if not build.isdecimal():
    sys.exit('Release build numbers must be increasing integers.')
if feed.exists():
    for element in ET.parse(feed).iter('{http://www.andymatuschak.org/xml-namespaces/sparkle}version'):
        if not (element.text or '').isdecimal() or int(element.text) > int(build):
            sys.exit('The release build number is older than a version already in the feed.')
PY
hdiutil detach "$temporary" >/dev/null
rmdir "$temporary"
trap - EXIT
# Do not overwrite an already prepared version with different bytes.
if [[ -f "$archives/Snap-$version.dmg" ]]; then
    cmp -s "$dmg" "$archives/Snap-$version.dmg" || {
        echo 'This version already has a different update archive. Increment the version and build number.' >&2; exit 1;
    }
else
    cp "$dmg" "$archives/"
fi
if [[ -n "${2:-}" ]]; then
    if [[ -f "$archives/Snap-$version.html" ]]; then
        cmp -s "$2" "$archives/Snap-$version.html" || {
            echo 'Different release notes already exist for this version; increment the version.' >&2; exit 1;
        }
    else
        cp "$2" "$archives/Snap-$version.html"
    fi
fi
"$bin/generate_appcast" --account cl.fplaz.snap --versions "$build" \
    --maximum-deltas 0 --download-url-prefix "${download_url%/}/" \
    --embed-release-notes -o "$archives/appcast.xml" "$archives"
# Keep versioned local archives for feed history, but publish one fixed-name asset
# inside each version's release. Older feed entries keep their existing URLs.
python3 "$repo_root/scripts/set-appcast-download.py" "$archives/appcast.xml" \
    "$build" "${download_url%/}/SNAP.dmg"
"$bin/sign_update" --account cl.fplaz.snap "$archives/appcast.xml"
"$bin/sign_update" --account cl.fplaz.snap --verify "$archives/appcast.xml"
publish="$repo_root/.build/distribution/publish/$version"
mkdir -p "$publish"
cp "$dmg" "$publish/SNAP.dmg"
cp "$archives/appcast.xml" "$publish/appcast.xml"
echo "Release files ready: $publish"
echo 'Upload Snap.dmg and appcast.xml to the matching version release.'
