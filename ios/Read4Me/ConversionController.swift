import AVFoundation
import Combine

@MainActor
final class ConversionController: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var pauseRequested = false
    private let writer: SpeechWriter
    private let apiKeys: any APIKeyProviding
    private let library: LibraryStore

    init(library: LibraryStore, apiKeys: any APIKeyProviding, writer: SpeechWriter = SpeechWriter()) {
        self.library = library
        self.apiKeys = apiKeys
        self.writer = writer
    }

    func requestPause() { pauseRequested = true }

    func recreate(_ id: UUID, configuration: SpeechConfiguration) async {
        guard activeID == nil else { return }
        do {
            guard let key = try apiKeys.load(), !key.isEmpty else { throw SpeechError.missingKey }
            try library.resetConversion(id)
        } catch { library.error = error.localizedDescription; return }
        await generate(id, configuration: configuration)
    }

    func generate(_ id: UUID, configuration: SpeechConfiguration) async {
        guard activeID == nil, var book = library.book(id) else { return }
        activeID = id
        pauseRequested = false
        defer { activeID = nil }
        do {
            guard let key = try apiKeys.load(), !key.isEmpty else { throw SpeechError.missingKey }
            if book.chunks.isEmpty {
                book.chunks = TextChunker.split(book.text, limit: 3500).map { AudioChunk(text: $0) }
                book.speechConfiguration = configuration
            }
            guard let savedConfiguration = book.speechConfiguration else { throw SpeechError.legacyConversion }
            book.conversionError = nil
            try library.update(book)
            for index in book.chunks.indices {
                if pauseRequested || Task.isCancelled { break }
                let destination = library.audioURL(for: id, chunk: index)
                if book.chunks[index].isComplete,
                   let audio = try? AVAudioPlayer(contentsOf: destination), audio.duration > 0 {
                    continue
                }
                let temporary = destination.deletingPathExtension().appendingPathExtension("partial.mp3")
                try? FileManager.default.removeItem(at: temporary)
                try await writer.write(book.chunks[index].text, configuration: savedConfiguration,
                                       apiKey: key, to: temporary)
                let audio = try AVAudioPlayer(contentsOf: temporary)
                guard audio.duration > 0 else { throw LibraryError.emptyAudio }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                guard var latest = library.book(id) else { return }
                latest.chunks = book.chunks
                latest.chunks[index].duration = audio.duration
                latest.chunks[index].isComplete = true
                try library.update(latest)
                book = latest
            }
        } catch {
            if var latest = library.book(id) {
                latest.conversionError = error.localizedDescription
                do { try library.update(latest) }
                catch { library.error = error.localizedDescription }
            }
            library.error = error.localizedDescription
        }
    }
}
