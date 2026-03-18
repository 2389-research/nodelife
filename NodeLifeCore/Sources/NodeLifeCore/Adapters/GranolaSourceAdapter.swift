// ABOUTME: GranolaSourceAdapter reads meeting data from Granola's cache-v6.json file
// ABOUTME: Parses documents, transcripts, and calendar events from the single cache file into Meeting and MeetingChunk records

import Foundation
import CryptoKit

/// Configuration for the GranolaSourceAdapter
public struct GranolaConfig: Sendable {
    /// Path to the Granola data directory (containing cache-v6.json)
    public let dataPath: String

    /// Default path based on typical macOS app data locations
    public static let defaultDataPath = "~/Library/Application Support/Granola"

    public init(dataPath: String? = nil) {
        self.dataPath = dataPath ?? Self.defaultDataPath.expandingTildeInPath
    }
}

/// Adapter for reading meetings from Granola app data
public struct GranolaSourceAdapter: SourceAdapter, Sendable {
    private let config: GranolaConfig

    public let metadata: AdapterMetadata = AdapterMetadata(
        id: "granola",
        name: "Granola Source Adapter",
        version: "1.0.0",
        description: "Reads meeting data from Granola app storage"
    )

    public init(config: GranolaConfig) {
        self.config = config
    }

    public func listMeetings(since: Date?) async throws -> [Meeting] {
        let cache = try loadCache()

        let meetings = cache.cache.state.documents.values.compactMap { doc -> Meeting? in
            guard doc.type == "meeting" else { return nil }
            guard doc.deletedAt == nil else { return nil }

            guard let createdDate = parseISO8601(doc.createdAt) else { return nil }

            if let since = since, createdDate < since {
                return nil
            }

            let duration = computeDuration(from: doc.googleCalendarEvent)
            let transcript = doc.notesPlain ?? ""

            return Meeting(
                id: deterministicUUID(from: doc.id),
                sourceID: doc.id,
                title: doc.title,
                date: createdDate,
                duration: duration,
                rawTranscript: transcript,
                sourceAdapter: metadata.id
            )
        }

        return meetings.sorted { $0.date > $1.date }
    }

    public func fetchMeeting(id: String) async throws -> Meeting {
        let meetings = try await listMeetings(since: nil)
        guard let meeting = meetings.first(where: { $0.sourceID == id }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with source ID '\(id)' not found")
        }
        return meeting
    }

    public func fetchTranscript(meetingID: UUID) async throws -> [MeetingChunk] {
        let cache = try loadCache()

        // Find the document matching this meeting UUID by listing meetings and matching
        let meetings = try await listMeetings(since: nil)
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with ID '\(meetingID)' not found")
        }

        guard let segments = cache.cache.state.transcripts?[meeting.sourceID], !segments.isEmpty else {
            return []
        }

        // Sort segments by start timestamp
        let sortedSegments = segments.sorted { a, b in
            guard let dateA = parseISO8601(a.startTimestamp), let dateB = parseISO8601(b.startTimestamp) else {
                return false
            }
            return dateA < dateB
        }

        // Compute base time from first segment
        guard let firstStart = parseISO8601(sortedSegments[0].startTimestamp) else {
            return []
        }
        let baseTime = firstStart.timeIntervalSince1970

        var chunks: [MeetingChunk] = []
        for (index, segment) in sortedSegments.enumerated() {
            let startOffset: TimeInterval?
            if let startDate = parseISO8601(segment.startTimestamp) {
                startOffset = startDate.timeIntervalSince1970 - baseTime
            } else {
                startOffset = nil
            }

            let endOffset: TimeInterval?
            if let endDate = parseISO8601(segment.endTimestamp) {
                endOffset = endDate.timeIntervalSince1970 - baseTime
            } else {
                endOffset = nil
            }

            let chunk = MeetingChunk(
                meetingID: meetingID,
                chunkIndex: index,
                text: segment.text,
                speaker: segment.source,
                startTime: startOffset,
                endTime: endOffset
            )
            chunks.append(chunk)
        }

