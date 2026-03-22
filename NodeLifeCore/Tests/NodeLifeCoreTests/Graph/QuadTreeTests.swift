// ABOUTME: Tests for Barnes-Hut quadtree spatial partitioning
// ABOUTME: Verifies mass tracking, center of mass, force approximation, and spatial queries

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func emptyTreeHasZeroMass() {
    let tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(tree.mass == 0)
}

@Test func insertSingleNodeMassAndCenter() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 25, y: 75))
    #expect(tree.mass == 1)
    #expect(abs(tree.centerOfMass.x - 25) < 0.001)
    #expect(abs(tree.centerOfMass.y - 75) < 0.001)
}

@Test func insertTwoNodesSubdivides() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 10, y: 10))
    tree.insert(index: 1, position: CGPoint(x: 90, y: 90))
    #expect(tree.mass == 2)
    #expect(abs(tree.centerOfMass.x - 50) < 0.001)
    #expect(abs(tree.centerOfMass.y - 50) < 0.001)
}

@Test func insertMultipleNodesCenterOfMass() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    let positions: [CGPoint] = [
        CGPoint(x: 10, y: 10),
        CGPoint(x: 20, y: 20),
        CGPoint(x: 30, y: 30),
        CGPoint(x: 40, y: 40),
        CGPoint(x: 50, y: 50),
    ]
    for (i, pos) in positions.enumerated() {
        tree.insert(index: i, position: pos)
    }
    #expect(tree.mass == 5)
    let expectedX = (10.0 + 20.0 + 30.0 + 40.0 + 50.0) / 5.0
    let expectedY = (10.0 + 20.0 + 30.0 + 40.0 + 50.0) / 5.0
    #expect(abs(tree.centerOfMass.x - expectedX) < 0.01)
    #expect(abs(tree.centerOfMass.y - expectedY) < 0.01)
}

@Test func forceApproximationWithinFivePercentOfBruteForce() {
    // Use a fixed seed via deterministic positions for reproducibility
    let positions: [CGPoint] = (0..<20).map { i in
        let angle = Double(i) * 0.31415
        let radius = 20.0 + Double(i) * 3.0
        return CGPoint(x: 250 + radius * cos(angle), y: 250 + radius * sin(angle))
    }

    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 500, height: 500))
    for (i, pos) in positions.enumerated() {
        tree.insert(index: i, position: pos)
    }

    let repulsion = 1000.0
    let theta = 0.8

    for testIdx in 0..<positions.count {
        let pos = positions[testIdx]

        // Barnes-Hut approximation
        let approxForce = tree.calculateForce(
            on: pos, excludingIndex: testIdx,
            repulsionStrength: repulsion, theta: theta
        )

        // Brute force
        var bruteForceX: CGFloat = 0
        var bruteForceY: CGFloat = 0
        for (j, otherPos) in positions.enumerated() {
            if j == testIdx { continue }
            let dx = pos.x - otherPos.x
            let dy = pos.y - otherPos.y
            let distSq = max(dx * dx + dy * dy, 1.0)
            let dist = sqrt(distSq)
            let force = repulsion / distSq
            bruteForceX += (dx / dist) * force
            bruteForceY += (dy / dist) * force
        }

        let approxMag = sqrt(approxForce.x * approxForce.x + approxForce.y * approxForce.y)
        let bruteMag = sqrt(bruteForceX * bruteForceX + bruteForceY * bruteForceY)

        if bruteMag > 0.001 {
            let relativeError = abs(approxMag - bruteMag) / bruteMag
            #expect(relativeError < 0.05, "Force approximation error \(relativeError) exceeds 5% for node \(testIdx)")
        }
    }
}

@Test func samePositionForceRemainsFinite() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    let samePos = CGPoint(x: 50, y: 50)
    for i in 0..<5 {
        tree.insert(index: i, position: samePos)
    }

    let force = tree.calculateForce(
        on: samePos, excludingIndex: 0,
        repulsionStrength: 1000.0, theta: 0.8
    )
    #expect(force.x.isFinite)
    #expect(force.y.isFinite)
}

@Test func singleNodeForceIsZeroOnSelf() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 50, y: 50))

    let force = tree.calculateForce(
        on: CGPoint(x: 50, y: 50), excludingIndex: 0,
        repulsionStrength: 1000.0, theta: 0.8
    )
    #expect(force.x == 0)
    #expect(force.y == 0)
}

@Test func nodesWithinDistanceFindsCorrectNodes() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 10, y: 10))
    tree.insert(index: 1, position: CGPoint(x: 15, y: 10))
    tree.insert(index: 2, position: CGPoint(x: 90, y: 90))

    let nearby = tree.nodesWithin(distance: 10, of: CGPoint(x: 10, y: 10))
    #expect(nearby.contains(0))
    #expect(nearby.contains(1))
    #expect(!nearby.contains(2))
}
