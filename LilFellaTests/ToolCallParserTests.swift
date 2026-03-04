import Testing
@testable import LilFella

@Suite("ToolCallParser")
struct ToolCallParserTests {

    @Test("Parses complete tag and strips from display")
    func completeTag() {
        let text = #"Sure thing!<tool>save_memory["User likes cats"]</tool>"#
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "Sure thing!")
        #expect(result.memoryFacts == ["User likes cats"])
        #expect(!result.hasPartialTag)
    }

    @Test("Handles multiple facts in one tag")
    func multipleFacts() {
        let text = #"Got it.<tool>save_memory["Name is Eric", "Likes hiking"]</tool>"#
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "Got it.")
        #expect(result.memoryFacts.count == 2)
        #expect(result.memoryFacts[0] == "Name is Eric")
        #expect(result.memoryFacts[1] == "Likes hiking")
    }

    @Test("Detects partial tag at end of stream")
    func partialTag() {
        let text = "Hmm interesting<tool>save_mem"
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "Hmm interesting")
        #expect(result.memoryFacts.isEmpty)
        #expect(result.hasPartialTag)
    }

    @Test("No tag present returns text unchanged")
    func noTag() {
        let text = "Just a normal message"
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "Just a normal message")
        #expect(result.memoryFacts.isEmpty)
        #expect(!result.hasPartialTag)
    }

    @Test("Invalid JSON in tag returns no facts")
    func invalidJSON() {
        let text = "<tool>save_memory[not valid json]</tool>Hello"
        let result = ToolCallParser.scan(text)
        #expect(result.memoryFacts.isEmpty)
        #expect(result.displayText == "Hello")
    }

    @Test("Mixed text and tool call")
    func mixedContent() {
        let text = #"I'll remember that! <tool>save_memory["Favorite color is blue"]</tool> Anything else?"#
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "I'll remember that!  Anything else?")
        #expect(result.memoryFacts == ["Favorite color is blue"])
    }

    @Test("Filters empty and oversized facts")
    func filtersEmptyAndLong() {
        let longFact = String(repeating: "a", count: 101)
        let text = "<tool>save_memory[\"\", \"\(longFact)\", \"valid fact\"]</tool>"
        let result = ToolCallParser.scan(text)
        #expect(result.memoryFacts == ["valid fact"])
    }

    @Test("Partial tag with just opening bracket")
    func partialOpeningBracket() {
        let text = "Hello<tool>"
        let result = ToolCallParser.scan(text)
        #expect(result.displayText == "Hello")
        #expect(result.hasPartialTag)
    }
}
