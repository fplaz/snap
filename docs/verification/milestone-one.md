# Milestone 1 verification

This file records execution evidence, not planned completion.

The user accepted milestone 1 on 2026-10-01 after confirming the Retina resolution and window-shadow fixes. This is product acceptance of the tested desktop flow; the unmeasured timing targets and unavailable hardware/OS coverage below remain unverified.

## Environment

- Development host: Apple silicon Mac.
- Command Line Tools Swift: 6.4.
- Installed full Xcode: 27.0, build 27A266a.
- Xcode setup and license acceptance completed by the user; the checked-in project now builds and tests successfully.
- The app targets macOS 14 and later; older-version runtime coverage is not yet established.

## Automated checks

- App plist and Xcode project pass `plutil -lint`.
- All app Swift sources compile and link with Command Line Tools, `-swift-version 5`, and `-target arm64-apple-macosx14.0`.
- Development bundle assembled at `.build/xcode/Build/Products/Debug/Snap.app`; ad-hoc signature passes `codesign --verify --deep --strict`.
- Native XCTest bundle compiled with the installed XCTest framework and Swift overlay, then executed with Xcode's `MacOSX.platform/Developer/Library/Xcode/Agents/xctest`: **19 tests passed, 0 failures** (7 session, 7 geometry, 5 image/export).
- Shared `Snap` scheme: `xcodebuild build` passed for arm64 and x86_64. A subsequent arm64 build including local shortcut diagnostics also passed.
- Shared `Snap` scheme: `xcodebuild test` passed **19 tests, 0 failures** on arm64. The first sandboxed attempt could not access macOS's test service; the rerun with that access succeeded. Result bundle: `.build/xcode/Logs/Test/Test-Snap-2026.10.01_21-04-15--0300.xcresult`.
- A temporary SwiftPM harness was attempted but cannot locate XCTest through Command Line Tools; it was superseded by the successful native XCTest bundle execution.
- New-project behavior tests were authored with implementation. No red-before-implementation test result is claimed.

## Desktop checks

- Launched the development app through Finder. Snap-specific runtime logs confirm an agent application (`uiElement=1`) and a completed AppKit status-item scene registration.
- Restarted the rebuilt app; its local shortcut log reports Carbon registration status `0` (success) for the Command–Shift–7 shortcut. Registration alone does not establish successful real-key invocation.
- Native UI automation cannot reliably address this menu-bar-only app; Snap and SystemUIServer queries timed out. A synthetic ⌘⇧7 sent through Finder selected Finder's Help menu, so global shortcut behavior is **not verified** by that test. No permission was granted on the user's behalf.
- Pending real-user checks: visible menu bar icon, ⌘⇧7 invocation, preparation cancellation, rectangle selection, Copy, Save, save-panel cancellation, Escape, previous-app focus, Screen Recording permission, fullscreen presentation, and mixed-scale displays.
- Session and geometry unit tests do not establish window/buffer cleanup across 30 real desktop captures.

### Permission regression after rebuild

- User reported successful real capture before the last rebuild, followed by repeated permission prompts despite an enabled Screen Recording entry.
- On 2026-10-01, `tccd` repeatedly logged `Failed to match existing code requirement for subject cl.assetplan.snap and service kTCCServiceScreenCapture`. The stored requirement used cdhash `88d0915a10ed5b71fa2e6b7eba96c98a69d0e679`; the rebuilt app's designated requirement used different cdhashes. `codesign -d -r-` confirmed the current hash-based requirement.
- Root cause: the project's ad-hoc signature changes with the binary, invalidating the saved permission's code requirement. No evidence supports changing `ScreenPermission.ensureAccess()` to ignore the failed preflight.
- `security find-identity -v -p codesigning` found zero valid signing identities. Stable Apple Development signing cannot be completed until the user sets up a certificate/team in Xcode. README now documents that setup, command-line signing overrides, and a scoped stale-entry recovery.
- No permission reset, certificate creation, or permission grant was performed by the agent. Recovery and persistence across signed rebuilds remain unverified.
- Follow-up: the user created an Apple Development identity for team `94K9S6W37W`. Installed Apple's G3 intermediate from its official PKI endpoint after successful verification against the existing Apple root; `security find-identity -v -p codesigning` then reported one valid identity. Both app build configurations now select Apple Development and that team; the test bundle retains ad-hoc signing.
- After the user approved signing-key access, the universal Debug build completed successfully. `codesign --verify --deep --strict` passed for the app and nested libraries. The designated requirement now uses the app identifier, Apple's signing anchor, and the Apple Development certificate rather than executable cdhashes; TeamIdentifier is `94K9S6W37W`.
- Restarted Snap from the same development bundle location with the signed build. A one-time Screen Recording reauthorization may still be needed when changing from the previous ad-hoc identity. Permission persistence across future signed rebuilds remains a real-user verification item.

## Frozen-image quality correction

- The user reported fuzzy fonts and missing subtle UI details/shadows in the frozen overlay.
- Display metadata reproduced the resolution mismatch: NSScreen logical size 1710×1112, backing scale 2, CoreGraphics display width/height 1710×1112, but display mode rendering size 3420×2224. The original capture requested the smaller dimensions and stretched them across the Retina overlay.
- Capture configuration now derives output dimensions from `SCContentFilter.contentRect` multiplied by `pointPixelScale`, requests `.best` source resolution, and explicitly retains window shadows. Export continues to crop the original captured image.
- Added two capture-configuration tests. Before the fix, the Retina case failed on both dimensions and source resolution; after the fix, the complete shared scheme passed **21 tests, 0 failures**. Result bundle: `.build/xcode/Logs/Test/Test-Snap-2026.10.01_21-35-05--0300.xcresult`.
- Visual comparison on the user's desktop is pending. This establishes the resolution defect and its correction, not exact visual equality for every display/color configuration.
- User confirmed resolution is now good, but shadows remain missing. Runtime defaults on this host report `ignoreShadowsDisplay=false` and `ignoreShadowsSingleWindow=true`. Capture now explicitly disables both shadow-exclusion flags. The strengthened configuration assertion failed before this change; the full 21-test suite passed afterward (`Test-Snap-2026.10.01_21-39-37--0300.xcresult`). Whether the single-window flag affects this display screenshot path still requires visual confirmation; a passing configuration test does not establish that shadows are present in the returned image.

## Speed

The plan's proposed budgets are warm invocation-to-visible-overlay p95 ≤300 ms and release-to-visible-toolbar p95 ≤50 ms over 30 single-display invocations. No measured visual latency result is available yet.

The two local signpost intervals end at UI scheduling. Use Instruments plus visual observation to establish rendering latency; do not label scheduling timings as displayed-frame timings.

## Review

- Applied an inline simplification/quality pass using the skill's reuse, code-quality, and efficiency lenses; no additional behavior-preserving simplification was justified.
- Inline correctness review corrected programmatic app startup (explicit delegate lifetime) and scoped the temporary Escape hotkey to preparation so save-dialog cancellation follows the normal responder chain.
- Code review: skipped (ce-code-review unavailable). The dedicated workflow cannot resolve a comparison base in this new repository with no commits, and its untracked-file policy excludes these new sources. Manual source review was performed; no independent or completed dedicated-review receipt is claimed.
- No commit, push, or PR was created. Source and documentation remain in the local feature branch.
