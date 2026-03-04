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
                    updateAnimationState(viewModel: viewModel)
                }
                .onChange(of: viewModel.currentStreamedText) { _, _ in
                    updateAnimationState(viewModel: viewModel)
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
                // Top spacing (~5%)
                Spacer()
                    .frame(height: geo.size.height * 0.05)

                // Environment + Character (~60%)
                ZStack(alignment: .bottom) {
                    PixelEnvironmentView(screenHeight: geo.size.height)

                    if let gameVM = viewModel.activeGame, gameVM.isActive {
                        // Game mode: board in center, character to the side
                        gameLayout(viewModel: viewModel, gameVM: gameVM, geo: geo)
                    } else {
                        // Normal mode: character centered
                        normalCharacterLayout(geo: geo)
                    }
                }
                .frame(height: geo.size.height * 0.60)

                // Dialogue Box (~35%)
                DialogueBoxView(viewModel: viewModel, screenSize: geo.size, onNewChat: {
                    showClearConfirmation = true
                })
                    .padding(.horizontal, geo.size.width * 0.03)
                    .padding(.top, geo.size.height * 0.005)
                    .padding(.bottom, geo.size.height * 0.01)
                    .frame(height: geo.size.height * 0.35)
            }
        }
        .background(PetPalette.skyTop)
        .confirmationDialog("Start a new chat?", isPresented: $showClearConfirmation) {
            Button("New Chat", role: .destructive) {
                viewModel.dismissGame()
                viewModel.clearConversation()
            }
        } message: {
            Text("Memories will be saved. Conversation will be cleared.")
        }
    }

    // MARK: - Normal Layout

    private func normalCharacterLayout(geo: GeometryProxy) -> some View {
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

    // MARK: - Game Layout

    private func gameLayout(viewModel: ChatViewModel, gameVM: TicTacToeViewModel, geo: GeometryProxy) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Character scaled down on the left
            VStack(spacing: 0) {
                if animationState.state == .thinking {
                    ThinkingDotsView(pixelSize: smallPixelSize(for: geo.size))
                }

                TimelineView(.periodic(from: .now, by: animationState.state.interval)) { _ in
                    PixelCharacterView(
                        frame: animationState.currentFrame,
                        pixelSize: smallPixelSize(for: geo.size)
                    )
                    .onAppear {
                        animationState.advance()
                    }
                }
            }
            .frame(width: geo.size.width * 0.25)
            .padding(.bottom, geo.size.height * 0.015)

            // Game board in the center-right area
            let boardSize = min(geo.size.width * 0.6, geo.size.height * 0.45)
            TicTacToeBoardView(
                game: gameVM.game,
                onCellTap: { index in
                    gameVM.userMove(at: index)
                },
                size: boardSize
            )
            .padding(.bottom, geo.size.height * 0.04)
            .padding(.trailing, geo.size.width * 0.05)
        }
    }

    // MARK: - Sizing

    private func pixelSize(for screenSize: CGSize) -> CGFloat {
        let fromWidth = screenSize.width * 0.38 / 20
        let fromHeight = screenSize.height * 0.22 / 16
        return min(fromWidth, fromHeight)
    }

    private func smallPixelSize(for screenSize: CGSize) -> CGFloat {
        // ~60% of normal size for game mode
        return pixelSize(for: screenSize) * 0.6
    }

    private func updateAnimationState(viewModel: ChatViewModel) {
        if let gameVM = viewModel.activeGame, gameVM.isThinking {
            animationState.state = .thinking
        } else if viewModel.isGenerating {
            animationState.state = viewModel.currentStreamedText.isEmpty ? .thinking : .talking
        } else {
            animationState.state = .idle
        }
        animationState.frameIndex = 0
    }
}

