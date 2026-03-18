// ABOUTME: Tests for the EntityAlias model record
// ABOUTME: Verifies GRDB conformance, default values, and enum types

import Testing
import Foundation
@testable import NodeLifeCore

@Test func entityAliasCreation() {
    let alias = EntityAlias(entityID: UUID(), alias: "Harp Dog", source: .manual)
    #expect(alias.source == .manual)
    #expect(alias.alias == "Harp Dog")
}

@Test func entityAliasAutoSource() {
    let alias = EntityAlias(entityID: UUID(), alias: "H.D.", source: .auto)
    #expect(alias.source == .auto)
}

@Test func entityAliasTableName() {
    #expect(EntityAlias.databaseTableName == "entity_aliases")
}

@Test func aliasSourceRawValues() {
    #expect(AliasSource.auto.rawValue == "auto")
    #expect(AliasSource.manual.rawValue == "manual")
    #expect(AliasSource.allCases.count == 2)
}
