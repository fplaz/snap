import XCTest
import Foundation
import CryptoKit
import AppKit
import SwiftUI
import AppAuth
import AppAuthCore
import GTMAppAuth

final class CloudTests: XCTestCase {
    private func response(_ request: URLRequest, _ status: Int, _ json: String = "{}", headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    @MainActor
    func testHistoryLimitsQueryToSnapImagesAndPreservesPageToken() async throws {
        var observed: URLRequest?
        let client = DriveClient(token: { account in XCTAssertEqual(account, "account-A"); return "test-token" }, transport: { request in
            observed = request; return self.response(request, 200, "{\"files\":[],\"nextPageToken\":\"next\"}")
        })
        let page = try await client.history(account: "account-A", page: "page+token")
        XCTAssertEqual(page.nextPageToken, "next")
        let request = try XCTUnwrap(observed)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "pageToken" }?.value, "page+token")
        XCTAssertTrue(query.first { $0.name == "q" }!.value!.contains("snapKind"))
        XCTAssertFalse(query.first { $0.name == "q" }!.value!.contains("parents"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    @MainActor
    func testTransientRetryIsBoundedAndHonorsRetryAfter() async throws {
        var calls = 0; var pauses: [UInt64] = []
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls += 1
            return self.response(request, 429, headers: ["Retry-After": "2"])
        }, pause: { pauses.append($0) })
        do { _ = try await client.generateID(account: "A"); XCTFail("Expected rate limit error") }
        catch { XCTAssertTrue(error is CloudError) }
        XCTAssertEqual(calls, 3); XCTAssertEqual(pauses, [2_000_000_000, 2_000_000_000])
    }

