// ABOUTME: Tests for extraction prompt templates
// ABOUTME: Verifies entity, relationship, and theme prompt generation

import Testing
import Foundation
@testable import NodeLifeCore

@Test func entityExtractionPromptContainsMeetingTitle() {
    let prompt = ExtractionPrompts.entityExtraction(
        meetingTitle: "Sprint Planning", attendees: ["Alice", "Bob"], transcriptText: "Hello"
    )
    #expect(prompt.userMessage.contains("Sprint Planning"))
    #expect(prompt.userMessage.contains("Alice"))
    #expect(prompt.systemPrompt.contains("entity"))
}

@Test func relationshipPromptIncludesEntities() {
    let prompt = ExtractionPrompts.relationshipExtraction(
        meetingTitle: "Review", entities: ["Harper Reed (person)", "Acme (organization)"],
        transcriptText: "Hello"
    )
    #expect(prompt.userMessage.contains("Harper Reed"))
    #expect(prompt.userMessage.contains("Acme"))
}

@Test func formatTranscriptIncludesChunkIndex() {
    let chunks = [
        MeetingChunk(meetingID: UUID(), chunkIndex: 0, text: "Hello", speaker: "Alice"),
        MeetingChunk(meetingID: UUID(), chunkIndex: 1, text: "World")
    ]
    let formatted = ExtractionPrompts.formatTranscriptForExtraction(chunks: chunks)
    #expect(formatted.contains("[0]"))
    #expect(formatted.contains("[Alice]"))
    #expect(formatted.contains("[1]"))
}

@Test func entityPromptIncludesAllEntityTypes() {
    let prompt = ExtractionPrompts.entityExtraction(
        meetingTitle: "Test", attendees: [], transcriptText: "Test"
    )
    #expect(prompt.systemPrompt.contains("person"))
    #expect(prompt.systemPrompt.contains("organization"))
    #expect(prompt.systemPrompt.contains("actionItem"))
    #expect(prompt.systemPrompt.contains("blogIdea"))
}
