// ABOUTME: Scans filesystem for Granola and Muesli data directories
// ABOUTME: Returns detection results with meeting counts for each source

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
    public let muesli: DataSourceResult

    public init(granola: DataSourceResult, muesli: DataSourceResult) {
        self.granola = granola
        self.muesli = muesli
    }
}

public struct DataSourceDetector: Sendable {
    public init() {}

    public func detectGranola(at path: String) -> DataSourceResult {
        let fm = FileManager.default
        let cacheFilePath = (path as NSString).appendingPathComponent("cache-v6.json")

        guard fm.fileExists(atPath: cacheFilePath),
              let data = fm.contents(atPath: cacheFilePath) else {
            return DataSourceResult(found: false, meetingCount: 0, path: path)
        }

        let meetingCount = countGranolaMeetings(in: data)
        return DataSourceResult(found: meetingCount > 0, meetingCount: meetingCount, path: path)
    }

    private func countGranolaMeetings(in data: Data) -> Int {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = json["cache"] as? [String: Any],
              let state = cache["state"] as? [String: Any],
              let documents = state["documents"] as? [String: [String: Any]] else {
            return 0
        }

        return documents.values.filter { doc in
            doc["type"] as? String == "meeting"
                && (doc["deleted_at"] == nil || doc["deleted_at"] is NSNull)
        }.count
    }

    public func detectMuesli(at path: String) -> DataSourceResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return DataSourceResult(found: false, meetingCount: 0, path: path)
        }

        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let metadataCount = contents.filter { $0.hasSuffix("_metadata.json") }.count
        return DataSourceResult(found: metadataCount > 0, meetingCount: metadataCount, path: path)
    }

    public func detectAll(granolaPath: String, muesliPath: String) -> AllSourcesResult {
        AllSourcesResult(
            granola: detectGranola(at: granolaPath),
            muesli: detectMuesli(at: muesliPath)
        )
    }
}
