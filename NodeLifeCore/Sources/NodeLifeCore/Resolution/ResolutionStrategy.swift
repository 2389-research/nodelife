// ABOUTME: Protocol for entity resolution strategies and candidate data type
// ABOUTME: Each strategy finds potential entity duplicates with a confidence score

import Foundation

public struct ResolutionCandidate: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var entity: Entity
    public var matchedEntity: Entity
    public var confidence: Double
    public var strategy: String
    public var reason: String

    public init(
        id: UUID = UUID(),
        entity: Entity,
        matchedEntity: Entity,
        confidence: Double,
        strategy: String,
        reason: String
    ) {
        self.id = id
        self.entity = entity
        self.matchedEntity = matchedEntity
        self.confidence = confidence
        self.strategy = strategy
        self.reason = reason
    }
}

public protocol ResolutionStrategy: Sendable {
    var name: String { get }
    var order: Int { get }
    func findCandidates(for entity: Entity, in entities: [Entity], db: AppDatabase) async throws -> [ResolutionCandidate]
}
