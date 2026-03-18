// ABOUTME: Tests for the Relationship model record
// ABOUTME: Verifies GRDB conformance, relationship kinds, and default confidence

import Testing
import Foundation
@testable import NodeLifeCore

@Test func relationshipCreationWithDefaults() {
    let rel = Relationship(
        sourceEntityID: UUID(),
        targetEntityID: UUID(),
        kind: .collaborates,
        weight: 1.0,
        extractionRunID: UUID()
    )
    #expect(rel.confidence == 0.0)
    #expect(rel.evidence == nil)
    #expect(rel.evidenceChunkRefsJson == nil)
}

@Test func relationshipTableName() {
    #expect(Relationship.databaseTableName == "relationships")
}

@Test func relationshipKindHasAllCases() {
    let kinds = RelationshipKind.allCases
    #expect(kinds.count == 12)
    #expect(kinds.contains(.worksFor))
    #expect(kinds.contains(.worksOn))
    #expect(kinds.contains(.manages))
    #expect(kinds.contains(.collaborates))
    #expect(kinds.contains(.mentions))
    #expect(kinds.contains(.cooccurs))
    #expect(kinds.contains(.discusses))
    #expect(kinds.contains(.relatesTo))
    #expect(kinds.contains(.owns))
    #expect(kinds.contains(.inspiredBy))
    #expect(kinds.contains(.partOf))
    #expect(kinds.contains(.reports))
}

@Test func relationshipKindRawValues() {
    #expect(RelationshipKind.worksFor.rawValue == "worksFor")
    #expect(RelationshipKind.cooccurs.rawValue == "cooccurs")
    #expect(RelationshipKind.inspiredBy.rawValue == "inspiredBy")
}
