# Snap

A native macOS menu bar screenshot app. Press **⌘⇧7**, drag a rectangle, then copy the image or save a PNG.

Snap includes capture, selection, annotations, clipboard output, and local save. Google Drive upload and screenshot history are implemented locally; The local OAuth configuration and signed development build are ready; real-account acceptance testing remains pending. See [Google setup](docs/google-setup.md).

## Requirements

- macOS 14 or newer.
- Full Xcode, with its license accepted and first-run setup complete.
- Screen Recording permission for Snap when taking the first screenshot.

Xcode resolves pinned GoogleSignIn 9.0.0 (button UI), AppAuth 2.1.0, and GTMAppAuth 5.0.0 through Swift Package Manager. Local capture works without Google configuration.

## Run in Xcode

Open `Snap.xcodeproj`, select the **Snap** scheme and **My Mac**, then Run. Snap appears in the menu bar with a viewfinder icon. It has no Dock icon.

The bundle identifier is `cl.fplaz.snap`. App builds use **Apple Development** signing with team `94K9S6W37W` so Screen Recording permission can recognize the same app across rebuilds. The unit-test bundle uses ad-hoc signing. Production distribution signing and notarization are outside milestone 1.

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

On first launch, a five-step tutorial covers capture, moving and resizing the area, Google sign-in and uploads, annotation tools, and keyboard shortcuts. Skip or close it at any time; it appears automatically only once per macOS user, including for existing users opening this update. Reopen it from **Snap → Tutorial…**. Starting a capture hides the tutorial.

1. Press **⌘⇧7**, or choose **Take Screenshot** from the menu bar.
2. If Screen Recording access is missing, Snap shows **Allow Screen Recording** and **Not Now**. Allow calls the native macOS request API on every confirmed attempt, including after access is removed. Follow the native dialog to enable Snap. Reopen Snap if needed, then try the screenshot shortcut again.
3. Drag a rectangular area. Each display is frozen before the overlay appears; the selected area is undimmed.
4. Click **Copy** (⌘C), **Save** (⌘S), or **Cancel** (Escape).

For a quick copy, press **⌘⇧6** or choose **Take screenshot and copy** from the Snap menu. Drag to select an area; releasing the mouse copies it immediately and closes capture, skipping the annotation toolbar. Escape cancels capture. **⌘⇧7** keeps the usual annotation workflow.

After selection, drawing keeps the crop fixed. Use **Clear Annotations** to immediately remove all drawing and text while keeping the selected area and toolbar open. Selection stays within the display where the drag starts. Canceling the native save panel keeps the screenshot and annotations available. Copy or successful save ends capture and returns focus to your previous app.

Drag any corner to resize the capture area, or drag the small black handle at the middle of an edge to move just that edge. Drag the rest of the border to move the whole area. Resizing keeps annotations at their screen positions; Escape during a resize restores the previous area.

## Annotate

Choose **Pen**, **Arrow**, **Line**, **Rectangle**, **Ellipse**, **Text**, **Blur**, or **Number stamps** in the toolbar. Color, stroke width, and text size apply to new marks. Drawing is clipped to the capture rectangle.

With **Number stamps**, click to place a circle in the selected color with a white number. Choose Small (24 pt), Medium (32 pt, the default), or Large (40 pt) from the stamp size control. Each capture starts at 1 and advances to one above the highest remaining stamp. Switching tools preserves the sequence. Undoing or deleting the highest stamp makes its number available again; existing stamps keep their numbers. Select a stamp to move it, change its color or size, or delete it. Stamps are included in Copy, Save, and uploads.

With **Rectangle** or **Ellipse**, the shape style menu offers **Thin outline**, **Medium outline**, **Thick outline**, and **Filled**. Filled shapes use the selected color. Select an existing shape to change between outline and fill; filled shapes can be selected and moved by clicking anywhere inside them. Style changes support undo and redo.

Open **Annotation tool settings…** from the Snap menu (⌘,) to configure the starting tool, color, line/outline width, shape fill, text size, and blur strength. Enable **Use last-used settings** to carry your toolbar choices across captures and app restarts. Otherwise, each capture starts with your configured defaults. Fresh installs start with a red rectangle and a thin outline.

With **Blur**, drag a rectangle over text or another area of the screenshot. Adjust the toolbar's strength slider from 1 (light) to 12 (strong), in half-step increments; the default is 3.5. Each area keeps its own strength. Select an existing blur area to change its strength, move it, or delete it; undo and redo work as with other annotations. Blur previews while drawing and is included in Copy, Save, and uploads. It affects the screenshot beneath drawing and text annotations. Color and line width do not affect it.

Use **Select** to click a mark, move it, change its style, or delete it. Double-click text with Select to edit it. **⌘Z** undoes one completed annotation operation; **⌘⇧Z** redoes it.

After selecting the screenshot area, hold **Space** to temporarily use Select; releasing it restores your previous tool. Press **Tab** to cycle through Select, Pen, Arrow, Line, Rectangle, Ellipse, Text, Blur, and Number stamps, or **Shift+Tab** to cycle backward. These shortcuts leave normal text input available while editing an annotation.

Text supports multiple lines. Return inserts a newline; **⌘Return** or clicking outside commits the edit. Escape cancels the current text edit and restores its previous value. Native text copy and undo remain available while typing. Toolbar Copy/Save commits pending text before exporting.

