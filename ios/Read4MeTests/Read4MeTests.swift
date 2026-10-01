import XCTest
import PDFKit
import UIKit
import AVFoundation
@testable import Read4Me

final class Read4MeTests: XCTestCase {
    func testLongSentenceAndWordStayWithinLimit() {
        let text = String(repeating: "a", count: 4700)
        let chunks = TextChunker.split(text, limit: 1800)
        XCTAssertEqual(chunks.map(\.count), [1800, 1800, 1100])
        XCTAssertEqual(chunks.joined(), text)
    }

    func testSentenceBoundariesMatchPythonAndRespectDefaultLimit() {
        XCTAssertEqual(TextChunker.split("One sentence. Another one! Last?", limit: 26),
                       ["One sentence. Another one!", "Last?"])
        XCTAssertEqual(TextChunker.split(String(repeating: "x", count: 3501)).map(\.count), [3500, 1])
    }

    func testWhitespaceUnicodeAndEmptyText() {
        XCTAssertEqual(TextChunker.split(" \n\t "), [])
        let text = String(repeating: "👩🏽‍🚀 reading café. ", count: 100)
        let chunks = TextChunker.split(text, limit: 40)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 40 })
        let words = chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(words, text.split(whereSeparator: \.isWhitespace))
    }

    @MainActor
    func testSameNamedImportsPersistIndependentlyAndRestorePosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Sample.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("An audiobook test document" as NSString).draw(at: CGPoint(x: 20, y: 20),
                                                          withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        let storage = root.appendingPathComponent("Library")
        let library = LibraryStore(root: storage)
        let first = try library.importPDF(url)
        let second = try library.importPDF(url)
        XCTAssertNotEqual(first, second)
        var book = try XCTUnwrap(library.book(first))
        book.chunks = [AudioChunk(text: book.text, duration: 120, isComplete: true)]
        book.position = 42
        book.speed = 1.5
        try library.update(book)
        let restored = LibraryStore(root: storage)
        XCTAssertEqual(restored.books.count, 2)
        XCTAssertEqual(restored.book(first)?.position, 42)
        XCTAssertEqual(restored.book(first)?.speed, 1.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.folder(for: first).appendingPathComponent("source.pdf").path))
        try restored.delete(first)
        XCTAssertEqual(LibraryStore(root: storage).books.map(\.id), [second])
    }

    @MainActor
    func testScannedPDFIsRejectedWithoutCreatingBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Blank.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        try renderer.writePDF(to: url) { $0.beginPage() }
        let library = LibraryStore(root: root.appendingPathComponent("Library"))
        XCTAssertThrowsError(try library.importPDF(url))
        XCTAssertTrue(library.books.isEmpty)
    }
    @MainActor
    func testSavedAudioPlayerRestoresSpeedAndPositionAcrossChunks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdfURL = root.appendingPathComponent("Player.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        try renderer.writePDF(to: pdfURL) { context in
            context.beginPage()
            ("Player fixture" as NSString).draw(at: CGPoint(x: 10, y: 10))
        }
        let storage = root.appendingPathComponent("Library")
        let library = LibraryStore(root: storage)
        let id = try library.importPDF(pdfURL)
        var book = try XCTUnwrap(library.book(id))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050 * 10))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
        for index in 0..<2 {
            let file = try AVAudioFile(forWriting: library.audioURL(for: id, chunk: index), settings: format.settings)
            try file.write(from: buffer)
        }
        book.chunks = [AudioChunk(text: "one", duration: 10, isComplete: true),
                       AudioChunk(text: "two", duration: 10, isComplete: true)]
        try library.update(book)
        let player = PlayerController(library: library)
        player.load(id)
        player.seek(12)
        player.setSpeed(1.5)
        let restored = PlayerController(library: LibraryStore(root: storage))
        XCTAssertEqual(restored.bookID, id)
        XCTAssertEqual(restored.position, 12, accuracy: 0.05)
        XCTAssertEqual(restored.speed, 1.5)
        restored.skip(-15)
        XCTAssertEqual(restored.position, 0)
        restored.skip(30)
        XCTAssertEqual(restored.position, 20)
        restored.clear()
        player.clear()
    }

}
