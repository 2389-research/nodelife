// ABOUTME: Barnes-Hut quadtree for O(n log n) repulsion force approximation
// ABOUTME: Partitions 2D space into quadrants, storing mass and center-of-mass per cell

import Foundation
import CoreGraphics

public struct QuadTree: Sendable {
    public var bounds: CGRect
    public private(set) var mass: Int = 0
    public private(set) var centerOfMass: CGPoint = .zero
    private var node: Node = .empty
    private var depth: Int = 0

    private static let maxDepth = 20

    indirect enum Node: Sendable {
        case empty
        case leaf(index: Int, position: CGPoint)
        case multiLeaf(indices: [Int], positions: [CGPoint])
        case `internal`(children: QuadTreeChildren)
    }

    public init(bounds: CGRect) {
        self.bounds = bounds
        self.depth = 0
    }

    init(bounds: CGRect, depth: Int) {
        self.bounds = bounds
        self.depth = depth
    }

    public mutating func insert(index: Int, position: CGPoint) {
        let newMass = mass + 1
        centerOfMass = CGPoint(
            x: (centerOfMass.x * CGFloat(mass) + position.x) / CGFloat(newMass),
            y: (centerOfMass.y * CGFloat(mass) + position.y) / CGFloat(newMass)
        )
        mass = newMass

        switch node {
        case .empty:
            node = .leaf(index: index, position: position)

        case .leaf(let existingIndex, let existingPos):
            if depth >= QuadTree.maxDepth {
                // At max depth, store multiple nodes in same leaf
                node = .multiLeaf(
                    indices: [existingIndex, index],
                    positions: [existingPos, position]
                )
            } else {
                var children = QuadTreeChildren(parentBounds: bounds, depth: depth + 1)
                children.insert(index: existingIndex, position: existingPos)
                children.insert(index: index, position: position)
                node = .internal(children: children)
            }

        case .multiLeaf(var indices, var positions):
            indices.append(index)
            positions.append(position)
            node = .multiLeaf(indices: indices, positions: positions)

        case .internal(var children):
            children.insert(index: index, position: position)
            node = .internal(children: children)
        }
    }

    public func calculateForce(
        on position: CGPoint,
        excludingIndex: Int,
        repulsionStrength: Double,
        theta: Double
    ) -> CGPoint {
        guard mass > 0 else { return .zero }

        switch node {
        case .empty:
            return .zero

        case .leaf(let index, let leafPos):
            if index == excludingIndex { return .zero }
            return repulsionForce(from: leafPos, to: position, strength: repulsionStrength)

        case .multiLeaf(let indices, let positions):
            var force = CGPoint.zero
            for i in 0..<indices.count {
                if indices[i] == excludingIndex { continue }
                let f = repulsionForce(from: positions[i], to: position, strength: repulsionStrength)
                force.x += f.x
                force.y += f.y
            }
            return force

        case .internal(let children):
            let dx = position.x - centerOfMass.x
            let dy = position.y - centerOfMass.y
            let distSq = dx * dx + dy * dy
            let cellSize = max(bounds.width, bounds.height)

            if cellSize * cellSize / max(distSq, 1.0) < theta * theta {
                return repulsionForce(
                    from: centerOfMass, to: position,
                    strength: repulsionStrength, mass: Double(mass)
                )
            }

            var force = CGPoint.zero
            for i in 0..<4 {
                let childForce = children[i].calculateForce(
                    on: position, excludingIndex: excludingIndex,
                    repulsionStrength: repulsionStrength, theta: theta
                )
                force.x += childForce.x
                force.y += childForce.y
            }
            return force
        }
    }

    public func nodesWithin(distance: Double, of point: CGPoint) -> [Int] {
        var result: [Int] = []
        collectNodesWithin(distance: distance, of: point, into: &result)
        return result
    }

    private func collectNodesWithin(distance: Double, of point: CGPoint, into result: inout [Int]) {
        let expanded = bounds.insetBy(dx: -distance, dy: -distance)
        guard expanded.contains(point) else { return }

        switch node {
        case .empty:
            break

        case .leaf(let index, let pos):
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            if dx * dx + dy * dy <= distance * distance {
                result.append(index)
            }

        case .multiLeaf(let indices, let positions):
            for i in 0..<indices.count {
                let dx = positions[i].x - point.x
                let dy = positions[i].y - point.y
                if dx * dx + dy * dy <= distance * distance {
                    result.append(indices[i])
                }
            }

        case .internal(let children):
            for i in 0..<4 {
                children[i].collectNodesWithin(distance: distance, of: point, into: &result)
            }
        }
    }

    private func repulsionForce(
        from source: CGPoint, to target: CGPoint,
        strength: Double, mass: Double = 1.0
    ) -> CGPoint {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distSq = max(dx * dx + dy * dy, 1.0)
        let dist = sqrt(distSq)
        let force = strength * mass / distSq
        return CGPoint(x: (dx / dist) * force, y: (dy / dist) * force)
    }
}

struct QuadTreeChildren: Sendable {
    private var nw: QuadTree
    private var ne: QuadTree
    private var sw: QuadTree
    private var se: QuadTree

    init(parentBounds: CGRect, depth: Int) {
        let midX = parentBounds.midX
        let midY = parentBounds.midY
        let halfW = parentBounds.width / 2
        let halfH = parentBounds.height / 2
        nw = QuadTree(bounds: CGRect(x: parentBounds.minX, y: parentBounds.minY, width: halfW, height: halfH), depth: depth)
        ne = QuadTree(bounds: CGRect(x: midX, y: parentBounds.minY, width: halfW, height: halfH), depth: depth)
        sw = QuadTree(bounds: CGRect(x: parentBounds.minX, y: midY, width: halfW, height: halfH), depth: depth)
        se = QuadTree(bounds: CGRect(x: midX, y: midY, width: halfW, height: halfH), depth: depth)
    }

    subscript(index: Int) -> QuadTree {
        get {
            switch index {
            case 0: return nw
            case 1: return ne
            case 2: return sw
            case 3: return se
            default: fatalError("QuadTree child index out of range")
            }
        }
    }

    mutating func insert(index: Int, position: CGPoint) {
        let quadrant = quadrantFor(position)
        switch quadrant {
        case 0: nw.insert(index: index, position: position)
        case 1: ne.insert(index: index, position: position)
        case 2: sw.insert(index: index, position: position)
        case 3: se.insert(index: index, position: position)
        default: break
        }
    }

    private func quadrantFor(_ position: CGPoint) -> Int {
        let midX = nw.bounds.maxX
        let midY = nw.bounds.maxY
        if position.x <= midX {
            return position.y <= midY ? 0 : 2
        } else {
            return position.y <= midY ? 1 : 3
        }
    }
}
