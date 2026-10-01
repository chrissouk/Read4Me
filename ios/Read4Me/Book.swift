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

    var duration: TimeInterval { chunks.reduce(0) { $0 + $1.duration } }
    var completedCount: Int { chunks.filter(\.isComplete).count }
    var isReady: Bool { !chunks.isEmpty && completedCount == chunks.count }
}

enum TextChunker {
    // Character-based boundaries also handle long sentences and unbroken words.
    static func split(_ text: String, limit: Int = 1800) -> [String] {
        precondition(limit > 0)
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var chunks: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: limit, limitedBy: remaining.endIndex) ?? remaining.endIndex
            var boundary = end
            if end != remaining.endIndex {
                let candidate = remaining[..<end]
                if let space = candidate.lastIndex(where: { $0.isWhitespace }), space != remaining.startIndex {
                    boundary = space
                }
            }
            chunks.append(String(remaining[..<boundary]))
            remaining = String(remaining[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return chunks
    }
}
