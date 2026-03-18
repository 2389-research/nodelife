// ABOUTME: Tests for the LLMClient protocol and LLMError types
// ABOUTME: Verifies error descriptions and protocol extension defaults

import Testing
import Foundation
@testable import NodeLifeCore

@Test func llmErrorDescriptions() {
    let apiErr = LLMError.apiError("rate limited")
    #expect(apiErr.localizedDescription.contains("rate limited"))

    let noContent = LLMError.noContent
    #expect(noContent.localizedDescription.contains("content"))
}

@Test func llmErrorEquality() {
    #expect(LLMError.noContent == LLMError.noContent)
    #expect(LLMError.apiError("a") == LLMError.apiError("a"))
    #expect(LLMError.apiError("a") != LLMError.apiError("b"))
}
