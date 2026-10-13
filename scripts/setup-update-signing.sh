#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$(bash "$repo_root/scripts/sparkle-tools.sh")"
# Reuses an existing key; never exports the private key or replaces it.
"$bin/generate_keys" --account cl.fplaz.snap
echo 'Copy the public key into Configuration/Updates.xcconfig as SNAP_UPDATE_PUBLIC_KEY.'
echo 'Keep the private key in your Keychain and securely back it up for future releases.'
