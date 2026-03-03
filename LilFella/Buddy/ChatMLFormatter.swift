import Foundation

enum ChatMLFormatter {
    static func format(
        messages: [ChatMessage],
        identity: BuddyIdentity,
        memories: [String] = []
    ) -> String {
        var result = ""

        // System prompt with memory facts
        let systemPrompt = identity.systemPrompt(memories: memories)
        result += "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"

        // Conversation messages
        for message in messages {
            switch message.role {
            case .system:
                continue // already handled above
            case .user:
                result += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                result += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            }
        }

        // Trailing assistant turn opener
        result += "<|im_start|>assistant\n"
        return result
    }
}
