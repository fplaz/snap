# Releasing Snap updates

Snap uses Sparkle 2.10.0. While Snap is running, Sparkle checks the HTTPS feed approximately daily. Users can check immediately with **Snap → Check for Updates…**. Updates show release notes and require user-approved installation. Snap delays an update restart while a capture or upload is active. Offline checks leave the installed app available.

## Hosting

The feed is `https://fplaz.github.io/snap/appcast.xml`, served by GitHub Pages. Each published stable GitHub release must include both `SNAP.dmg` and `appcast.xml`. The **Publish update feed** workflow downloads the latest stable release's signed feed and deploys it unchanged to Pages. GitHub serves these as static files; no application server or client registration is needed. Drafts and prereleases do not become the latest stable release.

To use another static HTTPS host, change `SNAP_UPDATE_FEED_URL` in `Configuration/Updates.xcconfig` **before distributing the app**. The `https:/$()/` syntax is intentional: it prevents xcconfig from interpreting `//` as a comment. Keep the feed URL stable across releases. Changing it later requires publishing a transition update at the old URL.

## Signing

The app and all embedded Sparkle helpers use the retained **Snap Local Distribution** certificate. The self-signed app disables library validation because its code has no Apple team ID. This does not provide Developer ID trust or notarization: users still need to approve the initial download through macOS Privacy & Security.

Packaging signs four Sparkle helpers, the Sparkle framework, and Snap itself. macOS may request Keychain access repeatedly when only one-time access is granted, including for each architecture in a universal build. Selecting **Always Allow** in the dialog for `/usr/bin/codesign` and this specific private key retains permission for future signing. Enter your password only in the macOS dialog. The build has no signing retry loop and excludes symlinks from helper discovery.

Sparkle uses a separate Ed25519 private key stored in the login Keychain under account `cl.fplaz.snap`. The public key is committed in `Configuration/Updates.xcconfig`. Both update archives and the feed are signed, and Snap verifies archives before extraction.

On the release Mac, set up or reuse the key:

```sh
bash scripts/setup-update-signing.sh
```

If this prints a different public key than the committed configuration, restore the original private key from your secure backup. Do not replace the public key in an already distributed app. Preserve and securely back up both the Sparkle private key and the local code-signing certificate/private key. Never upload private keys to GitHub or place them in the repository.

## Prepare a release

1. Increment both `CFBundleShortVersionString` and `CFBundleVersion` in `Snap/Info.plist`. Build numbers must increase, including when only fixing packaging. Use a new version for changed release bytes.
2. Write release notes in an HTML fragment, for example `<ul><li>Improved capture controls.</li></ul>`.
3. Build the DMG and generate the signed feed. For version 1.5:

```sh
bash scripts/build-dmg.sh
bash scripts/generate-appcast.sh \
  https://github.com/fplaz/snap/releases/download/v1.5/ \
  /path/to/release-notes.html
```

The download prefix must match the release tag, including its `v` prefix. Tools are resolved from the pinned Sparkle package. Preparation fails if the packaged public key differs from the Keychain key. Release notes are embedded in the signed feed, so there is no separate notes file to host. Full archives are used; delta updates are disabled for this initial integration.

Upload-ready files are in `.build/distribution/publish/1.5/`: `SNAP.dmg` and `appcast.xml`. Keep `.build/distribution/updates/` between releases: it retains versioned local archives and feed history. Only the current build's download URL changes to the fixed asset name; older entries keep their original URLs. The feed is re-signed after setting that URL. Do not edit signed XML after generation.

Use `https://github.com/fplaz/snap/releases/latest/download/SNAP.dmg` on your website. Appcast entries use immutable release URLs such as `https://github.com/fplaz/snap/releases/download/v1.5/SNAP.dmg`, so each download matches the advertised version and signature. Never use the latest-release redirect in the feed. Each GitHub release needs only one DMG.

## Publish

In repository **Settings → Pages**, select **GitHub Actions** as the publishing source. Commit the workflow and updater changes before publishing the first release.

The `github-pages` environment must also permit version **tags** matching `v*` for the release event to deploy. Its default `main` branch rule permits manual workflow runs from main but blocks release-tag runs. Changing this deployment permission requires the repository owner's approval.

Create a GitHub release tagged `v1.5`, attach `SNAP.dmg` and `appcast.xml` from the publish directory, and publish it as the latest stable release. Prepare uploads in a draft so the feed cannot advertise an unavailable download. The release event runs **Publish update feed**, deploying `appcast.xml` to GitHub Pages. The workflow can also be run manually to redeploy the latest stable release; it never deploys an older release selected by an event. Keep old release assets available because existing feed entries point to them.

Confirm the workflow succeeds and the Pages feed returns the exact signed bytes before announcing the release. Pages caching can delay availability of a changed feed.

For other hosting, upload the new DMG first, then replace the feed at the configured URL. Serve the feed with a short cache lifetime.

Existing Snap 1.2 and earlier users must manually install 1.3 once. They can receive subsequent updates through Sparkle.

## Verify before publishing

- Install a real older updater-enabled release in Applications on a second Mac. Confirm the feed URL returns signed XML and all listed download URLs work without authentication.
- Publish a newer test version to a separate test feed and confirm the update notice, release notes, successful installation, restart, and **Check for Updates…** behavior. The main stable feed must not advertise test releases.
- Check Screen Recording access and Google sign-in after the update. Capture and upload during installation to confirm restart waits for completion.
- Check an offline launch and a bad download signature. The installed app should remain usable and the bad update should be rejected.

Local compilation, code-signature verification, and feed-signature verification do not establish Gatekeeper or permission continuity on another Mac.
