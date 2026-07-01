import Foundation
import AuthenticationServices
import CryptoKit
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Google sign-in for reading private Google Docs from Drive.
///
/// Uses the OAuth 2.0 *Authorization Code + PKCE* flow for native apps via
/// `ASWebAuthenticationSession` (the same API on macOS and iOS), so this type is
/// portable to a future iOS target unchanged. The long-lived **refresh token** is
/// stored in the Keychain; the short-lived access token lives only in memory and
/// is refreshed on demand.
@MainActor
@Observable
final class GoogleAuth: NSObject {

    private static let refreshAccount = "google.refreshToken"
    private static let emailDefaultsKey = "googleEmail"

    /// Whether a refresh token is on hand (so we can mint access tokens silently).
    private(set) var isSignedIn = false
    /// Connected account's email, when known — for display only.
    private(set) var email: String?

    /// In-memory access token and its expiry. Never persisted.
    private var accessToken: String?
    private var accessTokenExpiry: Date?

    /// Retains the in-flight auth session for the duration of the flow.
    private var session: ASWebAuthenticationSession?

    var isConfigured: Bool { GoogleAuthConfig.isConfigured }

    /// Nonisolated so it can be constructed from `App.init`, matching
    /// `NotesFolderManager`. Persisted state is loaded later in `start()`.
    nonisolated override init() {
        super.init()
    }

    /// Hydrate sign-in state from the Keychain. Call once after launch from the
    /// main actor (alongside `NotesFolderManager.start()`).
    func start() {
        isSignedIn = Keychain.get(account: Self.refreshAccount) != nil
        email = UserDefaults.standard.string(forKey: Self.emailDefaultsKey)
    }

    // MARK: - Public API

    /// Present Google's sign-in UI and exchange the result for tokens. Throws on
    /// cancellation or failure.
    func signIn() async throws {
        guard GoogleAuthConfig.isConfigured else { throw GoogleAuthError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(url: GoogleAuthConfig.authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Request a refresh token, and re-consent so one is always returned.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let callback = try await authenticate(url: components.url!)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noAuthorizationCode
        }
        try await exchangeCode(code, verifier: verifier)
    }

    /// Forget the account. Best-effort revokes the refresh token with Google.
    func signOut() {
        let refresh = Keychain.get(account: Self.refreshAccount)
        accessToken = nil
        accessTokenExpiry = nil
        Keychain.delete(account: Self.refreshAccount)
        UserDefaults.standard.removeObject(forKey: Self.emailDefaultsKey)
        email = nil
        isSignedIn = false
        if let refresh { Task { await Self.revoke(refresh) } }
    }

    /// A valid access token, refreshing if the cached one is missing or near
    /// expiry. Returns nil when not signed in or refresh fails.
    func validAccessToken() async -> String? {
        if let accessToken, let accessTokenExpiry, accessTokenExpiry.timeIntervalSinceNow > 60 {
            return accessToken
        }
        guard let refresh = Keychain.get(account: Self.refreshAccount) else {
            isSignedIn = false
            return nil
        }
        do {
            try await refreshTokens(using: refresh)
            return accessToken
        } catch {
            // A revoked / expired refresh token means we're effectively signed
            // out; surface that so the UI can prompt re-auth.
            if case GoogleAuthError.refreshRejected = error {
                Keychain.delete(account: Self.refreshAccount)
                isSignedIn = false
            }
            return nil
        }
    }

    // MARK: - Authorization session

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleAuthConfig.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Reuse the browser's Google session so sign-in is usually one click.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleAuthError.cannotStart)
            }
        }
    }

    // MARK: - Token endpoint

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let id_token: String?
        /// Space-separated list of scopes actually granted (may be narrower than
        /// requested if the user unchecked a permission).
        let scope: String?
    }

    private static let driveScope = "https://www.googleapis.com/auth/drive.readonly"

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let token = try await postToken([
            "client_id": GoogleAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleAuthConfig.redirectURI,
        ])
        // Fail loudly at sign-in if Drive access wasn't granted, rather than 403ing
        // on every file later. Don't persist the useless grant.
        let granted = Set((token.scope ?? "").split(separator: " ").map(String.init))
        guard granted.contains(Self.driveScope) else {
            throw GoogleAuthError.driveScopeMissing(token.scope ?? "(none)")
        }
        if let refresh = token.refresh_token {
            Keychain.set(refresh, account: Self.refreshAccount)
        }
        applyAccessToken(token)
        isSignedIn = true
        if let idToken = token.id_token, let parsed = Self.email(fromIDToken: idToken) {
            email = parsed
            UserDefaults.standard.set(parsed, forKey: Self.emailDefaultsKey)
        }
    }

    private func refreshTokens(using refreshToken: String) async throws {
        let token = try await postToken([
            "client_id": GoogleAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        applyAccessToken(token)
        isSignedIn = true
    }

    private func applyAccessToken(_ token: TokenResponse) {
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(token.expires_in)
    }

    private func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAuthError.network }
        guard http.statusCode == 200 else {
            // 400/401 from the token endpoint on a refresh means the grant is dead.
            if fields["grant_type"] == "refresh_token" { throw GoogleAuthError.refreshRejected }
            let detail = String(data: data, encoding: .utf8) ?? "\(http.statusCode)"
            throw GoogleAuthError.tokenExchange(detail)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func revoke(_ token: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - PKCE & helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formURLEncoded(_ fields: [String: String]) -> Data {
        // Unreserved characters per RFC 3986; everything else is percent-encoded,
        // which is what `application/x-www-form-urlencoded` requires (so `:` and
        // `/` in redirect_uri become %3A / %2F).
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    /// Pulls `email` out of an OpenID Connect ID token (a JWT) without verifying
    /// the signature — it came straight from Google's token endpoint over TLS, and
    /// it's used for display only.
    private static func email(fromIDToken idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2, let payload = Data(base64URLEncoded: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String
    }
}

// MARK: - Presentation anchor

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case cannotStart
    case noAuthorizationCode
    case network
    case tokenExchange(String)
    case refreshRejected
    case driveScopeMissing(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google sign-in isn't configured. Add an OAuth client ID in GoogleAuthConfig."
        case .cancelled:
            return "Google sign-in was cancelled."
        case .cannotStart:
            return "Couldn't start the Google sign-in window."
        case .noAuthorizationCode:
            return "Google didn't return an authorization code."
        case .network:
            return "Network error talking to Google."
        case .tokenExchange(let detail):
            return "Google sign-in failed: \(detail)"
        case .refreshRejected:
            return "Your Google session expired. Please sign in again."
        case .driveScopeMissing(let granted):
            return "Google Drive access wasn't granted (Google granted: \(granted)). Sign in again and make sure the “See and download all your Google Drive files” checkbox is turned on."
        }
    }
}

// MARK: - base64url

private extension Data {
    /// RFC 7636 base64url (no padding) — the PKCE / JWT encoding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
