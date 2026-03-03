import Foundation

/// Accumulates raw bytes from token-to-piece conversion and yields
/// complete UTF-8 characters, handling partial multi-byte sequences
/// that may span token boundaries.
struct TokenDecoder: Sendable {
    private var buffer: [UInt8] = []

    /// Feed raw bytes from a single token. Returns any complete UTF-8 string
    /// that can be formed, leaving incomplete trailing bytes in the buffer.
    mutating func decode(_ bytes: [UInt8]) -> String {
        buffer.append(contentsOf: bytes)

        // Find the longest valid UTF-8 prefix
        var validEnd = 0
        var i = 0
        while i < buffer.count {
            let byte = buffer[i]
            let sequenceLength: Int
            if byte & 0x80 == 0 {
                sequenceLength = 1
            } else if byte & 0xE0 == 0xC0 {
                sequenceLength = 2
            } else if byte & 0xF0 == 0xE0 {
                sequenceLength = 3
            } else if byte & 0xF8 == 0xF0 {
                sequenceLength = 4
            } else {
                // Invalid leading byte — skip it
                i += 1
                validEnd = i
                continue
            }

            if i + sequenceLength <= buffer.count {
                // Full sequence available
                validEnd = i + sequenceLength
                i += sequenceLength
            } else {
                // Incomplete sequence — stop here, keep in buffer
                break
            }
        }

        guard validEnd > 0 else { return "" }

        let validBytes = Array(buffer.prefix(validEnd))
        buffer = Array(buffer.suffix(from: validEnd))

        return String(bytes: validBytes, encoding: .utf8) ?? ""
    }

    /// Flush any remaining bytes in the buffer, lossy.
    mutating func flush() -> String {
        guard !buffer.isEmpty else { return "" }
        let result = String(bytes: buffer, encoding: .utf8) ?? String(bytes: buffer, encoding: .ascii) ?? ""
        buffer = []
        return result
    }

    mutating func reset() {
        buffer = []
    }
}
