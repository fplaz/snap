import AppKit
import CoreGraphics
import os

@MainActor
enum ScreenPermission {
    private static let logger = Logger(subsystem: "cl.fplaz.snap", category: "ScreenPermission")

    static var hasAccess: Bool {
        let granted = CGPreflightScreenCaptureAccess()
        logger.notice("Screen capture preflight: granted=\(granted, privacy: .public), pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        return granted
    }

    static func ensureAccess(afterCaptureDenied: Bool = false,
                             check: @MainActor () -> Bool = { hasAccess },
                             request: @MainActor () -> Bool = {
                                 NSApp.activate(ignoringOtherApps: true)
                                 return CGRequestScreenCaptureAccess()
                             },
                             confirm: @MainActor () -> Bool = { confirmRequest() }) -> Bool {
        // A real capture denial overrides CoreGraphics' stale process-local preflight.
        if !afterCaptureDenied && check() { return true }
        guard confirm() else { return false }
        // Request every time the user chooses Allow; macOS owns prompt eligibility and Settings.
        let result = request()
        logger.notice("Screen capture request returned: granted=\(result, privacy: .public)")
        return check()
    }

    private static func confirmRequest() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = makeAlert()
        alert.messageText = "Let Snap capture your screen"
        alert.informativeText = "Snap needs Screen Recording access to capture the area you select. Click Allow Screen Recording, then follow the macOS dialog to enable Snap. If no system dialog appears, reopen Snap and try again."
        alert.addButton(withTitle: "Allow Screen Recording")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            alert.icon = icon
        }
        return alert
    }

}
