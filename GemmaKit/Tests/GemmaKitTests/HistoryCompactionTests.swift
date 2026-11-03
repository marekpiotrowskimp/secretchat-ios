import Foundation
import Testing
@testable import GemmaKit

struct HistoryCompactionTests {
    typealias T = GemmaPromptBuilder.Token

    /// A model turn like the app stores it: thinking, a web search, its (long) result, more thinking, the answer.
    static func searchTurn(sourceLength: Int = 3000) -> String {
        let source = "Legia wygrała 3:1. Bramki: Kowalski 2, Nowak. " + String(repeating: "Opis meczu. ", count: sourceLength / 12)
        let value = WebSearchInstructions.responseHeader + "\n\n[1] Legia – Lech — https://a.pl\n" + source
            + "\n\n[2] Relacja — https://b.pl\n" + source
        return "\(T.channelStart)thought\nSzukam wyniku.\(T.channelEnd)"
            + "\(T.toolCall)call:web_search{query:\(T.quote)Legia\(T.quote)}\(T.toolCallEnd)"
            + GemmaPromptBuilder.toolResponse(name: "web_search", value: value)
            + "\(T.channelStart)thought\nMam wynik.\(T.channelEnd)Legia wygrała 3:1 [1]."
    }

    private func cost(_ messages: [ChatMessage]) -> Int {
        GemmaPromptBuilder.render(messages, enableThinking: true).count
    }

    @Test func thinkingIsRemovedButToolsAndAnswerStay() {
        let stripped = HistoryCompaction.stripThinking(Self.searchTurn())
        #expect(!stripped.contains("Szukam wyniku") && !stripped.contains("Mam wynik"))
        #expect(stripped.contains(T.toolCall) && stripped.contains(T.toolResponseEnd))
        #expect(stripped.hasSuffix("Legia wygrała 3:1 [1]."))
    }

    @Test func toolResultsAreCutToExcerptsPerSource() {
        let turn = HistoryCompaction.stripThinking(Self.searchTurn())
        let short = HistoryCompaction.shortenToolResponses(turn)
        #expect(short.count < turn.count / 2)
        #expect(short.contains("[1] Legia – Lech") && short.contains("[2] Relacja"), "every numbered source keeps its title")
        #expect(short.contains("Kowalski 2, Nowak"), "the start of each source — where the facts are — is kept")
        #expect(short.contains(T.toolResponseEnd) && short.hasSuffix("Legia wygrała 3:1 [1]."))
        #expect(HistoryCompaction.shortenToolResponses(short) == short, "shortening twice changes nothing")
    }

    @Test func compactsBeforeDroppingTurns() {
        let messages: [ChatMessage] = [
            .system("System."),
            .user("Kto wygrał mecz?"), .assistant("Legia wygrała 3:1 [1].", raw: Self.searchTurn()),
            .user("A kto strzelił bramki?"),
        ]
        let full = cost(messages)
        // Thinking alone is not enough, shortening the search result is: nothing is dropped.
        let fitted = ContextWindow.fitCompacting(messages, budget: full - 200, cost: cost)
        #expect(fitted.messages.count == messages.count)
        #expect(fitted.compactedTurns == 1)
        #expect(fitted.messages[2].rawModelTurn?.contains("Kowalski") == true)
        #expect(cost(fitted.messages) <= full - 200)

        // Fits already: untouched (keeps the KV cache valid).
        let untouched = ContextWindow.fitCompacting(messages, budget: full, cost: cost)
        #expect(untouched.messages == messages && untouched.compactedTurns == 0)

        // Far too small: falls back to dropping the oldest turns.
        let dropped = ContextWindow.fitCompacting(messages, budget: 200, cost: cost)
        #expect(dropped.messages.count < messages.count && dropped.messages.last == messages.last)
    }
}
