// ABOUTME: Settings view for LLM provider configuration and extraction options
// ABOUTME: Manages API keys via Keychain, model selection, and extraction mode

import SwiftUI
import NodeLifeCore

enum SettingsDefaults {
    static let provider = "openai"
    static let model = "gpt-5.4-nano"
}

struct SettingsView: View {
    @AppStorage("nodelife.llm.provider") private var llmProvider: String = SettingsDefaults.provider
    @State private var apiKey: String = ""
    @AppStorage("nodelife.llm.model") private var model: String = SettingsDefaults.model
    @AppStorage("nodelife.extraction.mode") private var extractionMode: String = "quick"
    @AppStorage("nodelife.llm.baseURL") private var baseURL: String = ""
    @AppStorage("nodelife.jobs.maxConcurrency") private var maxConcurrency: Int = 2
    @AppStorage("nodelife.jobs.maxRetries") private var maxRetries: Int = 3
    @State private var saveStatus: String = ""
    @State private var hasExistingKey: Bool = false
    @State private var customModel: String = ""

    private let keychain = KeychainService(serviceName: "com.nodelife.settings")

    private static let openaiModels = [
        "gpt-5.4-nano", "gpt-5.4-mini", "gpt-5.4"
    ]

    private static let anthropicModels = [
        "claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-6"
    ]

    private var modelsForProvider: [String] {
        llmProvider == "anthropic" ? Self.anthropicModels : Self.openaiModels
    }

    var body: some View {
        TabView {
            llmTab
                .tabItem { Label("LLM", systemImage: "brain") }

            extractionTab
                .tabItem { Label("Extraction", systemImage: "wand.and.stars") }

            dataTab
                .tabItem { Label("Data", systemImage: "cylinder") }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            checkExistingKey()
        }
        .onChange(of: llmProvider) {
            checkExistingKey()
        }
    }

    private var llmTab: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $llmProvider) {
                    Text("OpenAI / Compatible").tag("openai")
                    Text("Anthropic").tag("anthropic")
                }
                .onChange(of: llmProvider) { _, newValue in
                    if newValue == "anthropic" {
                        model = "claude-sonnet-4-6"
                    } else {
                        model = "gpt-5.4-nano"
                    }
                    customModel = ""
                    apiKey = ""
                    saveStatus = ""
                }
            }

            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { modelsForProvider.contains(model) ? model : "__custom__" },
                    set: { newValue in
                        if newValue == "__custom__" {
                            customModel = model.hasPrefix("__") ? "" : model
                        } else {
                            model = newValue
                        }
                    }
                )) {
                    ForEach(modelsForProvider, id: \.self) { m in
                        Text(m).tag(m)
                    }
                    Divider()
                    Text("Custom…").tag("__custom__")
                }

                if !modelsForProvider.contains(model) {
                    TextField("Model ID", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModel) {
                            if !customModel.isEmpty {
                                model = customModel
                            }
                        }
                }

                TextField("Base URL (leave blank for default)", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            Section("API Key") {
                if hasExistingKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key configured")
                            .foregroundStyle(.secondary)
                    }
                }

                SecureField(hasExistingKey ? "Replace API Key" : "API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save API Key") {
                        do {
                            try keychain.save(key: "\(llmProvider)_api_key", value: apiKey)
                            saveStatus = "Saved"
                            apiKey = ""
                            hasExistingKey = true
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
            }
        }
        .formStyle(.grouped)
    }

    private var extractionTab: some View {
        Form {
            Section("Extraction Mode") {
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

            Section("Workers") {
                Stepper("Max Concurrency: \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
                Text("Number of extraction jobs to run in parallel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper("Max Retries: \(maxRetries)", value: $maxRetries, in: 1...10)
                Text("How many times to retry a failed extraction before giving up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section("Database") {
                let dbPath = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first!.appendingPathComponent("NodeLife/nodelife.sqlite").path

                LabeledContent("Location") {
                    Text(dbPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(dbPath, inFileViewerRootedAtPath: "")
                }
            }

            Section("Granola") {
                let granolaPath = NSString(string: GranolaConfig.defaultDataPath).expandingTildeInPath
                LabeledContent("Data Path") {
                    Text(granolaPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func checkExistingKey() {
        hasExistingKey = (try? keychain.retrieve(key: "\(llmProvider)_api_key"))?.flatMap({ !$0.isEmpty ? $0 : nil }) != nil
    }
}
