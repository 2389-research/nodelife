// ABOUTME: Tests for the Entity model record
// ABOUTME: Verifies GRDB conformance, entity kinds, and mergedIntoId field

import Testing
import Foundation
@testable import NodeLifeCore

@Test func entityCreationSetsDefaults() {
    let entity = Entity(name: "Harper Reed", kind: .person)

    #expect(entity.canonicalName == "harper reed")
    #expect(entity.mergedIntoId == nil)
    #expect(entity.mentionCount == 0)
}

@Test func entityKindHasAllCases() {
    let kinds = EntityKind.allCases
    #expect(kinds.contains(.person))
    #expect(kinds.contains(.organization))
    #expect(kinds.contains(.project))
    #expect(kinds.contains(.concept))
    #expect(kinds.contains(.topic))
    #expect(kinds.contains(.place))
    #expect(kinds.contains(.actionItem))
    #expect(kinds.contains(.blogIdea))
    #expect(kinds.contains(.idea))
    #expect(kinds.contains(.other))
    #expect(kinds.count == 10)
}

@Test func entityTableName() {
    #expect(Entity.databaseTableName == "entities")
}