        return chunks
    }

    // MARK: - Private Methods

    /// Generates a deterministic UUID from a source ID string using SHA256 hashing.
    /// This ensures the same sourceID always produces the same UUID across calls.
    private func deterministicUUID(from sourceID: String) -> UUID {
        let hash = SHA256.hash(data: Data(sourceID.utf8))
        let bytes = Array(hash)
        // Use first 16 bytes of SHA256 to form a UUID
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }

    private func loadCache() throws -> GranolaCacheFile {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: config.dataPath) else {
            throw SourceAdapterError.sourceNotAccessible("Granola data directory does not exist: \(config.dataPath)")
        }

        let cacheFileURL = URL(fileURLWithPath: config.dataPath).appendingPathComponent("cache-v6.json")

        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            throw SourceAdapterError.sourceNotAccessible("Granola cache file not found: \(cacheFileURL.path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: cacheFileURL)
        } catch {
            throw SourceAdapterError.ioError("Failed to read Granola cache file: \(error.localizedDescription)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(GranolaCacheFile.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse Granola cache JSON: \(error.localizedDescription)")
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func computeDuration(from event: GranolaCalendarEvent?) -> TimeInterval {
        guard let event = event,
              let startDate = parseISO8601(event.start.dateTime),
              let endDate = parseISO8601(event.end.dateTime) else {
            return 0
        }
        return endDate.timeIntervalSince(startDate)
    }
}

// MARK: - Codable Models (private, match Granola cache-v6.json structure)

private struct GranolaCacheFile: Codable {
    let cache: GranolaCacheWrapper
}

private struct GranolaCacheWrapper: Codable {
    let state: GranolaCacheState
}

private struct GranolaCacheState: Codable {
    let documents: [String: GranolaDocument]
    let transcripts: [String: [GranolaTranscriptSegment]]?
    let meetingsMetadata: [String: GranolaMeetingsMetadataEntry]?
}

private struct GranolaDocument: Codable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let title: String
    let type: String
    let transcribe: Bool?
    let notesPlain: String?
    let notesMarkdown: String?
    let deletedAt: String?
    let people: GranolaPeople?
    let googleCalendarEvent: GranolaCalendarEvent?
    let summary: String?
    let overview: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case title, type, transcribe
        case notesPlain = "notes_plain"
        case notesMarkdown = "notes_markdown"
        case deletedAt = "deleted_at"
        case people
        case googleCalendarEvent = "google_calendar_event"
        case summary, overview
    }
}

private struct GranolaPeople: Codable {
    let creator: GranolaPersonRef?
    let attendees: [GranolaAttendee]?
}

private struct GranolaPersonRef: Codable {
    let name: String?
    let email: String?
}

private struct GranolaAttendee: Codable {
    let email: String?
    let details: GranolaAttendeeDetails?
}

private struct GranolaAttendeeDetails: Codable {
    let person: GranolaAttendeePerson?
}

private struct GranolaAttendeePerson: Codable {
    let name: GranolaAttendeePersonName?
}

private struct GranolaAttendeePersonName: Codable {
    let fullName: String?
}

private struct GranolaCalendarEvent: Codable {
    let start: GranolaCalendarTime
    let end: GranolaCalendarTime
}

private struct GranolaCalendarTime: Codable {
    let dateTime: String
}

private struct GranolaTranscriptSegment: Codable {
    let id: String
    let documentId: String
    let startTimestamp: String
    let endTimestamp: String
    let text: String
    let source: String
    let isFinal: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case text, source
        case isFinal = "is_final"
    }
}

private struct GranolaMeetingsMetadataEntry: Codable {
    let creator: GranolaPersonRef?
    let attendees: [GranolaAttendee]?
}

// MARK: - Extensions

extension String {
    /// Expands tilde (~) in file paths to the user's home directory
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}
