// ABOUTME: MuesliCacheAdapter implementation for reading meeting data from local muesli cache directories
// ABOUTME: Parses JSON metadata and transcript files, chunks transcripts by speaker turns

import Foundation

/// Configuration for the MuesliCacheAdapter
public struct MuesliCacheConfig: Sendable {
    /// Path to the muesli cache directory
    public let cachePath: String

    /// Maximum chunk size in characters (used as fallback when speaker-based chunking isn't available)
    public let maxChunkSize: Int

    public init(cachePath: String, maxChunkSize: Int = 2000) {
        self.cachePath = cachePath
        self.maxChunkSize = maxChunkSize
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

        let metadataFiles = contents.filter { $0.pathExtension == "json" && $0.lastPathComponent.contains("metadata") }
        var meetings: [Meeting] = []

        for metadataFile in metadataFiles {
            do {
                if let meeting = try await parseMeetingMetadata(from: metadataFile, since: since) {
                    meetings.append(meeting)
                }
            } catch {
                // Log error but continue processing other files
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
        // First find the meeting to get the source ID
        let meetings = try await listMeetings(since: nil)
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else {
            throw SourceAdapterError.meetingNotFound("Meeting with ID '\(meetingID)' not found")
        }

        // Look for transcript file based on source ID
        let cacheURL = URL(fileURLWithPath: config.cachePath)
        let transcriptFile = try findTranscriptFile(for: meeting.sourceID, in: cacheURL)

        do {
            let transcriptData = try Data(contentsOf: transcriptFile)

            if transcriptFile.pathExtension == "json" {
                return try parseJSONTranscript(transcriptData, meetingID: meetingID)
            } else {
                // Assume markdown or plain text
                let content = String(data: transcriptData, encoding: .utf8) ?? ""
                return try parseTextTranscript(content, meetingID: meetingID)
            }
        } catch {
            throw SourceAdapterError.ioError("Failed to read transcript file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func parseMeetingMetadata(from file: URL, since: Date?) async throws -> Meeting? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw SourceAdapterError.ioError("Failed to read metadata file: \(error.localizedDescription)")
        }

        let muesliMetadata: MuesliMetadata
        do {
            muesliMetadata = try JSONDecoder().decode(MuesliMetadata.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse metadata JSON: \(error.localizedDescription)")
        }

        // Filter by date if specified
        if let since = since, muesliMetadata.date < since {
            return nil
        }

        // Extract source ID from filename (remove metadata suffix and extension)
        var sourceID = file.deletingPathExtension().lastPathComponent
        if sourceID.hasSuffix("_metadata") {
            sourceID = String(sourceID.dropLast("_metadata".count))
        }

        let meeting = Meeting(
            sourceID: sourceID,
            title: muesliMetadata.title ?? "Meeting \(sourceID)",
            date: muesliMetadata.date,
            duration: muesliMetadata.duration ?? 0,
            rawTranscript: "", // Will be filled when transcript is fetched
            sourceAdapter: metadata.id
        )

        return meeting
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
        let transcript: MuesliTranscript
        do {
            transcript = try JSONDecoder().decode(MuesliTranscript.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse transcript JSON: \(error.localizedDescription)")
        }

        var chunks: [MeetingChunk] = []

        if let speakers = transcript.speakers {
            // Chunk by speaker turns
            for (index, speaker) in speakers.enumerated() {
                let chunk = MeetingChunk(
                    meetingID: meetingID,
                    chunkIndex: index,
                    text: speaker.text,
                    speaker: speaker.name,
                    startTime: speaker.startTime,
                    endTime: speaker.endTime
                )
                chunks.append(chunk)
            }
        } else if let text = transcript.text {
            // Fallback: chunk by text size
            chunks = chunkTextBySpeaker(text, meetingID: meetingID)
        }

        return chunks
    }

    private func parseTextTranscript(_ content: String, meetingID: UUID) throws -> [MeetingChunk] {
        return chunkTextBySpeaker(content, meetingID: meetingID)
    }

    private func chunkTextBySpeaker(_ text: String, meetingID: UUID) -> [MeetingChunk] {
        var chunks: [MeetingChunk] = []
        let lines = text.components(separatedBy: .newlines)

        var currentSpeaker: String? = nil
        var currentText = ""
        var chunkIndex = 0

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if this line indicates a new speaker (common patterns)
            if let speakerMatch = extractSpeakerFromLine(trimmedLine) {
                // Save previous chunk if we have content
                if !currentText.isEmpty {
                    let chunk = MeetingChunk(
                        meetingID: meetingID,
                        chunkIndex: chunkIndex,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                        speaker: currentSpeaker
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                }

                currentSpeaker = speakerMatch
                currentText = ""
            } else if !trimmedLine.isEmpty {
                // Add content to current chunk
                if !currentText.isEmpty {
                    currentText += "\n"
                }
                currentText += trimmedLine

                // Check if we need to split due to size
                if currentText.count > config.maxChunkSize {
                    let chunk = MeetingChunk(
                        meetingID: meetingID,
                        chunkIndex: chunkIndex,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                        speaker: currentSpeaker
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                    currentText = ""
                }
            }
        }

        // Add final chunk if we have content
        if !currentText.isEmpty {
            let chunk = MeetingChunk(
                meetingID: meetingID,
                chunkIndex: chunkIndex,
                text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                speaker: currentSpeaker
            )
            chunks.append(chunk)
        }

        return chunks
    }

    private func extractSpeakerFromLine(_ line: String) -> String? {
        // Common speaker patterns:
        // "Speaker Name:"
        // "[Speaker Name]"
        // "Speaker Name -"
        // "## Speaker Name"

        let patterns = [
            #"^([^:]+):\s*$"#,           // "Name:"
            #"^\[([^\]]+)\]\s*$"#,       // "[Name]"
            #"^([^-]+)-\s*$"#,           // "Name -"
            #"^##\s*(.+)$"#,             // "## Name"
            #"^\*\*([^*]+)\*\*\s*$"#     // "**Name**"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)),
               let range = Range(match.range(at: 1), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }
}

// MARK: - Data Models

private struct MuesliMetadata: Codable {
    let id: String
    let title: String?
    let date: Date
    let duration: TimeInterval?
    let summary: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, date, duration, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)

        // Handle flexible date parsing
        if let dateString = try? container.decode(String.self, forKey: .date) {
            let formatter = ISO8601DateFormatter()
            if let parsed = formatter.date(from: dateString) {
                date = parsed
            } else {
                // Fallback to other common formats
                let fallbackFormatter = DateFormatter()
                fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                date = fallbackFormatter.date(from: dateString) ?? Date()
            }
        } else if let timestamp = try? container.decode(TimeInterval.self, forKey: .date) {
            date = Date(timeIntervalSince1970: timestamp)
        } else {
            date = Date()
        }
    }
}

private struct MuesliTranscript: Codable {
    let text: String?
    let speakers: [SpeakerSegment]?
}

private struct SpeakerSegment: Codable {
    let name: String?
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case name, text, startTime = "start_time", endTime = "end_time"
    }
}
