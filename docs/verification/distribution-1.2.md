# Snap 1.2 distribution — 2026-10-12

- Artifact: `.build/distribution/dist/Snap-1.2.dmg`, with a matching SHA-256 file. App version 1.2 / build 10; universal arm64 + x86_64 for macOS 14 or newer.
- Includes temporary Select with Space, tool cycling with Tab, and the approved five-page onboarding tutorial with quoted menu options and menu-bar replay.
- All 101 tests passed during onboarding validation. The final copy-only refinement subsequently compiled successfully in the signed preview and universal release builds.
- Visually inspected all five tutorial pages using an isolated preferences suite, without setting the real user's first-launch preference.
- The complete `scripts/build-dmg.sh` run succeeded. It verified both CPU architectures, the signed staging app, the completed disk image, and the app signature inside the mounted installer.
- Portable SHA-256 verification passed with `shasum -a 256 -c Snap-1.2.dmg.sha256`.
- Uses the retained Snap Local Distribution self-signed identity. The installer is not notarized. Installation and interaction on another Mac remain manual checks.
