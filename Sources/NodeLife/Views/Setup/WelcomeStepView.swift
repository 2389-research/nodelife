// ABOUTME: Step 1 of the setup wizard showing app name and tagline
// ABOUTME: Simple welcome screen with "Get Started" button to advance

import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("NodeLife")
                .font(.largeTitle.bold())

            Text("Build a knowledge graph from your meeting transcripts")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Get Started") {
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }
}
