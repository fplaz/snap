import AppKit
import Combine
import ImageIO

@MainActor
final class ScreenshotHistoryController: ObservableObject {
    @Published private(set) var files: [DriveFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var nextPage: String?
    @Published private(set) var actionID: String?
    private let thumbnailSession = URLSession(configuration: .ephemeral)
    private let drive: DriveClient
    private let accountID: () -> String?
    private var generation = UUID()
    private var loadingTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailFailures: Set<String> = []
    private var thumbnailQueue: [String] = []
    private var cacheOrder: [String] = []

    init(drive: DriveClient, accountID: @escaping () -> String?) {
        self.drive = drive; self.accountID = accountID
    }

    func accountChanged() {
        generation = UUID(); loadingTask?.cancel(); actionTask?.cancel()
        thumbnailTasks.values.forEach { $0.cancel() }; thumbnailTasks.removeAll()
        thumbnailQueue.removeAll(); thumbnailFailures.removeAll(); cacheOrder.removeAll()
        files = []; thumbnails = [:]; nextPage = nil; message = nil; isLoading = false; actionID = nil
    }

    func refresh() {
        guard accountID() != nil else { return }
        accountChanged(); loadMore()
    }

    func loadMore() {
        guard let account = accountID(), !isLoading, files.isEmpty || nextPage != nil else { return }
        let run = generation; let page = nextPage
        isLoading = true; message = nil
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.drive.history(account: account, page: page)
                guard self.generation == run, self.accountID() == account, !Task.isCancelled else { return }
                let known = Set(self.files.map(\.id))
                self.files.append(contentsOf: result.files.filter { !known.contains($0.id) })
                self.nextPage = result.nextPageToken; self.isLoading = false; self.loadingTask = nil
            } catch {
                guard self.generation == run, self.accountID() == account else { return }
                self.message = error.localizedDescription; self.isLoading = false; self.loadingTask = nil
            }
        }
    }

    func copyLink(_ file: DriveFile, retrySharing: Bool = false) {
        guard let account = accountID(), actionID == nil else { return }
        let run = generation; actionID = file.id; message = nil
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let current: DriveFile?
                if retrySharing { current = try await self.drive.share(file.id, account: account) }
                else { current = try await self.drive.file(file.id, account: account) }
                guard self.generation == run, self.accountID() == account, !Task.isCancelled else { return }
                guard let current, current.trashed != true else { self.message = "This screenshot is no longer available in Drive."; self.actionID = nil; return }
                if let index = self.files.firstIndex(where: { $0.id == current.id }) { self.files[index] = current }
                guard current.isPublic, let link = current.viewingURL else {
                    self.message = "This screenshot is not shared publicly. Choose Retry Sharing to make its link viewable."; self.actionID = nil; return
                }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.absoluteString, forType: .string)
                self.message = "Link copied"; self.actionID = nil
            } catch {
                guard self.generation == run, self.accountID() == account else { return }
                self.message = error.localizedDescription; self.actionID = nil
            }
        }
    }

    func requestThumbnail(_ id: String) {
        guard thumbnails[id] == nil, thumbnailTasks[id] == nil, !thumbnailFailures.contains(id), !thumbnailQueue.contains(id) else { return }
        thumbnailQueue.append(id); pumpThumbnails()
    }

    private func pumpThumbnails() {
        while thumbnailTasks.count < 4, !thumbnailQueue.isEmpty {
            let id = thumbnailQueue.removeFirst()
            guard let file = files.first(where: { $0.id == id }), let account = accountID() else { continue }
            let run = generation
            thumbnailTasks[id] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == run { self.thumbnailTasks[id] = nil; self.pumpThumbnails() }
                }
                do {
                    // Refresh metadata so an hours-old thumbnail URL is never treated as durable.
                    let fresh = try await self.drive.file(file.id, account: account)
                    guard self.generation == run, self.accountID() == account, !Task.isCancelled else { return }
                    guard let link = fresh?.thumbnailLink, let url = URL(string: link), Self.validThumbnailURL(url) else {
                        self.thumbnailFailures.insert(id); return
                    }
                    // Public screenshots need no bearer token on Google's thumbnail host.
                    // Private/failed-sharing items intentionally use a placeholder.
                    guard fresh?.isPublic == true else { self.thumbnailFailures.insert(id); return }
                    var request = URLRequest(url: url); request.timeoutInterval = 20
                    let (data, response) = try await self.thumbnailSession.data(for: request)
                    guard self.generation == run, self.accountID() == account, !Task.isCancelled else { return }
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8_000_000,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0,
                              [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) else {
                        self.thumbnailFailures.insert(id); return
                    }
                    self.thumbnails[id] = NSImage(cgImage: thumbnail, size: .zero); self.cacheOrder.append(id)
                    if self.cacheOrder.count > 80 { self.thumbnails[self.cacheOrder.removeFirst()] = nil }
                } catch {
                    if self.generation == run { self.thumbnailFailures.insert(id) }
                }
            }
        }
    }

    static func validThumbnailURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return host == "drive.google.com" || host == "lh3.googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
    }
}
