# Milestone 3 verification

Execution evidence as of 2026-10-03. The implementation builds and isolated tests pass; the signed development build is verified, while real Google sign-in/uploads are **not accepted or complete** yet.

## Implemented

- Pinned GoogleSignIn 9.0.0 through Swift Package Manager, optional local OAuth client configuration, macOS callback handling, asynchronous restoration, limited Drive scope, and Keychain entitlement.
- Status-menu account/history/link actions and the native dark My Screenshots window.
- Upload toolbar action using the existing composed full-resolution PNG; staging completes before releasing capture overlays, then network upload runs independently.
- Atomic account-partitioned pending job storage, explicit retry after restart, private folder identification, pre-generated file IDs, resumable upload, verified unlisted anyone-reader permission, and clipboard-change protection.
- Sharing-only retry, local discard semantics, replacement-folder recovery, bounded HTTP retries, account/job generation checks, and stale completion cancellation.
- App-marked paginated history, current sharing check before Copy Link, explicit Retry Sharing, validated viewing URLs, bounded lazy thumbnails, downsampled images, memory cache, ephemeral thumbnail HTTP session, and account-reset cleanup.
- Orphan staging PNG cleanup only for known UUID image files unreferenced by a successfully decoded manifest. Corrupt journals are preserved and prevent upload storage initialization rather than silently replacing work.

## Build and tests

- Xcode 27.0 / Apple silicon / Debug arm64.
- Final `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO` and a separate `.build/cloud-validation-products` product directory: **61 tests passed, 0 failures**.
- Result bundle: `.build/xcode/Logs/Test/Test-Snap-2026.10.03_19-04-45--0300.xcresult`.
- Existing 42 capture/annotation tests continue to pass. Nineteen new cloud tests cover HTTP query/permission contracts, bounded retries, revoked access, unsafe upload URLs, file-ID conflict reconciliation, journal persistence/account isolation/permissions/corruption, clipboard changes, late account-change completion, pagination, offline retry, missing OAuth config, sharing failure recovery, fractional timestamps, private-folder reuse across two complete stubbed uploads, and orphan cleanup.
- Native signed-out history view rendered offscreen and visually inspected. Preview: `.build/history-preview.png`. This is local UI rendering, not a browser sign-in or a real Drive gallery result.
- Initial Swift actor callback warnings were corrected by explicitly returning Google callbacks to MainActor. No app source warnings remain in the final compile; Xcode emitted its usual no-AppIntents metadata notice and unrelated desktop-service messages during the unhosted test process.
- Tests do not call real OAuth, mutate Keychain/Drive, or write to the real clipboard. Cloud transport, storage, and clipboard operations are isolated/injected.

## OAuth configuration follow-up

- Configured the user-supplied client ID and reversed URL scheme locally; updated Debug/Release app and test bundle IDs, logging, upload storage namespace, and setup documentation to `cl.fplaz.snap`.
- Re-ran isolated unsigned tests after configuration: **61 passed, 0 failures** (`/tmp/snap-client-config-tests.log`). Verified the built app Info.plist contains the requested bundle ID, exact client ID, and matching callback scheme.
- Signed deployment and real-account testing remain pending provisioning authorization. Changing the bundle ID creates a new app identity for macOS Screen Recording permission.

## Signing and configuration history

- The user supplied a public OAuth client ID, now configured in the ignored `Configuration/Google.local.xcconfig` with its matching reversed callback scheme. App and test bundle identifiers now use `cl.fplaz.snap` and `cl.fplaz.snap.tests`; the Keychain group expands to `94K9S6W37W.cl.fplaz.snap`. Real sign-in remains unverified.
- With Google's required Keychain access group, Xcode reported that Snap requires a provisioning profile. No profiles were found in the standard Xcode or MobileDevice profile directories on this host.
- App build settings now use automatic Apple Development signing with the existing team, in preparation for an appropriate profile. A proposed `-allowProvisioningUpdates` build was rejected by automatic approval review because creating/updating Apple portal profiles was not explicitly authorized. No profile/account update was performed, and no workaround was used to bypass that rejection.
- Subsequent compile/tests intentionally omitted signing and used a separate validation product directory. These unsigned products have not been launched as the user's app.
- The existing signed capture bundle at `.build/xcode/Build/Products/Debug/Snap.app` still passes host `codesign --verify --deep --strict`. It has not been replaced or restarted with the cloud validation build.
- Setup and the specific remaining provisioning approval are documented in `docs/google-setup.md`.

