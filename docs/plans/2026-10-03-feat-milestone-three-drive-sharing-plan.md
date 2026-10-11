---
title: Milestone 3 - Google Drive uploads and screenshot history
date: 2026-10-03
status: implemented-locally-awaiting-setup
---

# Milestone 3 — Google Drive uploads and screenshot history

## Outcome and authority

Connect a Google account, upload an annotated screenshot into a dedicated Drive folder, copy its viewing link, and browse previous uploads inside Snap.

The user already chose **anyone with the link can view**. Milestones 1–2 establish Command–Shift–7, full-resolution frozen captures, annotation tools, the compact metallic toolbar, and clearing annotations while preserving the selected rectangle. Preserve those behaviors.

The user approved this plan on 2026-10-03; local implementation and isolated verification are recorded in `docs/verification/milestone-three.md`. Real-service acceptance awaits OAuth configuration and provisioning. It creates no Google resources and performs no uploads, commits, or pushes. Defaults below are recommendations for approval before implementation.

## Proposed product contract

### Account

- Add **Sign in with Google** and **My Screenshots** to the status menu. A small account/history window presents sign-in and follows Google's button branding. Snap remains a menu-bar app with no permanent Dock icon.
- One connected account at a time; show its email and Sign Out. Sign out, then sign in to switch accounts.
- Restore credentials asynchronously at launch; capturing and local Copy/Save never wait for Google or network access.
- Request identity/profile access plus `drive.file`. Tokens remain in the SDK's Keychain storage. Local metadata and pending uploads are partitioned by stable account ID, not email.
- Sign Out cancels active network work and clears the visible account/history state. Pending work stays attached to its original account, with no automatic transfer to a newly connected account. Sign Out does not delete uploaded screenshots or revoke their viewing links.

