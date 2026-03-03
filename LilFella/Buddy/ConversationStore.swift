import Foundation

actor ConversationStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LilFella", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("conversation.json")
    }

    func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func save(_ messages: [ChatMessage]) {
        // Only persist user and assistant messages
        let toSave = messages.filter { $0.role != .system }
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
