// ABOUTME: SourceAdapter protocol defining the interface for reading meetings from different sources
// ABOUTME: Provides async methods for listing and fetching meetings with proper error handling

import Foundation

/// Metadata describing a source adapter implementation
public struct AdapterMetadata: Equatable, Sendable {
    /// Unique identifier for this adapter type
    public let id: String

    /// Human-readable name of the adapter
    public let name: String

    /// Version of the adapter implementation
    public let version: String

    /// Optional description of what this adapter does
    public let description: String?

    public init(id: String, name: String, version: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
    }
}

/// Errors that can occur during source adapter operations
public enum SourceAdapterError: Error, Equatable {
    /// The requested meeting could not be found
    case meetingNotFound(String)

    /// The source data is malformed or cannot be parsed
    case invalidData(String)

    /// The source location is not accessible or does not exist
    case sourceNotAccessible(String)

    /// An I/O error occurred while reading from the source
    case ioError(String)

    /// The adapter configuration is invalid
    case invalidConfiguration(String)

    /// A network error occurred (for remote sources)
    case networkError(String)

    /// An unexpected error occurred
    case unknown(String)
}

/// Protocol defining the interface for adapters that read meeting data from various sources
public protocol SourceAdapter: Sendable {
    /// Metadata describing this adapter implementation
    var metadata: AdapterMetadata { get }

    /// List all meetings available from this source since the given date
    /// - Parameter since: Optional date to filter meetings. If nil, returns all meetings
    /// - Returns: Array of Meeting objects
    /// - Throws: SourceAdapterError if the operation fails
    func listMeetings(since: Date?) async throws -> [Meeting]

    /// Fetch a specific meeting by its source ID
    /// - Parameter id: The source-specific identifier for the meeting
    /// - Returns: The Meeting object if found
    /// - Throws: SourceAdapterError if the meeting is not found or cannot be fetched
    func fetchMeeting(id: String) async throws -> Meeting

    /// Fetch the transcript chunks for a specific meeting
    /// - Parameter meetingID: The UUID of the meeting (from the Meeting object)
    /// - Returns: Array of MeetingChunk objects representing the segmented transcript
    /// - Throws: SourceAdapterError if the transcript cannot be fetched or processed
    func fetchTranscript(meetingID: UUID) async throws -> [MeetingChunk]
}
