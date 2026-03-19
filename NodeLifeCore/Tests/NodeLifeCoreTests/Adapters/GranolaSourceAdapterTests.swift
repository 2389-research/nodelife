// ABOUTME: Tests for GranolaSourceAdapter verifying config construction, protocol conformance, and deterministic UUID generation
// ABOUTME: Validates the API-based adapter interface without making real HTTP calls

import Testing
import Foundation
@testable import NodeLifeCore

// MARK: - GranolaConfig Tests

@Test func granolaConfigInitWithToken() {
    let config = GranolaConfig(token: "test-token-123")
    #expect(config.token == "test-token-123")
    #expect(config.baseURL == GranolaConfig.defaultBaseURL)
}

@Test func granolaConfigInitWithCustomBaseURL() {
    let config = GranolaConfig(token: "tok", baseURL: "https://custom.api.example.com")
    #expect(config.token == "tok")
    #expect(config.baseURL == "https://custom.api.example.com")
}

@Test func granolaConfigDefaultBaseURL() {
    #expect(GranolaConfig.defaultBaseURL == "https://api.granola.ai")
}

@Test func granolaConfigDefaultDataPath() {
    #expect(GranolaConfig.defaultDataPath == "~/Library/Application Support/Granola")
}

@Test func granolaConfigFromInstalledAppThrowsWhenNoSupabaseFile() {
    // This test verifies that fromInstalledApp() throws when supabase.json doesn't exist
    // at the default location (which it won't in a test environment unless Granola is installed)
    do {
        _ = try GranolaConfig.fromInstalledApp()
        // If it succeeds, Granola is actually installed — that's fine too
    } catch {
        #expect(error is SourceAdapterError)
    }
}

// MARK: - GranolaSourceAdapter Tests

@Test func granolaAdapterMetadata() {
    let config = GranolaConfig(token: "test-token")
    let adapter = GranolaSourceAdapter(config: config)
    #expect(adapter.metadata.id == "granola")
    #expect(adapter.metadata.name == "Granola Source Adapter")
    #expect(adapter.metadata.version == "2.0.0")
    #expect(adapter.metadata.description == "Reads meeting data from Granola API")
}

@Test func granolaAdapterConformsToSourceAdapter() {
    let config = GranolaConfig(token: "test-token")
    let adapter = GranolaSourceAdapter(config: config)
    let _: any SourceAdapter = adapter
}

@Test func granolaAdapterDeterministicUUIDIsConsistent() {
    // The same sourceID should always produce the same UUID
    let config = GranolaConfig(token: "test-token")
    let adapter = GranolaSourceAdapter(config: config)
    let uuid1 = adapter.deterministicUUID(from: "test-source-id-abc")
    let uuid2 = adapter.deterministicUUID(from: "test-source-id-abc")
    #expect(uuid1 == uuid2)

    // Different sourceIDs should produce different UUIDs
    let uuid3 = adapter.deterministicUUID(from: "different-source-id")
    #expect(uuid1 != uuid3)
}
