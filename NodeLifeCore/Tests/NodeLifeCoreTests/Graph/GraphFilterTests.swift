// ABOUTME: Tests for GraphFilter entity and relationship filtering
// ABOUTME: Verifies passes logic for type, weight, and confidence constraints

import Testing
import Foundation
@testable import NodeLifeCore

@Test func filterPassesMatchingEntityType() {
    let filter = GraphFilter(entityTypes: [.person, .organization])
    let entity = Entity(name: "Test", kind: .person)
    #expect(filter.passesEntity(entity) == true)
}

@Test func filterRejectsNonMatchingEntityType() {
    let filter = GraphFilter(entityTypes: [.person])
    let entity = Entity(name: "Test", kind: .concept)
    #expect(filter.passesEntity(entity) == false)
}

@Test func filterPassesRelationshipAboveWeight() {
    let filter = GraphFilter(minEdgeWeight: 0.5)
    let rel = Relationship(sourceEntityID: UUID(), targetEntityID: UUID(), kind: .worksFor, weight: 0.8, extractionRunID: UUID())
    #expect(filter.passesRelationship(rel) == true)
}

@Test func filterRejectsRelationshipBelowWeight() {
    let filter = GraphFilter(minEdgeWeight: 0.5)
    let rel = Relationship(sourceEntityID: UUID(), targetEntityID: UUID(), kind: .worksFor, weight: 0.3, extractionRunID: UUID())
    #expect(filter.passesRelationship(rel) == false)
}

@Test func defaultFilterPassesEverything() {
    let filter = GraphFilter.default
    let entity = Entity(name: "Any", kind: .other)
    let rel = Relationship(sourceEntityID: UUID(), targetEntityID: UUID(), kind: .relatesTo, weight: 0.01, extractionRunID: UUID())
    #expect(filter.passesEntity(entity) == true)
    #expect(filter.passesRelationship(rel) == true)
}
