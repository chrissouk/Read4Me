import AVFoundation

// The synthesizer stays alive for the whole write; buffer handling is serialized.
@MainActor
final class SpeechWriter {
    private let synthesizer = AVSpeechSynthesizer()

    func write(_ text: String, voiceIdentifier: String, to url: URL) async throws {
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) else {
            throw LibraryError.noVoice
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let sink = AudioBufferSink(url: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                sink.receive(buffer, continuation: continuation)
            }
        }
    }
}

private final class AudioBufferSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Read4Me.audio-writer")
    private let url: URL
    private var file: AVAudioFile?
    private var failure: Error?
    private var finished = false

    init(url: URL) { self.url = url }

    func receive(_ buffer: AVAudioBuffer, continuation: CheckedContinuation<Void, Error>) {
        queue.sync {
            guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                finished = true
                let didWrite = file != nil
                file = nil // Close the file before the caller validates or renames it.
                if let failure {
                    continuation.resume(throwing: failure)
                } else if !didWrite {
                    continuation.resume(throwing: LibraryError.emptyAudio)
                } else {
                    continuation.resume()
                }
                return
            }
            guard failure == nil else { return }
            do {
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                           commonFormat: pcm.format.commonFormat,
                                           interleaved: pcm.format.isInterleaved)
                }
                try file?.write(from: pcm)
            } catch {
                failure = error
            }
        }
    }
}
