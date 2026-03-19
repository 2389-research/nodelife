// ABOUTME: Scans filesystem for Granola data directories
// ABOUTME: Returns detection results indicating whether Granola is installed and authenticated

import Foundation

public struct DataSourceResult: Sendable, Equatable {
    public let found: Bool
    public let meetingCount: Int
    public let path: String

    public init(found: Bool, meetingCount: Int, path: String) {
        self.found = found
        self.meetingCount = meetingCount
        self.path = path
    }
}

public struct AllSourcesResult: Sendable, Equatable {
    public let granola: DataSourceResult

    public init(granola: DataSourceResult) {
        self.granola = granola
    }
}

public struct DataSourceDetector: Sendable {
    public init() {}

    public func detectGranola(at path: String) -> DataSourceResult {
        let fm = FileManager.default
        let sessionFilePath = (path as NSString).appendingPathComponent("supabase.json")

        guard fm.fileExists(atPath: sessionFilePath) else {
            return DataSourceResult(found: false, meetingCount: 0, path: path)
        }

        // supabase.json exists — Granola is installed and user is logged in
        // Meeting count requires an API call, so we return 0 here
        return DataSourceResult(found: true, meetingCount: 0, path: path)
    }

    public func detectAll(granolaPath: String) -> AllSourcesResult {
        AllSourcesResult(
            granola: detectGranola(at: granolaPath)
        )
    }
}
