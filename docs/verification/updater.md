# Updater validation — 2026-10-12

## Confirmed locally

- Sparkle 2.10.0 resolves and is pinned in Package.resolved.
- The isolated XCTest run passed 101 tests with no failures.
- The complete Release app compiled for arm64 and x86_64.
- The Snap 1.3 / build 11 DMG passed hdiutil checksum verification and strict nested code-signature verification.
- The packaged app contains `https://fplaz.github.io/snap/appcast.xml`, the configured 32-byte public key, daily automatic checks, user-approved installation, signed-feed verification, and verification before archive extraction.
- The release feed contains version 1.3 / build 11, the GitHub Release DMG URL, matching byte length, embedded notes, and signatures. Sparkle's signing utility verified the feed.
- Independent CryptoKit checks using the app's public key accepted the release feed and DMG. A changed test feed and a one-byte alteration of the DMG were rejected.
- Shell scripts passed syntax checks, workflow YAML parsed, and git diff whitespace checks passed.
- GitHub Pages is configured to use GitHub Actions with HTTPS enforced.

## Outstanding

- The Pages environment currently permits only main. Automatic release-tag deployment needs approval to add the `v*` tag rule; this mutation was rejected by automatic approval review and was not applied.
- Changes and workflow have not been committed or pushed, and release files have not been published. The public feed is not deployed.
- Actual update installation, restart timing during capture/upload, Gatekeeper approval, and Screen Recording / Google sign-in continuity on another Mac have not been tested.

The signing traversal excludes symlinks and signs four helpers, the framework, and Snap once each. Earlier signing attempts were stopped while waiting for Keychain access. The completed package reused the successfully signed helpers and finished framework/app signing without restarting those helper steps.
