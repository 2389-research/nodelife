// ABOUTME: MuesliCacheAdapter implementation for reading meeting data from local muesli cache directories
// ABOUTME: Parses paired _metadata.json and _transcript.json files matching muesli's actual data format

import Foundation

/// Configuration for the MuesliCacheAdapter
public struct MuesliCacheConfig: Sendable {
    /// Path to the muesli cache directory (typically ~/.local/share/muesli/raw/)
    public let cachePath: String

    public init(cachePath: String) {
        self.cachePath = cachePath
    }
}

/// Adapter for reading meetings from a local muesli cache directory
public struct MuesliCacheAdapter: SourceAdapter, Sendable {
    private let config: MuesliCacheConfig

    public let metadata: AdapterMetadata = AdapterMetadata(
        id: "muesli-cache",
        name: "Muesli Cache Adapter",
        version: "1.0.0",
        description: "Reads meeting data from local muesli cache directories"
    )

    public init(config: MuesliCacheConfig) {
        self.config = config
    }

    public func listMeetings(since: Date?) async throws -> [Meeting] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: config.cachePath) else {
            throw SourceAdapterError.sourceNotAccessible("Cache directory does not exist: \(config.cachePath)")
        }

        let cacheURL = URL(fileURLWithPath: config.cachePath)
        let contents: [URL]

        do {
            contents = try fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        } catch {
            throw SourceAdapterError.ioError("Failed to read cache directory: \(error.localizedDescription)")
        }

        let metadataFiles = contents.filter { $0.pathExtension == "json" && $0.lastPathComponent.contains("_metadata") }
        var meetings: [Meeting] = []

        for metadataFile in metadataFiles {
            do {
                if let meeting = try parseMeetingMetadata(from: metadataFile, since: since) {
                    meetings.append(meeting)
                }
            } catch {
                // Skip unparseable files and continue processing others
                continue
            }
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
        let meetings = try await listMeetings(since: nil)
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with ID '\(meetingID)' not found")
        }

        let cacheURL = URL(fileURLWithPath: config.cachePath)
        let transcriptFile = try findTranscriptFile(for: meeting.sourceID, in: cacheURL)

        do {
            let transcriptData = try Data(contentsOf: transcriptFile)
            return try parseJSONTranscript(transcriptData, meetingID: meetingID)
        } catch let error as SourceAdapterError {
            throw error
        } catch {
            throw SourceAdapterError.ioError("Failed to read transcript file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func parseMeetingMetadata(from file: URL, since: Date?) throws -> Meeting? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw SourceAdapterError.ioError("Failed to read metadata file: \(error.localizedDescription)")
        }

        let muesliMetadata: MuesliMetadata
        do {
            let decoder = JSONDecoder()
            muesliMetadata = try decoder.decode(MuesliMetadata.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse metadata JSON: \(error.localizedDescription)")
        }

        // Parse created_at as ISO8601 date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let meetingDate = formatter.date(from: muesliMetadata.created_at) else {
            // Try without fractional seconds as fallback
            let basicFormatter = ISO8601DateFormatter()
            guard let fallbackDate = basicFormatter.date(from: muesliMetadata.created_at) else {
                throw SourceAdapterError.invalidData("Failed to parse created_at date: \(muesliMetadata.created_at)")
            }
            return try buildMeeting(from: muesliMetadata, date: fallbackDate, file: file, since: since)
        }

        return try buildMeeting(from: muesliMetadata, date: meetingDate, file: file, since: since)
    }

    private func buildMeeting(from muesliMetadata: MuesliMetadata, date: Date, file: URL, since: Date?) throws -> Meeting? {
        // Filter by date if specified
        if let since = since, date < since {
            return nil
        }

        // Extract source ID from filename (strip _metadata suffix and .json extension)
        var sourceID = file.deletingPathExtension().lastPathComponent
        if sourceID.hasSuffix("_metadata") {
            sourceID = String(sourceID.dropLast("_metadata".count))
        }

        // Generate a deterministic UUID from the sourceID so the same file always produces the same meeting ID
        let deterministicID = UUID(uuidString: deterministicUUIDString(from: sourceID))
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        return Meeting(
            id: deterministicID,
            sourceID: sourceID,
            title: muesliMetadata.title ?? "Meeting \(sourceID)",
            date: date,
            duration: 0, // Duration is not available in muesli metadata
            rawTranscript: "",
            sourceAdapter: metadata.id
        )
    }

    private func findTranscriptFile(for sourceID: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let possibleNames = [
            "\(sourceID)_transcript.json",
            "\(sourceID).json",
            "\(sourceID)_transcript.md",
            "\(sourceID).md",
            "\(sourceID)_transcript.txt",
            "\(sourceID).txt"
        ]

        for name in possibleNames {
            let file = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: file.path) {
                return file
            }
        }

        throw SourceAdapterError.meetingNotFound("Transcript file not found for meeting: \(sourceID)")
    }

    private func parseJSONTranscript(_ data: Data, meetingID: UUID) throws -> [MeetingChunk] {
        let segments: [MuesliTranscriptSegment]
        do {
            segments = try JSONDecoder().decode([MuesliTranscriptSegment].self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse transcript JSON: \(error.localizedDescription)")
        }

        guard !segments.isEmpty else {
            return []
        }

        // Parse the first segment's start timestamp to use as the reference point for offsets
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let referenceDate: Date
        if let ref = formatter.date(from: segments[0].start_timestamp) {
            referenceDate = ref
        } else {
            let basicFormatter = ISO8601DateFormatter()
            referenceDate = basicFormatter.date(from: segments[0].start_timestamp) ?? Date()
        }

        var chunks: [MeetingChunk] = []

        for (index, segment) in segments.enumerated() {
            let startDate = formatter.date(from: segment.start_timestamp)
            let endDate = formatter.date(from: segment.end_timestamp)

            let startOffset: TimeInterval? = startDate.map { $0.timeIntervalSince(referenceDate) }
            let endOffset: TimeInterval? = endDate.map { $0.timeIntervalSince(referenceDate) }

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

    /// Generates a deterministic UUID v5-style string from a source identifier.
    /// Uses a simple hash-based approach to ensure the same sourceID always produces the same UUID.
    private func deterministicUUIDString(from input: String) -> String {
        var hash = [UInt8](repeating: 0, count: 16)
        let inputBytes = Array(input.utf8)
        for (i, byte) in inputBytes.enumerated() {
            hash[i % 16] ^= byte
            // Mix bits to improve distribution
            hash[i % 16] = hash[i % 16] &+ byte &* 31
        }
        // Set version 5 bits (name-based SHA-1) for format compliance
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80

        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return uuid
    }
}

// MARK: - Codable Models matching actual muesli data format

private struct MuesliMetadata: Codable {
    let title: String?
    let created_at: String
    let creator: MuesliCreator?
    let attendees: [MuesliAttendee]?
    let sharing_link_visibility: String?
}

private struct MuesliCreator: Codable {
    let name: String?
    let email: String?
    let details: MuesliPersonDetails?
}

private struct MuesliAttendee: Codable {
    let email: String?
    let details: MuesliPersonDetails?
}

private struct MuesliPersonDetails: Codable {
    let person: MuesliPersonName?
}

private struct MuesliPersonName: Codable {
    let name: MuesliFullName?
}

private struct MuesliFullName: Codable {
    let fullName: String?
}

private struct MuesliTranscriptSegment: Codable {
    let id: String
    let document_id: String
    let start_timestamp: String
    let end_timestamp: String
    let text: String
    let source: String
    let is_final: Bool
}
