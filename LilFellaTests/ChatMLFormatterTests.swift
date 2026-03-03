import Testing
@testable import LilFella

struct ChatMLFormatterTests {
    @Test func formatsBasicConversation() {
        let messages = [
            ChatMessage(role: .user, content: "Hello!"),
            ChatMessage(role: .assistant, content: "Hi there!"),
            ChatMessage(role: .user, content: "How are you?")
        ]

        let result = ChatMLFormatter.format(
            messages: messages,
            identity: BuddyIdentity.defaultBuddy
        )

        #expect(result.hasPrefix("<|im_start|>system\n"))
        #expect(result.contains("<|im_start|>user\nHello!<|im_end|>"))
        #expect(result.contains("<|im_start|>assistant\nHi there!<|im_end|>"))
        #expect(result.contains("<|im_start|>user\nHow are you?<|im_end|>"))
        #expect(result.hasSuffix("<|im_start|>assistant\n"))
    }

    @Test func includesMemoryFacts() {
        let messages = [ChatMessage(role: .user, content: "Hi")]
        let memories = ["User's name is Eric", "Eric likes hiking"]

        let result = ChatMLFormatter.format(
            messages: messages,
            identity: BuddyIdentity.defaultBuddy,
            memories: memories
        )

        #expect(result.contains("Things you remember about your human:"))
        #expect(result.contains("- User's name is Eric"))
        #expect(result.contains("- Eric likes hiking"))
    }

    @Test func emptyMessagesProducesSystemAndAssistantOpener() {
        let result = ChatMLFormatter.format(
            messages: [],
            identity: BuddyIdentity.defaultBuddy
        )

        #expect(result.hasPrefix("<|im_start|>system\n"))
        #expect(result.hasSuffix("<|im_start|>assistant\n"))
        // Should only have system block and assistant opener
        let components = result.components(separatedBy: "<|im_start|>")
        // "" (before first), "system\n...", "assistant\n"
        #expect(components.count == 3)
    }

    @Test func skipsSystemRoleMessages() {
        let messages = [
            ChatMessage(role: .system, content: "should be ignored"),
            ChatMessage(role: .user, content: "Hello")
        ]

        let result = ChatMLFormatter.format(
            messages: messages,
            identity: BuddyIdentity.defaultBuddy
        )

        // System content from messages should not appear (only buddy's system prompt)
        #expect(!result.contains("should be ignored"))
        #expect(result.contains("<|im_start|>user\nHello<|im_end|>"))
    }
}
