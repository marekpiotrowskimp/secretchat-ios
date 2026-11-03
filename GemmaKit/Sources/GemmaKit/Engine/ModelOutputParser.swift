import Foundation

/// A chunk of decoded model output, split into the thinking channel, the visible answer and tool calls.
public enum OutputChunk: Sendable, Equatable {
    case thinking(String)
    case answer(String)
    case toolCall(ToolCall)
}

/// Streaming splitter for Gemma 4 output: `<|channel>thought\n…<channel|>answer` and
/// `<|tool_call>call:name{…}<tool_call|>`.
///
/// Fed with whole token pieces (special tokens arrive as a single piece), so markers are matched by
/// equality on special tokens only — ordinary text that happens to spell a marker is never mistaken for one.
public struct ModelOutputParser: Sendable {
    public enum TokenKind: Sendable { case text, control, userDefined }

    private enum State { case answer, channelHeader, thinking, toolCall }
    private var state: State
    private var toolCallBuffer = ""

    /// - Parameter startInThinking: the prompt already opened the thought channel
    ///   (continuation after a tool response with thinking enabled).
    public init(startInThinking: Bool = false) {
        state = startInThinking ? .thinking : .answer
    }

    public mutating func consume(_ piece: String, kind: TokenKind = .text) -> OutputChunk? {
        if state == .toolCall {
            if kind != .text, piece == GemmaPromptBuilder.Token.toolCallEnd {
                state = .answer
                defer { toolCallBuffer = "" }
                return ToolCall.parse(toolCallBuffer).map(OutputChunk.toolCall)
            }
            toolCallBuffer += piece // includes <|"|> string delimiters
            return nil
        }

        if kind != .text {
            switch piece {
            case GemmaPromptBuilder.Token.channelStart:
                state = .channelHeader
                return nil
            case GemmaPromptBuilder.Token.channelEnd:
                state = .answer
                return nil
            case GemmaPromptBuilder.Token.toolCall:
                state = .toolCall
                return nil
            default:
                // Control tokens (e.g. <turn|>) are never shown; user-defined ones are ordinary text.
                if kind == .control { return nil }
            }
        }

        switch state {
        case .answer:
            return piece.isEmpty ? nil : .answer(piece)
        case .thinking:
            return piece.isEmpty ? nil : .thinking(piece)
        case .channelHeader:
            // Channel name (e.g. "thought") runs until the first newline.
            guard let newline = piece.firstIndex(of: "\n") else { return nil }
            state = .thinking
            let rest = String(piece[piece.index(after: newline)...])
            return rest.isEmpty ? nil : .thinking(rest)
        case .toolCall:
            return nil
        }
    }
}

/// Accumulates raw UTF-8 bytes from token pieces and releases only complete characters,
/// since a multi-byte character (e.g. "ż" or an emoji) may be split across tokens.
struct UTF8Accumulator {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: some Sequence<UInt8>) -> String {
        pending.append(contentsOf: bytes)
        let validLength = Self.longestValidPrefix(pending)
        guard validLength > 0 else { return "" }
        let text = String(decoding: pending[..<validLength], as: UTF8.self)
        pending.removeFirst(validLength)
        return text
    }

    /// Flushes whatever is left (invalid bytes become U+FFFD).
    mutating func flush() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }

    /// Length of the prefix that does not end in an incomplete multi-byte sequence.
    static func longestValidPrefix(_ bytes: [UInt8]) -> Int {
        var i = bytes.count
        // Walk back over at most 3 continuation bytes to find the last lead byte.
        var back = 0
        while i > 0, back < 4 {
            let b = bytes[i - 1]
            if b & 0b1100_0000 == 0b1000_0000 { i -= 1; back += 1; continue }
            let needed: Int
            switch b {
            case 0x00...0x7F: needed = 1
            case 0xC0...0xDF: needed = 2
            case 0xE0...0xEF: needed = 3
            case 0xF0...0xF7: needed = 4
            default: needed = 1 // invalid lead byte; let the decoder replace it
            }
            let available = back + 1
            return available >= needed ? bytes.count : i - 1
        }
        return bytes.count
    }
}
