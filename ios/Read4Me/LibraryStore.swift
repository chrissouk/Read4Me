import Foundation
import PDFKit
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var error: String?
    let root: URL
    private let manager = FileManager.default

    init(root: URL) {
        self.root = root
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let catalog = root.appendingPathComponent("library.json")
            if manager.fileExists(atPath: catalog.path) {
                books = try JSONDecoder().decode([Book].self, from: Data(contentsOf: catalog))
            }
        } catch {
            self.error = "Could not open your library: \(error.localizedDescription)"
        }
    }

    static func deviceLibrary() -> LibraryStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return LibraryStore(root: documents.appendingPathComponent("Library", isDirectory: true))
    }

    var lastPlayedID: UUID? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("last-played.json")) else { return nil }
        return try? JSONDecoder().decode(UUID.self, from: data)
    }

    func rememberPlayback(_ id: UUID) throws {
        try JSONEncoder().encode(id).write(to: root.appendingPathComponent("last-played.json"), options: .atomic)
    }

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audioURL(for id: UUID, chunk: Int) -> URL {
        var extensionName = "caf"
        if book(id)?.speechConfiguration != nil { extensionName = "mp3" }
        return folder(for: id).appendingPathComponent("chunk-\(chunk).\(extensionName)")
    }
    func book(_ id: UUID) -> Book? { books.first { $0.id == id } }

    func update(_ book: Book) throws {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        var updated = books
        updated[index] = book
        try save(updated)
    }

    func importPDF(_ url: URL) throws -> UUID {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let pdf = PDFDocument(url: url) else {
            throw LibraryError.invalidPDF
        }
        var pages: [String] = []
        for index in 0..<pdf.pageCount {
            if let text = pdf.page(at: index)?.string { pages.append(text) }
        }
        let text = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LibraryError.noText }
        let book = Book(id: UUID(), title: url.deletingPathExtension().lastPathComponent,
                        importedAt: Date(), text: text)
        let directory = folder(for: book.id)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try manager.copyItem(at: url, to: directory.appendingPathComponent("source.pdf"))
            try save([book] + books)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
        return book.id
    }

    func resetConversion(_ id: UUID) throws {
        guard var book = book(id) else { return }
        book.chunks = []
        book.position = 0
        book.speechConfiguration = nil
        book.voiceIdentifier = nil
        book.conversionError = nil
        try update(book)
        for url in try manager.contentsOfDirectory(at: folder(for: id), includingPropertiesForKeys: nil) {
            if url.lastPathComponent.hasPrefix("chunk-") { try manager.removeItem(at: url) }
        }
    }

    func delete(_ id: UUID) throws {
        // Save the catalog first so a deletion never leaves a dangling book entry.
        try save(books.filter { $0.id != id })
        try manager.removeItem(at: folder(for: id))
    }

    private func save(_ updated: [Book]) throws {
        let data = try JSONEncoder().encode(updated)
        try data.write(to: root.appendingPathComponent("library.json"), options: .atomic)
        books = updated
    }
}

enum LibraryError: LocalizedError {
    case invalidPDF, noText, emptyAudio
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "This file could not be opened as a PDF."
        case .noText: return "This PDF has no extractable text. Scanned PDFs need OCR before importing."
        case .emptyAudio: return "OpenAI returned no playable audio. Resume conversion to try again."
        }
    }
}
