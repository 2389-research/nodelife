// ABOUTME: Main wizard container with step navigation and indicator dots
// ABOUTME: Manages current step state, back/next buttons, and step content switching

import SwiftUI
import NodeLifeCore

struct SetupWizardView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    // Data source settings
    @AppStorage("nodelife.sources.granola.enabled") private var granolaEnabled = true
    @AppStorage("nodelife.sources.granola.path") private var granolaPath = GranolaConfig.defaultDataPath
    @AppStorage("nodelife.sources.muesli.enabled") private var muesliEnabled = true
    @AppStorage("nodelife.sources.muesli.path") private var muesliPath = "~/.local/share/muesli/raw/"

    // LLM settings
    @AppStorage("nodelife.llm.provider") private var llmProvider = "anthropic"
    @AppStorage("nodelife.llm.model") private var llmModel = "claude-sonnet-4-6"
    @AppStorage("nodelife.llm.baseURL") private var llmBaseURL = "https://api.openai.com/v1"

    // Extraction settings
    @AppStorage("nodelife.extraction.mode") private var extractionMode = "quick"

    @State private var currentStep = 1
    @State private var apiKey = ""

    let database: AppDatabase
    let onFinish: () -> Void
    let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator dots
            HStack(spacing: 8) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 1:
                    WelcomeStepView(onNext: { currentStep = 2 })
                case 2:
                    DataSourceStepView(
                        granolaEnabled: $granolaEnabled,
                        granolaPath: $granolaPath,
                        muesliEnabled: $muesliEnabled,
                        muesliPath: $muesliPath
                    )
                case 3:
                    LLMConfigStepView(
                        provider: $llmProvider,
                        model: $llmModel,
                        baseURL: $llmBaseURL,
                        apiKey: $apiKey
                    )
                case 4:
                    ExtractionModeStepView(extractionMode: $extractionMode)
                case 5:
                    SyncStepView(
                        database: database,
                        granolaEnabled: granolaEnabled,
                        granolaPath: granolaPath,
                        muesliEnabled: muesliEnabled,
                        muesliPath: muesliPath,
                        onFinish: {
                            hasCompletedSetup = true
                            onFinish()
                        }
                    )
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons (not shown on step 1 which has its own button, or step 5 which has its own)
            if currentStep > 1 && currentStep < 5 {
                Divider()
                HStack {
                    Button("Back") {
                        currentStep -= 1
                    }

                    Spacer()

                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 3 && apiKey.isEmpty)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 480)
        .interactiveDismissDisabled(true)
    }
}
