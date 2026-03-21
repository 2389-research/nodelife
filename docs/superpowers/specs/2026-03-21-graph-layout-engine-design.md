# Graph Layout Engine Redesign

## Problem

The current force-directed layout has two forces (repulsion + attraction), runs a one-shot batch of 300 iterations, and uses O(n^2) all-pairs repulsion. At 500+ nodes this produces overlapping hairballs with no visible structure and no interactivity.

## Goals

1. Visible cluster structure driven by actual connectivity (not entity types)
2. No node overlap
3. Responsive interactive simulation — drag a node, neighbors react at 60fps
4. Progressive reveal — graph appears by showing most-connected nodes first
5. Two-phase: show a good static layout immediately, then bring it to life

## Force Model

Five forces replace the current two:

| Force | Purpose | Algorithm |
|-------|---------|-----------|
| Repulsion | Prevent overlap, spread nodes | Barnes-Hut quadtree, O(n log n), theta=0.8 |
| Attraction | Pull connected nodes together | Spring force along edges, rest length proportional to 1/weight |
| Center gravity | Prevent drift | Linear pull toward canvas center |
| Community cohesion | Cluster related nodes | Label propagation assigns cluster IDs; weak attraction between same-cluster nodes |
| Collision | Hard overlap prevention | Radius-based repulsion when nodes closer than combined radii |

Initial force constants (tunable):
- Repulsion strength: 200.0 (Coulomb coefficient)
- Attraction strength: 0.02 (spring constant)
- Center gravity: 0.3 (linear coefficient)
- Community cohesion: 0.005 (weak spring between same-cluster nodes)
- Collision radius padding: 2.0px beyond node render radius

## Community Detection

Label propagation runs once when the graph loads:
- Each node starts with a unique label
- Each iteration, every node adopts the most common label among its neighbors
- Tie-breaking: lowest label ID wins
- Max 10 iterations (may not fully converge — acceptable since cohesion is a weak force)
- Cluster IDs stored on GraphNode.clusterID

This determines macro structure. The cohesion force gently pulls same-cluster nodes together, but connectivity (attraction force) is the primary layout driver.

## Concurrency Model

`ForceSimulation` is a `@MainActor` class. The simulation tick runs on the main thread, driven by `TimelineView(.animation)`. At 500 nodes with Barnes-Hut O(n log n), each tick takes <1ms on Apple Silicon — well within the 16ms frame budget.

This is the simplest correct approach:
- No cross-thread synchronization needed
- SwiftUI reads positions directly from `@Observable` state
- Matches how `TimelineView` already works (its closure runs on the main actor)
- `GraphViewModel` (already `@MainActor`) owns the simulation directly

If profiling shows the tick exceeds budget at very high node counts (2000+), the upgrade path is: move force calculation to a background actor, snapshot positions into an `AsyncStream`, consume on main actor.

## Simulation State

`ForceSimulation` maintains parallel arrays separate from the immutable `GraphNode` structs:
- `positions: [CGPoint]` — current position of each node
- `velocities: [CGPoint]` — current velocity of each node
- `clusterIDs: [Int]` — community labels
- `pinned: [Bool]` — whether each node is pinned
- `nodeIndex: [UUID: Int]` — O(1) lookup from node ID to array index

`GraphProjection` remains immutable. It holds the static topology (nodes, edges, filter, stats) and is only rebuilt when the filter or projection type changes. The simulation reads edge topology from the projection and maintains its own mutable position state.

`GraphNode.position` is kept for Phase 1 caching — when a `GraphProjection` is cached, the batch-computed positions are written back into the `GraphNode` structs. During Phase 2, the simulation's `positions` array is the source of truth for rendering. `GraphNode.position` is stale during live simulation and must not be read by the renderer.

The renderer uses the `nodeIndex` map for O(1) edge endpoint lookups instead of the current O(n) `first(where:)` per edge.

## Two-Phase Simulation

### Phase 1: Batch Layout (blocking)

1. Run community detection (label propagation, max 10 iterations)
2. Seed initial positions: arrange clusters in a circle, scatter nodes within their cluster region with jitter. Overlapping positions get small random displacement.
3. Run 100 iterations of the full force simulation at high speed (no rendering, no damping decay)
4. Positions stored in simulation's parallel arrays
5. Graph is visible and interactive

Phase 1 target is <100ms on M1 or later. Runs synchronously on the main actor — a brief UI freeze at this duration is acceptable. Iteration count is configurable; reduce if profiling shows it exceeds 100ms.

### Phase 2: Live Simulation (continuous, 60fps)

