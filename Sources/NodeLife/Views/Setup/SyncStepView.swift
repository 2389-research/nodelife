// ABOUTME: Step 5 of setup wizard that runs the initial meeting sync
// ABOUTME: Creates SyncService per enabled source, shows progress bar, handles errors

import SwiftUI
import NodeLifeCore

struct SyncStepView: View {
    let database: AppDatabase
    let granolaEnabled: Bool
    let granolaPath: String
    let muesliEnabled: Bool
    let muesliPath: String
    let onFinish: () -> Void
    var body: some View { Text("Sync (placeholder)") }
}
