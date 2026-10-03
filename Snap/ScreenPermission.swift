import AppKit
import CoreGraphics

@MainActor
enum ScreenPermission {
    static func ensureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        showHelp(requestAccess: true)
        return CGPreflightScreenCaptureAccess()
    }

    static func showHelp(requestAccess: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Let Snap capture your screen"
        alert.informativeText = "Snap needs Screen Recording access to capture the area you select. Screenshots stay on your Mac unless you save or copy them. Enable Snap in System Settings, then reopen Snap if macOS asks."
        alert.addButton(withTitle: requestAccess ? "Allow Screen Recording" : "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if requestAccess, CGRequestScreenCaptureAccess() { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
