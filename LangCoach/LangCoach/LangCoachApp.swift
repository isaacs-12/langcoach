import SwiftUI
import SwiftData

@main
struct LangCoachApp: App {
    let container: ModelContainer
    @State private var coach: Coach
    @State private var googleAuth: GoogleAuth
    @State private var folderManager: NotesFolderManager
    @State private var updater = UpdateChecker()

    init() {
        let schema = Schema([
            StudyDocument.self,
            NoteFolder.self,
            Deck.self,
            Flashcard.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.container = container
        let coach = Coach()
        _coach = State(initialValue: coach)
        let googleAuth = GoogleAuth()
        _googleAuth = State(initialValue: googleAuth)
        _folderManager = State(initialValue: NotesFolderManager(container: container, coach: coach, googleAuth: googleAuth))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coach)
                .environment(googleAuth)
                .environment(folderManager)
                .environment(updater)
                .task { googleAuth.start(); folderManager.start() }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        // Open large and only slightly wide — closer to square than the old default.
        .defaultSize(width: 1240, height: 940)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Lang Coach") { AboutPanel.show() }
                Button("Check for Updates…") { updater.userRequestedCheck() }
            }
        }

        // A standalone reader window for a single note, opened from the Library
        // with `openWindow(id: "note-reader", value: <persistentModelID>)`. Keyed
        // on the note's identifier so re-opening the same note reuses its window.
        WindowGroup(id: "note-reader", for: PersistentIdentifier.self) { $documentID in
            if let documentID {
                NoteReaderView(documentID: documentID)
                    .environment(coach)
                    .environment(googleAuth)
                    .environment(folderManager)
            }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        // Portrait, page-like proportions rather than a wide slab.
        .defaultSize(width: 700, height: 880)

        // A focused review window for one lesson, opened from the Library with
        // `openWindow(id: "lesson-review", value: <persistentModelID>)`. Keyed on
        // the lesson's identifier so re-opening the same lesson reuses its window.
        WindowGroup(id: "lesson-review", for: PersistentIdentifier.self) { $documentID in
            if let documentID {
                TargetedReviewView(documentID: documentID)
                    .environment(coach)
            }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 760)

        Settings {
            SettingsView()
                .environment(coach)
                .environment(googleAuth)
        }
    }
}

/// The standard macOS About panel, with a small credits blurb. Version and
/// copyright come from the bundle (MARKETING_VERSION /
/// NSHumanReadableCopyright build settings).
@MainActor
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSMutableAttributedString(
            string: "A local-first Korean study companion built around your own class notes.\nMade by Isaac Smith\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        credits.append(NSAttributedString(
            string: "github.com/\(UpdateChecker.repo)",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: URL(string: "https://github.com/\(UpdateChecker.repo)")!,
                .paragraphStyle: paragraph,
            ]
        ))
        NSApp.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
