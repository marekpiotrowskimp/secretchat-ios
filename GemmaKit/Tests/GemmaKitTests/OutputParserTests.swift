import Testing
@testable import GemmaKit

struct OutputParserTests {
    private func run(_ pieces: [(String, ModelOutputParser.TokenKind)]) -> [OutputChunk] {
        var parser = ModelOutputParser()
        return pieces.compactMap { parser.consume($0.0, kind: $0.1) }
    }

    @Test func plainAnswer() {
        #expect(run([("Ala", .text), (" ma", .text), (" kota", .text)]) == [.answer("Ala"), .answer(" ma"), .answer(" kota")])
    }

    @Test func thinkingThenAnswer() {
        let chunks = run([
            ("<|channel>", .userDefined), ("thought", .text), ("\n", .text),
            ("Liczę", .text), ("...", .text),
            ("<channel|>", .userDefined), ("4", .text),
        ])
        #expect(chunks == [.thinking("Liczę"), .thinking("..."), .answer("4")])
    }

    @Test func channelHeaderAndTextInOnePiece() {
        let chunks = run([("<|channel>", .control), ("thought\nNo", .text), ("<channel|>", .control), ("Tak", .text)])
        #expect(chunks == [.thinking("No"), .answer("Tak")])
    }

    @Test func markerSpelledByTextIsNotAMarker() {
        #expect(run([("<|channel>", .text)]) == [.answer("<|channel>")])
    }

    @Test func controlTokensHiddenUserDefinedShown() {
        #expect(run([("<turn|>", .control), ("<b>", .userDefined)]) == [.answer("<b>")])
    }
}

struct UTF8AccumulatorTests {
    @Test func splitMultiByteCharacter() {
        var acc = UTF8Accumulator()
        let bytes = Array("żółw🐢".utf8)
        var out = ""
        for b in bytes { out += acc.append([b]) }
        out += acc.flush()
        #expect(out == "żółw🐢")
    }

    @Test func holdsIncompleteSequence() {
        var acc = UTF8Accumulator()
        let emoji = Array("🐢".utf8) // 4 bytes
        #expect(acc.append(Array("a".utf8) + emoji.prefix(2)) == "a")
        #expect(acc.append(emoji.suffix(2)) == "🐢")
    }

    @Test func flushReplacesInvalidTail() {
        var acc = UTF8Accumulator()
        #expect(acc.append([0xF0, 0x9F]) == "")
        #expect(acc.flush() == "\u{FFFD}")
    }
}
