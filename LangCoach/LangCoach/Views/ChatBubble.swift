import SwiftUI

struct ChatBubble: View {
    let turn: ChatTurn
    var showTranslation: Bool

    var body: some View {
        switch turn.role {
        case .me:
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer(minLength: 60)
                    Text(turn.text)
                        .foregroundStyle(.white)
                        .padding(.vertical, 9).padding(.horizontal, 13)
                        .background(Theme.brandGradient, in: BubbleShape(isMe: true))
                        .textSelection(.enabled)
                }
                if let correction = turn.correction {
                    CorrectionCard(correction: correction)
                        .padding(.leading, 60)
                }
            }
        case .coach:
            HStack(alignment: .top, spacing: 8) {
                coachAvatar
                VStack(alignment: .leading, spacing: 5) {
                    Text(turn.text)
                        .padding(.vertical, 9).padding(.horizontal, 13)
                        .background(.background.secondary, in: BubbleShape(isMe: false))
                        .textSelection(.enabled)
                    if showTranslation, let t = turn.translation, !t.isEmpty {
                        Text(t)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
                Spacer(minLength: 60)
            }
        }
    }

    private var coachAvatar: some View {
        Circle()
            .fill(Theme.brandGradient)
            .frame(width: 28, height: 28)
            .overlay(Text("코").font(.caption.bold()).foregroundStyle(.white))
    }
}

private struct CorrectionCard: View {
    let correction: CorrectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Suggested correction", systemImage: "pencil.and.outline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
            if !correction.corrected.isEmpty {
                Text(correction.corrected)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
            }
            if !correction.note.isEmpty {
                Text(correction.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

struct BubbleShape: Shape {
    var isMe: Bool
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 14, style: .continuous)
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.brandGradient).frame(width: 28, height: 28)
                .overlay(Text("코").font(.caption.bold()).foregroundStyle(.white))
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(.background.secondary, in: Capsule())
            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct APIKeyMissingBanner: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text("Add an AI API key to enable coaching.").font(.callout)
            Spacer()
            Button("Open Settings") { openSettings() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(Theme.warning.opacity(0.12))
    }
}
