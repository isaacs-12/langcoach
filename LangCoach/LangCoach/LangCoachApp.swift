import SwiftUI
import SwiftData

@main
struct LangCoachApp: App {
    let container: ModelContainer
    @State private var coach = Coach()

    init() {
        let schema = Schema([
            StudyDocument.self,
            Deck.self,
            Flashcard.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coach)
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(coach)
        }
    }
}
