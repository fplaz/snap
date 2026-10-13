import AppKit
import Sparkle

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
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var account: AccountController?
    private var uploads: UploadCoordinator?
    private var history: ScreenshotHistoryController?
    private var historyWindow: ScreenshotHistoryWindow?
    private var uploadPanel: UploadProgressPanel?
    private var statusBar: StatusBarController?
    private var capture: CaptureCoordinator?
    private var tutorial: TutorialWindow?
    private var updater: SPUStandardUpdaterController?

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
        let tutorial = TutorialWindow()
        self.tutorial = tutorial
        coordinator.onCaptureStarted = { [weak uploadPanel, weak tutorial] in
            tutorial?.hide()
            uploadPanel?.captureStarted()
        }
        coordinator.onCaptureEnded = { [weak uploadPanel] in uploadPanel?.captureEnded() }
        capture = coordinator
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.updater = updater
        // Unconfigured developer builds keep local capture available without contacting a feed.
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: feed), url.scheme == "https", url.host != nil,
           let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           Data(base64Encoded: key)?.count == 32 {
            updater.startUpdater()
        }
        statusBar = StatusBarController(capture: coordinator, account: account, uploads: uploads,
                                        historyWindow: historyWindow, tutorial: tutorial, updater: updater)
        NSAppleEventManager.shared().setEventHandler(account, andSelector: #selector(AccountController.handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        account.restore()
        tutorial.showOnFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.cancel()
        uploads?.stop()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard capture?.isActive == true || uploads?.isWorking == true else { return false }
        // Finish the user's capture or upload before Sparkle quits and replaces Snap.
        Task { @MainActor [weak self] in
            while let self, self.capture?.isActive == true || self.uploads?.isWorking == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            installHandler()
        }
        return true
    }
}
