import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.screenState {
            case .needsDownload:
                ModelPickerView()
            case .readyToLoad:
                ModelPickerView()
            case .loading:
                ProgressView("Loading model...")
            case .ready:
                ChatView()
            case .error(let message):
                errorView(message)
            }
        }
        .task {
            await appState.autoLoadLastModel()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Dismiss") {
                appState.clearError()
            }
        }
        .padding()
    }
}
