import Foundation

/// Configuration for Google sign-in. The only thing you must supply is an OAuth
/// **client ID**; everything else is derived from it.
///
/// ## One-time setup (Google Cloud Console)
/// 1. Create / pick a project at <https://console.cloud.google.com>.
/// 2. APIs & Services ▸ **Enable** the *Google Drive API*.
/// 3. OAuth consent screen ▸ External ▸ add your Google account under *Test
///    users* (so the unverified-app warning doesn't block you).
/// 4. Credentials ▸ Create credentials ▸ **OAuth client ID** ▸ Application type
///    **iOS** ▸ Bundle ID `com.byisaacs.LangCoach`.
/// 5. Copy the generated client ID (it ends in `.apps.googleusercontent.com`)
///    into ``clientID`` below.
///
/// The iOS client type uses **PKCE** with no client secret, so nothing secret is
/// embedded in the app — the same client ID and flow work unchanged when this
/// code is reused in an iOS target.
enum GoogleAuthConfig {

    /// Paste your iOS OAuth client ID here, e.g.
    /// `"1234567890-abcdefg.apps.googleusercontent.com"`. Leave empty to keep
    /// Google sign-in disabled (the app still works; private `.gdoc`s just can't
    /// be fetched).
    static let clientID = "1023774352343-rnk4sprr76b6mjnpfu46pp25r47224vh.apps.googleusercontent.com"

    /// Drive scope (read-only) plus identity scopes so we can show which account
    /// is connected. `drive.readonly` is a *restricted* scope — fine for personal
    /// use / test users; production distribution would need Google verification.
    static let scopes = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/drive.readonly",
    ]

    /// Whether a usable client ID has been supplied.
    static var isConfigured: Bool {
        !clientID.isEmpty && clientID.hasSuffix(".apps.googleusercontent.com")
    }

    /// The reversed-domain form of the client ID, used as the custom URL scheme
    /// for the OAuth redirect — e.g. `com.googleusercontent.apps.1234567890-abcdefg`.
    static var redirectScheme: String {
        let suffix = ".apps.googleusercontent.com"
        let core = clientID.hasSuffix(suffix) ? String(clientID.dropLast(suffix.count)) : clientID
        return "com.googleusercontent.apps.\(core)"
    }

    /// Full redirect URI registered implicitly by the iOS client type.
    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
}
