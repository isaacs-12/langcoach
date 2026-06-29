import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(Coach.self) private var coach
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]

    @State private var selection: StudyDocument?
    @State private var importing = false
    @State private var importError: String?
    @State private var extracting: StudyDocument?
    /// IDs of documents currently having their study memory distilled.
    @State private var distilling: Set<PersistentIdentifier> = []

    var body: some View {
        Group {
            if documents.isEmpty {
                CalloutView(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Import your class notes",
                    message: "Export your Korean lessons from Google Docs (File ▸ Download ▸ .docx, PDF, or plain text) and import them here. The text is stored locally so you can study offline.",
                    actionTitle: "Import notes…",
                    action: { importing = true }
                )
            } else {
                HSplitView {
                    docList
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    docDetail
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importing = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .help("Import notes from your file system")
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: DocumentImporter.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Import problem", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $extracting) { doc in
            VocabExtractionSheet(document: doc)
        }
    }

    private var docList: some View {
        List(selection: $selection) {
            ForEach(documents) { doc in
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(doc.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(doc.wordCount) words · \(doc.importedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .tag(doc)
                .contextMenu {
                    Button(role: .destructive) {
                        delete(doc)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteAt)
        }
    }

    @ViewBuilder
    private var docDetail: some View {
        if let doc = selection ?? documents.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title).font(.title2.bold())
                        Text(doc.sourceFilename).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        extracting = doc
                    } label: {
                        Label("Extract vocab", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        memorySection(for: doc)
                        Text(doc.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
        } else {
            CalloutView(
                systemImage: "doc.text",
                title: "No document selected",
                message: "Select a note from the list to read it and pull out vocabulary."
            )
        }
    }

    // MARK: - Study memory

    @ViewBuilder
    private func memorySection(for doc: StudyDocument) -> some View {
        let isDistilling = distilling.contains(doc.persistentModelID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Theme.accent)
                Text("Study memory")
                    .font(.headline)
                Spacer()
                if isDistilling {
                    ProgressView().controlSize(.small)
                } else {
                    Button(doc.hasMemory ? "Regenerate" : "Generate") {
                        distill(doc)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!coach.hasKey)
                }
            }
            if doc.hasMemory {
                Text(doc.studyMemory)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(coach.hasKey
                     ? "A compact summary used for translation and conversation practice. Generated automatically on import."
                     : "Set up an API key to distill this note into practice context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private func distill(_ doc: StudyDocument) {
        let id = doc.persistentModelID
        guard coach.hasKey, !distilling.contains(id) else { return }
        distilling.insert(id)
        let text = doc.text
        Task {
            let memory = try? await coach.distillNotes(text)
            await MainActor.run {
                if let memory, !memory.isEmpty {
                    doc.studyMemory = memory
                    try? context.save()
                }
                distilling.remove(id)
            }
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failures: [String] = []
            var imported: [StudyDocument] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let (title, text) = try DocumentImporter.extract(from: url)
                    let doc = StudyDocument(title: title, sourceFilename: url.lastPathComponent, text: text)
                    context.insert(doc)
                    selection = doc
                    imported.append(doc)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            try? context.save()
            // Distill each new note into a compact study memory in the background.
            if coach.hasKey {
                for doc in imported { distill(doc) }
            }
            if !failures.isEmpty {
                importError = failures.joined(separator: "\n")
            }
        }
    }

    private func delete(_ doc: StudyDocument) {
        if selection == doc { selection = nil }
        context.delete(doc)
        try? context.save()
    }

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets { delete(documents[index]) }
    }
}
