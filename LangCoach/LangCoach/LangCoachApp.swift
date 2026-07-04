import SwiftUI
import SwiftData

@main
struct LangCoachApp: App {
    let container: ModelContainer
    @State private var coach: Coach
    @State private var googleAuth: GoogleAuth
    @State private var folderManager: NotesFolderManager

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
                .task { googleAuth.start(); folderManager.start() }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)

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

        Settings {
            SettingsView()
                .environment(coach)
                .environment(googleAuth)
        }
    }
}
