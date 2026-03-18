// ABOUTME: Main entry point for the NodeLife macOS application
// ABOUTME: Configures the app window and initializes the database

import SwiftUI
import NodeLifeCore

@main
struct NodeLifeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
    }
}
