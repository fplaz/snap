import AppKit
import Combine
import AppAuth
import AppAuthCore
import GTMAppAuth

@MainActor
final class AccountController: ObservableObject {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"
    typealias Presenter = (OIDAuthorizationRequest, @escaping OIDAuthStateAuthorizationCallback) -> OIDExternalUserAgentSession

    @Published private(set) var id: String?
    @Published private(set) var email: String?
    @Published private(set) var isSigningIn = false
    @Published private(set) var message: String?
    let configured: Bool
    var onChanged: (() -> Void)?
    private let clientID: String
    private let redirectURL: URL?
    private let store: AuthSessionStore
    private let present: Presenter
    private var auth: AuthSession?
    private var flow: OIDExternalUserAgentSession?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    init(bundle: Bundle = .main, store: AuthSessionStore? = nil, present: Presenter? = nil) {
        clientID = bundle.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        redirectURL = URL(string: "\(reversed):/oauthredirect")
        configured = clientID.hasSuffix(".apps.googleusercontent.com") && schemes.contains(reversed) && redirectURL != nil
        // Keep OAuth tokens in macOS Keychain without requiring a provisioning profile.
        self.store = store ?? Self.makeAuthStore()
        self.present = present ?? { request, callback in
            OIDAuthState.authState(byPresenting: request, externalUserAgent: DefaultBrowserAgent(), callback: callback)
        }
        if !configured { message = "Google sign-in is not configured for this build." }
    }

    static func makeAuthStore() -> KeychainStore {
        // Preserve the beta's item name so existing beta users stay signed in.
        return KeychainStore(itemName: "cl.fplaz.snap.private-beta.auth",
                             keychainAttributes: [.useFileBasedKeychain])
    }

    func restore() {
        guard configured, !isSigningIn else { return }
        do { try accept(store.retrieveAuthSession(), persist: false) }
        catch KeychainStore.Error.passwordNotFound { }
        catch { message = "Couldn't restore Google sign-in. Please sign in again." }
    }

    func authorizationRequest() -> OIDAuthorizationRequest? {
        guard configured, let redirectURL else { return nil }
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        return OIDAuthorizationRequest(configuration: configuration, clientId: clientID,
            scopes: ["openid", "email", "profile", Self.driveScope], redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline", "prompt": "select_account consent"])
    }

    func signIn() {
        guard !isSigningIn, let request = authorizationRequest() else { return }
        generation = UUID(); let run = generation
        isSigningIn = true; message = nil
        flow = present(request) { [weak self] state, error in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                self.timeout?.cancel(); self.timeout = nil; self.flow = nil; self.isSigningIn = false
                guard let state, error == nil else {
                    self.message = "Google sign-in wasn't completed. Please try again."
                    return
                }
                do { try self.accept(AuthSession(authState: state), persist: true) }
                catch { self.message = "Couldn't finish Google sign-in or save it in Keychain. Please try again." }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(600)) } catch { return }
            guard let self, self.generation == run else { return }
            self.cancelSignIn()
            self.message = "Google sign-in timed out. Please try again."
        }
    }

    func cancelSignIn() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        let active = flow; flow = nil; isSigningIn = false
        active?.cancel()
        message = nil
    }

    private func accept(_ session: AuthSession, persist: Bool) throws {
        guard session.authState.isAuthorized,
              session.authState.lastAuthorizationResponse.request.clientID == clientID,
              let userID = session.userID, !userID.isEmpty,
              session.authState.scope?.split(separator: " ").contains(Substring(Self.driveScope)) == true else {
            throw CloudError.signedOut
        }
        if persist { try store.save(authSession: session) }
        auth = session; id = userID; email = session.userEmail; message = nil
        onChanged?()
    }

    func signOut() {
        cancelSignIn()
        // If deletion fails, keep the visible account so it cannot silently return after relaunch.
        do { try store.removeAuthSession() }
        catch {
            // AuthSessionStore's Objective-C interface bridges Swift errors to NSError.
            let failure = error as NSError
            let missing = failure.domain == KeychainStore.Error.errorDomain &&
                (failure.code == KeychainStore.ErrorCode.passwordNotFound.rawValue ||
                 failure.code == KeychainStore.ErrorCode.failedToDeletePasswordBecauseItemNotFound.rawValue)
            guard missing else {
                message = "Couldn't remove Google sign-in from Keychain. Please try again."; return
            }
        }
        auth = nil; id = nil; email = nil; message = nil; onChanged?()
    }

    func accessToken(account: String) async throws -> String {
        guard id == account, let auth, auth.userID == account else { throw CloudError.signedOut }
        let run = generation
        let token: String = try await withCheckedThrowingContinuation { continuation in
            auth.authState.performAction { token, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token) }
                else { continuation.resume(throwing: CloudError.signedOut) }
            }
        }
        try Task.checkCancellation()
        guard generation == run, id == account, self.auth === auth else { throw CloudError.signedOut }
        try store.save(authSession: auth)
        return token
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard configured, isSigningIn, let flow, let redirectURL,
              url.scheme == redirectURL.scheme, url.host == redirectURL.host,
              url.path == redirectURL.path else { return false }
        // AppAuth verifies the random state and exchanges the code with the original PKCE verifier.
        // AppAuth 2.1's optional NSError overload crashes this Xcode Swift compiler during codegen.
        // Its required entry point performs the same redirect/state validation.
        return flow.resumeExternalUserAgentFlow(with: url)
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return }
        _ = handle(url)
    }
}

final class DefaultBrowserAgent: NSObject, OIDExternalUserAgent {
    private let open: (URL) -> Bool
    init(open: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.open = open
    }

    func present(_ request: OIDExternalUserAgentRequest, session: OIDExternalUserAgentSession) -> Bool {
        guard let url = request.externalUserAgentRequestURL(),
              url.scheme == "https", url.host == "accounts.google.com", open(url) else {
            session.failExternalUserAgentFlowWithError(NSError(domain: "Snap.GoogleSignIn", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't open the default browser."]))
            return false
        }
        return true
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        completion()
    }
}
