import Foundation

enum ToolCallParser {
    struct ScanResult: Sendable {
        let displayText: String
        let memoryFacts: [String]
        let hasPartialTag: Bool
    }

    /// Scans text for `<tool>save_memory["fact1", "fact2"]</tool>` tags.
    /// Returns display text with tags stripped, extracted facts, and whether a partial tag is at the end.
    static func scan(_ text: String) -> ScanResult {
        var displayText = text
        var facts: [String] = []

        // Extract complete <tool>save_memory[...]</tool> tags
        let completePattern = #"<tool>save_memory(\[.*?\])</tool>"#
        if let regex = try? NSRegularExpression(pattern: completePattern, options: .dotMatchesLineSeparators) {
            let nsText = displayText as NSString
            let matches = regex.matches(in: displayText, range: NSRange(location: 0, length: nsText.length))

            // Process matches in reverse to preserve indices
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let jsonRange = match.range(at: 1)
                    let jsonString = nsText.substring(with: jsonRange)
                    if let parsed = parseFactsArray(jsonString) {
                        facts.append(contentsOf: parsed)
                    }
                }
                // Remove the entire tag from display text
                let fullRange = match.range(at: 0)
                if let swiftRange = Range(fullRange, in: displayText) {
                    displayText.removeSubrange(swiftRange)
                }
            }
        }

        // Detect incomplete <tool>... at the end (still streaming)
        let hasPartialTag: Bool
        if let partialRange = displayText.range(of: #"<tool>[^<]*$"#, options: .regularExpression) {
            displayText.removeSubrange(partialRange)
            hasPartialTag = true
        } else if displayText.hasSuffix("<") || displayText.hasSuffix("<t")
                    || displayText.hasSuffix("<to") || displayText.hasSuffix("<too") {
            // Very beginning of a tag
            if let idx = displayText.lastIndex(of: "<") {
                let suffix = String(displayText[idx...])
                if "<tool>".hasPrefix(suffix) {
                    displayText.removeSubrange(idx...)
                    hasPartialTag = true
                } else {
                    hasPartialTag = false
                }
            } else {
                hasPartialTag = false
            }
        } else {
            hasPartialTag = false
        }

        return ScanResult(
            displayText: displayText.trimmingCharacters(in: .whitespacesAndNewlines),
            memoryFacts: facts,
            hasPartialTag: hasPartialTag
        )
    }

    private static func parseFactsArray(_ jsonString: String) -> [String]? {
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return array.filter { fact in
            let trimmed = fact.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.count <= 100
        }
    }
}
