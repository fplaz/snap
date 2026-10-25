import AppKit
import Carbon
import Combine
import Sparkle

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let capture: CaptureCoordinator
    private let account: AccountController
    private let uploads: UploadCoordinator
    private let historyWindow: ScreenshotHistoryWindow
    private let tutorial: TutorialWindow
    private let settings: SettingsWindow
    private let updater: SPUStandardUpdaterController
    private var observers: [AnyCancellable] = []
    private var shortcut: GlobalShortcut?
    private var copyShortcut: GlobalShortcut?

    init(capture: CaptureCoordinator, account: AccountController, uploads: UploadCoordinator,
         historyWindow: ScreenshotHistoryWindow, tutorial: TutorialWindow, settings: SettingsWindow,
         updater: SPUStandardUpdaterController) {
        self.capture = capture; self.account = account; self.uploads = uploads; self.historyWindow = historyWindow
        self.tutorial = tutorial
        self.settings = settings
        self.updater = updater
        super.init()
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imageScaling = .scaleNone
            button.toolTip = "Snap — ⌘⇧7 annotate · ⌘⇧6 copy"
        }
        shortcut = GlobalShortcut { [weak capture] in capture?.start() }
        copyShortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_6), identifier: 3) { [weak capture] in
            capture?.start(mode: .copy)
        }
        for publisher in [account.objectWillChange, uploads.objectWillChange] {
            observers.append(publisher.sink { [weak self] in DispatchQueue.main.async { self?.rebuildMenu() } })
        }
        observers.append(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildMenu() } })
        observers.append(updater.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildMenu() } })
        rebuildMenu()
    }

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for corner in [CGPoint(x: 2, y: 2), CGPoint(x: 16, y: 2),
                           CGPoint(x: 2, y: 16), CGPoint(x: 16, y: 16)] {
                let dx: CGFloat = corner.x < 9 ? 4 : -4
                let dy: CGFloat = corner.y < 9 ? 4 : -4
                let radius: CGFloat = 1.5
                let horizontal = CGPoint(x: corner.x + (dx > 0 ? radius : -radius), y: corner.y)
                let vertical = CGPoint(x: corner.x, y: corner.y + (dy > 0 ? radius : -radius))
                path.move(to: CGPoint(x: corner.x + dx, y: corner.y))
                path.line(to: horizontal)
                path.curve(to: vertical,
                           controlPoint1: CGPoint(x: horizontal.x + (corner.x - horizontal.x) * 0.55228475,
                                                  y: corner.y),
                           controlPoint2: CGPoint(x: corner.x,
                                                  y: vertical.y + (corner.y - vertical.y) * 0.55228475))
                path.line(to: CGPoint(x: corner.x, y: corner.y + dy))
            }
            path.stroke()
            let letter = "S" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.black
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
        let take = NSMenuItem(title: "Take screenshot and annotate", action: #selector(takeScreenshot), keyEquivalent: "7")
        take.keyEquivalentModifierMask = [.command, .shift]
        take.target = self
        if shortcut?.registrationStatus != noErr {
            take.toolTip = "⌘⇧7 unavailable — use this menu item"
        }
        let copy = NSMenuItem(title: "Take screenshot and copy", action: #selector(takeScreenshotAndCopy), keyEquivalent: "6")
        copy.keyEquivalentModifierMask = [.command, .shift]
        copy.target = self
        if copyShortcut?.registrationStatus != noErr {
            copy.toolTip = "⌘⇧6 unavailable — use this menu item"
        }
        menu.addItem(copy)
        menu.addItem(take)
        menu.addItem(.separator())
        let history = NSMenuItem(title: "My screenshots", action: #selector(showHistory), keyEquivalent: "")
        history.target = self; history.isEnabled = account.id != nil
        menu.addItem(history)
        let link = NSMenuItem(title: "Copy latest link", action: #selector(copyLink), keyEquivalent: "")
        link.target = self; link.isEnabled = uploads.latestLink != nil
        menu.addItem(link)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Annotation tool settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let tutorial = NSMenuItem(title: "Tutorial…", action: #selector(showTutorial), keyEquivalent: "")
        tutorial.target = self
        menu.addItem(tutorial)
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = updater.updater.canCheckForUpdates
        menu.addItem(update)
        let coffee = NSMenuItem(title: "Buy me a coffee", action: #selector(buyMeACoffee), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)
        let quit = NSMenuItem(title: "Quit Snap", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func takeScreenshot() {
        // Let the status menu close before capturing the desktop.
        DispatchQueue.main.async { [weak self] in self?.capture.start() }
    }

    @objc private func takeScreenshotAndCopy() {
        DispatchQueue.main.async { [weak self] in self?.capture.start(mode: .copy) }
    }

    @objc private func showHistory() {
        capture.cancel()
        DispatchQueue.main.async { [weak self] in self?.historyWindow.show() }
    }
    @objc private func showTutorial() {
        capture.cancel()
        historyWindow.hide()
        DispatchQueue.main.async { [weak self] in self?.tutorial.show() }
    }
    @objc private func showSettings() {
        capture.cancel()
        historyWindow.hide()
        tutorial.hide()
        DispatchQueue.main.async { [weak self] in self?.settings.show() }
    }
    @objc private func signOut() { account.signOut() }
    @objc private func checkForUpdates() {
        capture.cancel()
        DispatchQueue.main.async { [weak self] in self?.updater.checkForUpdates(nil) }
    }
    @objc private func copyLink() { uploads.copyLatestLink() }
    @objc private func buyMeACoffee() {
        guard let url = URL(string: "https://buymeacoffee.com/fernandoplaz") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
