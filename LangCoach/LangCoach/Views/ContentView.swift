import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case flashcards
    case conversation
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .flashcards: return "Flashcards"
        case .conversation: return "Conversation"
        case .translate: return "Translate"
        }
    }

    var subtitle: String {
        switch self {
        case .library: return "Import & manage notes"
        case .flashcards: return "Study vocab with SRS"
        case .conversation: return "Practice speaking"
        case .translate: return "Test your translation"
        }
    }

    var icon: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .flashcards: return "rectangle.on.rectangle.angled.fill"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .translate: return "character.book.closed.fill"
        }
    }
}

struct ContentView: View {
    @Environment(Coach.self) private var coach
    @State private var selection: AppSection? = .library
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            List(selection: $selection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title).font(.body.weight(.medium))
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: section.icon)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            providerFooter
        }
        .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Text("한")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text("Lang Coach").font(.headline)
                Text("Korean").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var providerFooter: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(coach.hasKey ? Theme.success : Theme.warning)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(coach.providerKind.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(coach.hasKey ? coach.model : "No API key — click to set up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .library: LibraryView()
        case .flashcards: FlashcardsView()
        case .conversation: ConversationView()
        case .translate: TranslateView()
        case nil:
            CalloutView(
                systemImage: "sidebar.left",
                title: "Welcome to Lang Coach",
                message: "Pick a section from the sidebar to get started."
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(Coach())
        .modelContainer(for: [StudyDocument.self, Deck.self, Flashcard.self], inMemory: true)
}
