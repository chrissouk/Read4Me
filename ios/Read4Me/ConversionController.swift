import AVFoundation
import Combine

@MainActor
final class ConversionController: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var pauseRequested = false
    private let writer = SpeechWriter()
    private let preview = AVSpeechSynthesizer()
    private let library: LibraryStore

    init(library: LibraryStore) { self.library = library }

    func previewVoice(_ identifier: String, text: String) {
        guard activeID == nil, let voice = AVSpeechSynthesisVoice(identifier: identifier) else { return }
        preview.stopSpeaking(at: .immediate)
        let sample = AVSpeechUtterance(string: String(text.prefix(300)))
        sample.voice = voice
        preview.speak(sample)
    }

    func requestPause() { pauseRequested = true }

    func generate(_ id: UUID, voiceIdentifier: String) async {
        guard activeID == nil, var book = library.book(id) else { return }
        preview.stopSpeaking(at: .immediate)
        activeID = id
        pauseRequested = false
        defer { activeID = nil }
        do {
            if book.chunks.isEmpty {
                book.chunks = TextChunker.split(book.text).map { AudioChunk(text: $0) }
                book.voiceIdentifier = voiceIdentifier
            }
            guard let voice = book.voiceIdentifier else { throw LibraryError.noVoice }
            book.conversionError = nil
            try library.update(book)
            for index in book.chunks.indices {
                if pauseRequested || Task.isCancelled { break }
                let destination = library.audioURL(for: id, chunk: index)
                if book.chunks[index].isComplete,
                   let audio = try? AVAudioPlayer(contentsOf: destination), audio.duration > 0 {
                    continue
                }
                let temporary = destination.deletingPathExtension().appendingPathExtension("partial.caf")
                try? FileManager.default.removeItem(at: temporary)
                try await writer.write(book.chunks[index].text, voiceIdentifier: voice, to: temporary)
                let audio = try AVAudioPlayer(contentsOf: temporary)
                guard audio.duration > 0 else { throw LibraryError.emptyAudio }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                // Preserve player updates made while this chunk was generating.
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
