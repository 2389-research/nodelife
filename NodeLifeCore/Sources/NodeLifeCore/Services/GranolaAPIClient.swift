// ABOUTME: HTTP client actor for communicating with the Granola API
// ABOUTME: Handles auth token discovery, document listing, metadata, and transcript retrieval

import Foundation

// MARK: - Codable Models

/// Response wrapper for the /v2/get-documents endpoint
public struct GranolaDocumentsResponse: Codable, Sendable {
    public let docs: [GranolaDocumentSummary]
}

/// Summary of a Granola document returned by the list endpoint
public struct GranolaDocumentSummary: Codable, Sendable {
    public let id: String
    public let title: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Metadata for a specific Granola document
public struct GranolaDocumentMetadata: Codable, Sendable {
    public let creator: GranolaAttendee?
    public let attendees: [GranolaAttendee]?
    public let durationSeconds: Int?
    public let title: String?
    public let createdAt: String?
    public let participants: [String]?
    public let labels: [String]?

    enum CodingKeys: String, CodingKey {
        case creator
        case attendees
        case durationSeconds = "duration_seconds"
        case title
        case createdAt = "created_at"
        case participants
        case labels
    }
}

/// A segment of a meeting transcript from Granola
public struct GranolaTranscriptSegment: Codable, Sendable {
    public let id: String
    public let documentId: String
    public let startTimestamp: String
    public let endTimestamp: String
    public let text: String
    public let source: String
    public let isFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case text
        case source
        case isFinal = "is_final"
    }
}

/// An attendee in a Granola meeting
public struct GranolaAttendee: Codable, Sendable {
    public let name: String?
    public let email: String?
    public let details: GranolaPersonDetails?
}

/// Wrapper for person details in attendee data
public struct GranolaPersonDetails: Codable, Sendable {
    public let person: GranolaPersonInfo?
}

/// Person info containing name details
public struct GranolaPersonInfo: Codable, Sendable {
    public let name: GranolaPersonName?
}

/// Person name with full name field
public struct GranolaPersonName: Codable, Sendable {
    public let fullName: String?
}

// MARK: - GranolaAPIClient

/// Actor that communicates with the Granola HTTP API for document and transcript retrieval
public actor GranolaAPIClient {
    private let baseURL: String
    private let token: String
    private let session: URLSession

    public init(token: String, baseURL: String = "https://api.granola.ai") {
        self.token = token
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    /// Discover auth token from Granola's installed session file
    /// - Parameter path: Optional custom path to supabase.json. Uses the default Granola path if nil.
    /// - Returns: The access token string
    /// - Throws: SourceAdapterError.sourceNotAccessible if the file is missing or token cannot be extracted
    public static func discoverToken(from path: String? = nil) throws -> String {
        let resolvedPath: String
        if let path = path {
            resolvedPath = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            resolvedPath = "\(home)/Library/Application Support/Granola/supabase.json"
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw SourceAdapterError.sourceNotAccessible(
                "Granola session file not found at \(resolvedPath)"
            )
        }

        let fileURL = URL(fileURLWithPath: resolvedPath)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SourceAdapterError.sourceNotAccessible(
                "Failed to read Granola session file: \(error.localizedDescription)"
            )
        }

        guard let outerJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceAdapterError.sourceNotAccessible(
                "Granola session file is not valid JSON"
            )
        }

        guard let workosTokensString = outerJSON["workos_tokens"] as? String else {
            throw SourceAdapterError.sourceNotAccessible(
                "workos_tokens key not found or not a string in Granola session file"
            )
        }

        guard let workosData = workosTokensString.data(using: .utf8),
              let workosJSON = try? JSONSerialization.jsonObject(with: workosData) as? [String: Any] else {
            throw SourceAdapterError.sourceNotAccessible(
                "workos_tokens contains malformed JSON"
            )
        }

        guard let accessToken = workosJSON["access_token"] as? String else {
            throw SourceAdapterError.sourceNotAccessible(
                "access_token not found in workos_tokens"
            )
        }

        return accessToken
    }

    /// List documents with pagination
    /// - Parameters:
    ///   - limit: Maximum number of documents to return
    ///   - offset: Number of documents to skip
    /// - Returns: Array of document summaries
    public func listDocuments(limit: Int = 100, offset: Int = 0) async throws -> [GranolaDocumentSummary] {
        let body: [String: Any] = ["limit": limit, "offset": offset]
        let data = try await performRequest(endpoint: "/v2/get-documents", body: body)

        do {
            let response = try JSONDecoder().decode(GranolaDocumentsResponse.self, from: data)
            return response.docs
        } catch {
            throw SourceAdapterError.invalidData(
                "Failed to parse documents response: \(error.localizedDescription)"
            )
        }
    }

    /// List all documents with automatic pagination and dedup guard
    /// - Returns: Array of all document summaries
    public func listAllDocuments() async throws -> [GranolaDocumentSummary] {
        var allDocs: [GranolaDocumentSummary] = []
        var seenIDs = Set<String>()
        var offset = 0
        let batchSize = 100

        while true {
            let batch = try await listDocuments(limit: batchSize, offset: offset)
            let newCount = batch.filter { seenIDs.insert($0.id).inserted }.count
            if newCount == 0 && !batch.isEmpty { break }
            allDocs.append(contentsOf: batch)
            if batch.count < batchSize { break }
            offset += batchSize
        }

        return allDocs
    }

    /// Get metadata for a specific document
    /// - Parameter documentID: The document UUID
    /// - Returns: Document metadata
    public func getMetadata(documentID: String) async throws -> GranolaDocumentMetadata {
        let body: [String: Any] = ["document_id": documentID]
        let data = try await performRequest(endpoint: "/v1/get-document-metadata", body: body)

        do {
            return try JSONDecoder().decode(GranolaDocumentMetadata.self, from: data)
        } catch {
            throw SourceAdapterError.invalidData(
                "Failed to parse document metadata: \(error.localizedDescription)"
            )
        }
    }

    /// Get transcript segments for a specific document
    /// - Parameter documentID: The document UUID
    /// - Returns: Array of transcript segments
    public func getTranscript(documentID: String) async throws -> [GranolaTranscriptSegment] {
        let body: [String: Any] = ["document_id": documentID]
        let data = try await performRequest(endpoint: "/v1/get-document-transcript", body: body)

        do {
            return try JSONDecoder().decode([GranolaTranscriptSegment].self, from: data)
        } catch {
            throw SourceAdapterError.invalidData(
                "Failed to parse transcript response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private Helpers

    /// Perform a POST request to the Granola API
    private func performRequest(endpoint: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            throw SourceAdapterError.invalidConfiguration(
                "Invalid URL: \(baseURL + endpoint)"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Granola/5.354.0", forHTTPHeaderField: "User-Agent")
        request.setValue("5.354.0", forHTTPHeaderField: "X-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceAdapterError.networkError(
                "Non-HTTP response received for \(endpoint)"
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SourceAdapterError.networkError(
                "Granola API returned status \(httpResponse.statusCode) for \(endpoint)"
            )
        }

        return data
    }
}
