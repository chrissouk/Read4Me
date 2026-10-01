import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var converter: ConversionController
    @ObservedObject var player: PlayerController
    @ObservedObject var apiKeys: APIKeyStore
    @State private var showingSettings = false
    @State private var importing = false
    @State private var path: [UUID] = []
    @State private var pendingDeletion: Book?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("Your documents. Your listening time.")
                        .font(.title2.bold())
                    Text("Import a PDF and turn it into an audiobook using OpenAI narration. Your library and audio stay on this device.")
                        .foregroundStyle(.secondary)
                }
                if library.books.isEmpty {
                    ContentUnavailableView("A little more time to read", systemImage: "headphones",
                                           description: Text("Add your first PDF to start listening."))
                }
                ForEach(library.books) { book in
                    NavigationLink(value: book.id) {
                        HStack(spacing: 16) {
                            Image(systemName: "book.closed.fill").font(.title).foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title).font(.headline)
                                if book.isReady {
                                    Text("\(Duration.seconds(book.position)) of \(Duration.seconds(book.duration))")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else if !book.chunks.isEmpty {
                                    Text("\(book.completedCount) of \(book.chunks.count) sections saved")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Ready to create audio").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                    .swipeActions {
                        if converter.activeID != book.id {
                            Button("Delete", role: .destructive) { pendingDeletion = book }
                        }
                    }
                }
            }
            .navigationTitle("Read4Me")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import PDF", systemImage: "plus") { importing = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                BookView(id: id, library: library, converter: converter, player: player, apiKeys: apiKeys)
            }
            .safeAreaInset(edge: .bottom) {
                if let book = player.currentBook {
                    HStack {
                        Button { path = [book.id] } label: {
                            VStack(alignment: .leading) {
                                Text(book.title).font(.headline).lineLimit(1)
                                Text(Duration.seconds(player.position)).font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(action: player.toggle) {
                            if player.isPlaying { Image(systemName: "pause.fill") }
                            else { Image(systemName: "play.fill") }
                        }.accessibilityLabel("Play or pause")
                    }.padding().background(.regularMaterial)
                }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(apiKeys: apiKeys) }
        .tint(.indigo)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            do {
                let id = try library.importPDF(result.get())
                path.append(id)
            } catch { library.error = error.localizedDescription }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { library.error != nil }, set: { if !$0 { library.error = nil } }
        )) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
        .confirmationDialog("Delete this book and its saved audio?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete book", role: .destructive) {
                guard let book = pendingDeletion else { return }
                if player.bookID == book.id { player.clear() }
                do { try library.delete(book.id) }
                catch { library.error = error.localizedDescription }
                pendingDeletion = nil
            }
        }
    }
}

enum Duration {
    static func seconds(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
