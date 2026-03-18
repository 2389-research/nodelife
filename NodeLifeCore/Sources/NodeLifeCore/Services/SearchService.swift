// ABOUTME: SearchService provides full-text search across meetings, chunks, and entities
// ABOUTME: Uses SQL LIKE queries with relevance scoring for search results

import Foundation
import GRDB

/// Represents a single search result from any searchable content type
public struct SearchResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: SearchResultType
    public let title: String
    public let snippet: String
    public let date: Date?
    public let context: String?
    public let meetingID: UUID?
    public let entityID: UUID?
    public let relevanceScore: Double

    public init(
        id: UUID,
        type: SearchResultType,
        title: String,
        snippet: String,
        date: Date? = nil,
        context: String? = nil,
        meetingID: UUID? = nil,
        entityID: UUID? = nil,
        relevanceScore: Double = 1.0
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.snippet = snippet
        self.date = date
        self.context = context
        self.meetingID = meetingID
        self.entityID = entityID
        self.relevanceScore = relevanceScore
    }
}

/// The type of content a search result originated from
public enum SearchResultType: String, Sendable, Equatable {
    case meetingChunk
    case meeting
    case entity
}

/// Errors that can occur during search operations
public enum SearchServiceError: Error, Sendable, Equatable {
    case emptyQuery
    case invalidQuery(String)
    case databaseError(String)
    case searchCancelled
}

/// Actor-based service providing search across meetings, chunks, and entities
public actor SearchService: Sendable {
    private let database: AppDatabase
    private var currentSearchTask: Task<[SearchResult], Error>?

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Search across all content types using LIKE queries
    /// - Parameters:
    ///   - query: The search string to match against
    ///   - limit: Maximum number of results to return (default 50)
    ///   - offset: Number of results to skip for pagination (default 0)
    /// - Returns: An array of SearchResult sorted by relevance score descending
    public func search(query: String, limit: Int = 50, offset: Int = 0) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Cancel any previously running search
        currentSearchTask?.cancel()

        let db = database
        let task = Task<[SearchResult], Error> {
            var results: [SearchResult] = []

            try Task.checkCancellation()

            let chunkResults = try searchMeetingChunks(query: trimmed, limit: limit, database: db)
            results.append(contentsOf: chunkResults)

            try Task.checkCancellation()

            let meetingResults = try searchMeetings(query: trimmed, limit: limit, database: db)
            results.append(contentsOf: meetingResults)

            try Task.checkCancellation()

            let entityResults = try searchEntities(query: trimmed, limit: limit, database: db)
            results.append(contentsOf: entityResults)

            return Array(
                results
                    .sorted { $0.relevanceScore > $1.relevanceScore }
                    .dropFirst(offset)
                    .prefix(limit)
            )
        }

        currentSearchTask = task
        return try await task.value
    }

    /// Cancel the currently running search task, if any
    public func cancelSearch() {
        currentSearchTask?.cancel()
        currentSearchTask = nil
    }

    // MARK: - Private Search Methods

    private func searchMeetingChunks(query: String, limit: Int, database: AppDatabase) throws -> [SearchResult] {
        try database.read { db in
            let pattern = "%\(query)%"
            let rows = try Row.fetchAll(db, sql: """
                SELECT mc.id, mc.meetingID, mc.text, mc.speaker, m.title, m.date
                FROM meeting_chunks mc
                JOIN meetings m ON mc.meetingID = m.id
                WHERE mc.text LIKE ? COLLATE NOCASE
                ORDER BY m.date DESC
                LIMIT ?
                """, arguments: [pattern, limit])

            return rows.compactMap { row -> SearchResult? in
                guard let idData = row["id"] as? Data,
                      let meetingIDData = row["meetingID"] as? Data,
                      let text = row["text"] as? String,
                      let title = row["title"] as? String else { return nil }

                let id = UUID(data: idData)
                let meetingID = UUID(data: meetingIDData)
                guard let id, let meetingID else { return nil }

                let date: Date? = row["date"]
                let speaker: String? = row["speaker"]
                let snippet = String(text.prefix(200))

                return SearchResult(
                    id: id,
                    type: .meetingChunk,
                    title: title,
                    snippet: snippet,
                    date: date,
                    context: speaker.map { "Speaker: \($0)" },
                    meetingID: meetingID,
                    relevanceScore: 1.0
                )
            }
        }
    }

    private func searchMeetings(query: String, limit: Int, database: AppDatabase) throws -> [SearchResult] {
        try database.read { db in
            let pattern = "%\(query)%"
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, title, date, summary
                FROM meetings
                WHERE title LIKE ? COLLATE NOCASE OR summary LIKE ? COLLATE NOCASE
                ORDER BY date DESC
                LIMIT ?
                """, arguments: [pattern, pattern, limit])

            return rows.compactMap { row -> SearchResult? in
                guard let idData = row["id"] as? Data,
                      let title = row["title"] as? String else { return nil }

                let id = UUID(data: idData)
                guard let id else { return nil }

                let date: Date? = row["date"]
                let summary: String? = row["summary"]
                let snippet = summary ?? title

                return SearchResult(
                    id: id,
                    type: .meeting,
                    title: title,
                    snippet: snippet,
                    date: date,
                    meetingID: id,
                    relevanceScore: 0.9
                )
            }
        }
    }

    private func searchEntities(query: String, limit: Int, database: AppDatabase) throws -> [SearchResult] {
        try database.read { db in
            let pattern = "%\(query)%"
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, kind, summary, lastSeenAt
                FROM entities
                WHERE name LIKE ? COLLATE NOCASE OR canonicalName LIKE ? COLLATE NOCASE
                ORDER BY mentionCount DESC
                LIMIT ?
                """, arguments: [pattern, pattern, limit])

            return rows.compactMap { row -> SearchResult? in
                guard let idData = row["id"] as? Data,
                      let name = row["name"] as? String,
                      let kind = row["kind"] as? String else { return nil }

                let id = UUID(data: idData)
                guard let id else { return nil }

                let summary: String? = row["summary"]
                let date: Date? = row["lastSeenAt"]

                return SearchResult(
                    id: id,
                    type: .entity,
                    title: name,
                    snippet: summary ?? name,
                    date: date,
                    context: kind.capitalized,
                    entityID: id,
                    relevanceScore: 0.8
                )
            }
        }
    }
}

// MARK: - UUID Data Conversion

extension UUID {
    /// Initialize a UUID from its 16-byte Data representation (as stored by GRDB)
    init?(data: Data) {
        guard data.count == 16 else { return nil }
        let uuid = data.withUnsafeBytes { buffer -> uuid_t in
            buffer.load(as: uuid_t.self)
        }
        self.init(uuid: uuid)
    }
}
