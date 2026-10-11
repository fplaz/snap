# UI polish preview — 2026-10-10

- Upload start hides the history window and shows only the upload progress panel. Capture completion no longer reactivates Snap itself when Snap was the previously active application; external application focus restoration remains intact. Manual upload/window behavior confirmation is pending.
- Menu-bar viewfinder template now includes a centered bold S. Rectangle is the initial drawing tool in both the overlay and its popup.
- All 93 tests passed (`/tmp/snap-polish-tests.log`), including a new test checking the popup and first drawn annotation agree on Rectangle. The universal preview build succeeded (`/tmp/snap-polish-preview-build.log`).
- The original PNG and the bundled ICNS were visually inspected and do not contain a white surrounding border. The reported logo display issue needs its location or a screenshot to identify the rendering problem; no asset modification has been made.
- Preview remains `.build/area-drag-preview/Snap.app`, including experimental resizing. The release DMG remains build 5.
