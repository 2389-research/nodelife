// ABOUTME: Tests for AnthropicClient request building and response parsing
// ABOUTME: Verifies HTTP headers, JSON body structure, and error handling

import Testing
import Foundation
@testable import NodeLifeCore

@Test func anthropicBuildsCorrectRequest() throws {
    let client = AnthropicClient(apiKey: "test-key", model: "claude-sonnet-4-6")
    let request = try client.buildRequest(
        prompt: "Hello", system: "You are helpful", maxTokens: 1024, temperature: 0.7
    )
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(body["model"] as? String == "claude-sonnet-4-6")
    #expect(body["max_tokens"] as? Int == 1024)
}

@Test func anthropicParsesSuccessResponse() throws {
    let json = """
    {"content":[{"type":"text","text":"Hello world"}],"type":"message"}
    """
    let result = try AnthropicClient.parseResponseText(from: json.data(using: .utf8)!)
    #expect(result == "Hello world")
}

@Test func anthropicParsesErrorResponse() throws {
    let json = """
    {"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}
    """
    #expect(throws: LLMError.self) {
        try AnthropicClient.parseResponseText(from: json.data(using: .utf8)!)
    }
}

@Test func anthropicParsesNoContent() throws {
    let json = """
    {"content":[],"type":"message"}
    """
    #expect(throws: LLMError.self) {
        try AnthropicClient.parseResponseText(from: json.data(using: .utf8)!)
    }
}
