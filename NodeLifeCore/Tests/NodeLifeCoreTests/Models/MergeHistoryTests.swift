// ABOUTME: Tests for the MergeHistory model record
// ABOUTME: Verifies GRDB conformance, default values, and merge action enum

import Testing
import Foundation
@testable import NodeLifeCore

@Test func mergeHistoryCreationWithDefaults() {
    let history = MergeHistory(
        primaryEntityId: UUID(),
        mergedEntityId: UUID(),
        action: .merge,
        originalEntityData: "{}"
    )
    #expect(history.action == .merge)
    #expect(history.reason == nil)
    #expect(history.originalAliasesData == nil)
    #expect(history.originalRelationshipsData == nil)
    #expect(history.undoneAt == nil)
}

@Test func mergeHistoryTableName() {
    #expect(MergeHistory.databaseTableName == "merge_history")
}

@Test func mergeActionRawValues() {
    #expect(MergeAction.merge.rawValue == "merge")
    #expect(MergeAction.split.rawValue == "split")
    #expect(MergeAction.undo.rawValue == "undo")
    #expect(MergeAction.allCases.count == 3)
}

@Test func mergeHistoryPreservesData() {
    let entityData = "{\"name\": \"Test\"}"
    let aliasData = "[\"alias1\"]"
    let history = MergeHistory(
        primaryEntityId: UUID(),
        mergedEntityId: UUID(),
        action: .split,
        reason: "incorrect merge",
        originalEntityData: entityData,
        originalAliasesData: aliasData
    )
    #expect(history.originalEntityData == entityData)
    #expect(history.originalAliasesData == aliasData)
    #expect(history.reason == "incorrect merge")
}
