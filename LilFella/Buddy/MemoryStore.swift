import Foundation

actor MemoryStore {
    private static let maxFacts = 30
    private static let compactionThreshold = 25
    private static let maxFactLength = 100

    private let fileURL: URL
    private var facts: [String] = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LilFella", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("memory.json")
    }

    func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        facts = decoded
        return facts
    }

    func save(_ newFacts: [String]) {
        facts = newFacts
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func merge(newFacts: [String]) {
        let existing = facts
        var merged = existing

        for fact in newFacts {
            let trimmed = String(fact.prefix(Self.maxFactLength))
            guard !trimmed.isEmpty else { continue }

            // Skip if any existing fact contains this one or vice versa
            let isDuplicate = existing.contains { existing in
                existing.localizedCaseInsensitiveContains(trimmed)
                || trimmed.localizedCaseInsensitiveContains(existing)
            }
            if !isDuplicate {
                merged.append(trimmed)
            }
        }

        // Drop oldest if over cap
        if merged.count > Self.maxFacts {
            merged = Array(merged.suffix(Self.maxFacts))
        }

        save(merged)
    }

    func currentFacts() -> [String] {
        return facts
    }

    var needsCompaction: Bool {
        facts.count >= Self.compactionThreshold
    }

    func deleteFact(at index: Int) {
        guard facts.indices.contains(index) else { return }
        facts.remove(at: index)
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func compactionPrompt(from facts: [String]) -> String {
        let factList = facts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        return """
        Consolidate these memory facts about a user into a shorter list.
        Merge related facts (e.g. multiple game results into one summary).
        Keep important unique facts. Drop trivial or redundant ones.
        Return ONLY a JSON array of short fact strings. Target 15 or fewer facts.

        Current facts:
        \(factList)

        Consolidated JSON array:
        """
    }

    func replaceAll(with newFacts: [String]) {
        let filtered = newFacts
            .map { String($0.prefix(Self.maxFactLength)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        save(filtered)
    }

    static func extractionPrompt(from conversation: [ChatMessage]) -> String {
        var conversationText = ""
        for message in conversation {
            switch message.role {
            case .system:
                continue
            case .user:
                conversationText += "User: \(message.content)\n"
            case .assistant:
                conversationText += "Assistant: \(message.content)\n"
            }
        }

        return """
        Extract key facts about the user from this conversation.
        Return ONLY a JSON array of short fact strings. Examples:
        ["User's name is Eric", "User likes hiking"]
        If there are no new facts worth remembering, return [].

        Conversation:
        \(conversationText)

        JSON array of facts:
        """
    }
}
