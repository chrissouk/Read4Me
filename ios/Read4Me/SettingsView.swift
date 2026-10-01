import SwiftUI

struct SettingsView: View {
    @ObservedObject var apiKeys: APIKeyStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API key") {
                    if apiKeys.hasKey { Label("API key saved", systemImage: "checkmark.shield") }
                    SecureField("Paste your API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityIdentifier("openai-api-key")
                    Button("Save API key") {
                        do {
                            try apiKeys.save(key)
                            key = ""
                            message = "API key saved securely."
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if apiKeys.hasKey {
                        Button("Remove saved API key", role: .destructive) {
                            do { try apiKeys.remove(); key = ""; message = "API key removed."; error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    Link("Open API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                    Text("Sign in to the OpenAI Platform to create a key. API usage is billed separately from ChatGPT.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Narration") {
                    LabeledContent("Model", value: "gpt-4o-mini-tts")
                    LabeledContent("Default voice", value: "onyx")
                    Text("Document text is sent to OpenAI to generate AI narration. Saved documents and MP3 audio stay on your iPhone. Listening to saved audio works offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Your key is stored in this device’s Keychain and is not included in your document library.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message).foregroundStyle(.green) }
                if let error { Text(error).foregroundStyle(.red) }
                if let error = apiKeys.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { key = ""; dismiss() } }
        }
    }
}
