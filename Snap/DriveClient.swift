import Foundation
import CryptoKit

@MainActor
final class DriveClient {
    private static let session = URLSession(configuration: .ephemeral, delegate: DriveRedirectPolicy(), delegateQueue: nil)
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private let token: (String) async throws -> String
    private let pause: (UInt64) async throws -> Void
    static let fields = "id,name,mimeType,webViewLink,thumbnailLink,createdTime,size,md5Checksum,trashed,appProperties,permissions(id,type,role,allowFileDiscovery)"

    init(token: @escaping (String) async throws -> String,
         transport: @escaping Transport = { request in
             let (data, response) = try await DriveClient.session.data(for: request)
             guard let response = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
             return (data, response)
         }, pause: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.token = token; self.transport = transport; self.pause = pause
    }

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/" + path)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func request(_ url: URL, account: String, method: String = "GET", body: Data? = nil,
                         headers: [String: String] = [:], accepted: Set<Int> = [200, 201, 204]) async throws -> (Data, HTTPURLResponse) {
        // Never forward OAuth credentials to an arbitrary resumable or thumbnail URL.
        guard url.scheme == "https", url.host == "www.googleapis.com" else { throw CloudError.invalidResponse }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 60
            request.setValue("Bearer " + (try await token(account)), forHTTPHeaderField: "Authorization")
            try Task.checkCancellation()
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let result: (Data, HTTPURLResponse)
            do { result = try await transport(request) }
            catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                guard attempt < 2 else { throw error }
                try await pause(UInt64(1 << attempt) * 1_000_000_000); continue
            }
            try Task.checkCancellation()
            let status = result.1.statusCode
            if accepted.contains(status) { return result }
            let reason = Self.reason(result.0)
            let transient = status == 429 || status >= 500 || (status == 403 && ["rateLimitExceeded", "userRateLimitExceeded"].contains(reason))
            if transient && attempt < 2 {
                let retry = min(30, max(1, Double(result.1.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(1 << attempt)))
                try await pause(UInt64(retry * 1_000_000_000)); continue
            }
            throw CloudError.http(status, reason)
        }
        throw CloudError.invalidResponse
    }

    private static func reason(_ data: Data) -> String {
        struct Envelope: Decodable {
            struct Detail: Decodable {
                struct Entry: Decodable { var reason: String? }
                var errors: [Entry]?
            }
            var error: Detail?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.errors?.first?.reason ?? "accessDenied"
    }

    func generateID(account: String) async throws -> String {
        struct IDs: Decodable { let ids: [String] }
        let (data, _) = try await request(url("drive/v3/files/generateIds", query: [.init(name: "count", value: "1"), .init(name: "space", value: "drive")]), account: account)
        guard let id = try JSONDecoder().decode(IDs.self, from: data).ids.first, !id.isEmpty else { throw CloudError.invalidResponse }
        return id
    }

    func file(_ id: String, account: String) async throws -> DriveFile? {
        let (data, response) = try await request(url("drive/v3/files/" + id, query: [.init(name: "fields", value: Self.fields)]), account: account, accepted: [200, 404])
        return response.statusCode == 404 ? nil : try JSONDecoder().decode(DriveFile.self, from: data)
    }

    func findFolder(account: String) async throws -> DriveFile? {
        let query = "trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='snapKind' and value='folder' }"
        let (data, _) = try await request(url("drive/v3/files", query: [.init(name: "q", value: query), .init(name: "fields", value: "files(" + Self.fields + ")"), .init(name: "orderBy", value: "createdTime")]), account: account)
        return try JSONDecoder().decode(DrivePage.self, from: data).files.first
    }

    func createFolder(id: String, account: String) async throws -> DriveFile {
        struct Folder: Encodable {
            let id: String
            let name = "Snap Screenshots"
            let mimeType = "application/vnd.google-apps.folder"
            let appProperties = ["snapKind": "folder"]
        }
        let (data, response) = try await request(url("drive/v3/files", query: [.init(name: "fields", value: Self.fields)]), account: account, method: "POST",
                                               body: try JSONEncoder().encode(Folder(id: id)), headers: ["Content-Type": "application/json"], accepted: [200, 201, 409])
        if response.statusCode == 409 {
            guard let existing = try await file(id, account: account), existing.trashed != true,
                  existing.appProperties?["snapKind"] == "folder" else { throw CloudError.folderMissing }
            return existing
        }
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    func upload(id: String, name: String, operation: String, folder: String, png: Data, account: String) async throws -> DriveFile {
        struct Metadata: Encodable {
            let id: String, name: String
            let mimeType = "image/png"
            let parents: [String]
            let appProperties: [String: String]
        }
        let metadata = Metadata(id: id, name: name, parents: [folder], appProperties: ["snapKind": "screenshot", "snapUpload": operation])
        let (_, response) = try await request(url("upload/drive/v3/files", query: [.init(name: "uploadType", value: "resumable"), .init(name: "fields", value: Self.fields)]),
                                            account: account, method: "POST", body: try JSONEncoder().encode(metadata),
                                            headers: ["Content-Type": "application/json", "X-Upload-Content-Type": "image/png", "X-Upload-Content-Length": String(png.count)], accepted: [200, 201, 409])
        if response.statusCode == 409 {
            guard let existing = try await file(id, account: account), Self.matches(existing, png: png, operation: operation) else { throw CloudError.fileConflict }
            return existing
        }
        guard let location = response.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location) else { throw CloudError.invalidResponse }
        let (data, _) = try await request(uploadURL, account: account, method: "PUT", body: png,
                                         headers: ["Content-Type": "image/png", "Content-Range": "bytes 0-\(png.count - 1)/\(png.count)"])
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    static func matches(_ file: DriveFile, png: Data, operation: String) -> Bool {
        file.trashed != true && file.appProperties?["snapUpload"] == operation && file.size == String(png.count)
            && file.md5Checksum == Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
    }

    func share(_ id: String, account: String) async throws -> DriveFile {
        if let existing = try await file(id, account: account), existing.isPublic { return existing }
        let permission = DrivePermission(type: "anyone", role: "reader", allowFileDiscovery: false)
        _ = try await request(url("drive/v3/files/" + id + "/permissions"), account: account, method: "POST",
                              body: try JSONEncoder().encode(permission), headers: ["Content-Type": "application/json"])
        guard let shared = try await file(id, account: account), shared.isPublic, shared.viewingURL != nil else { throw CloudError.sharingFailed }
        return shared
    }

    func history(account: String, page: String? = nil) async throws -> DrivePage {
        var query: [URLQueryItem] = [.init(name: "q", value: "trashed=false and mimeType='image/png' and appProperties has { key='snapKind' and value='screenshot' }"),
                                    .init(name: "orderBy", value: "createdTime desc"), .init(name: "pageSize", value: "40"),
                                    .init(name: "fields", value: "nextPageToken,files(" + Self.fields + ")")]
        if let page { query.append(.init(name: "pageToken", value: page)) }
        let (data, _) = try await request(url("drive/v3/files", query: query), account: account)
        return try JSONDecoder().decode(DrivePage.self, from: data)
    }
}

// Drive REST must not silently forward a bearer request to a redirected host.
private final class DriveRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
