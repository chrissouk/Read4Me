import XCTest
import AVFoundation
import UIKit
@testable import Read4Me

@MainActor
final class OpenAISpeechTests: XCTestCase {
    private var session: URLSession!
    private var root: URL!

    override func setUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechRequestStub.self]
        session = URLSession(configuration: configuration)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        SpeechRequestStub.handler = nil
        try FileManager.default.removeItem(at: root)
    }

    func testSpeechRequestMatchesPythonDefaultsAndSavesAudio() async throws {
        SpeechRequestStub.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(request.httpBody)
            let payload = try JSONDecoder().decode(SpeechPayload.self, from: body)
            XCTAssertEqual(payload.model, "gpt-4o-mini-tts")
            XCTAssertEqual(payload.voice, "onyx")
            XCTAssertEqual(payload.instructions, "be fluent & clear, like a podcast narrator")
            XCTAssertEqual(payload.response_format, "mp3")
            XCTAssertEqual(payload.input, "Read this passage.")
            return (200, Self.audioFixture())
        }
        let destination = root.appendingPathComponent("speech.mp3")
        try await SpeechWriter(session: session).write("Read this passage.", configuration: SpeechConfiguration(),
                                                       apiKey: "test-key", to: destination)
        XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: destination).duration, 0)
    }

    func testRejectedKeyDoesNotSaveResponseOrExposeKey() async throws {
        SpeechRequestStub.handler = { _ in (401, Data("test-key must never appear in errors".utf8)) }
        let destination = root.appendingPathComponent("speech.mp3")
        do {
            try await SpeechWriter(session: session).write("Read this.", configuration: SpeechConfiguration(),
                                                           apiKey: "test-key", to: destination)
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API key"))
            XCTAssertFalse(error.localizedDescription.contains("test-key"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testMissingKeyStopsBeforeNetworkOrConversionMetadata() async throws {
        SpeechRequestStub.handler = { _ in XCTFail("Missing keys must not send requests"); return (200, Data()) }
        let library = LibraryStore(root: root.appendingPathComponent("Library"))
        let id = try importBook(library)
        let converter = ConversionController(library: library, apiKeys: TestAPIKey(key: nil), writer: SpeechWriter(session: session))
        await converter.generate(id, configuration: SpeechConfiguration())
        XCTAssertTrue(try XCTUnwrap(library.book(id)).chunks.isEmpty)
        XCTAssertTrue(library.error?.contains("Settings") == true)
    }

    func testRetryKeepsSavedChunksAndOriginalNarrationConfiguration() async throws {
        let library = LibraryStore(root: root.appendingPathComponent("Library"))
        let id = try importBook(library)
        var book = try XCTUnwrap(library.book(id))
        book.text = String(repeating: "a", count: 3501)
        try library.update(book)
        var requests = 0
        SpeechRequestStub.handler = { _ in
            requests += 1
            if requests == 2 { return (429, Data()) }
            return (200, Self.audioFixture())
        }
        let converter = ConversionController(library: library, apiKeys: TestAPIKey(key: "test-key"), writer: SpeechWriter(session: session))
        await converter.generate(id, configuration: SpeechConfiguration())
        let interrupted = try XCTUnwrap(library.book(id))
        XCTAssertEqual(interrupted.completedCount, 1)
        XCTAssertNotNil(interrupted.conversionError)
        let firstURL = library.audioURL(for: id, chunk: 0)
        XCTAssertEqual(firstURL.pathExtension, "mp3")
        let firstData = try Data(contentsOf: firstURL)
        let modified = try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        SpeechRequestStub.handler = { request in
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertEqual(try JSONDecoder().decode(SpeechPayload.self, from: body).voice, "onyx")
            requests += 1
            return (200, Self.audioFixture())
        }
        var changed = SpeechConfiguration()
        changed.voice = "nova"
        await converter.generate(id, configuration: changed)
        XCTAssertTrue(try XCTUnwrap(library.book(id)).isReady)
        XCTAssertNil(library.book(id)?.conversionError)
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)
        XCTAssertEqual(try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
    }

    func testLegacyNarrationRecreationKeepsPDFAndUsesOpenAIOnly() async throws {
        let library = LibraryStore(root: root.appendingPathComponent("Library"))
        let id = try importBook(library)
        var book = try XCTUnwrap(library.book(id))
        book.voiceIdentifier = "old-apple-voice"
        book.chunks = [AudioChunk(text: book.text, duration: 1, isComplete: true)]
        book.position = 0.5
        try library.update(book)
        let legacyURL = library.audioURL(for: id, chunk: 0)
        try Self.audioFixture().write(to: legacyURL)
        XCTAssertEqual(legacyURL.pathExtension, "caf")
        SpeechRequestStub.handler = { _ in (200, Self.audioFixture()) }
        let converter = ConversionController(library: library, apiKeys: TestAPIKey(key: "test-key"), writer: SpeechWriter(session: session))
        await converter.recreate(id, configuration: SpeechConfiguration())
        let recreated = try XCTUnwrap(library.book(id))
        XCTAssertTrue(recreated.isReady)
        XCTAssertEqual(recreated.speechConfiguration?.voice, "onyx")
        XCTAssertEqual(recreated.position, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder(for: id).appendingPathComponent("source.pdf").path))
        let restored = LibraryStore(root: library.root)
        XCTAssertEqual(restored.book(id)?.speechConfiguration, SpeechConfiguration())
        XCTAssertEqual(restored.audioURL(for: id, chunk: 0).pathExtension, "mp3")
    }

    func testAPIKeyIsSavedReplacedAndRemovedFromKeychain() throws {
        let service = "Read4Me-tests-\(UUID().uuidString)"
        let keys = APIKeyStore(service: service)
        defer { try? keys.remove() }
        XCTAssertFalse(keys.hasKey)
        try keys.save("  test-key-one \n")
        XCTAssertEqual(try keys.load(), "test-key-one")
        XCTAssertTrue(APIKeyStore(service: service).hasKey)
        try keys.save("test-key-two")
        XCTAssertEqual(try APIKeyStore(service: service).load(), "test-key-two")
        try keys.remove()
        XCTAssertNil(try keys.load())
        XCTAssertFalse(keys.hasKey)
    }

    private func importBook(_ library: LibraryStore) throws -> UUID {
        let url = root.appendingPathComponent("Test.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("Read this passage." as NSString).draw(at: CGPoint(x: 20, y: 20))
        }
        return try library.importPDF(url)
    }

    nonisolated private static func audioFixture() -> Data {
        // A short silent MP3 validates actual decoding without paid API requests.
        let encoded = """
//NAxAAAAANIAAAAAExBTUUzLjEwMFVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/80LEWwAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/80DEpAAAA0gAAAAAVVVV
VVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVf/zQsSjAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/zQMSkAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVV
TEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NC
xKMAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NAxKQAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/80LEowAAA0gAAAAAVVVVVVVV
VVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVX/80DEpAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/zQsSjAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVUxB
TUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/zQMSk
AAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NCxKMAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
"""
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)!
    }
}

@MainActor
private struct TestAPIKey: APIKeyProviding {
    let key: String?
    func load() throws -> String? { key }
}

private struct SpeechPayload: Decodable {
    let model: String
    let voice: String
    let instructions: String
    let input: String
    let response_format: String
}

private final class SpeechRequestStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
                captured.httpBody = body
            }
            let (status, data) = try handler(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "audio/mpeg"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
