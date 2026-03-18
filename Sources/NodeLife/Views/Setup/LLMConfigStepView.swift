// ABOUTME: Step 3 of setup wizard for LLM provider configuration
// ABOUTME: Provider picker, API key (saved to Keychain), model name, and base URL fields

import SwiftUI
import NodeLifeCore

struct LLMConfigStepView: View {
    @Binding var provider: String
    @Binding var model: String
    @Binding var baseURL: String
    @Binding var apiKey: String

    @State private var saveStatus: String = ""

    private let keychain = KeychainService(serviceName: "com.nodelife.settings")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("LLM Configuration")
                .font(.title2.bold())

            Text("NodeLife uses a large language model to extract entities and relationships from your meeting transcripts.")
                .foregroundStyle(.secondary)

            Form {
                Picker("Provider", selection: $provider) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI / Compatible").tag("openai")
                }
                .onChange(of: provider) { _, newValue in
                    if newValue == "anthropic" {
                        model = "claude-sonnet-4-6"
                    } else {
                        model = "gpt-4o"
                    }
                    apiKey = ""
                    saveStatus = ""
                }

                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)

                if provider == "openai" {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save API Key") {
                    do {
                        try keychain.save(key: "\(provider)_api_key", value: apiKey)
                        saveStatus = "Saved"
                    } catch {
                        saveStatus = "Error: \(error.localizedDescription)"
                    }
                }
                .disabled(apiKey.isEmpty)

                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(saveStatus.hasPrefix("Error") ? .red : .green)
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .padding(40)
    }
}