## Review and remaining acceptance

Manual source review checked OAuth-token destination restrictions and rejected HTTP redirects, account/job identity across async boundaries, permission gating before link success, idempotent file creation, clipboard handling, capture cleanup, and retained-data behavior. No independent agent review or dedicated code-review skill receipt is claimed.

Remaining: launch the signed cloud build, real consent/cancellation/restore/refresh/sign-out, real upload and signed-out viewing link, folder privacy, real gallery/thumbnail behavior, quota/sharing-policy errors, same-app Screen Recording persistence, another capture during upload, and measured capture/overlay-release latency. Stubbed tests do not establish those real-service or desktop results.

No commit, push, Google Cloud resource creation, or real screenshot upload was performed in this pass.

## Authorized signing follow-up

- The user explicitly approved Apple provisioning updates. `xcodebuild -allowProvisioningUpdates build` succeeded; log: `/tmp/snap-signed-cloud-build.log`.
- Xcode selected `Mac Team Provisioning Profile: cl.fplaz.snap` on team `94K9S6W37W`. The signed app and decoded embedded profile authorize `94K9S6W37W.cl.fplaz.snap` and its Keychain group.
- Host `codesign --verify --deep --strict` passed. Built Info.plist values match the supplied client ID, callback scheme, and `cl.fplaz.snap`. A sandboxed entitlement inspection emitted an invalid-blob warning; host inspection confirmed the valid signed entitlements.
- The signed cloud app now occupies `.build/xcode/Build/Products/Debug/Snap.app`, replacing the previous capture build. It has not yet been launched or tested with a real Google account.

## Default-browser sign-in follow-up

- Replaced the interactive GoogleSignIn authentication session with public AppAuth 2.1.0 APIs and an external user agent opening the authorization URL through `NSWorkspace.shared.open`. This follows the configured macOS default browser without Apple's Safari fallback. The official Google button UI remains unchanged.
- Retained the configured iOS OAuth client, callback scheme, authorization-code/PKCE/random-state flow, limited Drive scope, refresh token handling, and GTMAppAuth 5.0.0 Keychain storage. The same `auth` item and archived format allow existing GoogleSignIn credentials to be restored.
- Added Cancel Sign In and a ten-minute timeout for abandoned browser flows; generation checks reject late completion after cancellation. A failed Keychain deletion keeps the visible account instead of pretending sign-out succeeded.
- **68 isolated tests passed, 0 failures** (`/tmp/snap-default-browser-tests.log`). Seven added tests cover PKCE/state and scope, browser opening/failure, restoring and saving an existing GTMAppAuth session, missing Drive scope, failed credential removal, canceled/late completion, successful sign-in persistence, and wrong-state rejection before any token exchange. All account fixtures use an in-memory credential store and fake authorization responses; no browser or real Google/Keychain mutation occurs in tests.
- Xcode's Swift compiler crashed when lowering AppAuth's optional NSError callback-resume method. The required callback method remains in AppAuth 2.1 and performs the same state validation; it emits a deprecation warning.
- Final signed build succeeded (`/tmp/snap-default-browser-signed-build.log`) and host `codesign --verify --deep --strict` passed. Bundle identity, configured Google client, embedded profile, and app icon were checked.
- Real default-browser consent, callback, token refresh, and restoration remain to be tested manually.

## Upload panel follow-up — 2026-10-04

