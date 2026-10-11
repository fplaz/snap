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
    private var account: AccountController?
    private var uploads: UploadCoordinator?
    private var history: ScreenshotHistoryController?
    private var historyWindow: ScreenshotHistoryWindow?
    private var uploadPanel: UploadProgressPanel?
    private var statusBar: StatusBarController?
    private var capture: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let account = AccountController()
        let drive = DriveClient(token: { [weak account] accountID in
            guard let account else { throw CloudError.signedOut }
            return try await account.accessToken(account: accountID)
        })
        let uploads = UploadCoordinator(drive: drive, accountID: { [weak account] in account?.id }, store: try? UploadStore())
        let history = ScreenshotHistoryController(drive: drive, accountID: { [weak account] in account?.id })
        let historyWindow = ScreenshotHistoryWindow(account: account, uploads: uploads, history: history)
        let uploadPanel = UploadProgressPanel(uploads: uploads, reviewUpload: { [weak historyWindow] in historyWindow?.show() })
        self.uploadPanel = uploadPanel
        uploads.onStarted = { [weak uploadPanel, weak historyWindow] in
            historyWindow?.hide()
            uploadPanel?.show()
        }
        account.onChanged = { [weak account, weak uploads, weak history, weak uploadPanel] in
            uploadPanel?.close()
            uploads?.accountChanged(); history?.accountChanged()
            if account?.id != nil { history?.refresh() }
        }
        uploads.onUploaded = { [weak history] in history?.refresh() }
        self.account = account; self.uploads = uploads; self.history = history; self.historyWindow = historyWindow
        let coordinator = CaptureCoordinator(uploads: uploads)
        coordinator.onCaptureStarted = { [weak uploadPanel] in uploadPanel?.captureStarted() }
        coordinator.onCaptureEnded = { [weak uploadPanel] in uploadPanel?.captureEnded() }
        capture = coordinator
        statusBar = StatusBarController(capture: coordinator, account: account, uploads: uploads, historyWindow: historyWindow)
        NSAppleEventManager.shared().setEventHandler(account, andSelector: #selector(AccountController.handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        account.restore()
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.cancel()
        uploads?.stop()
    }
}
