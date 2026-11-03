import Foundation

/// Before dropping whole turns, `ContextWindow.fitCompacting` first shrinks what the model no longer
/// needs verbatim. Dropping alone threw away web-search turns first (they are the biggest and usually
/// the oldest), so follow-up questions no longer saw what had been found.
public extension ContextWindow {
    /// Characters kept from each source of an older search result (the model's answer stays in full).
    static let keptCharactersPerSource = 700

    struct Fitted: Sendable {
        public var messages: [ChatMessage]
        /// Earlier answers whose thinking was removed or whose tool results were shortened.
        public var compactedTurns: Int
    }

    /// Fits `messages` into `budget` in steps, each only when the previous one was not enough:
    /// 1. thinking removed from earlier answers (the official Gemma template never keeps it),
    /// 2. tool results in earlier answers shortened to excerpts (numbered sources kept),
    /// 3. oldest turns dropped (`fit`).
    /// Steps 1–2 aim at `targetRatio` of the budget, so the next turns don't compact again at once; when
    /// they can't reach it but the conversation fits, nothing is dropped — losing turns is worse.
    static func fitCompacting(
        _ messages: [ChatMessage],
        budget: Int,
        targetRatio: Double = 0.7,
        cost: ([ChatMessage]) throws -> Int
    ) rethrows -> Fitted {
        guard try cost(messages) > budget else { return Fitted(messages: messages, compactedTurns: 0) }
        let target = Int(Double(budget) * targetRatio)

        var current = messages
        var compacted = Set<Int>()
        for step in [HistoryCompaction.stripThinking, HistoryCompaction.shortenToolResponses] {
            for index in current.indices where current[index].role == .assistant {
                guard let raw = current[index].rawModelTurn else { continue }
                let shorter = step(raw)
                if shorter != raw {
                    current[index].rawModelTurn = shorter
                    compacted.insert(index)
                }
            }
            if try cost(current) <= target { return Fitted(messages: current, compactedTurns: compacted.count) }
        }
        if try cost(current) <= budget { return Fitted(messages: current, compactedTurns: compacted.count) }
        let fitted = try fit(current, budget: budget, targetRatio: targetRatio, cost: cost)
        // `fit` drops turns right after the (kept) system message.
        let firstKept = (current.first?.role == .system ? 1 : 0) + (current.count - fitted.count)
        return Fitted(messages: fitted, compactedTurns: compacted.filter { $0 >= firstKept }.count)
    }
}

enum HistoryCompaction {
    typealias Token = GemmaPromptBuilder.Token

    /// Removes `<|channel>thought…<channel|>` blocks; tool calls, tool results and the answer stay.
    static func stripThinking(_ raw: String) -> String {
        var out = ""
        var rest = Substring(raw)
        while let start = rest.range(of: Token.channelStart) {
            out += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: Token.channelEnd) else { return out }
            rest = rest[end.upperBound...]
        }
        return out + rest
    }

    /// Shortens every `<|tool_response>…<tool_response|>` value: the header and the first
    /// `keptCharactersPerSource` characters of each numbered source (`[1] Title — url`) are kept.
    static func shortenToolResponses(_ raw: String) -> String {
        let open = Token.quote, close = Token.quote + "}" + Token.toolResponseEnd
        var out = ""
        var rest = Substring(raw)
        while let block = rest.range(of: Token.toolResponse),
              let valueStart = rest[block.upperBound...].range(of: open),
              let valueEnd = rest[valueStart.upperBound...].range(of: close) {
            out += rest[..<valueStart.upperBound]
            out += shortened(String(rest[valueStart.upperBound..<valueEnd.lowerBound]))
            out += rest[valueEnd.lowerBound..<valueEnd.upperBound]
            rest = rest[valueEnd.upperBound...]
        }
        return out + rest
    }

    private static let marker = "[…skrócono]"

    private static func shortened(_ value: String) -> String {
        guard !value.contains(marker) else { return value } // already shortened
        let parts = value.components(separatedBy: "\n\n[")
        let limit = ContextWindow.keptCharactersPerSource
        guard parts.dropFirst().contains(where: { $0.count > limit }) else { return value }
        let sources = parts.dropFirst().map { part in
            part.count > limit ? String(part.prefix(limit)) + " " + marker : part
        }
        return ([parts[0]] + sources).joined(separator: "\n\n[")
    }
}
