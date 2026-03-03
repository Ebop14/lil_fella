import SwiftUI

struct PetSceneView: View {
    @Environment(AppState.self) private var appState
    @State private var animationState = PetAnimationState()
    @State private var viewModel: ChatViewModel?
    @State private var showClearConfirmation = false

    var body: some View {
        if let viewModel {
            sceneContent(viewModel: viewModel)
                .onChange(of: viewModel.isGenerating) { _, generating in
                    updateAnimationState(generating: generating, text: viewModel.currentStreamedText)
                }
                .onChange(of: viewModel.currentStreamedText) { _, text in
                    updateAnimationState(generating: viewModel.isGenerating, text: text)
                }
                .task {
                    await viewModel.loadPersistedState()
                }
        } else {
            Color.clear.onAppear {
                viewModel = ChatViewModel(
                    llamaService: appState.llamaService,
                    memoryStore: appState.memoryStore,
                    conversationStore: appState.conversationStore,
                    buddy: appState.buddy
                )
            }
        }
    }

    private func sceneContent(viewModel: ChatViewModel) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top nav bar placeholder (~5%)
                HStack {
                    Spacer()
                }
                .frame(height: geo.size.height * 0.05)

                // Environment + Character (~60%)
                ZStack(alignment: .bottom) {
                    PixelEnvironmentView(screenHeight: geo.size.height)

                    // Character + thinking dots
                    VStack(spacing: 0) {
                        if animationState.state == .thinking {
                            ThinkingDotsView(pixelSize: pixelSize(for: geo.size))
                        }

                        TimelineView(.periodic(from: .now, by: animationState.state.interval)) { _ in
                            PixelCharacterView(
                                frame: animationState.currentFrame,
                                pixelSize: pixelSize(for: geo.size)
                            )
                            .onAppear {
                                animationState.advance()
                            }
                        }
                    }
                    .padding(.bottom, geo.size.height * 0.025)
                }
                .frame(height: geo.size.height * 0.60)

                // Dialogue Box (~35%)
                DialogueBoxView(viewModel: viewModel, screenSize: geo.size)
                    .padding(.horizontal, geo.size.width * 0.03)
                    .padding(.top, geo.size.height * 0.005)
                    .padding(.bottom, geo.size.height * 0.01)
                    .frame(height: geo.size.height * 0.35)
            }
        }
        .background(PetPalette.skyTop)
        .confirmationDialog("Clear conversation?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                viewModel.clearConversation()
            }
        }
        .onLongPressGesture {
            showClearConfirmation = true
        }
    }

    private func pixelSize(for screenSize: CGSize) -> CGFloat {
        // Scale sprite to ~38% of screen width, 20px wide sprite
        let fromWidth = screenSize.width * 0.38 / 20
        // Also cap relative to screen height
        let fromHeight = screenSize.height * 0.22 / 16
        return min(fromWidth, fromHeight)
    }

    private func updateAnimationState(generating: Bool, text: String) {
        if generating {
            animationState.state = text.isEmpty ? .thinking : .talking
        } else {
            animationState.state = .idle
        }
        animationState.frameIndex = 0
    }
}