    @MainActor
    func testRevokedAuthorizationDoesNotLoop() async throws {
        var calls = 0
        let client = DriveClient(token: { _ in "token" }, transport: { request in calls += 1; return self.response(request, 401) })
        do { _ = try await client.file("file", account: "A"); XCTFail("Expected auth error") } catch {}
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testSharingUsesUnlistedAnyoneReaderAndVerifiesReturnedLink() async throws {
        var calls: [URLRequest] = []
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls.append(request)
            if request.httpMethod == "POST" { return self.response(request, 200, "{\"id\":\"anyoneWithLink\"}") }
            return self.response(request, 200, calls.count == 1 ? "{\"id\":\"f\"}" : "{\"id\":\"f\",\"webViewLink\":\"https://drive.google.com/file/d/f/view\",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]}")
        })
        let file = try await client.share("f", account: "A")
        XCTAssertTrue(file.isPublic); XCTAssertNotNil(file.viewingURL)
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[1].url?.path, "/drive/v3/files/f/permissions")
        let permission = try JSONDecoder().decode(DrivePermission.self, from: calls[1].httpBody!)
        XCTAssertEqual(permission.type, "anyone"); XCTAssertEqual(permission.role, "reader")
        XCTAssertEqual(permission.allowFileDiscovery, false)
    }

    @MainActor
    func testUnsafeResumableLocationNeverReceivesCredentials() async throws {
        var calls = 0
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls += 1; return self.response(request, 200, headers: ["Location": "https://example.com/upload"])
        })
        do { _ = try await client.upload(id: "f", name: "image.png", operation: "op", folder: "folder", png: Data([1]), account: "A"); XCTFail("Expected unsafe URL rejection") } catch {}
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testUploadConflictReconcilesSameFileWithoutUploadingAgain() async throws {
        let png = Data([1, 2, 3])
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var calls: [URLRequest] = []
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls.append(request)
            if request.httpMethod == "POST" { return self.response(request, 409) }
            return self.response(request, 200, "{\"id\":\"same-id\",\"size\":\"3\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"operation\"}}")
        })
        let file = try await client.upload(id: "same-id", name: "image.png", operation: "operation", folder: "folder", png: png, account: "A")
        XCTAssertEqual(file.id, "same-id"); XCTAssertEqual(calls.count, 2)
        XCTAssertFalse(calls.contains { $0.httpMethod == "PUT" })
    }

    func testUntrustedViewingLinksAreNotOpened() throws {
        let file = try JSONDecoder().decode(DriveFile.self, from: Data("{\"id\":\"f\",\"webViewLink\":\"https://example.com/image\"}".utf8))
        XCTAssertNil(file.viewingURL)
    }

    @MainActor
    func testStagingSurvivesRelaunchAndIsPartitionedByAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root)
        let png = Data([1, 2, 3])
        var job = try await store.stage(png: png, account: "A")
        job.fileID = "allocated-id"; job.stage = .sharing; try store.save(job)
        let restored = try UploadStore(root: root)
        XCTAssertEqual(restored.pending(account: "A"), job)
        XCTAssertNil(restored.pending(account: "B"))
        XCTAssertEqual(try Data(contentsOf: restored.pngURL(job)), png)
        let attrs = try FileManager.default.attributesOfItem(atPath: restored.pngURL(job).path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try restored.discard(job)
        XCTAssertNil(restored.pending(account: "A")); XCTAssertFalse(FileManager.default.fileExists(atPath: restored.pngURL(job).path))
    }

    @MainActor
    func testCorruptJournalIsNotSilentlyReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try UploadStore(root: root))
    }

    @MainActor
    func testCompletedFileIsReconciledAndChangedClipboardIsPreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root)
        let png = Data([1, 2, 3]); let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var job = try await store.stage(png: png, account: "A"); job.fileID = "f"; try store.save(job)
        var calls: [URLRequest] = []
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls.append(request)
            return self.response(request, 200, "{\"id\":\"f\",\"size\":\"3\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(job.id.uuidString)\"},\"webViewLink\":\"https://drive.google.com/file/d/f/view\",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]}")
        })
        var version = 1; var writes = 0
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store, readClipboardVersion: { version }, writeLink: { _ in writes += 1 })
        uploads.accountChanged(); uploads.retry(); version = 2
        await settle(uploads)
        XCTAssertEqual(writes, 0); XCTAssertNotNil(uploads.latestLink)
        XCTAssertNil(uploads.pending); XCTAssertNil(store.pending(account: "A"))
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod == "GET" })
        uploads.copyLatestLink(); XCTAssertEqual(writes, 1)
    }

    @MainActor
    func testAccountChangeInvalidatesLateUploadCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root)
        var job = try await store.stage(png: Data([1]), account: "A"); job.fileID = "f"; try store.save(job)
        var account: String? = "A"
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Never>?
        var request: URLRequest?
        let client = DriveClient(token: { _ in "token" }, transport: { incoming in
            request = incoming
            return await withCheckedContinuation { continuation = $0 }
        })
        var writes = 0
        let uploads = UploadCoordinator(drive: client, accountID: { account }, store: store, readClipboardVersion: { 1 }, writeLink: { _ in writes += 1 })
        uploads.accountChanged(); uploads.retry()
        for _ in 0..<1000 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        account = "B"; uploads.accountChanged()
        continuation?.resume(returning: response(try XCTUnwrap(request), 404))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(uploads.pending); XCTAssertNil(uploads.latestLink); XCTAssertEqual(writes, 0)
        XCTAssertEqual(store.pending(account: "A")?.fileID, "f")
    }

    @MainActor
    func testHistoryPaginationAndAccountReset() async throws {
        var account: String? = "A"; var calls = 0
        let client = DriveClient(token: { expected in XCTAssertEqual(expected, account); return "token" }, transport: { request in
            calls += 1
            let body = calls == 1 ? "{\"files\":[{\"id\":\"one\"}],\"nextPageToken\":\"page2\"}" : "{\"files\":[{\"id\":\"one\"},{\"id\":\"two\"}]}"
            return self.response(request, 200, body)
        })
        let history = ScreenshotHistoryController(drive: client, accountID: { account })
        history.refresh()
        while history.isLoading { await Task.yield() }
        XCTAssertEqual(history.files.map(\.id), ["one"])
        history.loadMore()
        while history.isLoading { await Task.yield() }
        XCTAssertEqual(history.files.map(\.id), ["one", "two"])
        XCTAssertNil(history.nextPage)
        history.loadMore(); XCTAssertEqual(calls, 2)
        account = "B"; history.accountChanged()
        XCTAssertTrue(history.files.isEmpty); XCTAssertTrue(history.thumbnails.isEmpty)
    }

    @MainActor
    func testHistoryFailureIsVisibleAndRefreshCanRetry() async throws {
        var calls = 0
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return self.response(request, 200, "{\"files\":[]}")
        })
        let history = ScreenshotHistoryController(drive: client, accountID: { "A" })
        history.refresh(); while history.isLoading { await Task.yield() }
        XCTAssertNotNil(history.message)
        history.refresh(); while history.isLoading { await Task.yield() }
        XCTAssertNil(history.message)
    }

    @MainActor
    func testUnsignedValidationDoesNotRequireGoogleConfigurationOrTouchKeychain() throws {
        let account = AccountController(bundle: Bundle(for: CloudTests.self))
        XCTAssertFalse(account.configured)
        account.restore()
        XCTAssertNil(account.id)
        XCTAssertNotNil(account.message)
    }

    @MainActor
    func testSharingFailureKeepsSamePendingFileForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root); let png = Data([1])
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var job = try await store.stage(png: png, account: "A"); job.fileID = "f"; try store.save(job)
        var permissionRequests = 0; var fileCreates = 0; var shared = false
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            if request.httpMethod == "POST" {
                if request.url!.path.hasSuffix("/permissions") {
                    permissionRequests += 1
                    if permissionRequests == 1 { return self.response(request, 403) }
                    shared = true; return self.response(request, 200)
                }
                fileCreates += 1; return self.response(request, 500)
            }
            let permissions = shared ? ",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]" : ""
            return self.response(request, 200, "{\"id\":\"f\",\"size\":\"1\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(job.id.uuidString)\"},\"webViewLink\":\"https://drive.google.com/file/d/f/view\"\(permissions)}")
        })
        var writes = 0
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store, readClipboardVersion: { 1 }, writeLink: { _ in writes += 1 })
        uploads.accountChanged(); uploads.retry(); await settle(uploads)
        XCTAssertEqual(uploads.pending?.stage, .sharing); XCTAssertEqual(uploads.pending?.fileID, "f")
        XCTAssertEqual(writes, 0); XCTAssertTrue(uploads.status.contains("sharing failed"))
        uploads.retry(); await settle(uploads)
        XCTAssertNil(uploads.pending); XCTAssertEqual(writes, 1)
        XCTAssertEqual(fileCreates, 0); XCTAssertEqual(permissionRequests, 2)
    }

    @MainActor
    func testSignedOutHistoryViewRendersOffscreen() throws {
        let account = AccountController(bundle: Bundle(for: CloudTests.self))
        let client = DriveClient(token: { _ in throw CloudError.signedOut }, transport: { _ in XCTFail("Unexpected network request"); throw CloudError.invalidResponse })
        let uploads = UploadCoordinator(drive: client, accountID: { nil }, store: nil)
        let history = ScreenshotHistoryController(drive: client, accountID: { nil })
        let view = NSHostingView(rootView: ScreenshotHistoryView(account: account, uploads: uploads, history: history, signIn: {}))
        view.frame = CGRect(x: 0, y: 0, width: 780, height: 560)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        // Local verification artifact; no real account, screen capture, or OAuth session.
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/snap-history-preview.png"))
    }

    func testDriveTimestampAcceptsFractionalSeconds() throws {
        let file = try JSONDecoder().decode(DriveFile.self, from: Data("{\"id\":\"f\",\"createdTime\":\"2026-10-03T18:00:00.123Z\"}".utf8))
        XCTAssertNotNil(file.createdDate)
    }

    @MainActor
    func testColdUploadCompletesAndSubsequentUploadReusesPrivateFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root); let png = Data([1, 2, 3])
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var allocated = 0; var folderCreates = 0; var uploaded = 0; var shared: Set<String> = []
        var metadata: [String: Any] = [:]; var files: [String: String] = [:]
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            let path = request.url!.path
            if path.hasSuffix("/generateIds") {
                allocated += 1
                let id = allocated == 2 ? "folder-id" : "image-\(allocated)"
                return self.response(request, 200, "{\"ids\":[\"\(id)\"]}")
            }
            if path == "/drive/v3/files" && request.httpMethod == "GET" { return self.response(request, 200, "{\"files\":[]}") }
            if path == "/drive/v3/files" && request.httpMethod == "POST" {
                folderCreates += 1
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(body["id"] as? String, "folder-id")
                XCTAssertEqual(body["mimeType"] as? String, "application/vnd.google-apps.folder")
                return self.response(request, 200, "{\"id\":\"folder-id\",\"mimeType\":\"application/vnd.google-apps.folder\",\"appProperties\":{\"snapKind\":\"folder\"}}")
            }
            if path == "/upload/drive/v3/files" {
                metadata = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(metadata["parents"] as? [String], ["folder-id"])
                XCTAssertEqual(metadata["mimeType"] as? String, "image/png")
                return self.response(request, 200, headers: ["Location": "https://www.googleapis.com/upload-session"])
            }
            if path == "/upload-session" {
                XCTAssertEqual(request.httpBody, png); XCTAssertEqual(request.httpMethod, "PUT")
                uploaded += 1
                let id = metadata["id"] as! String
                let operation = (metadata["appProperties"] as! [String: String])["snapUpload"]!
                files[id] = operation
                return self.response(request, 200, "{\"id\":\"\(id)\"}")
            }
            if path.hasSuffix("/permissions") {
                let id = path.split(separator: "/").dropLast().last!.description
                XCTAssertNotEqual(id, "folder-id")
                shared.insert(id); return self.response(request, 200)
            }
            let id = path.split(separator: "/").last!.description
            if id == "folder-id" { return self.response(request, 200, "{\"id\":\"folder-id\",\"mimeType\":\"application/vnd.google-apps.folder\",\"appProperties\":{\"snapKind\":\"folder\"}}") }
            guard let operation = files[id] else { return self.response(request, 404) }
            let permissions = shared.contains(id) ? ",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]" : ""
            return self.response(request, 200, "{\"id\":\"\(id)\",\"size\":\"3\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(operation)\"},\"webViewLink\":\"https://drive.google.com/file/d/\(id)/view\"\(permissions)}")
        })
        var links: [URL] = []
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store, readClipboardVersion: { 1 }, writeLink: { links.append($0) })
        for _ in 0..<2 {
            let job = try await uploads.stage(png); uploads.begin(job); await settle(uploads)
            XCTAssertNil(uploads.pending)
        }
        XCTAssertEqual(uploaded, 2); XCTAssertEqual(folderCreates, 1); XCTAssertEqual(links.count, 2)
        XCTAssertEqual(store.folder("A")?.id, "folder-id"); XCTAssertEqual(store.folder("A")?.confirmed, true)
    }

    @MainActor
    func testRestartRemovesOnlyUnjournaledStagingImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let orphan = root.appendingPathComponent(UUID().uuidString + ".png")
        let unrelated = root.appendingPathComponent("notes.txt")
        try Data([1]).write(to: orphan); try Data([2]).write(to: unrelated)
        _ = try UploadStore(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @MainActor
    private func configuredAccount(store: MemoryAuthStore, present: AccountController.Presenter? = nil) throws -> AccountController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": UUID().uuidString,
            "GIDClientID": "snap-test.apps.googleusercontent.com",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["com.googleusercontent.apps.snap-test"]]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        return AccountController(bundle: try XCTUnwrap(Bundle(url: root)), store: store, present: present)
    }

    @MainActor
    private func storedSession(_ request: OIDAuthorizationRequest, scope: String? = nil) throws -> AuthSession {
        let response = OIDAuthorizationResponse(request: request, parameters:
            ["code": "test-code" as NSString, "state": request.state! as NSString])
        let state = OIDAuthState(authorizationResponse: response)
        let claims: [String: Any] = ["iss": "https://accounts.google.com", "sub": "test-user",
            "aud": request.clientID, "email": "test@example.com",
            "iat": Int(Date().timeIntervalSince1970), "exp": Int(Date().timeIntervalSince1970) + 3600]
        func part(_ object: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        let idToken = try part(["alg": "RS256", "typ": "JWT"]) + "." + part(claims) + ".dGVzdA"
        let token = OIDTokenResponse(request: try XCTUnwrap(response.tokenExchangeRequest()), parameters:
            ["access_token": "test-token" as NSString, "refresh_token": "test-refresh" as NSString,
             "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 3600), "id_token": idToken as NSString,
             "scope": (scope ?? AccountController.driveScope) as NSString])
        state.update(with: token, error: nil)
        return AuthSession(authState: state, userID: "test-user", userEmail: "test@example.com")
    }

    @MainActor
    func testBrowserRequestUsesPKCEStateAndScopedCodeFlow() throws {
        let account = try configuredAccount(store: MemoryAuthStore())
        let first = try XCTUnwrap(account.authorizationRequest())
        let second = try XCTUnwrap(account.authorizationRequest())
        XCTAssertEqual(first.responseType, OIDResponseTypeCode)
        XCTAssertEqual(first.redirectURL?.absoluteString, "com.googleusercontent.apps.snap-test:/oauthredirect")
        XCTAssertNotNil(first.codeVerifier); XCTAssertNotNil(first.codeChallenge)
        XCTAssertEqual(first.codeChallengeMethod, "S256")
        XCTAssertNotEqual(first.state, second.state); XCTAssertNotEqual(first.codeVerifier, second.codeVerifier)
        XCTAssertTrue(first.scope!.contains(AccountController.driveScope))
        XCTAssertFalse(first.scope!.split(separator: " ").contains("https://www.googleapis.com/auth/drive"))
    }

    @MainActor
    func testDefaultBrowserAgentOpensAuthorizationURLAndReportsOpenFailure() throws {
        let account = try configuredAccount(store: MemoryAuthStore())
        let request = try XCTUnwrap(account.authorizationRequest())
        var opened: URL?
        let agent = DefaultBrowserAgent(open: { opened = $0; return true })
        let flow = FakeBrowserFlow()
        XCTAssertTrue(agent.present(request, session: flow))
        XCTAssertEqual(opened?.host, "accounts.google.com")
        XCTAssertNil(flow.error)
        XCTAssertFalse(DefaultBrowserAgent(open: { _ in false }).present(request, session: flow))
        XCTAssertNotNil(flow.error)
    }

    @MainActor
    func testExistingGTMAccountRestoresAndTokenPersistsWithoutNetwork() async throws {
        let store = MemoryAuthStore()
        let account = try configuredAccount(store: store)
        store.session = try storedSession(try XCTUnwrap(account.authorizationRequest()))
        account.restore()
        XCTAssertEqual(account.id, "test-user"); XCTAssertEqual(account.email, "test@example.com")
        let token = try await account.accessToken(account: "test-user")
        XCTAssertEqual(token, "test-token"); XCTAssertEqual(store.saves, 1)
        account.signOut()
        XCTAssertNil(account.id); XCTAssertNil(store.session)
    }

    @MainActor
    func testAuthStoreUsesTheExpectedKeychainForEachBuild() {
        let store = AccountController.makeAuthStore()
        let fileBased = store.keychainAttributes.contains {
            if case .useFileBasedKeychain = $0.attribute { return true }
            return false
        }
        XCTAssertEqual(store.itemName, "cl.fplaz.snap.private-beta.auth")
        XCTAssertTrue(fileBased)
    }

    @MainActor
    func testSignOutSucceedsWhenKeychainCredentialWasAlreadyRemoved() throws {
        let store = MemoryAuthStore()
        let account = try configuredAccount(store: store)
        store.session = try storedSession(try XCTUnwrap(account.authorizationRequest()))
        account.restore()
        store.session = nil
        store.removalError = KeychainStore.Error.failedToDeletePasswordBecauseItemNotFound(itemName: "test")
        var changes = 0
        account.onChanged = { changes += 1 }
        account.signOut()
        XCTAssertNil(account.id); XCTAssertNil(account.email); XCTAssertNil(account.message)
        XCTAssertEqual(changes, 1)
    }

    @MainActor
    func testRestoreRejectsMissingDriveScopeAndSignOutKeepsAccountOnKeychainFailure() throws {
        let store = MemoryAuthStore()
        let account = try configuredAccount(store: store)
        let request = try XCTUnwrap(account.authorizationRequest())
        store.session = try storedSession(request, scope: "openid email")
        account.restore(); XCTAssertNil(account.id)
        store.session = try storedSession(request)
        account.restore(); XCTAssertNotNil(account.id)
        store.failRemoval = true
        account.signOut(); XCTAssertNotNil(account.id); XCTAssertNotNil(account.message)
    }

    @MainActor
    func testCancelSignInRejectsLateCompletionAndUnrelatedCallbacks() async throws {
        let store = MemoryAuthStore(); let flow = FakeBrowserFlow()
        var complete: OIDAuthStateAuthorizationCallback?
        let account = try configuredAccount(store: store, present: { _, callback in complete = callback; return flow })
        account.signIn(); XCTAssertTrue(account.isSigningIn)
        XCTAssertFalse(account.handle(URL(string: "https://example.com/oauthredirect?code=test")!))
        XCTAssertEqual(flow.resumes, 0)
        account.cancelSignIn(); XCTAssertTrue(flow.canceled); XCTAssertFalse(account.isSigningIn)
        let session = try storedSession(try XCTUnwrap(account.authorizationRequest()))
        complete?(session.authState, nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(account.id); XCTAssertEqual(store.saves, 0)
    }

    @MainActor
    func testBrowserSignInPersistsAcceptedAccount() async throws {
        let store = MemoryAuthStore(); let flow = FakeBrowserFlow()
        var complete: OIDAuthStateAuthorizationCallback?
        let account = try configuredAccount(store: store, present: { _, callback in complete = callback; return flow })
        account.signIn()
        let session = try storedSession(try XCTUnwrap(account.authorizationRequest()))
        complete?(session.authState, nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(account.id, "test-user"); XCTAssertEqual(store.saves, 1)
        XCTAssertFalse(account.isSigningIn)
    }

    @MainActor
    func testAppAuthRejectsWrongStateBeforeCodeExchange() async throws {
        let store = MemoryAuthStore()
        let account = try configuredAccount(store: store, present: { request, callback in
            OIDAuthState.authState(byPresenting: request,
                externalUserAgent: DefaultBrowserAgent(open: { _ in true }), callback: callback)
        })
        account.signIn()
        _ = account.handle(URL(string: "com.googleusercontent.apps.snap-test:/oauthredirect?code=fake&state=wrong")!)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(account.isSigningIn); XCTAssertNil(account.id)
        XCTAssertNotNil(account.message); XCTAssertEqual(store.saves, 0)
    }

    @MainActor
    func testCleanupWarningSurvivesAutomaticAndExplicitLinkCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root); let png = Data([1])
        var job = try await store.stage(png: png, account: "A")
        job.fileID = "f"; try store.save(job)
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var reads = 0
        let manifest = root.appendingPathComponent("manifest.json")
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            reads += 1
            // Fail the journal write during cleanup, after the public link is verified.
            if reads == 2 {
                try FileManager.default.removeItem(at: manifest)
                try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
            }
            return self.response(request, 200, "{\"id\":\"f\",\"size\":\"1\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(job.id.uuidString)\"},\"webViewLink\":\"https://drive.google.com/file/d/f/view\",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]}")
        })
        var writes = 0
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store,
            readClipboardVersion: { 1 }, writeLink: { _ in writes += 1 })
        uploads.accountChanged(); uploads.retry(); await settle(uploads)
        XCTAssertNotNil(uploads.latestLink); XCTAssertNotNil(uploads.pending)
        XCTAssertFalse(uploads.canUpload); XCTAssertEqual(writes, 1)
        XCTAssertTrue(uploads.status.contains("local cleanup failed"))
        let warning = uploads.status
        uploads.copyLatestLink()
        XCTAssertEqual(writes, 2); XCTAssertEqual(uploads.status, warning)
        try FileManager.default.removeItem(at: manifest)
        uploads.discardLocal()
        XCTAssertNil(uploads.pending); XCTAssertTrue(uploads.canUpload)
    }

    @MainActor
    func testSharingFailureMessageIsNotDuplicated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root); let png = Data([1])
        var job = try await store.stage(png: png, account: "A")
        job.fileID = "f"; try store.save(job)
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            return self.response(request, 200, "{\"id\":\"f\",\"size\":\"1\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(job.id.uuidString)\"}}")
        })
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store)
        uploads.accountChanged(); uploads.retry(); await settle(uploads)
        XCTAssertEqual(uploads.status, CloudError.sharingFailed.localizedDescription)
        XCTAssertEqual(uploads.pending?.stage, .sharing); XCTAssertNil(uploads.latestLink)
    }

    @MainActor
    func testUploadHintsExplainStorageAndStagingAndPendingStates() async throws {
        let client = DriveClient(token: { _ in "token" }, transport: { _ in
            XCTFail("No network request expected"); throw CloudError.invalidResponse
        })
        var accountID: String? = nil
        let unavailable = UploadCoordinator(drive: client, accountID: { accountID }, store: nil)
        XCTAssertTrue(unavailable.uploadHint.contains("Sign in"))
        accountID = "A"
        XCTAssertTrue(unavailable.uploadHint.contains("storage is unavailable"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root)
        var stagingHint: String?
        var uploads: UploadCoordinator!
        uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store,
            readClipboardVersion: { stagingHint = uploads.uploadHint; return 1 })
        _ = try await uploads.stage(Data([1]))
        XCTAssertTrue(stagingHint?.contains("in progress") == true)
        XCTAssertTrue(uploads.uploadHint.contains("pending upload"))
    }

    @MainActor
    func testAccountChangeDuringStagingCancelsWithoutLeavingPendingUpload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root)
        let client = DriveClient(token: { _ in "token" }, transport: { _ in
            XCTFail("Canceled staging must not upload"); throw CloudError.invalidResponse
        })
        var accountID = "A"
        let uploads = UploadCoordinator(drive: client, accountID: { accountID }, store: store,
            readClipboardVersion: { accountID = "B"; return 1 })
        do { _ = try await uploads.stage(Data([1])); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(uploads.pending); XCTAssertNil(store.pending(account: "A"))
        XCTAssertTrue(uploads.canUpload)
    }

    @MainActor
    func testUploadPanelShowsLoadingThenReadyAndOnlyCopiesVerifiedLink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try UploadStore(root: root); let png = Data([1, 2, 3])
        var version = 1; var writes: [URL] = []; var starts = 0
        var job = try await store.stage(png: png, account: "A")
        job.fileID = "f"; try store.save(job)
        let checksum = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let client = DriveClient(token: { _ in "token" }, transport: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return self.response(request, 200, "{\"id\":\"f\",\"size\":\"3\",\"md5Checksum\":\"\(checksum)\",\"appProperties\":{\"snapUpload\":\"\(job.id.uuidString)\"},\"webViewLink\":\"https://drive.google.com/file/d/f/view\",\"permissions\":[{\"type\":\"anyone\",\"role\":\"reader\",\"allowFileDiscovery\":false}]}")
        })
        let uploads = UploadCoordinator(drive: client, accountID: { "A" }, store: store,
            readClipboardVersion: { version }, writeLink: { writes.append($0) })
        uploads.accountChanged()
        let panel = UploadProgressPanel(uploads: uploads, reviewUpload: {})
        panel.copyLinkAndClose(); XCTAssertTrue(writes.isEmpty)
        uploads.onStarted = {
            starts += 1
            XCTAssertTrue(uploads.isWorking); XCTAssertNil(uploads.latestLink)
            XCTAssertTrue(uploads.uploadHint.contains("in progress"))
            panel.copyLinkAndClose(); XCTAssertTrue(writes.isEmpty)
            try? self.renderUploadPanel(uploads, path: "/tmp/snap-upload-panel-loading.png")
        }
        uploads.retry()
        // Protect a clipboard change while the upload is running; the panel offers explicit Copy.
        version = 2
        await settle(uploads)
        XCTAssertEqual(starts, 1); XCTAssertNotNil(uploads.latestLink); XCTAssertTrue(writes.isEmpty)
        try renderUploadPanel(uploads, path: "/tmp/snap-upload-panel-ready.png")
        panel.copyLinkAndClose()
        XCTAssertEqual(writes.map(\.absoluteString), ["https://drive.google.com/file/d/f/view"])
    }

    @MainActor
    private func renderUploadPanel(_ uploads: UploadCoordinator, path: String) throws {
        let view = NSHostingView(rootView: UploadProgressView(uploads: uploads, copyLink: {}, close: {}, reviewUpload: {}))
        view.frame = CGRect(x: 0, y: 0, width: 360, height: 130)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    func testUploadPanelPlacementUsesVisibleScreenTopRightIncludingNegativeOrigins() {
        let screen = CGRect(x: -1920, y: -400, width: 1920, height: 1055)
        let frame = UploadProgressPanel.frame(in: screen)
        XCTAssertEqual(screen.maxX - frame.maxX, 20)
        XCTAssertEqual(screen.maxY - frame.maxY, 20)
        XCTAssertTrue(screen.contains(frame))
    }

    @MainActor
    func testCaptureDeniedShowsPermissionHelpDespiteStaleGrantedPreflight() {
        var confirmations = 0; var requests = 0
        _ = ScreenPermission.ensureAccess(afterCaptureDenied: true, check: { true },
            request: { requests += 1; return false }, confirm: { confirmations += 1; return true })
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(requests, 1)

        XCTAssertFalse(ScreenPermission.ensureAccess(afterCaptureDenied: true, check: { true },
            request: { XCTFail("Not Now must not request access"); return false }, confirm: { false }))
    }

    @MainActor
    func testMissingPermissionRequestsNativeAccessOnEveryConfirmedAttempt() {
        var requests = 0; var confirmations = 0; var checks = 0
        for _ in 0..<2 {
            XCTAssertFalse(ScreenPermission.ensureAccess(check: { checks += 1; return false },
                request: { requests += 1; return false }, confirm: { confirmations += 1; return true }))
        }
        XCTAssertEqual(requests, 2); XCTAssertEqual(confirmations, 2); XCTAssertEqual(checks, 4)
    }

    @MainActor
    func testGrantedScreenPermissionDoesNotShowAnyPrompt() {
        XCTAssertTrue(ScreenPermission.ensureAccess(check: { true },
            request: { XCTFail("Already authorized: must not request permission"); return false },
            confirm: { XCTFail("Already authorized: must not show help"); return false }))
    }

    @MainActor
    func testPermissionIsRequestedAgainAfterPreviouslyGrantedAccessIsRemoved() {
        var granted = true; var requests = 0
        XCTAssertTrue(ScreenPermission.ensureAccess(check: { granted }, request: { requests += 1; return false }, confirm: { true }))
        XCTAssertEqual(requests, 0)
        granted = false
        XCTAssertTrue(ScreenPermission.ensureAccess(check: { granted },
            request: { requests += 1; granted = true; return false }, confirm: { true }))
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testDecliningPermissionHelpDoesNotTriggerNativePrompt() {
        var requests = 0
        XCTAssertFalse(ScreenPermission.ensureAccess(check: { false },
            request: { requests += 1; return false }, confirm: { false }))
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    private func settle(_ uploads: UploadCoordinator) async {
        let limit = Date().addingTimeInterval(3)
        while uploads.isWorking && Date() < limit { await Task.yield() }
        XCTAssertFalse(uploads.isWorking)
    }
}

private final class MemoryAuthStore: NSObject, AuthSessionStore {
    var session: AuthSession?
    var saves = 0
    var failRemoval = false
    var removalError: Error?
    func save(authSession: AuthSession) throws { session = authSession; saves += 1 }
    func retrieveAuthSession() throws -> AuthSession {
        guard let session else { throw KeychainStore.Error.passwordNotFound(forItemName: "test") }
        return session
    }
    func removeAuthSession() throws {
        if let removalError { throw removalError }
        if failRemoval { throw NSError(domain: "test", code: 1) }
        session = nil
    }
}

private final class FakeBrowserFlow: NSObject, OIDExternalUserAgentSession {
    var canceled = false
    var resumes = 0
    var error: Error?
    func cancel() { canceled = true }
    func cancel(completion: (() -> Void)?) { cancel(); completion?() }
    func resumeExternalUserAgentFlow(with url: URL) -> Bool { resumes += 1; return true }
    func failExternalUserAgentFlowWithError(_ error: Error) { self.error = error }
}
