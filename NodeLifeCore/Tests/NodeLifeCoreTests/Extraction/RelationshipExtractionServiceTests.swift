// ABOUTME: Tests for RelationshipExtractionService JSON parsing
// ABOUTME: Verifies relationship response parsing and type mapping via static methods

import Testing
import Foundation
@testable import NodeLifeCore

@Test func parseRelationshipResponseValidJSON() throws {
    let json = """
    {"relationships":[{"from_entity":"Harper","to_entity":"Acme","type":"worksFor","confidence":0.9,"evidence_chunk_ordinals":[0,1]}]}
    """
    let rels = try RelationshipExtractionService.parseRelationshipResponse(json)
    #expect(rels.count == 1)
    #expect(rels[0].fromEntity == "Harper")
    #expect(rels[0].type == "worksFor")
    #expect(rels[0].evidenceChunkOrdinals == [0, 1])
}

@Test func parseRelationshipResponseStripsMarkdownFences() throws {
    let json = """
    ```json
    {"relationships":[{"from_entity":"A","to_entity":"B","type":"relatesTo","confidence":0.5,"evidence_chunk_ordinals":[]}]}
    ```
    """
    let rels = try RelationshipExtractionService.parseRelationshipResponse(json)
    #expect(rels.count == 1)
}

@Test func mapRelationshipTypeCoversAllTypes() {
    #expect(RelationshipExtractionService.mapRelationshipType("worksFor") == .worksFor)
    #expect(RelationshipExtractionService.mapRelationshipType("collaborates") == .collaborates)
    #expect(RelationshipExtractionService.mapRelationshipType("unknown") == .relatesTo)
}
