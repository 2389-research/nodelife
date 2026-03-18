// ABOUTME: Database schema migrations for NodeLife
// ABOUTME: Creates all 9 tables, indexes, FTS5 virtual tables in a single v1 migration

import GRDB

public struct NodeLifeMigrations {
    public static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in

            // -- meetings --
            try db.create(table: "meetings") { t in
                t.column("id", .blob).primaryKey()
                t.column("sourceID", .text).notNull()
                t.column("title", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("duration", .double).notNull()
                t.column("rawTranscript", .text).notNull()
                t.column("normalizedTranscript", .text)
                t.column("summary", .text)
                t.column("sourceAdapter", .text).notNull()
                t.column("transcriptStatus", .text).notNull().defaults(to: "pending")
                t.column("importedAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "meetings_on_sourceID_sourceAdapter",
                on: "meetings",
                columns: ["sourceID", "sourceAdapter"],
                unique: true
            )
            try db.create(
                index: "meetings_on_date",
                on: "meetings",
                columns: ["date"]
            )

            // -- extraction_runs (after meetings, which it references) --
            try db.create(table: "extraction_runs") { t in
                t.column("id", .blob).primaryKey()
                t.column("meetingID", .blob).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("promptVersion", .text).notNull()
                t.column("passName", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("status", .text).notNull().defaults(to: "running")
                t.column("errorMessage", .text)
            }

            try db.create(
                index: "extraction_runs_on_meetingID",
                on: "extraction_runs",
                columns: ["meetingID"]
            )

            // -- meeting_chunks --
            try db.create(table: "meeting_chunks") { t in
                t.column("id", .blob).primaryKey()
                t.column("meetingID", .blob).notNull().references("meetings", onDelete: .cascade)
                t.column("chunkIndex", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("normalizedText", .text)
                t.column("speaker", .text)
                t.column("startTime", .double)
                t.column("endTime", .double)
                t.column("embeddingJson", .text)
            }

            try db.create(
                index: "meeting_chunks_on_meetingID",
                on: "meeting_chunks",
                columns: ["meetingID"]
            )
            try db.create(
                index: "meeting_chunks_on_meetingID_chunkIndex",
                on: "meeting_chunks",
                columns: ["meetingID", "chunkIndex"],
                unique: true
            )

            // -- entities --
            try db.create(table: "entities") { t in
                t.column("id", .blob).primaryKey()
                t.column("name", .text).notNull()
                t.column("canonicalName", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("summary", .text)
                t.column("mergedIntoId", .blob).references("entities")
                t.column("mentionCount", .integer).notNull().defaults(to: 0)
                t.column("firstSeenAt", .datetime).notNull()
                t.column("lastSeenAt", .datetime).notNull()
            }

            try db.create(
                index: "entities_on_canonicalName",
                on: "entities",
                columns: ["canonicalName"]
            )
            try db.create(
                index: "entities_on_kind",
                on: "entities",
                columns: ["kind"]
            )

            // -- entity_aliases --
            try db.create(table: "entity_aliases") { t in
                t.column("id", .blob).primaryKey()
                t.column("entityID", .blob).notNull().references("entities", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("source", .text).notNull()
            }

            try db.create(
                index: "entity_aliases_on_entityID_alias",
                on: "entity_aliases",
                columns: ["entityID", "alias"],
                unique: true
            )

            // -- mentions --
            try db.create(table: "mentions") { t in
                t.column("id", .blob).primaryKey()
                t.column("entityID", .blob).notNull().references("entities", onDelete: .cascade)
                t.column("meetingChunkID", .blob).notNull()
                    .references("meeting_chunks", onDelete: .cascade)
                t.column("confidence", .double).notNull()
                t.column("extractionRunID", .blob).notNull()
                    .references("extraction_runs")
            }

            try db.create(
                index: "mentions_on_entityID",
                on: "mentions",
                columns: ["entityID"]
            )
            try db.create(
                index: "mentions_on_meetingChunkID",
                on: "mentions",
                columns: ["meetingChunkID"]
            )

            // -- relationships --
            try db.create(table: "relationships") { t in
                t.column("id", .blob).primaryKey()
                t.column("sourceEntityID", .blob).notNull()
                    .references("entities", onDelete: .cascade)
                t.column("targetEntityID", .blob).notNull()
                    .references("entities", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.column("confidence", .double).notNull().defaults(to: 0.0)
                t.column("evidence", .text)
                t.column("evidenceChunkRefsJson", .text)
                t.column("extractionRunID", .blob).notNull()
                    .references("extraction_runs")
            }

            try db.create(
                index: "relationships_on_sourceEntityID",
                on: "relationships",
                columns: ["sourceEntityID"]
            )
            try db.create(
                index: "relationships_on_targetEntityID",
                on: "relationships",
                columns: ["targetEntityID"]
            )

            // -- jobs --
            try db.create(table: "jobs") { t in
                t.column("id", .blob).primaryKey()
                t.column("kind", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("maxAttempts", .integer).notNull().defaults(to: 3)
                t.column("lastError", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("scheduledAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
            }

            try db.create(
                index: "jobs_on_status_scheduledAt",
                on: "jobs",
                columns: ["status", "scheduledAt"]
            )
            try db.create(
                index: "jobs_on_kind",
                on: "jobs",
                columns: ["kind"]
            )

            // -- merge_history --
            try db.create(table: "merge_history") { t in
                t.column("id", .blob).primaryKey()
                t.column("primaryEntityId", .blob).notNull()
                t.column("mergedEntityId", .blob).notNull()
                t.column("action", .text).notNull()
                t.column("reason", .text)
                t.column("originalEntityData", .text).notNull()
                t.column("originalAliasesData", .text)
                t.column("originalRelationshipsData", .text)
                t.column("performedAt", .datetime).notNull()
                t.column("undoneAt", .datetime)
            }

            try db.create(
                index: "merge_history_on_primaryEntityId",
                on: "merge_history",
                columns: ["primaryEntityId"]
            )
            try db.create(
                index: "merge_history_on_mergedEntityId",
                on: "merge_history",
                columns: ["mergedEntityId"]
            )

            // -- FTS5 virtual tables (standalone, populated manually) --
            try db.create(virtualTable: "meeting_chunks_fts", using: FTS5()) { t in
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("text")
            }

            try db.create(virtualTable: "entities_fts", using: FTS5()) { t in
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("name")
            }
        }
    }
}
