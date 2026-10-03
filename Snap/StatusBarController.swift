import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let capture: CaptureCoordinator
    private var shortcut: GlobalShortcut?

    init(capture: CaptureCoordinator) {
        self.capture = capture
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snap")
            button.image?.isTemplate = true
            button.toolTip = "Snap — ⌘⇧7"
        }
        shortcut = GlobalShortcut { [weak capture] in capture?.start() }
        let menu = NSMenu()
        let title = NSMenuItem(title: "SNAP", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let take = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "7")
        take.keyEquivalentModifierMask = [.command, .shift]
        take.target = self
        menu.addItem(take)
        if shortcut?.registrationStatus != noErr {
            menu.addItem(NSMenuItem(title: "⌘⇧7 unavailable — use Take Screenshot", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let permission = NSMenuItem(title: "Screen Recording Permission…", action: #selector(permissionHelp), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snap", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func takeScreenshot() {
        // Let the status menu close before capturing the desktop.
        DispatchQueue.main.async { [weak self] in self?.capture.start() }
    }

    @objc private func permissionHelp() { ScreenPermission.showHelp() }
    @objc private func quit() { NSApp.terminate(nil) }
}
