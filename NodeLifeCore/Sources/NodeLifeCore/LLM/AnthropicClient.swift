// ABOUTME: Anthropic Messages API client conforming to LLMClient protocol
// ABOUTME: Sends REST requests to api.anthropic.com and parses JSON responses

import Foundation

public final class AnthropicClient: LLMClient, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession

    private static let apiVersion = "2023-06-01"

    public init(apiKey: String, model: String = "claude-sonnet-4-6", baseURL: String = "https://api.anthropic.com", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public func complete(
        prompt: String,
        system: String?,
        maxTokens: Int,
        temperature: Double?,
        jsonSchema: [String: Any]? = nil
    ) async throws -> String {
        let request = try buildRequest(
            prompt: prompt, system: system, maxTokens: maxTokens, temperature: temperature,
            jsonSchema: jsonSchema
        )

        let data: Data
        do {
            let (responseData, _) = try await session.data(for: request)
            data = responseData
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }

        return try AnthropicClient.parseResponseText(from: data)
    }

    // Internal for testing
    func buildRequest(
        prompt: String,
        system: String?,
        maxTokens: Int,
        temperature: Double?,
        jsonSchema: [String: Any]? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.apiError("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicClient.apiVersion, forHTTPHeaderField: "anthropic-version")

        let messages: [[String: String]] = [
            ["role": "user", "content": prompt]
        ]

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages
        ]

        if let system = system {
            body["system"] = system
        }

        if let temperature = temperature {
            body["temperature"] = temperature
        }

        // Use structured output via output_config.format for JSON responses
        if let schema = jsonSchema {
            body["output_config"] = [
                "format": [
                    "type": "json_schema",
                    "schema": schema
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseResponseText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError("Failed to parse response JSON")
        }

        // Check for error response
        if let type = json["type"] as? String, type == "error",
           let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            throw LLMError.apiError(message)
        }

        // Extract text from content array
        guard let content = json["content"] as? [[String: Any]] else {
            throw LLMError.decodingError("Missing content array in response")
        }

        guard let firstBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = firstBlock["text"] as? String else {
            throw LLMError.noContent
        }

        return text
    }
}
