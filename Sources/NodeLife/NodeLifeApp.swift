// ABOUTME: Main entry point for the NodeLife macOS application
// ABOUTME: Configures the app window, settings scene, and initializes the database

import SwiftUI
import NodeLifeCore

@main
struct NodeLifeApp: App {
    @State private var appState: AppState
    private let sparkleUpdateController = SparkleUpdateController()

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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    sparkleUpdateController.checkForUpdates()
                }
                .disabled(!sparkleUpdateController.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
        }

        Window("Job Log", id: "job-log") {
            JobLogView(appState: appState)
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 700, height: 400)
    }
}
