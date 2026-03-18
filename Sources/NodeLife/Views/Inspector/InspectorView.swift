// ABOUTME: Inspector panel showing entity details, relationships, mentions, and merge actions
// ABOUTME: Displays in the trailing column of the 3-pane layout

import SwiftUI
import NodeLifeCore
import GRDB

struct InspectorView: View {
    let entityID: UUID
    let database: AppDatabase
    @State private var entity: Entity?
    @State private var aliases: [EntityAlias] = []
    @State private var relationships: [Relationship] = []
    @State private var mentions: [Mention] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entity = entity {
                    // Entity header
                    VStack(alignment: .leading, spacing: 8) {
                        Label(entity.kind.rawValue.capitalized, systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entity.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if let summary = entity.summary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Mentions: \(entity.mentionCount)")
                            Spacer()
                            Text("First seen: \(entity.firstSeenAt, style: .date)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Aliases
                    if !aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aliases")
                                .font(.headline)
                            ForEach(aliases) { alias in
                                Text(alias.alias)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }

                    // Relationships
                    if !relationships.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relationships (\(relationships.count))")
                                .font(.headline)
                            ForEach(relationships) { rel in
                                HStack {
                                    Text(rel.kind.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                    Spacer()
                                    Text("w: \(rel.weight, specifier: "%.1f")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                    }

                    // Mentions
                    if !mentions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mentions (\(mentions.count))")
                                .font(.headline)
                            ForEach(mentions.prefix(20)) { mention in
                                Text("Confidence: \(mention.confidence, specifier: "%.0f%%")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Loading...", systemImage: "ellipsis.circle")
                }
            }
            .padding()
        }
        .task {
            loadEntityDetails()
        }
    }

    private func loadEntityDetails() {
        let targetID = entityID
        do {
            try database.read { db in
                entity = try Entity.fetchOne(db, key: targetID)
                aliases = try EntityAlias
                    .filter(EntityAlias.Columns.entityID == targetID)
                    .fetchAll(db)
                relationships = try Relationship
                    .filter(Relationship.Columns.sourceEntityID == targetID || Relationship.Columns.targetEntityID == targetID)
                    .fetchAll(db)
                mentions = try Mention
                    .filter(Mention.Columns.entityID == targetID)
                    .fetchAll(db)
            }
        } catch {
            // silently fail — entity will remain nil showing loading state
        }
    }
}
