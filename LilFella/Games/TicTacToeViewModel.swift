import Foundation

@Observable
@MainActor
final class TicTacToeViewModel {
    private let llamaService: LlamaService
    private let buddy: BuddyIdentity
    private let memories: [String]
    /// Live accessor for current conversation messages (includes game commentary as it happens)
    private let messageProvider: () -> [ChatMessage]

    private(set) var game = TicTacToeGame()
    private(set) var isThinking = false
    private(set) var isActive = false

    /// Callback to pipe commentary into ChatViewModel messages
    var onCommentary: ((String) -> Void)?
    /// Callback to save facts to memory store
    var onMemorySave: (([String]) -> Void)?

    private let gameSampling = SamplingConfig(
        temperature: 0.7,
        topK: 30,
        topP: 0.9,
        repeatPenalty: 1.0,
        maxTokens: 128,
        seed: UInt32.random(in: 0...UInt32.max)
    )

    init(llamaService: LlamaService, buddy: BuddyIdentity, memories: [String], messageProvider: @escaping () -> [ChatMessage]) {
        self.llamaService = llamaService
        self.buddy = buddy
        self.memories = memories
        self.messageProvider = messageProvider
    }

    /// Grab the latest conversation context (last 8 messages to keep prompt bounded)
    private var contextMessages: [ChatMessage] {
        Array(messageProvider().suffix(8))
    }

    func startGame() {
        game = TicTacToeGame()
        isActive = true
    }

    func dismissGame() {
        isActive = false
    }

    func userMove(at index: Int) {
        guard !isThinking, case .ongoing = game.result else { return }
        guard game.currentTurn == .x else { return }
        guard game.place(at: index) else { return }

        if case .ongoing = game.result {
            // Game continues, LLM's turn
            Task { await requestLLMMove() }
        } else {
            // Game over after user move
            Task { await requestOutcomeCommentary() }
        }
    }

    // MARK: - LLM Move

    private func requestLLMMove() async {
        isThinking = true
        defer { isThinking = false }

        let prompt = buildMovePrompt()
        var response = ""
        let stream = await llamaService.generate(prompt: prompt, sampling: gameSampling)
        for await chunk in stream {
            response += chunk
        }
        await llamaService.clearContext()

        // Parse MOVE: N from response
        let move = parseMoveFromResponse(response)
        let validMove = validateMove(move)

        guard game.place(at: validMove) else { return }

        // Extract any commentary (TALK: text)
        if let talk = parseTalkFromResponse(response) {
            onCommentary?(talk)
        }

        // Check if game is over after LLM's move
        if case .ongoing = game.result {
            // Game continues
        } else {
            await requestOutcomeCommentary()
        }
    }

    private func requestOutcomeCommentary() async {
        isThinking = true
        defer { isThinking = false }

        let outcomeText: String
        switch game.result {
        case .win(.x, _):
            outcomeText = "The human (X) won."
        case .win(.o, _):
            outcomeText = "You (O) won!"
        case .draw:
            outcomeText = "It's a draw."
        case .ongoing:
            return
        }

        var prompt = """
        <|im_start|>system
        \(buddy.systemPrompt(memories: memories))
        You just finished a tic tac toe game with your human. Look at the conversation to understand context.<|im_end|>
        """

        for message in contextMessages {
            switch message.role {
            case .user:
                prompt += "\n<|im_start|>user\n\(message.content)<|im_end|>"
            case .assistant:
                prompt += "\n<|im_start|>assistant\n\(message.content)<|im_end|>"
            case .system:
                continue
            }
        }

        prompt += """
        \n<|im_start|>user
        \(outcomeText) React briefly.<|im_end|>
        <|im_start|>assistant
        """

        var response = ""
        let stream = await llamaService.generate(prompt: prompt, sampling: gameSampling)
        for await chunk in stream {
            response += chunk
        }
        await llamaService.clearContext()

        let clean = ChatViewModel.stripThinkTags(response)
        if !clean.isEmpty {
            onCommentary?(clean)
        }

        // Save game outcome to memory
        let memoryFact: String
        switch game.result {
        case .win(.x, _):
            memoryFact = "Human beat Lil Fella at tic tac toe"
        case .win(.o, _):
            memoryFact = "Lil Fella beat human at tic tac toe"
        case .draw:
            memoryFact = "Played tic tac toe with human, ended in a draw"
        case .ongoing:
            return
        }
        onMemorySave?([memoryFact])
    }

    // MARK: - Prompt Building

    private func buildMovePrompt() -> String {
        let boardText = game.boardDescription()
        let available = game.availableMoves.map { "\($0 + 1)" }.joined(separator: ", ")

        var prompt = """
        <|im_start|>system
        \(buddy.systemPrompt(memories: memories))
        You are playing tic tac toe as O against your human who is X. Pick a smart move.
        Look at the conversation so far to understand context and your human's mood.
        Reply EXACTLY in this format (one line each):
        MOVE: N
        TALK: your brief comment
        Where N is a number from the available positions. Keep TALK under 15 words. No emojis.<|im_end|>
        """

        // Include recent conversation for context
        for message in contextMessages {
            switch message.role {
            case .user:
                prompt += "\n<|im_start|>user\n\(message.content)<|im_end|>"
            case .assistant:
                prompt += "\n<|im_start|>assistant\n\(message.content)<|im_end|>"
            case .system:
                continue
            }
        }

        prompt += """
        \n<|im_start|>user
        Board:
        \(boardText)
        Available positions: \(available)
        Your move as O?<|im_end|>
        <|im_start|>assistant
        """

        return prompt
    }

    // MARK: - Response Parsing

    private func parseMoveFromResponse(_ response: String) -> Int? {
        // Look for "MOVE: N" pattern
        let pattern = #"MOVE:\s*(\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response),
              let num = Int(response[range]) else {
            return nil
        }
        return num - 1 // Convert 1-indexed to 0-indexed
    }

    private func parseTalkFromResponse(_ response: String) -> String? {
        let pattern = #"TALK:\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response) else {
            return nil
        }
        let talk = ChatViewModel.stripThinkTags(String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines))
        return talk.isEmpty ? nil : talk
    }

    private func validateMove(_ parsed: Int?) -> Int {
        let available = game.availableMoves
        guard !available.isEmpty else { return 0 }

        if let parsed, available.contains(parsed) {
            return parsed
        }
        // Fallback: random valid move
        return available.randomElement()!
    }
}
