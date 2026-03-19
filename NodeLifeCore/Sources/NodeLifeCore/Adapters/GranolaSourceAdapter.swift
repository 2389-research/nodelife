// ABOUTME: GranolaSourceAdapter reads meeting data from the Granola HTTP API
// ABOUTME: Uses GranolaAPIClient for document listing, metadata retrieval, and transcript fetching

import Foundation
import CryptoKit

/// Configuration for the GranolaSourceAdapter
public struct GranolaConfig: Sendable {
    /// Auth token for Granola API
    public let token: String

    /// API base URL
    public let baseURL: String

    /// Default Granola API base URL
    public static let defaultBaseURL = "https://api.granola.ai"

    /// Default path for Granola application data
    public static let defaultDataPath = "~/Library/Application Support/Granola"

    public init(token: String, baseURL: String = Self.defaultBaseURL) {
        self.token = token
        self.baseURL = baseURL
    }

    /// Create config from installed Granola app session
    public static func fromInstalledApp() throws -> GranolaConfig {
        let token = try GranolaAPIClient.discoverToken()
        return GranolaConfig(token: token)
    }
}

/// Adapter for reading meetings from Granola via its HTTP API
public struct GranolaSourceAdapter: SourceAdapter, Sendable {
    private let client: GranolaAPIClient

    public let metadata: AdapterMetadata = AdapterMetadata(
        id: "granola",
        name: "Granola Source Adapter",
        version: "2.0.0",
        description: "Reads meeting data from Granola API"
    )

    public init(config: GranolaConfig) {
        self.client = GranolaAPIClient(token: config.token, baseURL: config.baseURL)
    }

    public func listMeetings(since: Date?) async throws -> [Meeting] {
        let docs = try await client.listAllDocuments()

        let meetings = docs.compactMap { doc -> Meeting? in
            let createdDate = parseISO8601(doc.createdAt) ?? parseISO8601(doc.updatedAt) ?? Date()

            if let since = since, createdDate < since {
                return nil
            }

            return Meeting(
                id: deterministicUUID(from: doc.id),
                sourceID: doc.id,
                title: doc.title ?? "Untitled",
                date: createdDate,
                duration: 0,
                rawTranscript: "",
                sourceAdapter: metadata.id
            )
        }

        return meetings.sorted { $0.date > $1.date }
    }

    public func fetchMeeting(id: String) async throws -> Meeting {
        let docs = try await client.listAllDocuments()
        guard let doc = docs.first(where: { $0.id == id }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with source ID '\(id)' not found")
        }

        let createdDate = parseISO8601(doc.createdAt) ?? parseISO8601(doc.updatedAt) ?? Date()

        // Fetch metadata for duration
        var duration: TimeInterval = 0
        if let meta = try? await client.getMetadata(documentID: id),
           let seconds = meta.durationSeconds {
            duration = TimeInterval(seconds)
        }

        return Meeting(
            id: deterministicUUID(from: doc.id),
            sourceID: doc.id,
            title: doc.title ?? "Untitled",
            date: createdDate,
            duration: duration,
            rawTranscript: "",
            sourceAdapter: metadata.id
        )
    }

    public func fetchTranscript(meetingID: UUID) async throws -> [MeetingChunk] {
        // Find the sourceID for this deterministic UUID
        let docs = try await client.listAllDocuments()
        guard let doc = docs.first(where: { deterministicUUID(from: $0.id) == meetingID }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with ID '\(meetingID)' not found")
        }

        let segments = try await client.getTranscript(documentID: doc.id)
        guard !segments.isEmpty else {
            return []
        }

        // Sort segments by start timestamp
        let sortedSegments = segments.sorted { a, b in
            guard let dateA = parseISO8601(a.startTimestamp),
                  let dateB = parseISO8601(b.startTimestamp) else {
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

    // MARK: - Internal Methods

    /// Generates a deterministic UUID from a source ID string using SHA256 hashing.
    /// This ensures the same sourceID always produces the same UUID across calls.
    func deterministicUUID(from sourceID: String) -> UUID {
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

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Extensions

extension String {
    /// Expands tilde (~) in file paths to the user's home directory
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}