1. `TimelineView(.animation)` drives `simulation.tick()` each frame on the main actor
2. Each tick: compute all 5 forces, update velocities with damping, integrate positions
3. Progressive reveal: nodes sorted by degree (descending), revealed over 30 frames (~500ms at 60fps). Each frame reveals `ceil(nodeCount / 30)` nodes. All nodes participate in forces from frame 1 (so layout is stable), but unrevealed nodes render at opacity 0, fading to 1 over 6 frames. The reveal is purely cosmetic.
4. Damping factor starts at 0.95 (low friction, fast movement), linearly decays to 0.85 (high friction, settling) over 120 ticks (~2 seconds at 60fps). Decay is wall-clock based (tick count), does not reset on wake.
5. Sleep/wake:
   - Kinetic energy: `sum(vx^2 + vy^2)` across all nodes
   - Sleep threshold: `< 0.1 * nodeCount`
   - Wake triggers: drag interaction, filter change, new nodes added
   - Minimum awake time: 500ms after wake to prevent rapid sleep/wake cycling

### Interaction

- **Drag vs pan**: drag gesture starts with hit test. If drag begins within hit radius of a node, enter "node drag" mode (pin node to cursor, wake simulation). Otherwise, enter "camera pan" mode. Hit radius = `nodeRadius + 4px` (accounts for degree-based variable sizing). This requires splitting the current single drag gesture.
- **Release**: unpin node, simulation settles it under forces
- **Zoom/pan**: camera transform only, no simulation impact
- **Select**: tap to highlight node + edges, no physics change

### Lifecycle

On filter or projection type change:
1. Stop current simulation (if running)
2. Run Phase 1 with new data
3. Start new Phase 2
4. Positions are NOT preserved across changes (fresh layout each time)

## Barnes-Hut Quadtree

Struct (value type) using an enum for node kind (empty leaf, occupied leaf, internal with 4 children):
- Each node: bounding rect, total mass (node count), center of mass
- Leaf nodes hold a single graph node index or are empty
- Internal nodes have 4 children (NW, NE, SW, SE)
- Build: O(n log n), insert all nodes, subdivide when leaf gets second node
- Query: walk tree, if cellSize/distance < theta (0.8), treat cell as point mass. Otherwise recurse.
- Rebuilt every tick (~0.1ms at 500 nodes)

Future Metal upgrade path: quadtree stays on CPU for hit testing and spatial queries, force accumulation moves to compute shader reading from shared buffer.

## Edge Cases

- **Zero edges**: only repulsion, gravity, and collision apply. Produces a uniform radial layout. This is correct behavior.
- **Zero-distance nodes**: add small random jitter (as current code does) to break symmetry and avoid NaN/Inf in force calculations.
- **Empty graph**: skip simulation entirely, show empty canvas.
- **Single node**: skip simulation, place at center.
- **Disconnected components**: center gravity prevents them from flying apart. Each component clusters internally via attraction forces.

## Rendering Changes

Replace Canvas with TimelineView(.animation) + Canvas:
- TimelineView provides display-link-driven redraw
- Canvas draws from simulation's current positions each frame
- Build `[UUID: Int]` nodeIndex once for O(1) edge endpoint lookups

Node rendering additions:
- Opacity: 0 to 1 over 500ms for progressive reveal, degree-sorted order
- Size: scaled by degree (more connections = bigger), 4px to 16px radius, log-scaled

Edge rendering additions:
- Opacity: edges appear when both endpoints visible
- Curvature: multiple edges between same pair use quadratic bezier with offset control points

Colors, labels, zoom/pan unchanged. Hit testing updated to use nodeIndex for O(1) lookup.

## File Changes

### Keep as-is
- GraphNode.swift, GraphEdge.swift (models)
- GraphBuilder.swift, GraphProjection.swift, GraphFilter.swift, GraphStats.swift
- GraphCache.swift (caches Phase 1 result, not live positions)
- GraphToolbar.swift, GraphFilterPanel.swift

### New files (NodeLifeCore)
- QuadTree.swift — Barnes-Hut quadtree struct
- CommunityDetection.swift — label propagation algorithm
- ForceSimulation.swift — 5-force simulation engine (@MainActor class)

### Modified files
- GraphCanvasView.swift — TimelineView wrapper, progressive reveal, degree-based sizing, drag-vs-pan gesture split
- GraphViewModel.swift — simulation lifecycle (start, sleep, wake), drag-to-pin

### Delete
- ForceDirectedLayout.swift — replaced by ForceSimulation.swift

## Testing

### QuadTree
- Insertion and subdivision correctness
- Center-of-mass calculation accuracy
- Force approximation accuracy vs brute-force (error within 5% at theta=0.8)
- Edge cases: all nodes at same position, single node, empty tree

### CommunityDetection
- Two cliques connected by bridge yields 2 communities
- Disconnected components get separate labels
- Single node graph
- Complete graph (single community)
- Tie-breaking produces deterministic results

### ForceSimulation
- Total kinetic energy decreases over time (convergence)
- Pinned nodes maintain position
- Batch mode produces positions within canvas bounds
- Sleep/wake lifecycle: sleeps when energy below threshold, wakes on perturbation
- Minimum awake time prevents rapid cycling
- All forces produce finite values (no NaN/Inf from zero-distance edge cases)
- Zero-edge graph produces radial layout
- Single node placed at center

### Integration
- GraphViewModel loads graph, shows Phase 1 result, transitions to Phase 2
- Drag on node pins/unpins correctly, drag on empty space pans camera
- Filter change stops simulation, runs fresh layout cycle