- After the capture overlays close and upload begins, a nonactivating floating panel appears at the top right of the screen containing the mouse. It respects the screen's visible frame, including screens with negative origins.
- Uploading/sharing shows a native indeterminate loading bar and a disabled Copy Link button. The client does not provide byte progress, so no percentage is fabricated. A verified public viewing link enables Copy Link and shows Close; explicit copying dismisses the panel. Existing clipboard protection/automatic copying remains unchanged.
- Failures show the error and Review Upload, which opens the existing history/retry workflow. Account changes dismiss the panel. Capture start temporarily hides it; capture cleanup restores it only if it has not been dismissed.
- **70 isolated tests passed, 0 failures** (`/tmp/snap-upload-panel-tests.log`). Added coverage exercises the start event, prevents copying before completion, renders loading and ready states, verifies explicit copying after a clipboard change, and checks top-right placement on a screen with a negative origin.
- Loading and completed states rendered offscreen and visually inspected: `/tmp/snap-upload-panel-loading.png` and `/tmp/snap-upload-panel-ready.png`. These are stubbed local previews. Real upload timing, floating-window behavior, and screenshot exclusion await manual desktop verification.
- Final signed build succeeded (`/tmp/snap-upload-panel-signed-build.log`); host `codesign --verify --deep --strict` passed.

## First-use permission follow-up — 2026-10-04

- An initial screenshot/permissions request checks `CGPreflightScreenCaptureAccess`, records that Snap has requested access, and invokes only `CGRequestScreenCaptureAccess`. A false result does not automatically open Settings or display a second Snap dialog.
- Subsequent attempts without access show Snap’s recovery help with Open System Settings and Not Now. Granted access bypasses both prompts. The permissions menu retains its already-enabled message.
- Returning to Snap rebuilds the status menu and refreshes its permission check/tooltip. No screenshot is automatically taken when returning from Settings.
- **73 isolated tests passed, 0 failures** (`/tmp/snap-permission-onboarding-tests.log`). Added tests verify native-only first request, persisted request history versus actual grants, recovery help on later attempts, prompt-free authorized capture, and rechecking after requests/help. Checks and UI callbacks are injected; no real permission changes, native dialogs, or Settings launches occur in tests.
- A real first-install/native-dialog/list-refresh acceptance run remains pending. Existing user permissions were not reset.
- Signed build succeeded (`/tmp/snap-permission-onboarding-build.log`) and host signature verification passed.

## Removed-permission recovery follow-up — 2026-10-04

- Supersedes the one-time request flow above: no saved request-history flag gates native requests. Missing access shows Snap's modal with Allow Screen Recording, Not Now, and a separate Open System Settings fallback.
- Allow closes Snap's modal and calls `CGRequestScreenCaptureAccess` on every confirmed attempt. Its false result never automatically launches Settings. macOS determines whether to display a native dialog; requesting access does not guarantee it will reappear in the same running process.
- **74 isolated tests passed, 0 failures** (`/tmp/snap-permission-recovery-tests.log`). Coverage verifies repeated confirmed requests, prompt-free granted access, fresh checks after access removal/request, and cancellation without native requests. Actual Screen Recording permissions were not modified.
- Removed-entry/native-dialog reappearance requires manual verification with the new running build; a restart may be needed if macOS retains the current process's permission state.

## Permission state investigation — 2026-10-04

- Confirmed that every idle screenshot attempt checks CoreGraphics and each capture enumerates fresh ScreenCaptureKit content. Snap does not cache authorization or shareable content. Only one Snap process was running; its build was signed with the expected Apple Development identity and bundle ID.
- Read-only TCC logs show a permission modification at 22:40:45, a reopened Snap process receiving a non-granted result at 22:40:50, and another process receiving granted authorization at 22:41:09. The modification event does not disclose its new value, so these logs alone do not establish why the extra restart was necessary. Later deletion events and a refused native prompt also appear.
- Removed the permission query during menu construction. Permission checks remain on screenshot attempts and explicit permissions-menu clicks. This avoids an unnecessary launch-time query; it is not a proven fix for stale authorization.
- Added public, narrowly scoped diagnostic logs for preflight results with PID, native request return values, and capture error domain/code plus the contemporaneous preflight result. No screenshot contents, account data, or URLs are logged.
- Signed build succeeded (`/tmp/snap-permission-diagnostics-build.log`). No new automated tests were run for these diagnostic changes. A manual grant/reopen/revoke reproduction with the rebuilt app is still required; no permissions were reset during this investigation.

