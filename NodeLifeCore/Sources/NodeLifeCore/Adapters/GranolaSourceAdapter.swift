// ABOUTME: GranolaSourceAdapter implementation for reading meeting data from Granola app storage
// ABOUTME: Parses Granola meeting data and transcript files, converting them to Meeting and MeetingChunk records

import Foundation

/// Configuration for the GranolaSourceAdapter
public struct GranolaConfig: Sendable {
    /// Path to the Granola data directory
    public let dataPath: String

    /// Maximum chunk size in characters (used as fallback when speaker-based chunking isn't available)
    public let maxChunkSize: Int

    /// Default path based on typical macOS app data locations
    public static let defaultDataPath = "~/Library/Application Support/Granola"

    public init(dataPath: String? = nil, maxChunkSize: Int = 2000) {
        self.dataPath = dataPath ?? Self.defaultDataPath.expandingTildeInPath
        self.maxChunkSize = maxChunkSize
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
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: config.dataPath) else {
            throw SourceAdapterError.sourceNotAccessible("Granola data directory does not exist: \(config.dataPath)")
        }

        let dataURL = URL(fileURLWithPath: config.dataPath)
        let contents: [URL]

        do {
            contents = try fileManager.contentsOfDirectory(at: dataURL, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch {
            throw SourceAdapterError.ioError("Failed to read Granola data directory: \(error.localizedDescription)")
        }

        // Look for meeting files - Granola may store as JSON, SQLite, or other formats
        // Filter for files that match common meeting file patterns
        let meetingFiles = contents.filter { url in
            let fileName = url.lastPathComponent.lowercased()
            return fileName.contains("meeting") ||
                   fileName.hasPrefix("granola_") ||
                   (url.pathExtension.lowercased() == "json" && !fileName.contains("config"))
        }

        var meetings: [Meeting] = []

        for meetingFile in meetingFiles {
            do {
                if let meeting = try await parseMeetingFile(meetingFile, since: since) {
                    meetings.append(meeting)
                }
            } catch {
                // Log error but continue processing other files
                // In production, we might want to use structured logging here
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

        // Look for associated transcript data
        let dataURL = URL(fileURLWithPath: config.dataPath)
        let transcriptFile = try findTranscriptFile(for: meeting.sourceID, in: dataURL)

        do {
            let transcriptData = try Data(contentsOf: transcriptFile)

            if transcriptFile.pathExtension.lowercased() == "json" {
                return try parseJSONTranscript(transcriptData, meetingID: meetingID)
            } else {
                // Assume text-based format (markdown, plain text, etc.)
                let content = String(data: transcriptData, encoding: .utf8) ?? ""
                return try parseTextTranscript(content, meetingID: meetingID)
            }
        } catch {
            throw SourceAdapterError.ioError("Failed to read transcript file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func parseMeetingFile(_ file: URL, since: Date?) async throws -> Meeting? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw SourceAdapterError.ioError("Failed to read meeting file: \(error.localizedDescription)")
        }

        // Try to parse as JSON first, then fallback to other formats
        if file.pathExtension.lowercased() == "json" {
            return try parseJSONMeeting(data, from: file, since: since)
        } else {
            // For non-JSON files, try to extract basic metadata
            return try parseTextMeeting(data, from: file, since: since)
        }
    }

    private func parseJSONMeeting(_ data: Data, from file: URL, since: Date?) throws -> Meeting? {
        let meeting: GranolaMeeting
        do {
            meeting = try JSONDecoder().decode(GranolaMeeting.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse Granola meeting JSON: \(error.localizedDescription)")
        }

        // Filter by date if specified
        if let since = since, meeting.date < since {
            return nil
        }

        // Extract source ID from filename or use the meeting ID from the data
        let sourceID = meeting.id ?? file.deletingPathExtension().lastPathComponent

        return Meeting(
            sourceID: sourceID,
            title: meeting.title ?? "Granola Meeting \(sourceID)",
            date: meeting.date,
            duration: meeting.duration ?? 0,
            rawTranscript: meeting.transcript ?? "",
            sourceAdapter: metadata.id
        )
    }

    private func parseTextMeeting(_ data: Data, from file: URL, since: Date?) throws -> Meeting? {
        guard let content = String(data: data, encoding: .utf8) else {
            throw SourceAdapterError.invalidData("Unable to decode text content from file")
        }

        // Extract metadata from file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        // Filter by date if specified
        if let since = since, modificationDate < since {
            return nil
        }

        let sourceID = file.deletingPathExtension().lastPathComponent
        let title = extractTitleFromContent(content) ?? "Granola Meeting \(sourceID)"

        return Meeting(
            sourceID: sourceID,
            title: title,
            date: modificationDate,
            duration: estimateDurationFromContent(content),
            rawTranscript: content,
            sourceAdapter: metadata.id
        )
    }

    private func findTranscriptFile(for sourceID: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default

        // Common patterns for transcript files
        let possibleNames = [
            "\(sourceID)_transcript.json",
            "\(sourceID).json",
            "\(sourceID)_transcript.txt",
            "\(sourceID)_transcript.md",
            "\(sourceID).txt",
            "\(sourceID).md",
            "transcript_\(sourceID).json",
            "transcript_\(sourceID).txt"
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
        let transcript: GranolaTranscript
        do {
            transcript = try JSONDecoder().decode(GranolaTranscript.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData("Failed to parse Granola transcript JSON: \(error.localizedDescription)")
        }

        var chunks: [MeetingChunk] = []

        if let segments = transcript.segments {
            // Chunk by speaker turns or time segments
            for (index, segment) in segments.enumerated() {
                let chunk = MeetingChunk(
                    meetingID: meetingID,
                    chunkIndex: index,
                    text: segment.text,
                    speaker: segment.speaker,
                    startTime: segment.startTime,
                    endTime: segment.endTime
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

            // Check if this line indicates a new speaker
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
        // Common speaker patterns for Granola transcripts
        let patterns = [
            #"^([^:]+):\s*$"#,           // "Name:"
            #"^\[([^\]]+)\]\s*$"#,       // "[Name]"
            #"^([^-]+)-\s*$"#,           // "Name -"
            #"^##\s*(.+)$"#,             // "## Name"
            #"^\*\*([^*]+)\*\*\s*$"#,    // "**Name**"
            #"^Speaker\s*(\d+):\s*$"#,   // "Speaker 1:"
            #"^Person\s*([^:]+):\s*$"#   // "Person Name:"
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

    private func extractTitleFromContent(_ content: String) -> String? {
        // Try to extract title from various patterns
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines.prefix(10) { // Check first 10 lines
            if !line.isEmpty {
                // Check for markdown header
                if line.hasPrefix("#") {
                    return line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                }

                // Check for title patterns
                if line.lowercased().contains("title:") || line.lowercased().contains("meeting:") {
                    return line.replacingOccurrences(of: "^[^:]*:\\s*", with: "", options: .regularExpression)
                }

                // Use first non-empty line as fallback if it's not too long
                if line.count < 100 && !line.contains(":") {
                    return line
                }
            }
        }

        return nil
    }

    private func estimateDurationFromContent(_ content: String) -> TimeInterval {
        // Rough estimate based on content length
        // Average speaking pace is about 150-160 words per minute
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let estimatedMinutes = Double(wordCount) / 150.0
        return estimatedMinutes * 60.0 // Convert to seconds
    }
}

// MARK: - Data Models

/// Granola meeting data structure (flexible to accommodate various formats)
private struct GranolaMeeting: Codable {
    let id: String?
    let title: String?
    let date: Date
    let duration: TimeInterval?
    let transcript: String?
    let summary: String?
    let attendees: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, title, date, duration, transcript, summary, attendees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        attendees = try container.decodeIfPresent([String].self, forKey: .attendees)

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

/// Granola transcript data structure
private struct GranolaTranscript: Codable {
    let text: String?
    let segments: [GranolaSegment]?
}

/// Individual segment of a Granola transcript
private struct GranolaSegment: Codable {
    let speaker: String?
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case speaker, text, startTime = "start_time", endTime = "end_time"
    }
}

// MARK: - Extensions

extension String {
    /// Expands tilde (~) in file paths to the user's home directory
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}