Google documents a macOS sign-in SDK, URL callbacks, previous-session restoration, and Keychain setup. Its macOS integration uses an **iOS-type OAuth client**, despite the platform name. [Setup](https://developers.google.com/identity/sign-in/ios/start-integrating), [sign-in lifecycle](https://developers.google.com/identity/sign-in/ios/sign-in).

### Folder and ownership

- Default dedicated folder: **Snap Screenshots**, created in the connected account's My Drive on first upload. Folder remains private; sharing applies to each screenshot.
- Store its Drive ID per account and mark it with app metadata. Resolve by ID/marker rather than folder name, so a user rename does not create another folder. An unrelated same-name folder is not adopted.
- If the folder is trashed or unavailable, explain the problem and let the user explicitly create a replacement before retrying. Do not silently scatter screenshots across folders.
- Files are PNGs with timestamp names and a unique upload identifier. Attach an app marker so history can recognize screenshots even if the user moves them in Drive.
- Folder picking, arbitrary imported files, Shared Drives, and multiple simultaneously connected accounts are deferred.

`drive.file` covers app-created files and works with Drive REST resources; broad whole-Drive access is unnecessary for this design. [Drive scope guide](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

### Upload and copy link

- Add an icon-only **Upload & Copy Link** action to the existing toolbar. Keep the current tool/style, clear, Copy, Save, and Cancel controls; widen the strip only as needed.
- Signed out: disable Upload with a sign-in tooltip; sign-in happens from the status menu/account window, outside the capture overlay.
- Upload commits pending text and renders the same full-resolution annotated PNG used by Copy/Save. A current unfinished drawing must finish or cancel before export.
- First persist the immutable PNG and upload record locally. If composition/persistence fails, keep the capture editable. Once staging succeeds, close the overlay, release the frozen displays, and return focus to the previous app. Upload then proceeds in the background.
- Allow one active/pending upload at a time for this first pass. Another capture can still be copied or saved; Upload shows that the existing job needs completion/retry/discard. No unbounded offline queue.
- Status menu shows uploading, failure, or link-ready state. History shows the pending item and Retry/Discard Local Copy where relevant.
- Success requires file upload, confirmed public-view permission, and a nonempty Drive `webViewLink`. Copy that returned URL rather than inventing a URL. A Drive viewer link satisfies this milestone; custom short URLs/viewer hosting are deferred.
- If the clipboard is unchanged since Upload was clicked, copy the link automatically. If the user copied something else during upload, preserve it and show **Link ready — Copy Link** in the status menu/history.
- Clean up staged PNGs after success or explicit local discard. Interrupted jobs survive app restart, but resume only when the original account is connected and the user selects Retry. Only the composed crop is staged, never the entire frozen display or editable annotation document.

The local staging store uses an app-private Application Support directory and atomic writes. Store job/account/file IDs, stage, and PNG path; never credentials or bearer URLs there.

### Sharing, failures, and retry safety

- Set file permission to `type=anyone`, `role=reader`, `allowFileDiscovery=false`. The uploaded image is viewable by link; the folder is not made public. Display a concise “Anyone with the link can view” note next to the upload action's tooltip/account explanation, without a per-upload confirmation.
- Google Workspace policy can reject public sharing. Then show **Uploaded, sharing failed**, retain the file ID, and allow retrying permission creation. Do not copy a link as if sharing succeeded.
- Allocate and persist a Drive file ID before creation. Retry the same file ID after an ambiguous response; reconcile existing metadata/permissions before progressing. A permission retry must never upload another PNG. Folder creation also needs an ID persisted before its request to prevent duplicate folders after a timeout.
- Use bounded retry/backoff for transient network errors, rate limits, and server failures. Refresh authentication once when appropriate. Consent denial, revoked credentials, quota exhaustion, and sharing-policy errors require a clear actionable state rather than repeated automatic retries.
- Signing out, quitting, or discarding cancels local work. Cancellation does not prove a server mutation was rolled back: reconcile recorded file IDs on next explicit retry. Discard Local Copy removes local staging only; it does not delete a possibly uploaded Drive file. History can still display such a file.
- Never log tokens, PNG data, OAuth callback contents, or resumable session URLs. Every completion checks its account/job identity before updating UI or clipboard.

Drive supports link-oriented permissions and discoverability control. Pre-generated IDs let ambiguous file creation be retried without duplicates. [Permissions](https://developers.google.com/workspace/drive/api/reference/rest/v3/permissions), [retry-safe uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads#use_a_pre-generated_id_to_upload_files).

### My Screenshots

- A native window opened from the status menu: newest-first thumbnail grid, capture/upload date, Copy Link, and Open in Drive. Match the toolbar's dark surface treatment while keeping Google sign-in branding intact.
- Load app-marked, non-trashed PNGs accessible to the connected account, with pagination and Refresh. Drive is the source of truth for uploaded items; local staging contributes the pending/failed item.
- Include uploads moved out of the dedicated folder. Do not include unrelated Drive images. Cross-install history depends on retaining the same OAuth app identity and user authorization.
- Handle loading, signed out, empty, offline/error, missing thumbnail, and pending sharing states. Lazy-load thumbnails with bounded concurrency and a bounded account-scoped memory cache; refresh expired URLs. Cancel/invalidate requests and clear images on sign-out.
- Copy Link checks current sharing state; if permission was removed in Drive, show a sharing-needed state and require an explicit Retry Sharing action before republishing it. Do not silently re-share on refresh.
- No in-app deletion, search, albums, annotation re-editing, or whole-Drive synchronization in this milestone. Those actions remain available in Drive where applicable.

Drive exposes `webViewLink` and short-lived `thumbnailLink` fields, and supports searches by app properties. [File metadata](https://developers.google.com/workspace/drive/api/reference/rest/v3/files), [file search](https://developers.google.com/workspace/drive/api/guides/search-files).

## Implementation sequence

| Pass | Work and integration points | Completion evidence |
| --- | --- | --- |
| 1. Google setup and account | Add GoogleSignIn through Swift Package Manager; pin a compatible release. Configure client ID, reversed URL scheme, callback handling in AppDelegate, Keychain entitlement, and AccountController. Add account window/status actions. | Real sign-in, cancellation, restart restoration, token refresh, sign-out; existing signed capture still works. |
| 2. Drive client and folder | Small URLSession-based DriveClient with explicit Codable request/response types and injectable transport. Folder ID resolution, app markers, pre-generated IDs, metadata/permission operations. | Stubbed HTTP contracts and retry/reconciliation tests; one real private folder created/reused. |
| 3. Upload job | UploadCoordinator plus small atomic pending-job store. Separate background job lifetime from CaptureSession; reuse ScreenshotExporter.compose/png. Use Drive resumable upload with explicit timeouts and bounded retries. | File creation, sharing failure/retry, ambiguous timeout, relaunch recovery, cancellation, and account isolation verified. |
| 4. Capture integration | Upload callback/button in CaptureToolbar/CaptureOverlayView, staging handoff in CaptureCoordinator, progress in StatusBarController. Release overlay only after staging succeeds. | No duplicate click/job; pending text included; Copy/Save/clear/cancel regressions pass; another capture works during upload. |
| 5. History | ScreenshotHistoryController and native window, paginated metadata, lazy thumbnails, link/open actions, pending/error states. | Empty/offline/expired thumbnail/page/account-change cases; older uploaded images survive relaunch and folder moves. |
| 6. Acceptance | Update README/setup instructions and milestone-three verification record. | Full tests, stable signing, real-account end-to-end checks and actual speed evidence below. |

Keep AppKit as the application lifecycle/UI foundation. A hosted SwiftUI view is acceptable for Google's branded sign-in control and the gallery if it reduces UI code; it must not change menu-bar behavior. Use SDK-managed OAuth rather than implementing a custom token flow. No Snap backend, Firebase, service account, or server client secret is required by this design.

## Setup needed before real-account testing

1. A Google Cloud project with Drive API enabled.
2. OAuth consent configuration and the development Google account added as a test user where required.
3. An iOS-type OAuth client for `cl.fplaz.snap`, with the public client ID supplied to the app configuration. Verify the exact console fields during setup. A client secret is not needed in the Mac app.
4. Existing Apple Development signing plus the SDK-required Keychain access group. Verify entitlement/signing compatibility in pass 1 before building the rest.

No additional Xcode installation is expected. Public distribution may require Google's OAuth branding/verification work, privacy-policy hosting, and notarization; those release requirements are separate from this development milestone. Do not report public-release readiness from a successful test-account login.

## Acceptance and speed

- Complete capture → annotate → Upload → copied link; open that link in a signed-out browser and verify the correct full-resolution PNG and annotations.
- Folder itself remains private. Repeated uploads reuse it; permission retries produce one screenshot file.
- Cancelled sign-in leaves local capture usable. Relaunch restores account/history; sign-out prevents stale jobs or thumbnails appearing under another account.
- Simulate upload success with lost response, sharing failure, offline/429/5xx, revoked access, full Drive, clipboard changes, staging failure, restart, and account changes.
- Verify history pagination and missing/expired thumbnails without fetching every full-size PNG.
- Run existing 42 tests plus meaningful account/upload/history tests with isolated storage and stubbed HTTP. Integration tests must never mutate real Drive or Keychain by default.
- Capture preparation must perform no Drive requests and wait on no sign-in restoration. Measure warm capture latency against the existing app on the same Mac; disclose regressions and unavailable hardware coverage.
- Record overlay release timing separately from network completion. Upload duration depends on network/Google; do not claim a fixed upload-latency budget without measurements.

## Deferred scope

Public release, custom web viewer/short links, editable cloud documents, image deletion in Snap, arbitrary destination picking, Shared Drives, multiple concurrent accounts/uploads, automatic offline scheduling, and notifications requiring new OS permissions.

## Repository grounding

- `Snap/CaptureCoordinator.swift`: existing composition, export guard, session identity checks, and finish/cleanup.
- `Snap/CaptureSession.swift`: local capture lifecycle; avoid extending it into a network queue.
- `Snap/CaptureToolbar.swift`: icon strip, style menus, drag handle, and export control lockout.
- `Snap/StatusBarController.swift` and `Snap/AppDelegate.swift`: account/history/progress integration and OAuth callback lifecycle.
- `Snap/ScreenshotExporter.swift`: shared full-resolution renderer/encoder.
- Milestones 1–2 plans and verification records: existing behavior and unmeasured performance coverage.
