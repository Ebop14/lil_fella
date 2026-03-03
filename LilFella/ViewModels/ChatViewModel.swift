import Foundation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    private let llamaService: LlamaService
    private let memoryStore: MemoryStore
    private let buddy: BuddyIdentity

    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var currentStreamedText = ""
    private(set) var tokensPerSecond: Double = 0
    var inputText = ""
    private let samplingConfig = SamplingConfig()

    /// The latest assistant message text, for display in the dialogue box.
    var latestBuddyText: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }

    private var generateTask: Task<Void, Never>?
    private var memories: [String] = []
    /// Raw streamed tokens including <think> blocks; displayed text has them stripped
    private var rawStreamBuffer = ""

    init(llamaService: LlamaService, memoryStore: MemoryStore, buddy: BuddyIdentity) {
        self.llamaService = llamaService
        self.memoryStore = memoryStore
        self.buddy = buddy
    }

    func loadMemories() async {
        memories = await memoryStore.load()
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        isGenerating = true
        currentStreamedText = ""
        rawStreamBuffer = ""
        tokensPerSecond = 0

        generateTask = Task {
            let prompt = ChatMLFormatter.format(
                messages: messages,
                identity: buddy,
                memories: memories
            )

            let startTime = Date()
            var tokenCount = 0

            let stream = await llamaService.generate(prompt: prompt, sampling: samplingConfig)
            for await chunk in stream {
                rawStreamBuffer += chunk
                currentStreamedText = Self.stripThinkTags(rawStreamBuffer)
                tokenCount += 1

                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    tokensPerSecond = Double(tokenCount) / elapsed
                }
            }

            let finalText = Self.stripThinkTags(rawStreamBuffer)
            if !finalText.isEmpty {
                let assistantMessage = ChatMessage(role: .assistant, content: finalText)
                messages.append(assistantMessage)
            }

            currentStreamedText = ""
            rawStreamBuffer = ""
            isGenerating = false
            generateTask = nil

            // Clear KV cache for next turn (we re-encode full context each time)
            await llamaService.clearContext()
        }
    }

    func stopGenerating() {
        Task {
            await llamaService.cancelGeneration()
        }
        generateTask?.cancel()

        let finalText = Self.stripThinkTags(rawStreamBuffer)
        if !finalText.isEmpty {
            let partial = ChatMessage(role: .assistant, content: finalText)
            messages.append(partial)
        }

        currentStreamedText = ""
        rawStreamBuffer = ""
        isGenerating = false
        generateTask = nil
    }

    func clearConversation() {
        // Extract memories before clearing
        if messages.count >= 2 {
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
        }
    }

    private func extractMemories(from conversation: [ChatMessage]) async {
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

        // Timeout: cancel after 10 seconds
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

        // Parse JSON array from response
        guard let facts = parseFactsJSON(response) else { return }
        guard !facts.isEmpty else { return }

        await memoryStore.merge(newFacts: facts)
        memories = await memoryStore.currentFacts()

        let factList = facts.joined(separator: ", ")
        messages.append(ChatMessage(role: .system, content: "Memory updated: \(factList)"))
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
        // Find JSON array in response (model might include extra text)
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            return nil
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        // Filter out empty strings and overly long facts
        return array.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 100 }
    }
}
