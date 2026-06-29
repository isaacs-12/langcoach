import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]

    @State private var selection: StudyDocument?
    @State private var importing = false
    @State private var importError: String?
    @State private var extracting: StudyDocument?

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
                    Text(doc.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
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

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let (title, text) = try DocumentImporter.extract(from: url)
                    let doc = StudyDocument(title: title, sourceFilename: url.lastPathComponent, text: text)
                    context.insert(doc)
                    selection = doc
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            try? context.save()
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
