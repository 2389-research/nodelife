// ABOUTME: LLM-powered relationship extraction service for meeting transcripts
// ABOUTME: Parses LLM JSON responses into Relationship records linking entities via GRDB

import Foundation
import GRDB

// MARK: - JSON Response Types

public struct ExtractedRelationship: Codable, Sendable {
    public let fromEntity: String
    public let toEntity: String
    public let type: String
    public let confidence: Double
    public let evidenceChunkOrdinals: [Int]

    enum CodingKeys: String, CodingKey {
        case fromEntity = "from_entity"
        case toEntity = "to_entity"
        case type
        case confidence
        case evidenceChunkOrdinals = "evidence_chunk_ordinals"
    }
}

public struct RelationshipExtractionResponse: Codable, Sendable {
    public let relationships: [ExtractedRelationship]
}

// MARK: - RelationshipExtractionService

public struct RelationshipExtractionService: Sendable {
    public let database: AppDatabase
    public let llmClient: any LLMClient

    public init(database: AppDatabase, llmClient: any LLMClient) {
        self.database = database
        self.llmClient = llmClient
    }

    // MARK: - Relationship Extraction

    /// Extracts relationships between entities from a meeting transcript using the LLM.
    /// Requires that entity extraction has already been run for the meeting.
    public func extractRelationships(meetingId: UUID) async throws {
        let (meeting, chunks, entities) = try database.read { db -> (Meeting, [MeetingChunk], [Entity]) in
            guard let meeting = try Meeting.fetchOne(db, key: meetingId) else {
                throw ExtractionError.meetingNotFound(meetingId)
            }

            let chunks = try MeetingChunk
                .filter(MeetingChunk.Columns.meetingID == meetingId)
                .order(MeetingChunk.Columns.chunkIndex)
                .fetchAll(db)

            // Find entities that have mentions in this meeting's chunks
            let chunkIDs = chunks.map(\.id)
            let mentions = try Mention
                .filter(chunkIDs.contains(Mention.Columns.meetingChunkID))
                .fetchAll(db)
            let entityIDs = Array(Set(mentions.map(\.entityID)))
            let entities = try Entity
                .filter(entityIDs.contains(Entity.Columns.id))
                .fetchAll(db)

            return (meeting, chunks, entities)
        }

        guard !entities.isEmpty else { return }

        var extractionRun = ExtractionRun(
            meetingID: meetingId,
            model: "default",
            promptVersion: "rel-v1",
            passName: "relationship_extraction",
            status: .running
        )

        try database.write { db in
            try extractionRun.insert(db)
        }

        do {
            let entityLabels = entities.map { "\($0.canonicalName) (\($0.kind.rawValue))" }
            let transcriptText = ExtractionPrompts.formatTranscriptForExtraction(chunks: chunks)
            let prompt = ExtractionPrompts.relationshipExtraction(
                meetingTitle: meeting.title,
                entities: entityLabels,
                transcriptText: transcriptText
            )

            let response = try await llmClient.complete(
                prompt: prompt.userMessage,
                system: prompt.systemPrompt,
                maxTokens: 4096,
                temperature: 0.0
            )

            let extracted = try Self.parseRelationshipResponse(response)

            // Build entity canonical name to ID lookup
            let entityLookup = Dictionary(
                uniqueKeysWithValues: entities.map { ($0.canonicalName, $0.id) }
            )

            try database.write { db in
                for rel in extracted {
                    let fromCanonical = rel.fromEntity.lowercased()
                    let toCanonical = rel.toEntity.lowercased()

                    guard let fromID = entityLookup[fromCanonical],
                          let toID = entityLookup[toCanonical] else { continue }

                    let chunkRefsJson: String?
                    if !rel.evidenceChunkOrdinals.isEmpty {
                        let data = try JSONSerialization.data(withJSONObject: rel.evidenceChunkOrdinals)
                        chunkRefsJson = String(data: data, encoding: .utf8)
                    } else {
                        chunkRefsJson = nil
                    }

                    var relationship = Relationship(
                        sourceEntityID: fromID,
                        targetEntityID: toID,
                        kind: Self.mapRelationshipType(rel.type),
                        weight: rel.confidence,
                        confidence: rel.confidence,
                        evidenceChunkRefsJson: chunkRefsJson,
                        extractionRunID: extractionRun.id
                    )
                    try relationship.insert(db)
                }

                extractionRun.status = .completed
                extractionRun.completedAt = Date()
                try extractionRun.update(db)
            }
        } catch {
            try? database.write { db in
                extractionRun.status = .failed
                extractionRun.completedAt = Date()
                extractionRun.errorMessage = error.localizedDescription
                try extractionRun.update(db)
            }
            throw error
        }
    }

    // MARK: - Static Helpers

    /// Parses an LLM response string into extracted relationships.
    /// Strips markdown code fences if present, then decodes JSON.
    public static func parseRelationshipResponse(_ response: String) throws -> [ExtractedRelationship] {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences (```json ... ``` or ``` ... ```)
        if cleaned.hasPrefix("```") {
            // Remove opening fence (with optional language tag)
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            // Remove closing fence
            if let lastFence = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<lastFence.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ExtractionError.invalidJSON("Could not convert response to data")
        }

        do {
            let decoded = try JSONDecoder().decode(RelationshipExtractionResponse.self, from: data)
            return decoded.relationships
        } catch {
            throw ExtractionError.invalidJSON(error.localizedDescription)
        }
    }

    /// Maps a string relationship type from the LLM response to a RelationshipKind enum value.
    /// Defaults to .relatesTo for unrecognized types.
    public static func mapRelationshipType(_ type: String) -> RelationshipKind {
        switch type.lowercased() {
        case "worksfor": return .worksFor
        case "workson": return .worksOn
        case "manages": return .manages
        case "collaborates": return .collaborates
        case "mentions": return .mentions
        case "cooccurs": return .cooccurs
        case "discusses": return .discusses
        case "relatesto": return .relatesTo
        case "owns": return .owns
        case "inspiredby": return .inspiredBy
        case "partof": return .partOf
        case "reports": return .reports
        default: return .relatesTo
        }
    }
}
