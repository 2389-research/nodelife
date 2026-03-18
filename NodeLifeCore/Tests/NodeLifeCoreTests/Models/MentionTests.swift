// ABOUTME: Tests for the Mention model record
// ABOUTME: Verifies GRDB conformance, field storage, and foreign key references

import Testing
import Foundation
@testable import NodeLifeCore

@Test func mentionCreation() {
    let entityID = UUID()
    let chunkID = UUID()
    let runID = UUID()
    let mention = Mention(entityID: entityID, meetingChunkID: chunkID, confidence: 0.95, extractionRunID: runID)
    #expect(mention.entityID == entityID)
    #expect(mention.meetingChunkID == chunkID)
    #expect(mention.confidence == 0.95)
    #expect(mention.extractionRunID == runID)
}

@Test func mentionTableName() {
    #expect(Mention.databaseTableName == "mentions")
}

@Test func mentionHasUUID() {
    let mention = Mention(entityID: UUID(), meetingChunkID: UUID(), confidence: 0.5, extractionRunID: UUID())
    #expect(mention.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
}
