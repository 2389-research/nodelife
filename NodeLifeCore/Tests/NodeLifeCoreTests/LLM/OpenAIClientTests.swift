// ABOUTME: Tests for OpenAIClient request building and response parsing
// ABOUTME: Verifies chat completions format and configurable base URL

import Testing
import Foundation
@testable import NodeLifeCore

@Test func openaiBuildsCorrectRequest() throws {
    let client = OpenAIClient(apiKey: "sk-test", model: "gpt-4o")
    let request = try client.buildRequest(
        prompt: "Hello", system: "Be helpful", maxTokens: 2048, temperature: 0.5
    )
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: String]]
    #expect(messages.count == 2) // system + user
    #expect(messages[0]["role"] == "system")
    #expect(messages[1]["role"] == "user")
}

@Test func openaiParsesSuccessResponse() throws {
    let json = """
    {"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}
    """
    let result = try OpenAIClient.parseResponseText(from: json.data(using: .utf8)!)
    #expect(result == "Hello")
}

@Test func openaiSupportsCustomBaseURL() throws {
    let client = OpenAIClient(apiKey: "test", model: "local", baseURL: "http://localhost:11434/v1")
    let request = try client.buildRequest(prompt: "hi", system: nil, maxTokens: 100, temperature: nil)
    #expect(request.url?.host == "localhost")
}
