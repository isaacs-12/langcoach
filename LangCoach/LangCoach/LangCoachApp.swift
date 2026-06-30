import SwiftUI
import SwiftData

@main
struct LangCoachApp: App {
    let container: ModelContainer
    @State private var coach: Coach
    @State private var folderManager: NotesFolderManager

    init() {
        let schema = Schema([
            StudyDocument.self,
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
        _folderManager = State(initialValue: NotesFolderManager(container: container, coach: coach))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coach)
                .environment(folderManager)
                .task { folderManager.start() }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(coach)
        }
    }
}
