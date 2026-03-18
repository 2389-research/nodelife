// ABOUTME: Tests for database schema migrations
// ABOUTME: Verifies all tables, indexes, FTS5, and foreign keys are created correctly

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func migrationsCreateAllTables() throws {
    let db = try AppDatabase.makeInMemory()
    let tables = try db.read { db in
        try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type='table'
                AND name NOT LIKE 'sqlite_%'
                AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """
        )
    }

    #expect(tables.contains("meetings"))
    #expect(tables.contains("meeting_chunks"))
    #expect(tables.contains("entities"))
    #expect(tables.contains("entity_aliases"))
    #expect(tables.contains("mentions"))
    #expect(tables.contains("relationships"))
    #expect(tables.contains("extraction_runs"))
    #expect(tables.contains("jobs"))
    #expect(tables.contains("merge_history"))
}

@Test func migrationsCreateFTS5Tables() throws {
    let db = try AppDatabase.makeInMemory()
    let tables = try db.read { db in
        try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type='table'
                AND name LIKE '%fts%'
                ORDER BY name
                """
        )
    }

    #expect(tables.contains("meeting_chunks_fts"))
    #expect(tables.contains("entities_fts"))
}

@Test func migrationsEnforceForeignKeys() throws {
    let db = try AppDatabase.makeInMemory()
    let fkEnabled = try db.read { db in
        try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
    }
    #expect(fkEnabled == 1)
}

@Test func relationshipUsesWeightColumn() throws {
    let db = try AppDatabase.makeInMemory()
    let columns = try db.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(relationships)")
    }
    let columnNames = columns.map { $0["name"] as String }

    #expect(columnNames.contains("weight"))
    #expect(!columnNames.contains("strength"))
}

@Test func migrationsCreateUniqueIndexes() throws {
    let db = try AppDatabase.makeInMemory()
    let indexes = try db.read { db in
        try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type='index' AND sql LIKE '%UNIQUE%'"
        )
    }

    #expect(!indexes.isEmpty)
}
