import AppKit
import Combine

@MainActor
final class UploadCoordinator: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var pending: PendingUpload?
    @Published private(set) var isWorking = false
    @Published private(set) var latestLink: URL?
    @Published private(set) var needsReplacementFolder = false
    private let store: UploadStore?
    private let drive: DriveClient
    private let accountID: () -> String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var staging = false
    private var clipboardAtStart: Int?
    private let readClipboardVersion: () -> Int
    private let writeLink: (URL) -> Void
    var onUploaded: (() -> Void)?
    var onStarted: (() -> Void)?

    init(drive: DriveClient, accountID: @escaping () -> String?, store: UploadStore?,
         readClipboardVersion: @escaping () -> Int = { NSPasteboard.general.changeCount },
         writeLink: @escaping (URL) -> Void = { url in
             NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
         }) {
        self.drive = drive; self.accountID = accountID; self.store = store
        self.readClipboardVersion = readClipboardVersion; self.writeLink = writeLink
        if store == nil { status = "Local upload storage is unavailable. Local Copy and Save still work." }
    }

    var canUpload: Bool { store != nil && accountID() != nil && pending == nil && !isWorking && !staging }
    var uploadHint: String {
        if accountID() == nil { return "Sign in from the Snap menu to upload" }
        if store == nil { return "Local upload storage is unavailable. Local Copy and Save still work." }
        if isWorking || staging { return "An upload is in progress. Please wait." }
        if pending != nil { return "Resolve the pending upload in My Screenshots" }
        return "Upload & Copy Link — anyone with the link can view"
    }

    func accountChanged() {
        generation = UUID(); task?.cancel(); task = nil
        isWorking = false; latestLink = nil; clipboardAtStart = nil; needsReplacementFolder = false
        pending = accountID().flatMap { store?.pending(account: $0) }
        status = pending == nil ? (store == nil ? "Local upload storage is unavailable." : "") : "Interrupted upload — Retry in My Screenshots"
    }

    // The capture owns composition; this handoff persists only its finished crop.
    func stage(_ png: Data) async throws -> PendingUpload {
        guard let account = accountID() else { throw CloudError.signedOut }
        guard canUpload, let store else { throw CloudError.busy }
        staging = true
        defer { staging = false; objectWillChange.send() }
        let version = readClipboardVersion()
        let job = try await store.stage(png: png, account: account)
        guard accountID() == account, !Task.isCancelled else {
            // No network request has begun; safe to remove this staged local image.
            try store.discard(job)
            throw CancellationError()
        }
        pending = job; clipboardAtStart = version
        return job
    }

    func begin(_ job: PendingUpload) {
        guard !isWorking, accountID() == job.accountID, pending?.id == job.id else { return }
        launch(job)
    }

    func retry() {
        guard let pending, !isWorking, accountID() == pending.accountID else { return }
        clipboardAtStart = readClipboardVersion()
        launch(pending)
    }

    func replaceFolderAndRetry() {
        guard let account = accountID(), needsReplacementFolder, !isWorking else { return }
        do {
            try store?.setFolder(nil, account: account)
            needsReplacementFolder = false
            retry()
        } catch { status = error.localizedDescription }
    }

    func discardLocal() {
        guard let pending, let store else { return }
        generation = UUID(); task?.cancel(); task = nil; isWorking = false
        do {
            try store.discard(pending)
            self.pending = nil; needsReplacementFolder = false
            status = "Local copy discarded. Any file already uploaded remains in Drive."
        } catch { status = error.localizedDescription }
    }

    func copyLatestLink() {
        guard let latestLink else { return }
        writeLink(latestLink)
        // Copying a successful link must not hide an unresolved local cleanup warning.
        if pending == nil { status = "Link copied" }
    }

    func stop() { generation = UUID(); task?.cancel(); task = nil }

    private func launch(_ original: PendingUpload) {
        guard let store else { return }
        generation = UUID()
        let run = generation
        isWorking = true; needsReplacementFolder = false; latestLink = nil; status = "Preparing upload…"
        onStarted?()
        task = Task { [weak self] in
            guard let self else { return }
            var job = original
            do {
                let source = store.pngURL(job)
                let png = try await Task.detached { try Data(contentsOf: source) }.value
                try self.check(run, account: job.accountID)
                if job.fileID == nil {
                    job.fileID = try await self.drive.generateID(account: job.accountID)
                    try self.check(run, account: job.accountID)
                    try store.save(job); self.pending = job
                }
                let id = job.fileID!
                var file = try await self.drive.file(id, account: job.accountID)
                try self.check(run, account: job.accountID)
                if let existing = file, !DriveClient.matches(existing, png: png, operation: job.id.uuidString) { throw CloudError.fileConflict }
                if file == nil {
                    let folder = try await self.resolveFolder(account: job.accountID, run: run)
                    try self.check(run, account: job.accountID)
                    job.stage = .uploading; try store.save(job); self.pending = job; self.status = "Uploading screenshot…"
                    file = try await self.drive.upload(id: id, name: job.name, operation: job.id.uuidString, folder: folder, png: png, account: job.accountID)
                    try self.check(run, account: job.accountID)
                }
                job.stage = .sharing; try store.save(job); self.pending = job; self.status = "Creating viewing link…"
                let shared = try await self.drive.share(id, account: job.accountID)
                try self.check(run, account: job.accountID)
                guard let link = shared.viewingURL else { throw CloudError.invalidResponse }
                // Cleanup failure must not turn a completed public upload into another upload.
                do { try store.discard(job); self.pending = nil }
                catch { self.status = "Link ready; local cleanup failed. Discard the local copy in My Screenshots." }
                self.latestLink = link
                if self.clipboardAtStart == self.readClipboardVersion() {
                    self.copyLatestLink()
                } else if self.pending == nil { self.status = "Link ready — Copy Link" }
                self.isWorking = false; self.task = nil; self.onUploaded?()
            } catch {
                guard self.generation == run, self.accountID() == job.accountID else { return }
                self.isWorking = false; self.task = nil; self.pending = store.pending(account: job.accountID)
                if case CloudError.folderMissing = error { self.needsReplacementFolder = true }
                if error is CancellationError { self.status = "Upload interrupted — Retry in My Screenshots" }
                else if case CloudError.sharingFailed = error { self.status = error.localizedDescription }
                else if job.stage == .sharing { self.status = "Uploaded, sharing failed. " + error.localizedDescription }
                else { self.status = error.localizedDescription }
            }
        }
    }

    private func check(_ run: UUID, account: String) throws {
        try Task.checkCancellation()
        guard generation == run, accountID() == account else { throw CancellationError() }
    }

    private func resolveFolder(account: String, run: UUID) async throws -> String {
        guard let store else { throw CloudError.invalidResponse }
        if let record = store.folder(account) {
            if let folder = try await drive.file(record.id, account: account) {
                try check(run, account: account)
                guard folder.trashed != true, folder.mimeType == "application/vnd.google-apps.folder",
                      folder.appProperties?["snapKind"] == "folder" else { throw CloudError.folderMissing }
                try store.setFolder(FolderRecord(id: record.id, confirmed: true), account: account)
                return record.id
            }
            try check(run, account: account)
            if record.confirmed { throw CloudError.folderMissing }
            _ = try await drive.createFolder(id: record.id, account: account)
            try check(run, account: account)
            try store.setFolder(FolderRecord(id: record.id, confirmed: true), account: account)
            return record.id
        }
        if let existing = try await drive.findFolder(account: account) {
            try check(run, account: account)
            try store.setFolder(FolderRecord(id: existing.id, confirmed: true), account: account)
            return existing.id
        }
        let id = try await drive.generateID(account: account)
        try check(run, account: account)
        try store.setFolder(FolderRecord(id: id, confirmed: false), account: account)
        _ = try await drive.createFolder(id: id, account: account)
        try check(run, account: account)
        try store.setFolder(FolderRecord(id: id, confirmed: true), account: account)
        return id
    }
}
