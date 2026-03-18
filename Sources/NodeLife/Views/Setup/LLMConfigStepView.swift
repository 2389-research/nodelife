// ABOUTME: Step 3 of setup wizard for LLM provider configuration
// ABOUTME: Provider picker, API key (saved to Keychain), model name, and base URL fields

import SwiftUI

struct LLMConfigStepView: View {
    @Binding var provider: String
    @Binding var model: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    var body: some View { Text("LLM Config (placeholder)") }
}