Escape first cancels an unfinished drawing, then clears a selected mark, then cancels the capture. Copy and Save include annotations at the original screenshot resolution; toolbar controls and selection outlines are excluded. No editable document is saved automatically.

Snap captures only when invoked. It does not continuously record or upload screenshots. Exports preserve the source image's pixel resolution, including Retina scaling.

If another app owns ⌘⇧7 or ⌘⇧6, the corresponding Snap menu item shows a shortcut warning in its tooltip; both menu actions still work. Shortcut customization is deferred.

For isolated cloud validation before provisioning is configured, build/test without signing into a separate product directory:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Snap.xcodeproj -scheme Snap -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/cloud-validation \
  CONFIGURATION_BUILD_DIR="$PWD/.build/cloud-validation-products" \
  CODE_SIGNING_ALLOWED=NO test
```

The unhosted test target compiles the app sources without building a second Snap.app. Keep test DerivedData separate from the signed app build so testing cannot replace or unregister it. Use the normally signed bundle for real capture and Google login.

## Google Drive and history

For an unnotarized website download, first run `bash scripts/setup-local-signing.sh`, then `bash scripts/build-dmg.sh`. The output is `.build/distribution/dist/Snap-1.3.dmg`. The build creates a project-local Python environment with pinned `dmgbuild` tooling on first use. The installer opens a dark metallic Finder layout with Snap, an Applications shortcut, and drag-to-install instructions; its layout and background files are hidden. No separate installation guide is bundled. The app supports Intel and Apple Silicon on macOS 14 or newer and uses the file-based Keychain without provisioning-backed entitlements.

Releases use the retained **Snap Local Distribution** self-signed identity from your login Keychain. Preserve and securely back up that identity and its private key for updates. `SNAP_SIGNING_IDENTITY` can override the identity; the build never silently falls back to ad-hoc signing. Local trust applies only to the creator's code-signing policy; no certificate or private key needs to be installed on users' Macs. This does not provide Developer ID trust or notarization: users must approve the downloaded app through Privacy & Security. The Google OAuth project must be configured for production before accepting arbitrary users.

Sign in from Snap's menu, then use the toolbar's **Upload & Copy Link** icon. Uploads contain the same full-resolution PNG as Copy/Save and are placed in the private **Snap Screenshots** folder. Each uploaded screenshot is viewable by anyone with its link.

Upload stages only the composed crop before closing the overlay and returning focus. Network work continues in the background. One upload can be pending for the connected account; other captures can still be copied or saved. **My Screenshots** shows uploaded images, pending failures, Retry, and Discard Local Copy. Discarding local staging does not delete files already uploaded to Drive.

Retry uses the original file ID to avoid duplicates. A failed sharing request retries sharing, not PNG upload. Interrupted jobs persist locally and resume only on explicit Retry with their original account. Sign Out cancels network work, clears visible account/history state, and leaves uploaded files and their public links intact.

After the capture overlay closes, a small panel appears at the top right of the active screen. An indeterminate loading bar runs while uploading/sharing, with Copy Link disabled until the viewing link is verified. Once ready, the panel shows the link, Copy Link, and Close; Copy Link dismisses the panel. Failed uploads offer Review Upload for the existing retry controls. The panel hides during new captures so it is not included in screenshots.

The viewing link is copied automatically if your clipboard has not changed during upload; otherwise Snap shows **Link ready — Copy Link**. History refreshes sharing state before copying a link and never silently republishes a file whose public permission was removed in Drive.

Google sign-in opens the Mac’s default browser through NSWorkspace. AppAuth manages the authorization-code flow, random state, PKCE, and token refresh; GTMAppAuth stores credentials in the macOS file-based Keychain using its supported configuration. The beta's credential item name is retained for continuity; older development builds using the data-protection Keychain require signing in again. Cancel Sign In stops an abandoned flow, and unanswered sign-in attempts expire after ten minutes. Pending PNGs and their job metadata use app-private Application Support storage; successful/discarded jobs are cleaned up. Whole frozen displays are never staged. Google API access uses `drive.file`, not unrestricted Drive access.

Complete [Google setup](docs/google-setup.md) before real-account testing. The signed milestone-three build is available at `.build/xcode/Build/Products/Debug/Snap.app`; real sign-in/upload testing remains pending.

## App updates

Snap checks for updates daily using Sparkle and includes **Check for Updates…** in its menu. Users approve installation; restarting for an update waits for active captures and uploads. Signed feeds and DMGs can be hosted as GitHub Release assets without an update server or Apple membership. The feed becomes available when an updater-enabled release is published. Existing users must install that first release manually.

See [Releasing Snap updates](docs/updates.md) for signing-key setup, build commands, hosting, and publishing.

## Verification

The XCTest target is unhosted and compiles app capture, cloud, and UI sources directly. Cloud tests use stubbed HTTP, temporary storage, and injected clipboard behavior; they do not sign in or mutate real Drive/Keychain. It does not launch the app, take screenshots, or alter the real clipboard. It verifies crop coordinates and pixels, PNG encoding, and session transitions.

Desktop behavior needs a real macOS check: global shortcut, screen permission, overlays, fullscreen apps, multiple monitors, clipboard interoperability, save panel, and focus restoration. See `docs/verification/milestone-one.md` for observed results and remaining checks.

Local Instruments signposts in the `cl.fplaz.snap` / `Capture` category record preparation-to-overlay scheduling and release-to-toolbar scheduling. These are useful attribution timings; they do not alone prove when a frame was actually displayed.
