# Snap 1.1 distribution — 2026-10-10

- Final artifact: `.build/distribution/dist/Snap-1.1.dmg`, with a matching portable SHA-256 file. App version 1.1 / build 8, universal arm64 + x86_64, macOS 14 minimum.
- Includes approved selection moving/resizing, annotation clipping, toolbar attachment, easier border hit testing, default Rectangle tool, menu-bar S, and upload history-window suppression.
- Added a native Icon Composer resource with an explicit black background, compiled Assets.car, and CFBundleIconName. Retained the original artwork and legacy ICNS. Removed the launch-time ICNS override. Both the native renderer and actual Finder icon show the black surface without the silver surround.
- Installer artwork stays at the top left of a 1920 × 1200-point Retina backdrop so larger Finder windows do not reveal white space. Default layout is 640 × 400 points, with 96-point icons at (160, 190) and (480, 190). Label plates were aligned against actual Finder text during visual QA.
- Only Snap and Applications are normally visible; .background.tiff and .DS_Store are hidden layout resources. This Mac has Show Hidden Files enabled, so the background resource appeared during inspection. The global Finder preference was preserved.
- Used project-local dmgbuild 1.6.5, ds-store, and mac-alias. Build script compiles the modern icon, generates the background, and verifies the signed app inside the completed image. The existing ICNS supports older macOS versions.
- All 93 tests passed in /tmp/snap-icon-layout-fixes-tests.log. Project/plist lint, shell syntax, and diff checks passed. The completed disk image checksum and strict packaged-app signature passed verification.
- Packaging was resumed from the verified signed app after editing a running shell script disrupted its subsequent commands. Keychain approval succeeded. Future builds use the complete saved script.
- Visual QA used Finder icon view in a larger window, confirming the icon and background coverage. App interaction after installation on another Mac remains a manual check.

- Final refinements: border drag tolerance reduced from 10 to 7 points on each side (30%); resize corner uses open-hand hover and closed-hand drag cursors. Updated existing border interaction test for the narrower target. All 93 tests passed in /tmp/snap-final-cursor-tests.log. Rebuilt the same Snap-1.1.dmg with the full build script; completed-image and packaged-signature checks passed.
