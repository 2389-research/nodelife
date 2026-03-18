# NodeLife

Merged best-of-breed macOS application from 4 prior implementations. A knowledge graph built from meeting transcripts.

- **AI name:** Chaos Dumpster Supreme
- **Human name:** Harp Daddy Deluxe

## Build & Test

```bash
cd /Users/harper/Public/src/2389/nl/NodeLife && swift build
cd /Users/harper/Public/src/2389/nl/NodeLife && swift test
```

## Tech Stack

- Swift 6.0 with strict concurrency
- SwiftUI for the UI layer
- GRDB v7+ for local SQLite persistence
- macOS 14+ (Sonoma)
- Swift Testing framework for tests

## Project Structure

- **NodeLife** (Sources/NodeLife) — SwiftUI app target (windows, views, app entry point)
- **NodeLifeCore** (NodeLifeCore/Sources/NodeLifeCore) — Library with models, database, services

## Conventions

- All files start with two-line ABOUTME comments
- TDD: write tests first, then implementation
- Never use `--no-verify` when committing
- UUID primary keys everywhere
- Actor concurrency for all services
- No mock modes; always use real data and APIs

## Roadmap

### Phase 1: Foundation
Models, database layer, adapters, services, job system.

### Phase 2: Intelligence
LLM clients, extraction pipelines, entity resolution, merge engine.

### Phase 3: Visualization
Graph system, force-directed rendering, full 3-pane UI.
