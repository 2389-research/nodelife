// ABOUTME: Tests for GraphCache TTL-based projection caching
// ABOUTME: Verifies get/set, expiry, size limits, and selective invalidation

import Testing
import Foundation
@testable import NodeLifeCore

@Test func cacheStoresAndRetrievesProjection() async {
    let cache = GraphCache(maxCacheSize: 10, maxAge: 300)
    let projection = GraphProjection(nodes: [], edges: [], projectionType: .full)

    await cache.set(projection: projection, projectionType: .full, filter: .default)
    let retrieved = await cache.get(projectionType: .full, filter: .default)
    #expect(retrieved != nil)
    #expect(retrieved?.projectionType == .full)
}

@Test func cacheMissReturnsNil() async {
    let cache = GraphCache()
    let result = await cache.get(projectionType: .full, filter: .default)
    #expect(result == nil)
}

@Test func cacheInvalidateAllClearsEverything() async {
    let cache = GraphCache()
    let projection = GraphProjection(nodes: [], edges: [], projectionType: .full)
    await cache.set(projection: projection, projectionType: .full, filter: .default)
    await cache.invalidateAll()
    let result = await cache.get(projectionType: .full, filter: .default)
    #expect(result == nil)
}

@Test func cacheInvalidateByProjectionType() async {
    let cache = GraphCache()
    let p1 = GraphProjection(nodes: [], edges: [], projectionType: .full)
    let p2 = GraphProjection(nodes: [], edges: [], projectionType: .semantic)
    await cache.set(projection: p1, projectionType: .full, filter: .default)
    await cache.set(projection: p2, projectionType: .semantic, filter: .default)

    await cache.invalidate(projectionType: .full)

    #expect(await cache.get(projectionType: .full, filter: .default) == nil)
    #expect(await cache.get(projectionType: .semantic, filter: .default) != nil)
}

@Test func cacheEvictsOldestWhenSizeLimitExceeded() async {
    let cache = GraphCache(maxCacheSize: 2, maxAge: 300)

    let p1 = GraphProjection(nodes: [], edges: [], projectionType: .full)
    let p2 = GraphProjection(nodes: [], edges: [], projectionType: .semantic)
    let p3 = GraphProjection(nodes: [], edges: [], projectionType: .cooccurrence)

    await cache.set(projection: p1, projectionType: .full, filter: .default)
    await cache.set(projection: p2, projectionType: .semantic, filter: .default)
    await cache.set(projection: p3, projectionType: .cooccurrence, filter: .default)

    // Oldest entry (full) should have been evicted
    #expect(await cache.get(projectionType: .full, filter: .default) == nil)
    // Newer entries should remain
    #expect(await cache.get(projectionType: .semantic, filter: .default) != nil)
    #expect(await cache.get(projectionType: .cooccurrence, filter: .default) != nil)
}

@Test func cacheExpiredEntryReturnsNil() async {
    let cache = GraphCache(maxCacheSize: 10, maxAge: 0)
    let projection = GraphProjection(nodes: [], edges: [], projectionType: .full)
    await cache.set(projection: projection, projectionType: .full, filter: .default)

    // With maxAge of 0, the entry should be expired immediately
    let result = await cache.get(projectionType: .full, filter: .default)
    #expect(result == nil)
}
