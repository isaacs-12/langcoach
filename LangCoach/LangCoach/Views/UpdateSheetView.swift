import SwiftUI

/// Sheet shown when a newer release is available (or while a user-initiated
/// check runs). Presented from `ContentView`, driven by `UpdateChecker`.
struct UpdateSheetView: View {
    @Environment(UpdateChecker.self) private var updater
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            switch updater.phase {
            case .idle, .checking:
                ProgressView()
                Text("Checking for updates…")
                    .foregroundStyle(.secondary)

            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.success)
                Text("You're up to date").font(.title3.bold())
                Text("Lang Coach \(updater.currentVersion) is the latest version.")
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .available:
                availableContent

            case .downloading:
                ProgressView()
                Text("Downloading update…")
                    .foregroundStyle(.secondary)

            case .installing:
                ProgressView()
                Text("Installing… the app will relaunch automatically.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.warning)
                Text("Update problem").font(.title3.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    if let url = updater.latest?.htmlURL {
                        Button("View on GitHub") { openURL(url) }
                    }
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 440)
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private var availableContent: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 56, height: 56)
                .overlay(Text("한").font(.title.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available").font(.title3.bold())
                Text("Lang Coach \(updater.latest?.version ?? "?") — you have \(updater.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        if let notes = updater.latest?.body, !notes.isEmpty {
            ScrollView {
                Text(notes)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }

        HStack {
            if let url = updater.latest?.htmlURL {
                Button("View on GitHub") { openURL(url) }
            }
            Spacer()
            Button("Later") { dismiss() }
            Button("Install Update") {
                Task { await updater.downloadAndInstall() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}
