# NodeLife

A macOS app that turns your meeting transcripts into a knowledge graph. It pulls transcripts from Granola, extracts the people, projects, and ideas mentioned, figures out how they relate to each other, and renders the whole thing as an interactive force-directed graph.

The idea: you sit through dozens of meetings a week. Names come up, projects get referenced, someone mentions a thing from three weeks ago. NodeLife maps all of that automatically so you can actually see the connections.

## What it does

- Syncs meeting transcripts from [Granola](https://www.granola.so) via their API
- Runs entity extraction (people, orgs, projects, concepts) using Claude or GPT
- Finds relationships between entities across meetings
- Deduplicates entities with multiple resolution strategies (exact match, normalized, alias, co-occurrence)
- Renders everything as a force-directed graph you can pan, zoom, and click through
- Stores everything locally in SQLite — your data stays on your machine

## Getting started

You'll need macOS 14 (Sonoma) or later and Granola installed.

```bash
git clone git@github.com:2389-research/nodelife.git
cd nodelife
swift build
swift run NodeLife
```

The setup wizard walks you through connecting Granola and picking an LLM provider. It auto-discovers your Granola auth token from the installed app, so there's nothing to copy-paste.

## How it works

NodeLife has two layers:

**NodeLifeCore** is the library. Models, database migrations, the Granola API client, extraction pipelines, entity resolution, the graph system — all testable without a UI.

**NodeLife** is the SwiftUI app. Three-pane layout: sidebar with meetings and entities, a detail view for transcripts or the graph canvas, and an inspector panel for drilling into individual entities.

The extraction pipeline works in passes:
1. Normalize the transcript text
2. Send chunks to an LLM to extract entities with confidence scores
3. Send another pass to extract relationships between those entities
4. Run resolution strategies to merge duplicates (e.g., "Bob" and "Robert Smith")

Everything runs through a job queue with retry and exponential backoff, so if the LLM hiccups mid-extraction, it picks back up.

## Building

```bash
swift build        # compile
swift test         # run all 203 tests
```

CI runs on every push to main. Tagged releases (`v*`) get built, code-signed, notarized, and published as DMGs on GitHub Releases.

## Tech stack

- Swift 6.0 with strict concurrency
- SwiftUI for the UI
- GRDB v7 for SQLite
- Granola HTTP API for transcript import
- Claude or OpenAI-compatible endpoints for extraction

## Project structure

```
Sources/NodeLife/                  # SwiftUI app target
  Views/                           # All the views (setup wizard, graph, sidebar, etc.)
  GraphViewModel.swift             # Graph state management
  ContentView.swift                # Root 3-pane layout

NodeLifeCore/Sources/NodeLifeCore/ # Library target
  Models/                          # GRDB record types
  Database/                        # Migrations, AppDatabase
  Adapters/                        # Granola source adapter
  Services/                        # Sync, search, API clients
  Extraction/                      # LLM-powered entity & relationship extraction
  Resolution/                      # Entity dedup strategies + merge engine
  Graph/                           # Graph types, builder, layout, cache
  Jobs/                            # Background job queue + runner
  LLM/                             # Anthropic + OpenAI clients

NodeLifeCore/Tests/                # 203 tests covering all of the above
```

## License

MIT
