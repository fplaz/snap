import Foundation

struct PendingUpload: Codable, Equatable, Identifiable {
    var id: UUID
    let accountID: String
    let name: String
    let created: Date
    var fileID: String?
    var stage: Stage = .staged
    enum Stage: String, Codable { case staged, uploading, sharing }
}

struct FolderRecord: Codable {
    var id: String
    var confirmed: Bool
}

@MainActor
final class UploadStore {
    struct Manifest: Codable {
        var jobs: [PendingUpload] = []
        var folders: [String: FolderRecord] = [:]
    }
    let root: URL
    private(set) var manifest: Manifest

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("cl.fplaz.snap/Uploads", isDirectory: true)) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("manifest.json")
        manifest = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)) : Manifest()
        // A crash between the PNG write and journal commit cannot have begun an upload.
        let referenced = Set(manifest.jobs.map { $0.id.uuidString + ".png" })
        for candidate in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard candidate.pathExtension == "png", UUID(uuidString: candidate.deletingPathExtension().lastPathComponent) != nil,
                  !referenced.contains(candidate.lastPathComponent) else { continue }
            try FileManager.default.removeItem(at: candidate)
        }
    }

    func pending(account: String) -> PendingUpload? { manifest.jobs.first { $0.accountID == account } }
    func pngURL(_ job: PendingUpload) -> URL { root.appendingPathComponent(job.id.uuidString + ".png") }

    func stage(png: Data, account: String) async throws -> PendingUpload {
        guard pending(account: account) == nil else { throw CloudError.busy }
        let job = PendingUpload(id: UUID(), accountID: account,
                                name: "Snap-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".png", created: Date())
        let destination = pngURL(job)
        try await Task.detached(priority: .userInitiated) {
            try png.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }.value
        do { try save(job) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        return job
    }

    func save(_ job: PendingUpload) throws {
        var next = manifest
        next.jobs.removeAll { $0.id == job.id }; next.jobs.append(job)
        try persist(next)
    }

    func folder(_ account: String) -> FolderRecord? { manifest.folders[account] }
    func setFolder(_ folder: FolderRecord?, account: String) throws {
        var next = manifest; next.folders[account] = folder; try persist(next)
    }

    func discard(_ job: PendingUpload) throws {
        var next = manifest; next.jobs.removeAll { $0.id == job.id }
        try persist(next)
        if FileManager.default.fileExists(atPath: pngURL(job).path) { try FileManager.default.removeItem(at: pngURL(job)) }
    }

    private func persist(_ next: Manifest) throws {
        let url = root.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        manifest = next
    }
}
