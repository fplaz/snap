# Snap 1.0 download — 2026-10-06

- Output: `.build/distribution/dist/Snap-1.0.dmg`, with a portable SHA-256 checksum file. Read-only HFS+ image contains exactly `Snap.app` and the Applications shortcut. No guide is included; the previous guide source was removed.
- Version 1.0 / build 2. Regenerated all macOS icon sizes from the user's replacement `snap_icon.png` and rebuilt AppIcon.icns. Packaged icon bytes match the new resource; the source PNG remains untouched.
- File-based Keychain is now the standard app configuration. The beta's item name is retained to avoid unnecessary credential migration. Provisioning-restricted Keychain entitlements were removed. Development users on the earlier data-protection store need to sign in again.
- `setup-local-signing.sh` created **Snap Local Distribution** in the login Keychain with user-level code-signing trust only. No system trust, SSL trust, or Gatekeeper policy was changed. Private key files and the temporary encrypted PKCS#12 were removed after import. This identity must be retained and securely backed up for future releases; users do not install it.
- `build-dmg.sh` requires that identity (or an explicit override) and never falls back to ad-hoc signing. The designated requirement binds `cl.fplaz.snap` to the retained certificate. This is self-signed, unnotarized code; it does not obtain Developer ID / Gatekeeper approval.
- The mounted final app passed strict signature verification. Executable mode is 0755; arm64 and x86_64 slices both declare macOS 14.0 minimum. OAuth configuration and absence of an embedded provisioning profile were verified. Dependencies reference system libraries/frameworks, not developer-machine paths.
- **82 tests passed, 0 failures** (`/tmp/snap-1.0-tests.log`). A signed, isolated dummy-data Keychain check also launched and completed add/read/delete under the new certificate without restricted entitlements. Full Snap launch, Google login, Screen Recording, and update continuity remain unverified on another Mac.
- A friend reported a generic Finder cannot-open alert with the earlier private-beta DMG on Apple Silicon / macOS 15.6.1 after copying into Applications. This is within the declared architecture/OS range. The screenshot alone cannot identify a Gatekeeper, signature, installation, or loader failure. Await per-app Open Anyway outcome and, if necessary, the friend's launch error/signature diagnostic. Do not claim the new signing change has resolved that external failure until retested.

## Build 3 — first-click selection and menu-bar icon

- The user confirmed the self-signed build opens successfully on the friend's Mac. The earlier external launch failure is resolved; its exact cause was not established.
- CaptureOverlayView now accepts the first mouse event in a non-key window, allowing the first drag to select on another display. A regression test checks first-mouse acceptance and the resulting rectangle in a non-key overlay.
- Replaced the menu-bar system symbol with a directly drawn 18-point template viewfinder icon. Multi-display interaction and icon visibility on the friend's Mac still require manual confirmation; an item hidden by menu-bar overflow is a separate possibility.
- **83 tests passed, 0 failures** (`/tmp/snap-build3-tests.log`). Rebuilt version 1.0 / build 3 at the same `Snap-1.0.dmg` path; the package script verified the strict code signature, both architectures, and the disk-image checksum (`/tmp/snap-build3-dmg.log`).

## Build 5 — approved border dragging

- Released the user-approved border drag interaction: the capture rectangle, annotations, and toolbar move together within the current display. Hand cursors indicate hover and active drag. Edge grip indicators were removed after preview review; the toolbar retains its original compact placement.
- Escape restores the original position during a drag. Export waits for the gesture to finish, then uses the updated crop rectangle. Annotation coordinates and undo history are preserved.
- **86 tests passed, 0 failures** (`/tmp/snap-build5-tests.log`). The universal build 5 DMG passed the packaging script's strict signature, architecture, and disk-image checksum checks (`/tmp/snap-build5-dmg.log`).
