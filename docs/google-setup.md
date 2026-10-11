# Google setup for Snap

Snap's cloud code is implemented, and this checkout has a configured Google OAuth client and signed development build. Real sign-in/upload testing remains pending. Local capture, Copy, and Save do not require a Google account.

## 1. Google Cloud

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select or create a project for Snap.
2. Enable **Google Drive API** in the API Library.
3. Configure the app under **Google Auth Platform** (or OAuth consent screen). Use the Snap application name and your contact email. Choose the audience appropriate to your accounts; use External if personal Google accounts will sign in. During development, add your account under test users when the app is in testing mode.
4. Configure the requested access: identity/profile plus `https://www.googleapis.com/auth/drive.file`. Snap only needs files it creates; do not add whole-Drive scopes.
5. Create an OAuth client with application type **iOS**, as Google's SDK requires for both iOS and macOS. Bundle ID: `cl.fplaz.snap`. If the console asks for the Apple team ID, use `94K9S6W37W` for this checkout's signing team. No backend/server client is needed.
6. Copy the public client ID and its reversed iOS URL scheme. You can send the client ID to Chad to configure the local build, or use the file below yourself. Do not send passwords, refresh tokens, or a client secret.

Google references: [macOS SDK setup](https://developers.google.com/identity/sign-in/ios/start-integrating), [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

## 2. Local build configuration

Copy `Configuration/Google.example.xcconfig` to `Configuration/Google.local.xcconfig` and replace its placeholders:

```xcconfig
GOOGLE_CLIENT_ID = YOUR_ACTUAL_CLIENT_ID.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.YOUR_ACTUAL_CLIENT_ID
```

The second value is the dot-separated components of the full client ID in reverse order. Prefer copying the URL scheme displayed by Google rather than manually transcribing it. The local file is ignored by Git. `Configuration/Snap.xcconfig` includes it if present and otherwise builds a clearly unconfigured Google state.

## 3. Signing and Keychain

GTMAppAuth uses the macOS data-protection Keychain for the AppAuth browser flow. `Snap/Snap.entitlements` declares the app's own Keychain access group. Both app configurations use automatic Apple Development signing with the existing team so Xcode can select a profile containing that entitlement.

Open `Snap.xcodeproj`, select the Snap target, and review Signing & Capabilities. The configured group expands to `94K9S6W37W.cl.fplaz.snap`. An eligible Apple developer account/profile is required. Do not remove the Keychain entitlement or switch to ad-hoc signing to make Google login appear to work; that would leave credential persistence unverified and could regress Screen Recording permission.

The user explicitly approved provisioning updates on 2026-10-03. Xcode successfully produced a signed build using **Mac Team Provisioning Profile: cl.fplaz.snap**. The host signature check passed, and the embedded profile and signed Keychain access group were verified. Real Google sign-in remains unverified.

To rebuild with the approved automatic provisioning configuration:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Snap.xcodeproj -scheme Snap -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode \
  -allowProvisioningUpdates build
```

The signed cloud build is now at `.build/xcode/Build/Products/Debug/Snap.app`. Unsigned compile/test products remain in `.build/cloud-validation-products`. The new signed build has not yet been launched; because its bundle identifier changed, macOS may require a new Screen Recording permission grant.

## 4. Real acceptance run

1. Launch the newly signed, configured build from the same stable app location.
2. Open Snap's menu → Sign in with Google. The Mac’s default browser opens. Complete the Google consent flow yourself and approve the requested Drive file access. Snap receives the registered URL callback, validates state, and exchanges the code using PKCE. Use Cancel Sign In in Snap if you abandon the browser tab.
3. Capture with Command–Shift–7, annotate, then Upload & Copy Link. The overlay closes after the composed PNG is staged; upload continues in the status menu.
4. Verify a private **Snap Screenshots** folder exists in My Drive and contains one annotated PNG. Open the copied file link in a signed-out browser; anyone with the link must be able to view the image. The folder must remain private.
5. Relaunch and verify account restoration and My Screenshots. Try sharing failure/retry on a test account where practical, and sign out/reconnect to verify account isolation.

A Google Workspace administrator can prohibit public sharing. Snap reports that as a sharing failure and will not copy a success link. Public release verification, privacy-policy hosting, and notarization are separate from these development checks.
