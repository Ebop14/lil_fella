import Foundation
import SwiftUI
import os.log

private let log = Logger(subsystem: "com.lilfella", category: "ChatViewModel")

@Observable
@MainActor
final class ChatViewModel {
    private let llamaService: LlamaService
    private let memoryStore: MemoryStore
    private let conversationStore: ConversationStore
    private let buddy: BuddyIdentity

    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var currentStreamedText = ""
    private(set) var tokensPerSecond: Double = 0
    var inputText = ""
    private let samplingConfig = SamplingConfig()

    /// Active tic tac toe game, if any
    var activeGame: TicTacToeViewModel?

    /// The latest assistant message text, for display in the dialogue box.
    var latestBuddyText: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }

    private var generateTask: Task<Void, Never>?
    private var memories: [String] = []
    /// Raw streamed tokens including <think> and <tool> blocks; displayed text has them stripped
    private var rawStreamBuffer = ""
    /// Facts already processed from the current stream (avoid double-processing)
    private var processedFactCount = 0

    init(llamaService: LlamaService, memoryStore: MemoryStore, conversationStore: ConversationStore, buddy: BuddyIdentity) {
        self.llamaService = llamaService
        self.memoryStore = memoryStore
        self.conversationStore = conversationStore
        self.buddy = buddy
    }

    func loadPersistedState() async {
        memories = await memoryStore.load()
        let saved = await conversationStore.load()
        if !saved.isEmpty {
            messages = saved
            log.info("Loaded \(saved.count) persisted messages and \(self.memories.count) memories")
        }
    }

    func loadMemoriesOnly() async {
        memories = await memoryStore.load()
        await conversationStore.clear()
        log.info("Loaded \(self.memories.count) memories, cleared conversation")
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        log.info("User message: \(text.prefix(80))... (total messages: \(self.messages.count))")

        // Check for game trigger
        if detectGameTrigger(text) {
            return
        }

        isGenerating = true
        currentStreamedText = ""
        rawStreamBuffer = ""
        processedFactCount = 0
        tokensPerSecond = 0

        generateTask = Task {
            // Truncate conversation to fit context window
            let truncatedMessages = await truncateToFitContext(messages: messages)
            if truncatedMessages.count < messages.count {
                let dropped = messages.count - truncatedMessages.count
                log.info("Truncated \(dropped) old messages to fit context window")
            }

            let prompt = ChatMLFormatter.format(
                messages: truncatedMessages,
                identity: buddy,
                memories: memories
            )

            log.info("Formatted prompt: \(prompt.count) chars")
            let promptTokenCount = await llamaService.tokenCount(for: prompt)
            let ctxLimit = await llamaService.availableContextLength
            log.info("Prompt token count: \(promptTokenCount), context limit: \(ctxLimit)")

            let startTime = Date()
            var tokenCount = 0

            let stream = await llamaService.generate(prompt: prompt, sampling: samplingConfig)
            for await chunk in stream {
                rawStreamBuffer += chunk

                // Scan for tool calls, then strip think tags from display text
                let scanResult = ToolCallParser.scan(rawStreamBuffer)
                currentStreamedText = Self.stripThinkTags(scanResult.displayText)

                // Process any new memory facts
                if scanResult.memoryFacts.count > processedFactCount {
                    let newFacts = Array(scanResult.memoryFacts[processedFactCount...])
                    processedFactCount = scanResult.memoryFacts.count
                    log.info("New memory facts detected: \(newFacts)")
                    await processMemorySave(facts: newFacts)
                }

                tokenCount += 1
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    tokensPerSecond = Double(tokenCount) / elapsed
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            log.info("Generation complete: \(tokenCount) tokens in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", self.tokensPerSecond)) t/s)")

            // Final scan for any remaining tool calls
            let finalScan = ToolCallParser.scan(rawStreamBuffer)
            if finalScan.memoryFacts.count > processedFactCount {
                let newFacts = Array(finalScan.memoryFacts[processedFactCount...])
                await processMemorySave(facts: newFacts)
            }

            let finalText = Self.stripThinkTags(finalScan.displayText)
            if !finalText.isEmpty {
                let assistantMessage = ChatMessage(role: .assistant, content: finalText)
                messages.append(assistantMessage)
                log.info("Assistant response: \(finalText.prefix(80))...")
            } else {
                log.warning("Generation produced empty response after stripping think tags")
                log.debug("Raw stream buffer was: \(self.rawStreamBuffer.prefix(200))")
            }

            currentStreamedText = ""
            rawStreamBuffer = ""
            processedFactCount = 0
            isGenerating = false
            generateTask = nil

            await llamaService.clearContext()
            await conversationStore.save(messages)
        }
    }

    /// Truncate older messages so the prompt fits within the context window.
    /// Always keeps the most recent user message and as many recent messages as fit.
    private func truncateToFitContext(messages: [ChatMessage]) async -> [ChatMessage] {
        let contextLimit = Int(await llamaService.availableContextLength)
        // Reserve tokens for generation output
        let reserveForGeneration = Int(samplingConfig.maxTokens / 2)
        let maxPromptTokens = contextLimit - reserveForGeneration

        guard maxPromptTokens > 0 else {
            log.error("Context too small for any generation (limit: \(contextLimit), reserve: \(reserveForGeneration))")
            return messages
        }

        // First, try with all messages
        let fullPrompt = ChatMLFormatter.format(messages: messages, identity: buddy, memories: memories)
        let fullTokens = await llamaService.tokenCount(for: fullPrompt)

        if fullTokens <= maxPromptTokens {
            return messages
        }

        log.warning("Full prompt (\(fullTokens) tokens) exceeds budget (\(maxPromptTokens) tokens), truncating")

        // Binary search: keep removing oldest non-system messages until it fits
        // Always keep the system messages and at least the last user message
        var truncated = messages
        while truncated.count > 1 {
            // Remove the oldest non-system message
            if let firstNonSystemIdx = truncated.firstIndex(where: { $0.role != .system }) {
                truncated.remove(at: firstNonSystemIdx)
            } else {
                break
            }

            let prompt = ChatMLFormatter.format(messages: truncated, identity: buddy, memories: memories)
            let tokenCount = await llamaService.tokenCount(for: prompt)
            if tokenCount <= maxPromptTokens {
                log.info("Truncated to \(truncated.count) messages (\(tokenCount) tokens)")
                return truncated
            }
        }

        log.error("Could not fit even a single message in context window!")
        return [messages.last!]
    }

    func stopGenerating() {
        log.info("Stop generating requested")
        Task {
            await llamaService.cancelGeneration()
        }
        generateTask?.cancel()

        // Final scan for tool calls before finalizing
        let scanResult = ToolCallParser.scan(rawStreamBuffer)
        if scanResult.memoryFacts.count > processedFactCount {
            let newFacts = Array(scanResult.memoryFacts[processedFactCount...])
            Task { await processMemorySave(facts: newFacts) }
        }

        let finalText = Self.stripThinkTags(scanResult.displayText)
        if !finalText.isEmpty {
            let partial = ChatMessage(role: .assistant, content: finalText)
            messages.append(partial)
        }

        currentStreamedText = ""
        rawStreamBuffer = ""
        processedFactCount = 0
        isGenerating = false
        generateTask = nil

        Task { await conversationStore.save(messages) }
    }

    func clearConversation() {
        log.info("Clearing conversation (\(self.messages.count) messages)")
        // Extract memories before clearing (fallback for models that don't use tool calls)
        if messages.count >= 4 {
            let conversationMessages = messages
            Task {
                await extractMemories(from: conversationMessages)
            }
        }

        messages = []
        currentStreamedText = ""
        tokensPerSecond = 0

        Task {
            await llamaService.clearContext()
            await conversationStore.clear()
        }
    }

    // MARK: - Game Trigger

    private static let gameTriggerPatterns = [
        "tic tac toe", "tic-tac-toe", "tictactoe",
        "play ttt", "let's play ttt",
        "play tic tac", "play a game of tic",
        "wanna play tic", "want to play tic",
    ]

    private func detectGameTrigger(_ text: String) -> Bool {
        let lower = text.lowercased()
        let isGameRequest = Self.gameTriggerPatterns.contains { lower.contains($0) }
        guard isGameRequest else { return false }

        log.info("Game trigger detected")
        let gameVM = TicTacToeViewModel(
            llamaService: llamaService,
            buddy: buddy,
            memories: memories,
            messageProvider: { [weak self] in self?.messages ?? [] }
        )
        gameVM.onCommentary = { [weak self] text in
            self?.appendGameCommentary(text)
        }
        gameVM.onMemorySave = { [weak self] facts in
            guard let self else { return }
            Task { await self.processMemorySave(facts: facts) }
        }
        activeGame = gameVM

        messages.append(ChatMessage(role: .assistant, content: "Alright, let's play! You're X, I'm O. Tap a square to make your move."))
        Task { await conversationStore.save(messages) }

        gameVM.startGame()
        return true
    }

    func appendGameCommentary(_ text: String) {
        messages.append(ChatMessage(role: .assistant, content: text))
        Task { await conversationStore.save(messages) }
    }

    func dismissGame() {
        activeGame?.dismissGame()
        activeGame = nil
    }

    // MARK: - Memory Tool Calls

    private func processMemorySave(facts: [String]) async {
        guard !facts.isEmpty else { return }
        log.info("Saving \(facts.count) memory facts")
        await memoryStore.merge(newFacts: facts)
        memories = await memoryStore.currentFacts()

        let factList = facts.joined(separator: ", ")
        messages.append(ChatMessage(role: .system, content: "Remembered: \(factList)"))

        // Compact memory if getting full (run in background, non-blocking)
        if await memoryStore.needsCompaction {
            log.info("Memory needs compaction (\(self.memories.count) facts)")
            Task { await compactMemories() }
        }
    }

    private func compactMemories() async {
        let currentFacts = await memoryStore.currentFacts()
        guard currentFacts.count >= 20 else { return }

        log.info("Starting memory compaction with \(currentFacts.count) facts")
        let prompt = MemoryStore.compactionPrompt(from: currentFacts)
        let compactionSampling = SamplingConfig(
            temperature: 0.1,
            topK: 10,
            topP: 0.9,
            repeatPenalty: 1.0,
            maxTokens: 512,
            seed: 42
        )

        var response = ""
        let stream = await llamaService.generate(prompt: prompt, sampling: compactionSampling)

        let compactionTask = Task {
            for await chunk in stream {
                response += chunk
            }
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(15))
            compactionTask.cancel()
            await llamaService.cancelGeneration()
        }

        await compactionTask.value
        timeoutTask.cancel()
        await llamaService.clearContext()

        guard let compacted = parseFactsJSON(response), !compacted.isEmpty else {
            log.warning("Memory compaction produced no valid output")
            return
        }
        // Only accept if we actually reduced the count
        guard compacted.count < currentFacts.count else {
            log.info("Compaction didn't reduce facts (\(compacted.count) >= \(currentFacts.count)), keeping originals")
            return
        }

        log.info("Memory compacted: \(currentFacts.count) -> \(compacted.count) facts")
        await memoryStore.replaceAll(with: compacted)
        memories = await memoryStore.currentFacts()
    }

    // MARK: - Fallback Memory Extraction

    private func extractMemories(from conversation: [ChatMessage]) async {
        log.info("Extracting memories from \(conversation.count) messages")
        let prompt = MemoryStore.extractionPrompt(from: conversation)

        let extractionSampling = SamplingConfig(
            temperature: 0.1,
            topK: 10,
            topP: 0.9,
            repeatPenalty: 1.0,
            maxTokens: 256,
            seed: 42
        )

        var response = ""
        let stream = await llamaService.generate(prompt: prompt, sampling: extractionSampling)

        let extractionTask = Task {
            for await chunk in stream {
                response += chunk
            }
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(10))
            extractionTask.cancel()
            await llamaService.cancelGeneration()
        }

        await extractionTask.value
        timeoutTask.cancel()
        await llamaService.clearContext()

        guard let facts = parseFactsJSON(response) else {
            log.warning("Memory extraction produced no valid JSON")
            return
        }
        guard !facts.isEmpty else {
            log.info("Memory extraction found no new facts")
            return
        }

        log.info("Extracted \(facts.count) facts from conversation")
        await memoryStore.merge(newFacts: facts)
        memories = await memoryStore.currentFacts()

        let factList = facts.joined(separator: ", ")
        messages.append(ChatMessage(role: .system, content: "Remembered: \(factList)"))
    }

    /// Strips `<think>...</think>` blocks (including incomplete ones still streaming)
    static func stripThinkTags(_ text: String) -> String {
        // Remove complete <think>...</think> blocks
        var result = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        // Remove incomplete <think>... at the end (still streaming)
        if let range = result.range(of: "<think>[\\s\\S]*$", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseFactsJSON(_ text: String) -> [String]? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            return nil
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        return array.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 100 }
    }
}
