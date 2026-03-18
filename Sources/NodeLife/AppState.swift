// ABOUTME: Observable application state for the NodeLife macOS app
// ABOUTME: Manages database, sync, selection, entities, and detail mode switching

import SwiftUI
import NodeLifeCore
import GRDB

enum DetailMode: Hashable {
    case meeting
    case graph
    case search
}

@Observable
@MainActor
final class AppState {
    let database: AppDatabase
    var meetings: [Meeting] = []
    var entities: [Entity] = []
    var selectedMeetingId: UUID?
    var searchQuery: String = ""
    var isSyncing: Bool = false
    var syncProgress: String = ""
    var detailMode: DetailMode = .meeting
    @ObservationIgnored
    private var _graphViewModel: GraphViewModel?
    var graphViewModel: GraphViewModel {
        if let vm = _graphViewModel { return vm }
        let vm = GraphViewModel(database: database)
        _graphViewModel = vm
        return vm
    }

    init(database: AppDatabase) {
        self.database = database
    }

    func loadMeetings() throws {
        meetings = try database.read { db in
            try Meeting.order(Meeting.Columns.date.desc).fetchAll(db)
        }
    }

    func loadEntities() throws {
        entities = try database.read { db in
            try Entity.filter(Entity.Columns.mergedIntoId == nil)
                .order(Entity.Columns.name.asc)
                .fetchAll(db)
        }
    }

    func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        try? loadMeetings()
        try? loadEntities()
    }
}
