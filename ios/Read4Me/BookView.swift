import SwiftUI
import AVFoundation

struct BookView: View {
    let id: UUID
    @ObservedObject var library: LibraryStore
    @ObservedObject var converter: ConversionController
    @ObservedObject var player: PlayerController
    @State private var draft = ""
    @State private var voiceID = AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
    @State private var showingText = false

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { $0.name < $1.name }
    }

    var body: some View {
        if let book = library.book(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80)).foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity).padding(.top, 24)
                    Text(book.title).font(.largeTitle.bold())
                    Label("Stored on this iPhone", systemImage: "internaldrive").foregroundStyle(.secondary)
                    if book.isReady {
                        PlayerView(id: id, player: player)
                    } else {
                        conversionSection(book)
                    }
                    Button("Preview extracted text", systemImage: "doc.text") {
                        draft = book.text
                        showingText = true
                    }
                    Text("Apple voices generate speech on the device. Listen to a sample before converting a long document. Generation pauses between sections when you leave the app; reopen it and tap Resume.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Audiobook").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingText) {
                NavigationStack {
                    TextEditor(text: $draft).padding()
                        .disabled(!book.chunks.isEmpty)
                        .navigationTitle("Extracted text")
                        .toolbar {
                            Button("Done") {
                                guard book.chunks.isEmpty else { showingText = false; return }
                                guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                    library.error = "Add some text before saving."
                                    return
                                }
                                var updated = book
                                updated.text = draft
                                do { try library.update(updated); showingText = false }
                                catch { library.error = error.localizedDescription }
                            }
                        }
                }
            }
        }
    }

    private func conversionSection(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if book.chunks.isEmpty {
                Picker("Narrator", selection: $voiceID) {
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
                Button("Listen to voice sample", systemImage: "speaker.wave.2") {
                    player.pause()
                    converter.previewVoice(voiceID, text: book.text)
                }.disabled(converter.activeID != nil)
                Text("More voices: Settings → Accessibility → Spoken Content → Voices.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value: Double(book.completedCount), total: Double(book.chunks.count))
                Text("\(book.completedCount) of \(book.chunks.count) sections saved")
            }
            if let error = book.conversionError {
                Text(error).foregroundStyle(.red)
            }
            if converter.activeID == id {
                if converter.pauseRequested {
                    Text("Finishing this section before pausing…")
                } else {
                    Button("Pause after this section") { converter.requestPause() }
                }
            } else {
                Button {
                    Task { await converter.generate(id, voiceIdentifier: voiceID) }
                } label: {
                    if book.chunks.isEmpty { Text("Create audiobook").frame(maxWidth: .infinity) }
                    else { Text("Resume conversion").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(converter.activeID != nil || voiceID.isEmpty)
            }
        }
    }
}
