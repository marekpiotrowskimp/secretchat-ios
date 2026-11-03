import Foundation
import GemmaKit
import SwiftData
import Synchronization
import Testing
@testable import SecretChat

/// Records every query, so tests can prove that nothing is searched without consent.
final class RecordingResearcher: WebResearching, @unchecked Sendable {
    let queries = Mutex<[String]>([])
    var count: Int { queries.withLock { $0.count } }

    func research(_ query: String, budget: Int, progress: @escaping @Sendable (WebResearcher.Progress) async -> Void) async throws -> WebResearch {
        queries.withLock { $0.append(query) }
        await progress(.searching)
        await progress(.reading(pages: 2))
        let sources = [
            WebSource(index: 1, title: "Legia – Lech 3:1", url: URL(string: "https://sport.example.pl/legia")!),
            WebSource(index: 2, title: "Ekstraklasa", url: URL(string: "https://wyniki.example.pl")!),
        ]
        let text = WebSearchInstructions.responseHeader + "\n\n[1] Legia – Lech 3:1 — https://sport.example.pl/legia\nLegia Warszawa wygrała z Lechem Poznań 3:1 (1 października 2026). Bramki: Kowalski 2, Nowak."
        return WebResearch(query: query, engine: "Test", sources: sources, toolResponse: text)
    }
}

/// End-to-end with the real 12B model; the search itself is faked (no network in tests).
@MainActor
@Suite(.serialized, .enabled(if: modelsAvailable, "model files not available"))
struct WebSearchFlowTests {
    let context: ModelContext
    let researcher = RecordingResearcher()

    init() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        ChatViewModelTests.app.researcherOverride = researcher
        ChatViewModelTests.app.settings.maxTokens = 128
    }

    private func ask(_ text: String, web: Bool, decide: Bool?, forConversation: Bool = false) async throws -> (ChatViewModel, StoredMessage) {
        ChatViewModelTests.app.settings.webSearchEnabled = web
        let conversation = Conversation()
        context.insert(conversation)
        let model = ChatViewModel(conversation: conversation, app: ChatViewModelTests.app, context: context)
        model.draft = text
        let task = model.send()
        if let decide {
            // Wait for the consent card, then answer it like the user would.
            for _ in 0..<3600 { // simulator CPU: prefill of the system prompt with tool declarations takes minutes
                if case .awaitingWebConsent = model.phase { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard case .awaitingWebConsent(let query) = model.phase else {
                Issue.record("model did not ask to search; phase=\(model.phase)")
                model.stop()
                await task?.value
                throw CancellationError()
            }
            #expect(query.lowercased().contains("legi"))
            #expect(researcher.count == 0, "nothing may be searched before the user decides")
            model.answerWebConsent(decide, forConversation: forConversation)
        }
        await task?.value
        let answer = try #require(conversation.orderedMessages.last)
        #expect(answer.role == .assistant)
        return (model, answer)
    }

    /// "Nie pytaj mnie w tej rozmowie": the next search in the same open conversation runs without the card;
    /// a new conversation asks again.
    @Test func dontAskAgainInThisConversation() async throws {
        let (model, first) = try await ask("Kto wygrał wczorajszy mecz Legii Warszawa?", web: true, decide: true, forConversation: true)
        #expect(first.usedWeb && researcher.count == 1)
        #expect(model.webApprovedForConversation)

        model.draft = "Sprawdź jeszcze w internecie, kiedy Legia gra następny mecz."
        var asked = false
        let task = model.send()
        while task != nil, model.isBusy || model.conversation.orderedMessages.last?.role == .user {
            if case .awaitingWebConsent = model.phase { asked = true; model.answerWebConsent(false) }
            try await Task.sleep(for: .milliseconds(100))
        }
        await task?.value
        #expect(!asked, "no consent card in the same conversation")
        #expect(researcher.count == 2, "the second search ran without asking")

        model.revokeWebApproval()
        #expect(!model.webApprovedForConversation)
        let fresh = ChatViewModel(conversation: Conversation(), app: ChatViewModelTests.app, context: context)
        #expect(!fresh.webApprovedForConversation, "a new conversation asks again")
    }

    @Test func webOffNeverAsks() async throws {
        let (_, answer) = try await ask("Kto wygrał wczorajszy mecz Legii Warszawa?", web: false, decide: nil)
        #expect(!answer.usedWeb)
        #expect(researcher.count == 0)
    }

    @Test func approvedSearchAnswersWithSources() async throws {
        let (_, answer) = try await ask("Kto wygrał wczorajszy mecz Legii Warszawa?", web: true, decide: true)
        print("web answer=\(answer.text.debugDescription)")
        #expect(researcher.count == 1)
        #expect(answer.usedWeb)
        #expect(answer.sources.count == 2)
        #expect(answer.text.contains("3:1"))
        #expect(!answer.text.contains("tool_call"))
        #expect(answer.rawModelTurn?.contains("<|tool_response>") == true, "the full turn is kept for the KV cache")
    }

    @Test func declinedSearchSendsNothing() async throws {
        let (_, answer) = try await ask("Kto wygrał wczorajszy mecz Legii Warszawa?", web: true, decide: false)
        print("declined answer=\(answer.text.debugDescription)")
        #expect(researcher.count == 0)
        #expect(!answer.usedWeb)
        #expect(!answer.text.isEmpty)
    }
}
