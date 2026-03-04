import SwiftUI

struct PetSceneView: View {
    @Environment(AppState.self) private var appState
    @State private var animationState = PetAnimationState()
    @State private var viewModel: ChatViewModel?
    @State private var showClearConfirmation = false
    @FocusState private var isInputFocused: Bool

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
                    await viewModel.loadMemoriesOnly()
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
                // 1. Conversation box at the top
                ConversationBoxView(viewModel: viewModel, screenSize: geo.size)
                    .padding(.horizontal, geo.size.width * 0.03)
                    .padding(.top, geo.size.height * 0.005)

                // 2. Lil Fella character in the middle
                ZStack(alignment: .bottom) {
                    PixelEnvironmentView(screenHeight: geo.size.height)

                    if let gameVM = viewModel.activeGame, gameVM.isActive {
                        gameLayout(viewModel: viewModel, gameVM: gameVM, geo: geo)
                    } else {
                        normalCharacterLayout(geo: geo)
                    }
                }
                .frame(height: geo.size.height * 0.22)

                // 3. Input bar at the bottom (just above keyboard)
                InputBarView(viewModel: viewModel, screenSize: geo.size, onNewChat: {
                    showClearConfirmation = true
                }, isInputFocused: $isInputFocused)
                    .padding(.horizontal, geo.size.width * 0.03)
                    .padding(.bottom, geo.size.height * 0.005)
            }
        }
        .background(PetPalette.skyTop)
        .onAppear {
            UITextField.appearance().keyboardAppearance = .light
            isInputFocused = true
        }
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
        .padding(.bottom, geo.size.height * 0.01)
    }

    // MARK: - Game Layout

    private func gameLayout(viewModel: ChatViewModel, gameVM: TicTacToeViewModel, geo: GeometryProxy) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
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

            let boardSize = min(geo.size.width * 0.5, geo.size.height * 0.2)
            TicTacToeBoardView(
                game: gameVM.game,
                onCellTap: { index in
                    gameVM.userMove(at: index)
                },
                size: boardSize
            )
            .padding(.bottom, geo.size.height * 0.02)
            .padding(.trailing, geo.size.width * 0.05)
        }
    }

    // MARK: - Sizing

    private func pixelSize(for screenSize: CGSize) -> CGFloat {
        let fromWidth = screenSize.width * 0.30 / 20
        let fromHeight = screenSize.height * 0.18 / 16
        return min(fromWidth, fromHeight)
    }

    private func smallPixelSize(for screenSize: CGSize) -> CGFloat {
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
