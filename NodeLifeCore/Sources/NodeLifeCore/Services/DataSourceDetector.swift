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
        guard fm.fileExists(atPath: path) else {
            return DataSourceResult(found: false, meetingCount: 0, path: path)
        }

        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let jsonCount = contents.filter { $0.hasSuffix(".json") }.count
        return DataSourceResult(found: jsonCount > 0, meetingCount: jsonCount, path: path)
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
