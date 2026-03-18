// ABOUTME: Tests for KeychainService secure storage
// ABOUTME: Verifies save, retrieve, update, and delete operations

import Testing
import Foundation
@testable import NodeLifeCore

@Test func keychainSaveAndRetrieve() throws {
    let keychain = KeychainService(serviceName: "com.nodelife.test.\(UUID().uuidString)")
    try keychain.save(key: "api_key", value: "sk-test-123")
    let retrieved = try keychain.retrieve(key: "api_key")
    #expect(retrieved == "sk-test-123")
    try keychain.delete(key: "api_key")
}

@Test func keychainRetrieveNonexistent() throws {
    let keychain = KeychainService(serviceName: "com.nodelife.test.\(UUID().uuidString)")
    let result = try keychain.retrieve(key: "nonexistent")
    #expect(result == nil)
}

@Test func keychainUpdateExisting() throws {
    let keychain = KeychainService(serviceName: "com.nodelife.test.\(UUID().uuidString)")
    try keychain.save(key: "api_key", value: "old-value")
    try keychain.save(key: "api_key", value: "new-value")
    let retrieved = try keychain.retrieve(key: "api_key")
    #expect(retrieved == "new-value")
    try keychain.delete(key: "api_key")
}

@Test func keychainDelete() throws {
    let keychain = KeychainService(serviceName: "com.nodelife.test.\(UUID().uuidString)")
    try keychain.save(key: "api_key", value: "to-delete")
    try keychain.delete(key: "api_key")
    let result = try keychain.retrieve(key: "api_key")
    #expect(result == nil)
}
