// ABOUTME: Tests for ExtractionService JSON parsing and entity creation
// ABOUTME: Verifies static parsing helpers for LLM response processing

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func parseEntityResponseValidJSON() throws {
    let json = """
    {"entities":[{"name":"Harper Reed","type":"person","confidence":0.95,"mentions":[{"surface_form":"Harper","chunk_ordinal":0}]}]}
    """
    let entities = try ExtractionService.parseEntityResponse(json)
    #expect(entities.count == 1)
    #expect(entities[0].name == "Harper Reed")
    #expect(entities[0].confidence == 0.95)
}

@Test func parseEntityResponseStripsMarkdownFences() throws {
    let json = """
    ```json
    {"entities":[{"name":"Test","type":"concept","confidence":0.8,"mentions":[]}]}
    ```
    """
    let entities = try ExtractionService.parseEntityResponse(json)
    #expect(entities.count == 1)
}

@Test func parseEntityResponseInvalidJSON() {
    #expect(throws: ExtractionError.self) {
        try ExtractionService.parseEntityResponse("not json at all")
    }
}

@Test func mapEntityTypeCoversAllTypes() {
    #expect(ExtractionService.mapEntityType("person") == .person)
    #expect(ExtractionService.mapEntityType("organization") == .organization)
    #expect(ExtractionService.mapEntityType("org") == .organization)
    #expect(ExtractionService.mapEntityType("project") == .project)
    #expect(ExtractionService.mapEntityType("concept") == .concept)
    #expect(ExtractionService.mapEntityType("topic") == .topic)
    #expect(ExtractionService.mapEntityType("place") == .place)
    #expect(ExtractionService.mapEntityType("actionItem") == .actionItem)
    #expect(ExtractionService.mapEntityType("action_item") == .actionItem)
    #expect(ExtractionService.mapEntityType("blogIdea") == .blogIdea)
    #expect(ExtractionService.mapEntityType("blog_idea") == .blogIdea)
    #expect(ExtractionService.mapEntityType("idea") == .idea)
    #expect(ExtractionService.mapEntityType("unknown") == .other)
}
