import AppKit

@main
@MainActor
enum SnapMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var capture: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = CaptureCoordinator()
        capture = coordinator
        statusBar = StatusBarController(capture: coordinator)
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.cancel()
    }
}
