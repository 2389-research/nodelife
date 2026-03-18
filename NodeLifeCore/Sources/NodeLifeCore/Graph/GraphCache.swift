// ABOUTME: Actor providing TTL-based caching for graph projections
// ABOUTME: Supports size limits, selective invalidation by projection type, and automatic expiry

import Foundation

public actor GraphCache {
    private struct CacheEntry {
        let projection: GraphProjection
        let storedAt: Date
    }

    private var entries: [String: CacheEntry] = [:]
    private let maxCacheSize: Int
    private let maxAge: TimeInterval

    public init(maxCacheSize: Int = 10, maxAge: TimeInterval = 300) {
        self.maxCacheSize = maxCacheSize
        self.maxAge = maxAge
    }

    public func get(projectionType: ProjectionType, filter: GraphFilter) -> GraphProjection? {
        let key = cacheKey(projectionType: projectionType, filter: filter)
        guard let entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > maxAge {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.projection
    }

    public func set(projection: GraphProjection, projectionType: ProjectionType, filter: GraphFilter) {
        let key = cacheKey(projectionType: projectionType, filter: filter)
        entries[key] = CacheEntry(projection: projection, storedAt: Date())
        evictIfNeeded()
    }

    public func invalidateAll() {
        entries.removeAll()
    }

    public func invalidate(projectionType: ProjectionType) {
        let prefix = "\(projectionType)"
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
    }

    private func cacheKey(projectionType: ProjectionType, filter: GraphFilter) -> String {
        "\(projectionType)_\(filter.hashValue)"
    }

    private func evictIfNeeded() {
        if entries.count > maxCacheSize {
            let sorted = entries.sorted { $0.value.storedAt < $1.value.storedAt }
            let toRemove = sorted.prefix(entries.count - maxCacheSize)
            for (key, _) in toRemove {
                entries.removeValue(forKey: key)
            }
        }
    }
}
