// ABOUTME: Database lifecycle manager providing read/write access to SQLite via GRDB
// ABOUTME: Configures WAL mode, foreign keys, and provides factory methods for in-memory and persistent databases

import Foundation
import GRDB

public struct AppDatabase: Sendable {
    private let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        NodeLifeMigrations.registerMigrations(&migrator)
        return migrator
    }

    public var writer: any DatabaseWriter { dbWriter }
}

extension AppDatabase {
    public static func makeInMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDatabase(dbQueue)
    }

    public static func makePersistent(at path: String) throws -> AppDatabase {
        let dbPool = try DatabasePool(path: path, configuration: makeConfiguration())
        return try AppDatabase(dbPool)
    }

    public static func makeDefault() throws -> AppDatabase {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dbDir = appSupport.appendingPathComponent("NodeLife", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("nodelife.sqlite").path
        return try makePersistent(at: dbPath)
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }
        #endif
        return config
    }
}

extension AppDatabase {
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.read(block)
    }

    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.write(block)
    }
}
