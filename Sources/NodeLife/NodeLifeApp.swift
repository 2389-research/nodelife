// ABOUTME: Main entry point for the NodeLife macOS application
// ABOUTME: Configures the app window and initializes the database

import SwiftUI
import NodeLifeCore

@main
struct NodeLifeApp: App {
    @State private var appState: AppState

    init() {
        do {
            let database = try AppDatabase.makeDefault()
            _appState = State(initialValue: AppState(database: database))
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .defaultSize(width: 1200, height: 800)
    }
}
