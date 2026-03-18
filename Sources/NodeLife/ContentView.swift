// ABOUTME: Root content view placeholder for the NodeLife app
// ABOUTME: Will become the 3-pane NavigationSplitView in a later phase

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("NodeLife")
                .font(.largeTitle)
            Text("Knowledge Graph from Meeting Transcripts")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
