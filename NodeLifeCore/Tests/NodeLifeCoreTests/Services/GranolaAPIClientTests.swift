// ABOUTME: Tests for GranolaAPIClient covering token discovery and Codable model parsing
// ABOUTME: Validates auth token extraction from supabase.json and JSON deserialization of API models

import Testing
import Foundation
@testable import NodeLifeCore

@Suite("GranolaAPIClient Tests")
struct GranolaAPIClientTests {

    // MARK: - Token Discovery

    @Test("discoverToken extracts access_token from valid supabase.json")
    func discoverTokenFromValidFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let supabasePath = tempDir.appendingPathComponent("supabase.json").path

        // workos_tokens is a STRINGIFIED JSON inside the top-level JSON
        let workosTokensJSON = #"{"access_token":"test-token-abc123","refresh_token":"refresh-xyz"}"#
        let outerJSON: [String: Any] = [
            "workos_tokens": workosTokensJSON,
            "other_key": "other_value"
        ]
        let data = try JSONSerialization.data(withJSONObject: outerJSON)
        try data.write(to: URL(fileURLWithPath: supabasePath))

        let token = try GranolaAPIClient.discoverToken(from: supabasePath)
        #expect(token == "test-token-abc123")
    }

    @Test("discoverToken throws when file is missing")
    func discoverTokenMissingFile() {
        let bogusPath = "/tmp/nonexistent-\(UUID().uuidString)/supabase.json"
        #expect(throws: SourceAdapterError.self) {
            try GranolaAPIClient.discoverToken(from: bogusPath)
        }
    }

    @Test("discoverToken throws when workos_tokens key is missing")
    func discoverTokenMissingWorkosTokens() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let supabasePath = tempDir.appendingPathComponent("supabase.json").path
        let outerJSON: [String: Any] = ["some_other_key": "value"]
        let data = try JSONSerialization.data(withJSONObject: outerJSON)
        try data.write(to: URL(fileURLWithPath: supabasePath))

        #expect(throws: SourceAdapterError.self) {
            try GranolaAPIClient.discoverToken(from: supabasePath)
        }
    }

    @Test("discoverToken throws when workos_tokens is malformed JSON string")
    func discoverTokenMalformedWorkosTokens() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let supabasePath = tempDir.appendingPathComponent("supabase.json").path
        let outerJSON: [String: Any] = ["workos_tokens": "not-valid-json{{{"]
        let data = try JSONSerialization.data(withJSONObject: outerJSON)
        try data.write(to: URL(fileURLWithPath: supabasePath))

        #expect(throws: SourceAdapterError.self) {
            try GranolaAPIClient.discoverToken(from: supabasePath)
        }
    }

    @Test("discoverToken throws when access_token is missing from workos_tokens")
    func discoverTokenMissingAccessToken() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let supabasePath = tempDir.appendingPathComponent("supabase.json").path
        let workosTokensJSON = #"{"refresh_token":"refresh-xyz"}"#
        let outerJSON: [String: Any] = ["workos_tokens": workosTokensJSON]
        let data = try JSONSerialization.data(withJSONObject: outerJSON)
        try data.write(to: URL(fileURLWithPath: supabasePath))

        #expect(throws: SourceAdapterError.self) {
            try GranolaAPIClient.discoverToken(from: supabasePath)
        }
    }

    // MARK: - Codable Model Parsing

    @Test("GranolaDocumentSummary decodes from JSON with snake_case keys")
    func documentSummaryDecoding() throws {
        let json = """
        {
            "id": "doc-123",
            "title": "Weekly Standup",
            "created_at": "2026-01-15T10:00:00Z",
            "updated_at": "2026-01-15T11:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let summary = try decoder.decode(GranolaDocumentSummary.self, from: json)
        #expect(summary.id == "doc-123")
        #expect(summary.title == "Weekly Standup")
        #expect(summary.createdAt == "2026-01-15T10:00:00Z")
        #expect(summary.updatedAt == "2026-01-15T11:00:00Z")
    }

    @Test("GranolaDocumentSummary decodes with minimal fields")
    func documentSummaryMinimalDecoding() throws {
        let json = """
        {"id": "doc-456"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let summary = try decoder.decode(GranolaDocumentSummary.self, from: json)
        #expect(summary.id == "doc-456")
        #expect(summary.title == nil)
        #expect(summary.createdAt == nil)
        #expect(summary.updatedAt == nil)
    }

    @Test("GranolaDocumentMetadata decodes with attendees")
    func documentMetadataDecoding() throws {
        let json = """
        {
            "creator": {"name": "Alice", "email": "alice@example.com"},
            "attendees": [
                {"name": "Bob", "email": "bob@example.com", "details": {"person": {"name": {"fullName": "Bob Smith"}}}},
                {"name": "Carol", "email": null}
            ],
            "duration_seconds": 3600,
            "title": "Design Review",
            "created_at": "2026-01-15T10:00:00Z",
            "participants": ["alice@example.com", "bob@example.com"],
            "labels": ["design", "review"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(GranolaDocumentMetadata.self, from: json)
        #expect(metadata.creator?.name == "Alice")
        #expect(metadata.attendees?.count == 2)
        #expect(metadata.durationSeconds == 3600)
        #expect(metadata.title == "Design Review")
        #expect(metadata.attendees?[0].details?.person?.name?.fullName == "Bob Smith")
        #expect(metadata.participants?.count == 2)
        #expect(metadata.labels?.count == 2)
    }

    @Test("GranolaDocumentMetadata decodes with empty object")
    func documentMetadataEmptyDecoding() throws {
        let json = "{}".data(using: .utf8)!
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(GranolaDocumentMetadata.self, from: json)
        #expect(metadata.creator == nil)
        #expect(metadata.attendees == nil)
        #expect(metadata.durationSeconds == nil)
    }

    @Test("GranolaTranscriptSegment decodes from JSON")
    func transcriptSegmentDecoding() throws {
        let json = """
        {
            "id": "seg-001",
            "document_id": "doc-123",
            "start_timestamp": "2026-01-15T10:00:00Z",
            "end_timestamp": "2026-01-15T10:01:00Z",
            "text": "Hello everyone, let's get started.",
            "source": "microphone",
            "is_final": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let segment = try decoder.decode(GranolaTranscriptSegment.self, from: json)
        #expect(segment.id == "seg-001")
        #expect(segment.documentId == "doc-123")
        #expect(segment.startTimestamp == "2026-01-15T10:00:00Z")
        #expect(segment.endTimestamp == "2026-01-15T10:01:00Z")
        #expect(segment.text == "Hello everyone, let's get started.")
        #expect(segment.source == "microphone")
        #expect(segment.isFinal == true)
    }

    @Test("GranolaTranscriptSegment decodes without is_final")
    func transcriptSegmentWithoutIsFinal() throws {
        let json = """
        {
            "id": "seg-002",
            "document_id": "doc-123",
            "start_timestamp": "2026-01-15T10:00:00Z",
            "end_timestamp": "2026-01-15T10:01:00Z",
            "text": "Some text",
            "source": "system"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let segment = try decoder.decode(GranolaTranscriptSegment.self, from: json)
        #expect(segment.id == "seg-002")
        #expect(segment.source == "system")
        #expect(segment.isFinal == nil)
    }

    @Test("GranolaAttendee nested details structure decodes")
    func attendeeDetailsDecoding() throws {
        let json = """
        {
            "name": "Test User",
            "email": "test@example.com",
            "details": {
                "person": {
                    "name": {
                        "fullName": "Test A. User"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let attendee = try decoder.decode(GranolaAttendee.self, from: json)
        #expect(attendee.name == "Test User")
        #expect(attendee.details?.person?.name?.fullName == "Test A. User")
    }

    @Test("Documents list response wrapper decodes")
    func documentsListResponseDecoding() throws {
        let json = """
        {
            "docs": [
                {"id": "doc-1", "title": "Meeting 1"},
                {"id": "doc-2", "title": "Meeting 2"}
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(GranolaDocumentsResponse.self, from: json)
        #expect(response.docs.count == 2)
        #expect(response.docs[0].id == "doc-1")
        #expect(response.docs[1].title == "Meeting 2")
    }

    // MARK: - Client Initialization

    @Test("GranolaAPIClient can be initialized")
    func clientInitialization() {
        let client = GranolaAPIClient(token: "test-token")
        // Verifying the actor can be constructed without errors
        #expect(client is GranolaAPIClient)
    }

    @Test("GranolaAPIClient can be initialized with custom baseURL")
    func clientInitializationWithCustomBaseURL() {
        let client = GranolaAPIClient(token: "test-token", baseURL: "https://custom.api.example.com")
        #expect(client is GranolaAPIClient)
    }
}