## Extra restart cause identified — 2026-10-05

- The reproduction logs establish that the first reopen launched a different app bundle: PID 8998 ran `.build/cloud-validation-products/Snap.app`, while the initial request (PID 8778) and successful manual reopen (PID 9349) ran `.build/xcode/Build/Products/Debug/Snap.app`. The signed build's preflight returned true on the successful attempt.
- The validation copy advertised the same `cl.fplaz.snap` Info.plist bundle ID, but `codesign -dv` showed linker ad-hoc signing, identifier `Snap`, no bound Info.plist, and no Team ID. It was an obsolete unsigned test-build product, not the signed app that received access.
- Unregistered the validation app with Launch Services, removed only that generated Snap.app, and explicitly registered the signed app. No TCC records or user permission settings were modified.
- Set the app scheme's `buildForTesting` to `NO`: the unhosted test target already compiles the app sources and has no app-target dependency. Updated the validation command to use separate DerivedData, avoiding both duplicate app creation and interference with signed build products.
- The earlier process retained a true preflight after the permission entry was deleted. That separate live-revocation behavior remains an OS-state investigation; the wrong-bundle fix addresses the extra restart after granting permission.
- The revised validation run passed **74 tests, 0 failures** (`/tmp/snap-test-bundle-isolation.log`), created no competing Snap.app, and retained the signed app with a valid signature. The native Quit & Reopen flow needs one manual retest after cleanup.

## Revoked-permission capture recovery — 2026-10-05

- After cleanup, the user confirmed the first grant / native reopen flow works. When permission is subsequently revoked, CoreGraphics may still report true, but ScreenCaptureKit fails with its `userDeclined` error.
- Capture cleanup now routes that specific error domain/code to the existing Allow Screen Recording dialog, overriding the preliminary granted result. Other capture errors retain their normal error dialog; cancellation remains silent. Recovery does not automatically retry capture or open Settings.
- Added regressions for error-domain/code classification, recovery despite a stale true preflight, and Not Now preventing a native request. **76 tests passed, 0 failures** (`/tmp/snap-permission-denied-tests.log`); signed build succeeded (`/tmp/snap-permission-denied-build.log`). No competing validation app was created. Manual revocation/recovery verification remains pending.

## Account and upload review fixes — 2026-10-05

- Sign-out accepts both GTMAppAuth missing-password codes, matching the library's NSError domain and code so the Objective-C protocol bridge is supported. Other deletion failures still keep the visible account and show an error.
- Automatic and explicit link copying preserve pending-upload status, including local cleanup warnings. Successful link delivery remains available, while My Screenshots explains how to discard the unresolved local copy.
- A `CloudError.sharingFailed` uses its complete message directly; other sharing-stage errors retain the uploaded/sharing-failed context.
- Disabled upload hints distinguish signed-out, unavailable storage, work/staging in progress, and unresolved pending uploads.
- Export failure resumes the ready/editing state before suppressing `CancellationError` alerts. Real export failures continue to show their alert.
- **81 tests passed, 0 failures** (`/tmp/snap-review-fixes-tests.log`). Added coverage for already-removed credentials, a real temporary-filesystem cleanup failure plus both link-copy paths and recovery, sharing wording, storage/staging/pending hints, and account-change cancellation during staging. The existing upload-panel test now also checks the working-state hint. The actual account-switch/capture-overlay alert flow remains manually unverified.
