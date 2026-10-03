# Snap

A native macOS menu bar screenshot app. Press **⌘⇧7**, drag a rectangle, then copy the image or save a PNG.

Snap includes capture, selection, annotations, clipboard output, and local save. Google Drive uploads and screenshot history are a later milestone.

## Requirements

- macOS 14 or newer.
- Full Xcode, with its license accepted and first-run setup complete.
- Screen Recording permission for Snap when taking the first screenshot.

No packages or third-party dependencies are required.

## Run in Xcode

Open `Snap.xcodeproj`, select the **Snap** scheme and **My Mac**, then Run. Snap appears in the menu bar with a viewfinder icon. It has no Dock icon.

The bundle identifier is `cl.assetplan.snap`. App builds use **Apple Development** signing with team `94K9S6W37W` so Screen Recording permission can recognize the same app across rebuilds. The unit-test bundle uses ad-hoc signing. Production distribution signing and notarization are outside milestone 1.

### Keep Screen Recording permission across builds

1. In **Xcode → Settings → Accounts**, add your Apple Account. Select your team, open **Manage Certificates**, and create an **Apple Development** certificate if needed.
2. In the **Snap app target → Signing & Capabilities**, enable **Automatically manage signing**, select your team, and ensure the signing certificate is **Apple Development**, rather than **Sign to Run Locally**. If needed, set **Build Settings → Code Signing Identity → Debug** to **Apple Development**.
3. Build and run from the same app location. After switching identities, replace the old Snap entry in Screen Recording settings and grant access to the newly signed app once.

The normal command-line build below uses the configured signing identity. On another developer's Mac, override the team ID:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Snap.xcodeproj -scheme Snap -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY='Apple Development' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

If Snap repeatedly asks despite an enabled permission entry after an ad-hoc rebuild: quit Snap, remove its entry with the minus button in **System Settings → Privacy & Security → Screen Recording**, reopen the current app, and grant access again. Re-enabling the existing stale entry may retain the old signature. This is a temporary recovery; another ad-hoc rebuild can cause it again.

See [Apple's explanation of the signing issue](https://developer.apple.com/forums/thread/819406) and [certificate management instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html).

## Build and test from Terminal

These commands use the installed Xcode without changing the system-wide developer directory:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Snap.xcodeproj -scheme Snap -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Snap.xcodeproj -scheme Snap -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode test

open .build/xcode/Build/Products/Debug/Snap.app
```

Use the same built app location across launches. Changing its identity or signing can affect macOS permission recognition.

## Capture

1. Press **⌘⇧7**, or choose **Take Screenshot** from the menu bar.
2. Allow Screen Recording access when requested. Enable Snap in **System Settings → Privacy & Security → Screen Recording** (the label may include System Audio on newer macOS). Relaunch Snap if macOS requests it.
3. Drag a rectangular area. Each display is frozen before the overlay appears; the selected area is undimmed.
4. Click **Copy** (⌘C), **Save** (⌘S), or **Cancel** (Escape).

After selection, drawing keeps the crop fixed. Use **Clear Annotations** to immediately remove all drawing and text while keeping the selected area and toolbar open. Selection stays within the display where the drag starts. Canceling the native save panel keeps the screenshot and annotations available. Copy or successful save ends capture and returns focus to your previous app.

## Annotate

Choose **Pen**, **Arrow**, **Line**, **Rectangle**, **Ellipse**, or **Text** in the toolbar. Color, stroke width, and text size apply to new marks. Drawing is clipped to the capture rectangle.

Use **Select** to click a mark, move it, change its style, or delete it. Double-click text with Select to edit it. **⌘Z** undoes one completed annotation operation; **⌘⇧Z** redoes it.

Text supports multiple lines. Return inserts a newline; **⌘Return** or clicking outside commits the edit. Escape cancels the current text edit and restores its previous value. Native text copy and undo remain available while typing. Toolbar Copy/Save commits pending text before exporting.

Escape first cancels an unfinished drawing, then clears a selected mark, then cancels the capture. Copy and Save include annotations at the original screenshot resolution; toolbar controls and selection outlines are excluded. No editable document is saved automatically.

Snap captures only when invoked. It does not continuously record or upload screenshots. Exports preserve the source image's pixel resolution, including Retina scaling.

If another app owns ⌘⇧7, Snap shows a shortcut warning in its menu; **Take Screenshot** still works. Shortcut customization is deferred.

## Verification

The XCTest target is unhosted and compiles the app's geometry, session, and export sources directly. It does not launch the app, take screenshots, or alter the real clipboard. It verifies crop coordinates and pixels, PNG encoding, and session transitions.

Desktop behavior needs a real macOS check: global shortcut, screen permission, overlays, fullscreen apps, multiple monitors, clipboard interoperability, save panel, and focus restoration. See `docs/verification/milestone-one.md` for observed results and remaining checks.

Local Instruments signposts in the `cl.assetplan.snap` / `Capture` category record preparation-to-overlay scheduling and release-to-toolbar scheduling. These are useful attribution timings; they do not alone prove when a frame was actually displayed.
