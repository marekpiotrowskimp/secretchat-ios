import Foundation
import GemmaKit
import SwiftData
import Testing
import UIKit
@testable import SecretChat

/// End-to-end: ChatViewModel → AppModel → LlamaEngine with the real 12B model
/// (GEMMA_MODEL_DIR is set by the test scheme; run scripts/prepare_test_models.sh first).
nonisolated let modelsAvailable: Bool = {
    guard let dir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] else { return false }
    return FileManager.default.fileExists(atPath: dir + "/" + ModelCatalog.gemma12B.model.fileName)
}()

@MainActor
@Suite(.serialized, .enabled(if: modelsAvailable, "model files not available"))
struct ChatViewModelTests {
    static let app: AppModel = {
        let defaults = UserDefaults(suiteName: "ChatViewModelTests")!
        defaults.removePersistentDomain(forName: "ChatViewModelTests")
        let settings = AppSettings(defaults: defaults)
        settings.temperature = 0 // greedy → deterministic answers
        settings.maxTokens = 64
        settings.systemPrompt = "Odpowiadaj bardzo krótko."
        settings.webSearchEnabled = false
        return AppModel(settings: settings)
    }()

    let context: ModelContext

    init() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func makeModel() -> ChatViewModel {
        let conversation = Conversation()
        context.insert(conversation)
        return ChatViewModel(conversation: conversation, app: Self.app, context: context)
    }

    @Test func answersAndPersistsTwoTurns() async throws {
        let model = makeModel()
        model.draft = "Jaka jest stolica Polski? Jedno słowo."
        await model.send()?.value

        let first = try #require(model.conversation.orderedMessages.last)
        #expect(first.role == .assistant)
        #expect(first.text.contains("Warszawa"), "\(first.text)")
        #expect(first.rawModelTurn?.isEmpty == false)
        #expect(first.stats?.stopReason == .endOfTurn)
        #expect(model.phase == .idle)
        #expect(model.errorMessage == nil)
        #expect(model.conversation.title == "Jaka jest stolica Polski? Jedno słowo.")

        model.draft = "A Czech?"
        await model.send()?.value
        let second = try #require(model.conversation.orderedMessages.last)
        #expect(second.text.contains("Praga"), "\(second.text)")
        #expect((second.stats?.reusedTokens ?? 0) > 0, "follow-up should reuse the KV cache")
        #expect(model.conversation.messages.count == 4)
    }

    @Test func conciseStyleShortensTheAnswer() async throws {
        Self.app.settings.maxTokens = 400
        Self.app.settings.responseStyle = .concise
        defer { Self.app.settings.maxTokens = 64; Self.app.settings.responseStyle = .balanced }
        let model = makeModel()
        model.draft = "Czym jest fotosynteza?"
        await model.send()?.value
        let answer = try #require(model.conversation.orderedMessages.last)
        #expect(answer.role == .assistant)
        // Without a style the model uses all 400 tokens on this question.
        #expect((answer.stats?.generatedTokens ?? 999) < 200, "\(answer.text)")
        #expect(answer.stats?.stopReason == .endOfTurn)
    }

    @Test func stopKeepsPartialAnswer() async throws {
        Self.app.settings.maxTokens = 400
        defer { Self.app.settings.maxTokens = 64 }
        let model = makeModel()
        model.draft = "Napisz długie opowiadanie o smoku."
        let task = model.send()
        // Wait for the first answer tokens, then press Stop.
        for _ in 0..<6000 where model.streamingAnswer.count < 20 { try await Task.sleep(for: .milliseconds(50)) } // simulator CPU prefill is slow
        model.stop()
        await task?.value

        let answer = try #require(model.conversation.orderedMessages.last)
        #expect(answer.role == .assistant)
        #expect(answer.stats?.stopReason == .cancelled)
        #expect(!answer.text.isEmpty)
        #expect(model.canSend == false) // draft is empty
        #expect(!model.isBusy)
    }

    @Test func imageMessageUsesVision() async throws {
        let model = makeModel()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        let image = renderer.jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        model.draftImages = [image]
        model.draft = "Jaki kolor ma ten obrazek? Jedno słowo."
        await model.send()?.value

        let answer = try #require(model.conversation.orderedMessages.last)
        #expect(answer.role == .assistant)
        let colour = answer.text.lowercased()
        #expect(colour.contains("niebiesk") || colour.contains("granat"), "\(answer.text)") // blue / navy
        #expect(await Self.app.engine.isVisionLoaded)
    }

    @Test func thinkingModeStoresReasoningSeparately() async throws {
        Self.app.settings.thinkingEnabled = true
        Self.app.settings.maxTokens = 1500
        defer {
            Self.app.settings.thinkingEnabled = false
            Self.app.settings.maxTokens = 64
        }
        let model = makeModel()
        model.draft = "Ile to 12*13? Podaj sam wynik."
        await model.send()?.value

        let answer = try #require(model.conversation.orderedMessages.last)
        #expect(!answer.thinking.isEmpty)
        #expect(answer.text.contains("156"), "\(answer.text)")
        #expect(!answer.text.contains("<|channel>"))
    }
}
