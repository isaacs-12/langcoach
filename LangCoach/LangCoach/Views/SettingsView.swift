import SwiftUI

struct SettingsView: View {
    @Environment(Coach.self) private var coach

    var body: some View {
        TabView {
            ProviderSettingsView()
                .tabItem { Label("AI Provider", systemImage: "sparkles") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ProviderSettingsView: View {
    @Environment(Coach.self) private var coach
    @State private var keyInput: String = ""
    @State private var saved = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var coach = coach
        Form {
            Section {
                Picker("Provider", selection: Binding(
                    get: { coach.providerKind },
                    set: { newValue in
                        coach.switchProvider(to: newValue)
                        keyInput = coach.key(for: newValue)
                        saved = false
                    }
                )) {
                    ForEach(LLMProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Picker("Model", selection: $coach.model) {
                    ForEach(coach.providerKind.suggestedModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                    if !coach.providerKind.suggestedModels.contains(coach.model) {
                        Text(coach.model).tag(coach.model)
                    }
                }
            } header: {
                Text("Coaching engine")
            } footer: {
                Text("Lang Coach is fully local except for these AI requests. Your notes and flashcards never leave your Mac unless sent to the model you choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API key") {
                SecureField("Paste your \(coach.providerKind.displayName) key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Get a key…") {
                        if let url = URL(string: coach.providerKind.apiKeyURL) { openURL(url) }
                    }
                    Spacer()
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .font(.caption)
                    }
                    Button("Save key") {
                        coach.setKey(keyInput, for: coach.providerKind)
                        saved = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(coach.hasKey ? Theme.success : Theme.warning)
                        .frame(width: 8, height: 8)
                    Text(coach.hasKey ? "A key is stored in your macOS Keychain." : "No key stored yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { keyInput = coach.key(for: coach.providerKind) }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 72, height: 72)
                .overlay(Text("한").font(.largeTitle.bold()).foregroundStyle(.white))
            Text("Lang Coach").font(.title2.bold())
            Text("A local-first Korean study companion built around your own class notes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
