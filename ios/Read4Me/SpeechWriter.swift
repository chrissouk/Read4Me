import Foundation

struct SpeechConfiguration: Codable, Equatable {
    var model = "gpt-4o-mini-tts"
    var voice = "onyx"
    var instructions = "be fluent & clear, like a podcast narrator"

    static let voices = ["alloy", "ash", "ballad", "coral", "echo", "fable",
                         "nova", "onyx", "sage", "shimmer", "verse"]
}

final class SpeechWriter {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func write(_ text: String, configuration: SpeechConfiguration, apiKey: String, to url: URL) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechRequest(configuration: configuration, input: text))
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SpeechError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 429,
               let failure = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               failure.error.code == "insufficient_quota" {
                throw SpeechError.insufficientQuota
            }
            throw SpeechError.httpStatus(response.statusCode)
        }
        guard !data.isEmpty else { throw SpeechError.invalidResponse }
        try data.write(to: url, options: .atomic)
    }
}

private struct SpeechRequest: Encodable {
    let model: String
    let voice: String
    var instructions: String
    let input: String
    let response_format = "mp3"

    init(configuration: SpeechConfiguration, input: String) {
        model = configuration.model
        voice = configuration.voice
        instructions = configuration.instructions
        if instructions.isEmpty { instructions = SpeechConfiguration().instructions }
        self.input = input
    }
}

private struct APIErrorResponse: Decodable {
    struct Failure: Decodable { let code: String? }
    let error: Failure
}

enum SpeechError: LocalizedError {
    case missingKey, legacyConversion, invalidResponse, insufficientQuota
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings before creating audio."
        case .legacyConversion: return "Use Recreate with OpenAI to replace the previous Apple narration."
        case .invalidResponse: return "OpenAI returned no usable audio. Resume conversion to try again."
        case .insufficientQuota: return "Your OpenAI API account needs available credits. Check API billing, then resume conversion."
        case .httpStatus(401): return "OpenAI rejected your API key. Replace it in Settings, then resume conversion."
        case .httpStatus(403): return "This API key cannot access speech generation. Check its project permissions."
        case .httpStatus(429): return "OpenAI is limiting requests. Wait briefly, then resume conversion."
        case .httpStatus(let status): return "OpenAI could not generate this section (HTTP \(status)). Resume conversion to try again."
        }
    }
}
