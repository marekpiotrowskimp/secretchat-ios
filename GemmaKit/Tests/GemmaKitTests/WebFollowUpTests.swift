import Foundation
import Testing
@testable import GemmaKit

extension RealModelTests {
    /// Reported on the phone: after a web search, later questions in the same chat ignored what was found.
    /// The phone's store showed why: with the default 4K context the very next question already dropped
    /// the search turn (`droppedMessages` = 14, prompt ≈ 2.1K tokens). Same settings and system prompt as
    /// the app there (4K, 2048-token answers, memory + web tools, concise style); history is rebuilt the
    /// way the app does it (`rawModelTurn` of every answer).
    @Suite(.serialized)
    struct WebFollowUpTests {
        static let system = "Jesteś pomocnym asystentem. Odpowiadaj w języku, w którym pisze użytkownik.\n\n"
            + MemoryInstructions.text(index: []) + "\n\n"
            + WebSearchInstructions.text(date: Date(timeIntervalSince1970: 1_790_942_400)) + "\n\n"
            + ResponseStyle.concise.instruction()!

        /// A search result as long as the app allows for a 16K context, with one fact to remember.
        static func toolResponse(contextLength: Int) -> String {
            var text = WebSearchInstructions.responseHeader
                + "\n\n[1] Legia – Lech 3:1 — https://sport.example.pl/legia\n"
                + "Legia Warszawa wygrała z Lechem Poznań 3:1 (1 października 2026). Bramki dla Legii: Kowalski 2, Nowak. "
            let filler = [
                "Mecz rozpoczął się od wyrównanej gry w środku pola, a obie drużyny długo szukały sposobu na rozmontowanie defensywy rywala. ",
                "Kibice na Łazienkowskiej stworzyli znakomitą atmosferę, a oprawa przed pierwszym gwizdkiem przypominała o stuleciu stadionu. ",
                "Trener gospodarzy chwalił po meczu organizację gry w obronie i skuteczność w kluczowych momentach spotkania. ",
                "Goście z Poznania mieli więcej rzutów rożnych, ale rzadko zagrażali bramce, a ich napastnicy byli dobrze pilnowani. ",
            ]
            var i = 0
            while text.count < WebResearcher.budget(contextLength: contextLength) {
                if i % 12 == 0 { text += "\n\n[\(i / 12 + 2)] Relacja \(i / 12 + 1) — https://wyniki.example.pl/\(i)\n" }
                text += filler[i % filler.count]
                i += 1
            }
            return text
        }

        private func turn(_ engine: LlamaEngine, _ history: inout [ChatMessage], _ text: String, contextLength: Int) async throws -> (answer: String, stats: GenerationStats) {
            history.append(.user(text))
            var request = ChatRequest(messages: history, systemPrompt: Self.system,
                                      sampling: SamplingParameters(temperature: 1, topK: 64, topP: 0.95, maxTokens: 2048),
                                      tools: ToolDeclaration.memoryTools + [.webSearch])
            var answer = ""
            while true {
                var result: GenerationResult?
                for try await event in engine.chat(request) {
                    if case .chunk(.answer(let s)) = event { answer += s }
                    if case .finished(let r) = event { result = r }
                }
                let r = try #require(result)
                if r.stats.stopReason == .toolCall, let call = r.toolCall {
                    request = request.continuing(after: r, toolName: call.name, toolResponse: Self.toolResponse(contextLength: contextLength))
                    continue
                }
                history.append(.assistant(answer, raw: r.rawModelTurn))
                return (answer, r.stats)
            }
        }

        @Test func searchResultsStayAvailableForFollowUps() async throws {
            let contextLength = 4096
            let variant = ModelCatalog.gemmaE4B
            let engine = LlamaEngine()
            try await engine.load(modelURL: SmallModelTests.modelsDir.appending(path: variant.model.fileName),
                                  configuration: EngineConfiguration(contextLength: contextLength))
            do {
                var history: [ChatMessage] = []
                let first = try await turn(engine, &history, "Kto wygrał wczorajszy mecz Legii Warszawa?", contextLength: contextLength)
                #expect(history.last?.rawModelTurn?.contains("Kowalski") == true, "the search must have happened")
                print("FOLLOWUP 0 dropped=\(first.stats.droppedMessages) prompt=\(first.stats.promptTokens + first.stats.reusedTokens)")
                var compacted = 0
                for (n, question) in ["Z kim grała Legia?", "Jak się nazywa stadion Legii?", "Opisz krótko historię Legii Warszawa."].enumerated() {
                    let r = try await turn(engine, &history, question, contextLength: contextLength)
                    compacted = max(compacted, r.stats.compactedTurns)
                    print("FOLLOWUP \(n + 1) dropped=\(r.stats.droppedMessages) compacted=\(r.stats.compactedTurns) prompt=\(r.stats.promptTokens + r.stats.reusedTokens) answer=\(r.answer.prefix(80).debugDescription)")
                    #expect(r.stats.droppedMessages == 0, "follow-up \(n + 1) dropped the search turn")
                }
                let last = try await turn(engine, &history, "A kto strzelił bramki dla Legii w tym meczu?", contextLength: contextLength)
                print("FOLLOWUP final dropped=\(last.stats.droppedMessages) compacted=\(last.stats.compactedTurns) answer=\(last.answer.prefix(300).debugDescription)")
                #expect(last.answer.contains("Kowalski"), "the answer must use the search result: \(last.answer.prefix(300))")
                #expect(max(compacted, last.stats.compactedTurns) > 0, "4K fills up: the search turn must have been compacted, not dropped")
            } catch {
                await engine.unload()
                throw error
            }
            await engine.unload()
        }
    }
}
