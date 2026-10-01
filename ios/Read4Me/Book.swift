import Foundation

struct AudioChunk: Codable, Equatable {
    let text: String
    var duration: TimeInterval = 0
    var isComplete = false
}

struct Book: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let importedAt: Date
    var text: String
    var chunks: [AudioChunk] = []
    var position: TimeInterval = 0
    var speed: Float = 1
    var voiceIdentifier: String?
    var conversionError: String?
    var speechConfiguration: SpeechConfiguration?

    var duration: TimeInterval { chunks.reduce(0) { $0 + $1.duration } }
    var completedCount: Int { chunks.filter(\.isComplete).count }
    var isReady: Bool { !chunks.isEmpty && completedCount == chunks.count }
}

enum TextChunker {
    // Match the Python sentence boundaries, then split unusually long sentences safely.
    static func split(_ text: String, limit: Int = 3500) -> [String] {
        precondition(limit > 0)
        let source = text as NSString
        let boundaries = try! NSRegularExpression(pattern: "(?<=[.!?])\\s+")
            .matches(in: text, range: NSRange(location: 0, length: source.length))
        var sentences: [String] = []
        var start = 0
        for boundary in boundaries {
            sentences.append(source.substring(with: NSRange(location: start, length: boundary.range.location - start)))
            start = NSMaxRange(boundary.range)
        }
        sentences.append(source.substring(from: start))
        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            for part in boundedParts(sentence, limit: limit) {
                if !current.isEmpty && current.count + 1 + part.count > limit {
                    chunks.append(current)
                    current = ""
                }
                if current.isEmpty { current = part }
                else { current += " " + part }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func boundedParts(_ text: String, limit: Int) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: limit, limitedBy: remaining.endIndex) ?? remaining.endIndex
            var boundary = end
            if end != remaining.endIndex {
                let candidate = remaining[..<end]
                if let space = candidate.lastIndex(where: { $0.isWhitespace }), space != remaining.startIndex {
                    boundary = space
                }
            }
            parts.append(String(remaining[..<boundary]))
            remaining = String(remaining[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts
    }
}
