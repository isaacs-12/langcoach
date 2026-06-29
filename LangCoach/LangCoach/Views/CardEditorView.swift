import SwiftUI
import SwiftData

struct CardEditorView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var korean = ""
    @State private var english = ""
    @State private var reading = ""
    @State private var example = ""
    @State private var keepOpen = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New card in \(deck.name)").font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            Form {
                TextField("Korean", text: $korean)
                TextField("English", text: $english)
                TextField("Reading / romanization (optional)", text: $reading)
                TextField("Example sentence (optional)", text: $example, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Toggle("Add another after saving", isOn: $keepOpen)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Done") { dismiss() }
                Button("Save card") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(korean.trimmingCharacters(in: .whitespaces).isEmpty ||
                              english.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
    }

    private func save() {
        let card = Flashcard(
            korean: korean.trimmingCharacters(in: .whitespaces),
            english: english.trimmingCharacters(in: .whitespaces),
            reading: reading.trimmingCharacters(in: .whitespaces),
            example: example.trimmingCharacters(in: .whitespaces),
            deck: deck
        )
        context.insert(card)
        try? context.save()
        if keepOpen {
            korean = ""; english = ""; reading = ""; example = ""
        } else {
            dismiss()
        }
    }
}
