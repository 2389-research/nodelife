// ABOUTME: Settings view for LLM provider configuration and extraction options
// ABOUTME: Manages API keys via Keychain, model selection, and extraction mode

import SwiftUI
import NodeLifeCore

struct SettingsView: View {
    @State private var llmProvider: String = "anthropic"
    @State private var apiKey: String = ""
    @State private var model: String = "claude-sonnet-4-6"
    @State private var extractionMode: String = "quick"
    @State private var openaiBaseURL: String = "https://api.openai.com/v1"
    @State private var saveStatus: String = ""

    private let keychain = KeychainService(serviceName: "com.nodelife.settings")

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $llmProvider) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI / Compatible").tag("openai")
                }

                if llmProvider == "anthropic" {
                    TextField("Model", text: $model)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Model", text: $model)
                        .textFieldStyle(.roundedBorder)
                    TextField("Base URL", text: $openaiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save API Key") {
                    do {
                        try keychain.save(key: "\(llmProvider)_api_key", value: apiKey)
                        saveStatus = "Saved"
                        apiKey = ""
                    } catch {
                        saveStatus = "Error: \(error.localizedDescription)"
                    }
                }

                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(saveStatus.hasPrefix("Error") ? .red : .green)
                }
            }

            Section("Extraction") {
                Picker("Mode", selection: $extractionMode) {
                    Text("Quick (2-pass)").tag("quick")
                    Text("Deep (5-pass)").tag("deep")
                }
                Text(extractionMode == "quick"
                    ? "Extracts entities and relationships in 2 passes."
                    : "Full 5-pass extraction: persons, orgs/projects, themes, relationships, merge recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
