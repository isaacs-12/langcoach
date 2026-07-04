import AppKit
import Foundation
import Observation

/// Checks GitHub for a newer release of the app and, when the user opts in,
/// downloads the release asset, swaps the installed bundle, and relaunches.
///
/// The whole check is a single API call to
/// `GET /repos/{repo}/releases/latest`; the release's `tag_name` (vX.Y.Z, as
/// created by `make release`) is compared against the running app's
/// `CFBundleShortVersionString`.
@Observable
@MainActor
final class UpdateChecker {
    /// GitHub repository the app was released from.
    static let repo = "isaacs-12/langcoach"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed(String)
    }

    var phase: Phase = .idle
    var latest: GitHubRelease?
    /// Drives the update sheet in `ContentView`. Set when an update is found,
    /// or immediately for user-initiated checks (so "checking…"/"up to date"
    /// feedback is visible).
    var showSheet = false

    private static let lastCheckKey = "lastUpdateCheckAt"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Menu item entry point ("Check for Updates…").
    func userRequestedCheck() {
        Task { await check(userInitiated: true) }
    }

    /// Silent check at launch, throttled to roughly once a day. Failures are
    /// swallowed (no network, repo unreachable) — the user never asked.
    func checkAtLaunch() async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 60 * 60 * 20 else { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        if case .downloading = phase { return }
        if case .installing = phase { return }
        phase = .checking
        if userInitiated { showSheet = true }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            latest = release
            if Self.isVersion(release.version, newerThan: currentVersion) {
                phase = .available
                showSheet = true
            } else {
                phase = .upToDate
                if !userInitiated { showSheet = false }
            }
        } catch {
            if userInitiated {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .idle
                showSheet = false
            }
        }
    }

    /// Numeric dotted-version comparison; tolerates a leading "v".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let (pa, pb) = (parts(a), parts(b))
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Download & install

    func downloadAndInstall() async {
        guard let release = latest,
              let asset = release.assets.first(where: { $0.name == "LangCoach.zip" })
                ?? release.assets.first(where: { $0.name.hasSuffix(".zip") })
        else {
            phase = .failed("This release has no downloadable app archive. Use “View on GitHub” instead.")
            return
        }
        phase = .downloading
        do {
            let (zipURL, _) = try await URLSession.shared.download(from: asset.browserDownloadURL)
            phase = .installing
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("LangCoachUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Self.unzip(zipURL, to: staging)
            let newApp = staging.appendingPathComponent("LangCoach.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.missingApp
            }
            try installAndRelaunch(newApp: newApp)
        } catch let error as UpdateError where error == .cancelled {
            phase = .available
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func unzip(_ zip: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unzipFailed }
    }

    private func installAndRelaunch(newApp: URL) throws {
        let currentApp = Bundle.main.bundleURL
        let installDir = currentApp.deletingLastPathComponent()
        do {
            try Self.swap(newApp: newApp, currentApp: currentApp)
        } catch {
            // Sandbox blocked the write (typical when installed in
            // /Applications). One folder pick grants user-selected read-write
            // access and the swap goes through.
            try promptForInstallAccess(to: installDir)
            try Self.swap(newApp: newApp, currentApp: currentApp)
        }
        relaunch(at: currentApp)
    }

    /// Replace the running bundle in place. Renaming the running app is safe —
    /// the process keeps its open files — so: move the old bundle aside, copy
    /// the new one in, then discard the old.
    private static func swap(newApp: URL, currentApp: URL) throws {
        let fm = FileManager.default
        let backup = currentApp.deletingLastPathComponent()
            .appendingPathComponent(".LangCoach-old-\(ProcessInfo.processInfo.processIdentifier).app")
        try fm.moveItem(at: currentApp, to: backup)
        do {
            try fm.copyItem(at: newApp, to: currentApp)
        } catch {
            try? fm.moveItem(at: backup, to: currentApp)
            throw error
        }
        try? fm.trashItem(at: backup, resultingItemURL: nil)
        try? fm.removeItem(at: backup)
    }

    private func promptForInstallAccess(to installDir: URL) throws {
        let panel = NSOpenPanel()
        panel.message = "To install the update, allow Lang Coach to write to the folder it's installed in (\(installDir.path))."
        panel.prompt = "Install Update"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = installDir
        guard panel.runModal() == .OK, let chosen = panel.url else {
            throw UpdateError.cancelled
        }
        guard chosen.standardizedFileURL.path == installDir.standardizedFileURL.path else {
            throw UpdateError.wrongFolder(installDir.path)
        }
    }

    private func relaunch(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        // Terminate even if the open callback never fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}

enum UpdateError: LocalizedError, Equatable {
    case badStatus(Int)
    case unzipFailed
    case missingApp
    case cancelled
    case wrongFolder(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return code == 404
                ? "No releases have been published yet."
                : "GitHub returned an unexpected response (HTTP \(code))."
        case .unzipFailed: return "Couldn't unpack the downloaded update."
        case .missingApp: return "The downloaded archive didn't contain LangCoach.app."
        case .cancelled: return "Update cancelled."
        case .wrongFolder(let path):
            return "Please select the folder that contains the app (\(path)) so the update can be installed."
        }
    }
}

/// Subset of the GitHub "latest release" payload the updater needs.
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }

    /// "v0.0.3" → "0.0.3"
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}
