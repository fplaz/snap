import Foundation

struct DriveFile: Codable, Identifiable, Equatable {
    let id: String
    var name: String?
    var mimeType: String?
    var webViewLink: String?
    var thumbnailLink: String?
    var createdTime: String?
    var size: String?
    var md5Checksum: String?
    var trashed: Bool?
    var appProperties: [String: String]?
    var permissions: [DrivePermission]?

    var createdDate: Date? {
        guard let createdTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdTime) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdTime)
    }

    var isPublic: Bool {
        permissions?.contains { $0.type == "anyone" && $0.role == "reader" && $0.allowFileDiscovery != true } == true
    }
    var viewingURL: URL? {
        guard let webViewLink, let url = URL(string: webViewLink), url.scheme == "https",
              url.host == "drive.google.com" else { return nil }
        return url
    }
}

struct DrivePermission: Codable, Equatable {
    var id: String?
    var type: String
    var role: String
    var allowFileDiscovery: Bool?
}

struct DrivePage: Decodable {
    var files: [DriveFile]
    var nextPageToken: String?
}

enum CloudError: LocalizedError {
    case signedOut, busy, folderMissing, sharingFailed, invalidResponse, fileConflict
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sign in with Google again to continue."
        case .busy: return "Complete or discard the pending upload before uploading another screenshot."
        case .folderMissing: return "The Snap folder is unavailable. Create a replacement folder, then retry."
        case .sharingFailed: return "Uploaded, but sharing failed. Your Google account may prohibit public links. Retry sharing from My Screenshots."
        case .invalidResponse: return "Google returned an unexpected response. Please retry."
        case .fileConflict: return "The saved upload does not match the file in Drive. Open My Screenshots to review it."
        case .http(let status, let reason):
            if status == 401 { return "Google access has expired or was revoked. Sign out and reconnect."
            }
            if reason == "storageQuotaExceeded" { return "Your Google Drive is full. Free some space and retry." }
            if status == 403 { return "Google denied this action (\(reason)). Check your Drive access or sharing policy." }
            return "Google Drive request failed (\(status)). Please retry."
        }
    }
}
