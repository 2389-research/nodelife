// ABOUTME: Fuzzy name matching strategy using normalization and Levenshtein distance
// ABOUTME: Finds entities with similar names after stripping case, whitespace, and punctuation

import Foundation

public struct NormalizedMatchStrategy: ResolutionStrategy, Sendable {
    public var name: String { "normalized_match" }
    public var order: Int { 2 }

    public let similarityThreshold: Double

    public init(similarityThreshold: Double = 0.8) {
        self.similarityThreshold = similarityThreshold
    }

    public func findCandidates(
        for entity: Entity,
        in entities: [Entity],
        db: AppDatabase
    ) async throws -> [ResolutionCandidate] {
        let normalizedSource = normalize(entity.name)

        return entities.compactMap { other in
            guard other.id != entity.id else { return nil }
            guard other.kind == entity.kind else { return nil }
            // Skip exact name matches (handled by ExactMatchStrategy)
            guard other.name != entity.name else { return nil }

            let normalizedOther = normalize(other.name)
            let similarity = stringSimilarity(normalizedSource, normalizedOther)

            guard similarity >= similarityThreshold else { return nil }

            return ResolutionCandidate(
                entity: entity,
                matchedEntity: other,
                confidence: similarity,
                strategy: name,
                reason: "Normalized match: '\(entity.name)' ≈ '\(other.name)' (similarity: \(String(format: "%.2f", similarity)))"
            )
        }
    }

    // MARK: - Private Helpers

    /// Normalize a string for comparison by lowercasing, stripping diacritics,
    /// removing punctuation, and collapsing whitespace.
    private func normalize(_ string: String) -> String {
        string
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Calculate similarity between two strings using Levenshtein distance.
    /// Returns a value between 0.0 (completely different) and 1.0 (identical).
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        guard s1 != s2 else { return 1.0 }
        guard !s1.isEmpty, !s2.isEmpty else { return 0.0 }

        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein edit distance between two strings.
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = Array(repeating: 0, count: s2.count)
        var last = Array(0...s2.count)

        for (i, char1) in s1.enumerated() {
            var cur = [i + 1] + empty
            for (j, char2) in s2.enumerated() {
                cur[j + 1] = char1 == char2
                    ? last[j]
                    : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }

        return last.last ?? 0
    }
}
