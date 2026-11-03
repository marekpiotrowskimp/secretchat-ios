import Foundation
import Testing
@testable import GemmaKit

/// Gemma 4 E2B / E4B with the real GGUFs from .models/ (skipped when missing).
extension RealModelTests {
    @Suite(.serialized)
    struct SmallModelTests {
        static let modelsDir = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".models")

        static let available = [ModelCatalog.gemmaE2B, ModelCatalog.gemmaE4B].filter {
            FileManager.default.fileExists(atPath: modelsDir.appending(path: $0.model.fileName).path)
        }

        private func collect(_ stream: AsyncThrowingStream<GenerationEvent, Error>) async throws -> (answer: String, thinking: String, result: GenerationResult) {
            var answer = "", thinking = ""
            var result: GenerationResult?
            for try await event in stream {
                switch event {
                case .chunk(.answer(let s)): answer += s
                case .chunk(.thinking(let s)): thinking += s
                case .finished(let r): result = r
                case .prefillProgress, .chunk(.toolCall): break
                }
            }
            return (answer, thinking, try #require(result))
        }

        @Test(arguments: available)
        func chatsWithCacheVisionAndThinking(_ variant: ModelVariant) async throws {
            let engine = LlamaEngine()
            try await engine.load(modelURL: Self.modelsDir.appending(path: variant.model.fileName))
            #expect(await engine.promptFormat == .gemma4_E, "E models have no empty-thought prefill")

            // Two turns, second one reusing the KV cache.
            var messages: [ChatMessage] = [.user("Jaka jest stolica Polski? Odpowiedz jednym słowem.")]
            let first = try await collect(engine.chat(.init(messages: messages, sampling: .greedy(maxTokens: 32))))
            print("\(variant.id) turn1=\(first.answer.debugDescription) \(first.result.stats)")
            #expect(first.answer.contains("Warszawa"))
            #expect(!first.answer.contains("<"))

            messages += [.assistant(first.answer, raw: first.result.rawModelTurn), .user("A Francji?")]
            let second = try await collect(engine.chat(.init(messages: messages, sampling: .greedy(maxTokens: 32))))
            #expect(second.answer.contains("Paryż"))
            #expect(second.result.stats.reusedTokens == first.result.stats.promptTokens + first.result.stats.generatedTokens)

            // Vision.
            try await engine.loadVision(mmprojURL: Self.modelsDir.appending(path: variant.vision.fileName))
            let red = try #require(TestImages.solid(width: 640, height: 480, red: 230, green: 20, blue: 20))
            let vision = try await collect(engine.chat(.init(
                messages: [.user("Jaki kolor ma ten obrazek? Odpowiedz jednym słowem.", images: [red])],
                sampling: .greedy(maxTokens: 16)
            )))
            print("\(variant.id) vision=\(vision.answer.debugDescription) \(vision.result.stats)")
            #expect(vision.answer.lowercased().contains("czerwon"))

            // Thinking mode.
            let thought = try await collect(engine.chat(.init(
                messages: [.user("Ile to 17*23? Podaj wynik.")], enableThinking: true, sampling: .greedy(maxTokens: 1500)
            )))
            print("\(variant.id) thinking=\(thought.thinking.count) chars answer=\(thought.answer.debugDescription)")
            #expect(!thought.thinking.isEmpty)
            #expect(thought.answer.contains("391"))

            await engine.unload()
        }
    }
}

extension ModelVariant: CustomTestStringConvertible {
    public var testDescription: String { displayName }
}
