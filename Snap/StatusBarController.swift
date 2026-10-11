import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let capture: CaptureCoordinator
    private let account: AccountController
    private let uploads: UploadCoordinator
    private let historyWindow: ScreenshotHistoryWindow
    private var observers: [AnyCancellable] = []
    private var shortcut: GlobalShortcut?

    init(capture: CaptureCoordinator, account: AccountController, uploads: UploadCoordinator, historyWindow: ScreenshotHistoryWindow) {
        self.capture = capture; self.account = account; self.uploads = uploads; self.historyWindow = historyWindow
        super.init()
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imageScaling = .scaleNone
            button.toolTip = "Snap — ⌘⇧7"
        }
        shortcut = GlobalShortcut { [weak capture] in capture?.start() }
        for publisher in [account.objectWillChange, uploads.objectWillChange] {
            observers.append(publisher.sink { [weak self] in DispatchQueue.main.async { self?.rebuildMenu() } })
        }
        observers.append(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildMenu() } })
        rebuildMenu()
    }

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for corner in [CGPoint(x: 2, y: 2), CGPoint(x: 16, y: 2),
                           CGPoint(x: 2, y: 16), CGPoint(x: 16, y: 16)] {
                let dx: CGFloat = corner.x < 9 ? 4 : -4
                let dy: CGFloat = corner.y < 9 ? 4 : -4
                path.move(to: CGPoint(x: corner.x + dx, y: corner.y))
                path.line(to: corner)
                path.line(to: CGPoint(x: corner.x, y: corner.y + dy))
            }
            path.stroke()
            let letter = "S" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.black
            ]
            let size = letter.size(withAttributes: attributes)
            letter.draw(at: CGPoint(x: (18 - size.width) / 2, y: (18 - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snap"
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "SNAP", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        if account.id != nil {
            if let email = account.email {
                let identity = NSMenuItem(title: "Signed in as \(email)", action: nil, keyEquivalent: "")
                identity.isEnabled = false
                menu.addItem(identity)
            }
            let signOut = NSMenuItem(title: "Sign out", action: #selector(signOut), keyEquivalent: "")
            signOut.target = self; signOut.isEnabled = !account.isSigningIn
            menu.addItem(signOut)
        } else {
            let signIn = NSMenuItem(title: "Sign in with Google…", action: #selector(showHistory), keyEquivalent: "")
            signIn.target = self
            menu.addItem(signIn)
        }
        menu.addItem(.separator())
        let take = NSMenuItem(title: "Take screenshot", action: #selector(takeScreenshot), keyEquivalent: "7")
        take.keyEquivalentModifierMask = [.command, .shift]
        take.target = self
        if shortcut?.registrationStatus != noErr {
            take.toolTip = "⌘⇧7 unavailable — use this menu item"
        }
        menu.addItem(take)
        let history = NSMenuItem(title: "My screenshots", action: #selector(showHistory), keyEquivalent: "")
        history.target = self; history.isEnabled = account.id != nil
        menu.addItem(history)
        let link = NSMenuItem(title: "Copy latest link", action: #selector(copyLink), keyEquivalent: "")
        link.target = self; link.isEnabled = uploads.latestLink != nil
        menu.addItem(link)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snap", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func takeScreenshot() {
        // Let the status menu close before capturing the desktop.
        DispatchQueue.main.async { [weak self] in self?.capture.start() }
    }

    @objc private func showHistory() {
        capture.cancel()
        DispatchQueue.main.async { [weak self] in self?.historyWindow.show() }
    }
    @objc private func signOut() { account.signOut() }
    @objc private func copyLink() { uploads.copyLatestLink() }
    @objc private func quit() { NSApp.terminate(nil) }
}
