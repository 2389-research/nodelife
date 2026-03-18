// ABOUTME: Observable application state for the NodeLife macOS app
// ABOUTME: Manages database, sync, and selection state for the UI

import SwiftUI
import NodeLifeCore

@Observable
@MainActor
final class AppState {
    let database: AppDatabase
    var meetings: [Meeting] = []
    var selectedMeetingId: UUID?
    var searchQuery: String = ""
    var isSyncing: Bool = false
    var syncProgress: String = ""

    init(database: AppDatabase) {
        self.database = database
    }

    func loadMeetings() throws {
        meetings = try database.read { db in
            try Meeting
                .order(Meeting.Columns.date.desc)
                .fetchAll(db)
        }
    }
}
