// ABOUTME: Step 2 of setup wizard for data source detection and selection
// ABOUTME: Auto-detects Granola and Muesli directories, shows counts with enable/disable toggles

import SwiftUI
import NodeLifeCore

struct DataSourceStepView: View {
    @Binding var granolaEnabled: Bool
    @Binding var granolaPath: String
    @Binding var muesliEnabled: Bool
    @Binding var muesliPath: String
    var body: some View { Text("Data Sources (placeholder)") }
}
