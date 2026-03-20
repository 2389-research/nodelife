// ABOUTME: Protocol for LLM interactions with error types
// ABOUTME: Provides a provider-agnostic interface for text completion

import Foundation

public enum LLMError: Error, LocalizedError, Equatable, Sendable {
    case apiError(String)
    case networkError(String)
    case decodingError(String)
    case noContent
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .noContent: return "No content in response"
        case .rateLimited(let retry): return "Rate limited\(retry.map { ", retry after \($0)s" } ?? "")"
        }
    }

    public static func == (lhs: LLMError, rhs: LLMError) -> Bool {
        switch (lhs, rhs) {
        case (.apiError(let a), .apiError(let b)): return a == b
        case (.networkError(let a), .networkError(let b)): return a == b
        case (.decodingError(let a), .decodingError(let b)): return a == b
        case (.noContent, .noContent): return true
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        default: return false
        }
    }
}

public protocol LLMClient: Sendable {
    func complete(
        prompt: String,
        system: String?,
        maxTokens: Int,
        temperature: Double?,
        jsonMode: Bool
    ) async throws -> String
}

extension LLMClient {
    public func complete(prompt: String, system: String? = nil) async throws -> String {
        try await complete(prompt: prompt, system: system, maxTokens: 4096, temperature: nil, jsonMode: false)
    }

    public func complete(prompt: String, system: String?, maxTokens: Int, temperature: Double?) async throws -> String {
        try await complete(prompt: prompt, system: system, maxTokens: maxTokens, temperature: temperature, jsonMode: false)
    }
}
