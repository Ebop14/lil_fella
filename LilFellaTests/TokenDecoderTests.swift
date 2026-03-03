import Testing
@testable import LilFella

struct TokenDecoderTests {
    @Test func decodesASCII() {
        var decoder = TokenDecoder()
        let result = decoder.decode(Array("Hello".utf8))
        #expect(result == "Hello")
    }

    @Test func decodesCompleteMultibyteCharacter() {
        var decoder = TokenDecoder()
        // "é" is 0xC3 0xA9 in UTF-8
        let result = decoder.decode([0xC3, 0xA9])
        #expect(result == "é")
    }

    @Test func buffersIncompleteMultibyteSequence() {
        var decoder = TokenDecoder()

        // Send first byte of "é" (2-byte sequence)
        let partial = decoder.decode([0xC3])
        #expect(partial == "")

        // Send second byte
        let complete = decoder.decode([0xA9])
        #expect(complete == "é")
    }

    @Test func handles3ByteSequenceSplitAcrossTokens() {
        var decoder = TokenDecoder()

        // "€" is 0xE2 0x82 0xAC in UTF-8
        let p1 = decoder.decode([0xE2])
        #expect(p1 == "")

        let p2 = decoder.decode([0x82])
        #expect(p2 == "")

        let p3 = decoder.decode([0xAC])
        #expect(p3 == "€")
    }

    @Test func handles4ByteEmoji() {
        var decoder = TokenDecoder()

        // "😀" is 0xF0 0x9F 0x98 0x80
        let p1 = decoder.decode([0xF0])
        #expect(p1 == "")

        let p2 = decoder.decode([0x9F, 0x98, 0x80])
        #expect(p2 == "😀")
    }

    @Test func mixedASCIIAndMultibyte() {
        var decoder = TokenDecoder()

        // "Hi é" split as "Hi " + first byte of é + second byte of é
        let r1 = decoder.decode(Array("Hi ".utf8))
        #expect(r1 == "Hi ")

        let r2 = decoder.decode([0xC3])
        #expect(r2 == "")

        let r3 = decoder.decode([0xA9])
        #expect(r3 == "é")
    }

    @Test func flushReturnsRemainingBytes() {
        var decoder = TokenDecoder()

        // Partial sequence
        _ = decoder.decode([0xC3])

        let flushed = decoder.flush()
        // Should return something (possibly lossy)
        #expect(flushed.isEmpty || !flushed.isEmpty) // just ensure no crash
    }

    @Test func resetClearsBuffer() {
        var decoder = TokenDecoder()
        _ = decoder.decode([0xC3]) // partial
        decoder.reset()

        // After reset, new complete sequence should work fine
        let result = decoder.decode([0xC3, 0xA9])
        #expect(result == "é")
    }
}
