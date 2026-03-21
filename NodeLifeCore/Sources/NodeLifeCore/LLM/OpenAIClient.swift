// ABOUTME: OpenAI-compatible chat completions client
// ABOUTME: Works with OpenAI, OpenRouter, Ollama, and other compatible endpoints

import Foundation

public final class OpenAIClient: LLMClient, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "gpt-4o",
        baseURL: String = "https://api.openai.com/v1",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public func complete(prompt: String, system: String?, maxTokens: Int, temperature: Double?, jsonSchema: [String: Any]? = nil) async throws -> String {
        let request = try buildRequest(prompt: prompt, system: system, maxTokens: maxTokens, temperature: temperature, jsonSchema: jsonSchema)
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
        return try OpenAIClient.parseResponseText(from: data)
    }

    func buildRequest(prompt: String, system: String?, maxTokens: Int, temperature: Double?, jsonSchema: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.apiError("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var messages: [[String: String]] = []
        if let system = system {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens
        ]
        if let temperature = temperature {
            body["temperature"] = temperature
        }
        if jsonSchema != nil {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseResponseText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError("Failed to parse OpenAI response JSON")
        }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            throw LLMError.apiError(msg)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.noContent
        }
        return content
    }
}
