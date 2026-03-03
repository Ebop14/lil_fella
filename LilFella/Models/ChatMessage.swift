import Foundation

struct ChatMessage: Identifiable, Sendable, Codable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
