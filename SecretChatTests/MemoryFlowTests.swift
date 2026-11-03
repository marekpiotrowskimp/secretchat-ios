import Foundation
import GemmaKit
import SwiftData
import Testing
@testable import SecretChat

/// Long-term memory end to end with the real model: save in one conversation, use it in another, forget.
@MainActor
@Suite(.serialized, .enabled(if: modelsAvailable, "model files not available"))
struct MemoryFlowTests {
    let app = ChatViewModelTests.app
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        app.settings.memoryEnabled = true
        app.settings.webSearchEnabled = false
        app.settings.speechAutoRead = false
        app.settings.maxTokens = 96
        app.dictation.fakeAudio = true
    }

    private func memories() -> [MemoryItem] { (try? context.fetch(FetchDescriptor<MemoryItem>())) ?? [] }

    private func ask(_ text: String, in conversation: Conversation? = nil) async throws -> (ChatViewModel, StoredMessage) {
        let conversation = conversation ?? {
            let c = Conversation()
            context.insert(c)
            return c
        }()
        let model = ChatViewModel(conversation: conversation, app: app, context: context)
        model.draft = text
        await model.send()?.value
        let answer = try #require(conversation.orderedMessages.last)
        #expect(answer.role == .assistant, "\(model.errorMessage ?? "")")
        return (model, answer)
    }

    @Test func saveInOneConversationUseInAnotherThenForget() async throws {
        // 1. Save (no name given → the model names it).
        let (_, saved) = try await ask("Zapamiętaj, że mój pies ma na imię Burek i jest jamnikiem.")
        print("save answer=\(saved.text.debugDescription) events=\(saved.memoryEvents)")
        let stored = try #require(memories().first, "nothing was saved")
        #expect(memories().count == 1)
        #expect(stored.content.contains("Burek"))
        #expect(!stored.name.isEmpty && !stored.summary.isEmpty)
        #expect(saved.memoryEvents == [MemoryEvent(kind: .saved, name: stored.name)])

        // 2. A new conversation sees the index and reads the memory when relevant.
        let (_, used) = try await ask("Jak ma na imię mój pies?")
        print("read answer=\(used.text.debugDescription) events=\(used.memoryEvents)")
        #expect(used.memoryEvents.contains(MemoryEvent(kind: .read, name: stored.name)))
        #expect(used.text.contains("Burek"))
        #expect(stored.useCount == 1 && stored.lastUsedAt != nil)

        // 3. Unrelated question → memory is not touched.
        let (_, plain) = try await ask("Ile to 2+2? Odpowiedz liczbą.")
        #expect(plain.memoryEvents.isEmpty)

        // 4. Forget.
        let (_, forgot) = try await ask("Zapomnij, jak ma na imię mój pies.")
        print("forget answer=\(forgot.text.debugDescription) events=\(forgot.memoryEvents)")
        #expect(forgot.memoryEvents.contains(MemoryEvent(kind: .deleted, name: stored.name)))
        #expect(memories().isEmpty)
        #expect(forgot.text.lowercased().contains("zapomnia"), "confirmation must say it was forgotten: \(forgot.text)")
    }

    @Test func savingMidConversationKeepsTheKVCache() async throws {
        memories().forEach(context.delete)
        let conversation = Conversation()
        context.insert(conversation)
        _ = try await ask("Zapamiętaj pod nazwą „kawa”: piję kawę z mlekiem owsianym.", in: conversation)
        #expect(memories().count == 1)
        let snapshot = conversation.memoryIndexData
        let (_, next) = try await ask("Dzięki! Ile to 3+4? Odpowiedz liczbą.", in: conversation)
        #expect(conversation.memoryIndexData == snapshot, "index stays fixed within a conversation")
        #expect((next.stats?.reusedTokens ?? 0) > 0, "the next turn must reuse the KV cache, not re-prefill")
        memories().forEach(context.delete)
    }

    @Test func disabledMemoryNeverSaves() async throws {
        memories().forEach(context.delete)
        app.settings.memoryEnabled = false
        defer { app.settings.memoryEnabled = true }
        let (_, answer) = try await ask("Zapamiętaj, że lubię herbatę.")
        #expect(memories().isEmpty)
        #expect(answer.memoryEvents.isEmpty)
    }
}
