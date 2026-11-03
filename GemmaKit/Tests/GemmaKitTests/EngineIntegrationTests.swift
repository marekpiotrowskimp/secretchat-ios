import Foundation
import Testing
@testable import GemmaKit

/// Runs the real Gemma 4 12B model. Skipped when the GGUF is not present
/// (download: see PLAN.md, or set GEMMA_MODEL_PATH).
let testModelURL: URL? = {
    if let path = ProcessInfo.processInfo.environment["GEMMA_MODEL_PATH"] { return URL(filePath: path) }
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".models/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}()

extension RealModelTests {
    @Suite(.serialized, .enabled(if: testModelURL != nil, "Gemma GGUF not found"))
    struct EngineIntegrationTests {

        /// One engine shared by the suite — loading 7 GB per test would dominate the run time.
        static let engine: LlamaEngine = LlamaEngine()

        private func loadedEngine() async throws -> LlamaEngine {
            if await !Self.engine.isLoaded {
                try await Self.engine.load(modelURL: testModelURL!, configuration: .init(contextLength: 4096))
            }
            await Self.engine.resetCache()
            return Self.engine
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

        @Test func specialTokensTokenizeAsSingleTokens() async throws {
            let engine = try await loadedEngine()
            #expect(try await engine.tokenize("<bos>") == [2])
            for marker in ["<|turn>", "<turn|>", "<|channel>", "<channel|>", "<|think|>", "<|image|>"] {
                #expect(try await engine.tokenize(marker).count == 1, "\(marker)")
            }
        }

        @Test func answersSimpleQuestion() async throws {
            let engine = try await loadedEngine()
            let prompt = GemmaPromptBuilder.render([.user("Ile to 2+2? Odpowiedz tylko liczbą.")], enableThinking: false)
            let (answer, thinking, result) = try await collect(engine.generate(prompt: prompt, sampling: .greedy(maxTokens: 16)))
            print("answer=\(answer.debugDescription) stats=\(result.stats)")
            #expect(answer.contains("4"))
            #expect(thinking.isEmpty)
            #expect(result.stats.stopReason == .endOfTurn)
            #expect(!answer.contains("<"), "special markers must not leak into the answer")
        }

        @Test func secondTurnReusesKVCache() async throws {
            let engine = try await loadedEngine()
            var history: [ChatMessage] = [.system("Odpowiadaj jednym krótkim zdaniem."), .user("Jak ma na imię stolica Polski?")]
            let first = try await collect(engine.generate(prompt: GemmaPromptBuilder.render(history, enableThinking: false), sampling: .greedy(maxTokens: 64)))
            #expect(first.answer.contains("Warszawa"))

            let raw = GemmaPromptBuilder.generationPrefix(enableThinking: false) + first.result.rawOutput
            history += [.assistant(first.answer, raw: raw), .user("A Niemiec?")]
            let second = try await collect(engine.generate(prompt: GemmaPromptBuilder.render(history, enableThinking: false), sampling: .greedy(maxTokens: 64)))
            print("turn2 answer=\(second.answer.debugDescription) stats=\(second.result.stats)")

            #expect(second.answer.contains("Berlin"))
            let firstTotal = first.result.stats.promptTokens + first.result.stats.generatedTokens
            #expect(second.result.stats.reusedTokens == firstTotal, "whole first exchange should stay in KV cache")
            #expect(second.result.stats.promptTokens < 20, "only the new user turn should be prefilled")
        }

        @Test func thinkingModeProducesThinkingChunks() async throws {
            let engine = try await loadedEngine()
            let prompt = GemmaPromptBuilder.render([.user("Ile to 17*23? Podaj wynik.")], enableThinking: true)
            let (answer, thinking, result) = try await collect(engine.generate(prompt: prompt, sampling: .greedy(maxTokens: 1500)))
            print("thinking=\(thinking.prefix(200).debugDescription)… answer=\(answer.debugDescription) stats=\(result.stats)")
            #expect(!thinking.isEmpty)
            #expect(answer.contains("391"))
            #expect(result.rawOutput.hasPrefix("<|channel>thought"))
        }

        @Test func cancellationStopsGeneration() async throws {
            let engine = try await loadedEngine()
            let prompt = GemmaPromptBuilder.render([.user("Napisz długie opowiadanie o smoku.")], enableThinking: false)
            let task = Task { () -> Int in
                var chunks = 0
                for try await event in engine.generate(prompt: prompt, sampling: .init(maxTokens: 2000)) {
                    if case .chunk = event { chunks += 1 }
                    if chunks == 10 { break } // consumer stops listening → onTermination cancels
                }
                return chunks
            }
            #expect(try await task.value == 10)
            // Engine must be usable right after and the cache prefix still consistent.
            let follow = GemmaPromptBuilder.render([.user("Ile to 2+2? Odpowiedz tylko liczbą.")], enableThinking: false)
            let (answer, _, _) = try await collect(engine.generate(prompt: follow, sampling: .greedy(maxTokens: 8)))
            #expect(answer.contains("4"))
        }

        @Test func stopGenerationFinishesWithPartialOutput() async throws {
            let engine = try await loadedEngine()
            let prompt = GemmaPromptBuilder.render([.user("Napisz długie opowiadanie o smoku.")], enableThinking: false)
            var chunks = 0
            var result: GenerationResult?
            for try await event in engine.generate(prompt: prompt, sampling: .init(maxTokens: 2000)) {
                switch event {
                case .chunk: chunks += 1; if chunks == 5 { engine.stopGeneration() }
                case .finished(let r): result = r
                case .prefillProgress: break
                }
            }
            let r = try #require(result)
            #expect(r.stats.stopReason == .cancelled)
            #expect(r.stats.generatedTokens < 20)
            #expect(!r.rawOutput.isEmpty)
        }

        @Test func stopDuringPrefillFinishesCleanly() async throws {
            let engine = try await loadedEngine()
            let long = String(repeating: "Zdanie wypełniające kontekst do testu przerwania. ", count: 250) // ~2.5K tokens, 5 batches
            let prompt = GemmaPromptBuilder.render([.user(long)], enableThinking: false)
            var result: GenerationResult?
            for try await event in engine.generate(prompt: prompt, sampling: .greedy(maxTokens: 8)) {
                switch event {
                case .prefillProgress: engine.stopGeneration()
                case .finished(let r): result = r
                case .chunk: Issue.record("no tokens expected after stop during prefill")
                }
            }
            #expect(result?.stats.stopReason == .cancelled)
            #expect(await engine.cachedTokenCount == 0)
            // Engine is usable afterwards.
            let ok = GemmaPromptBuilder.render([.user("Ile to 2+2? Odpowiedz tylko liczbą.")], enableThinking: false)
            let (answer, _, _) = try await collect(engine.generate(prompt: ok, sampling: .greedy(maxTokens: 8)))
            #expect(answer.contains("4"))
        }

        @Test func contextOverflowThrows() async throws {
            let engine = try await loadedEngine()
            let huge = String(repeating: "słowo ", count: 6000)
            let prompt = GemmaPromptBuilder.render([.user(huge)], enableThinking: false)
            await #expect(throws: EngineError.self) {
                for try await _ in engine.generate(prompt: prompt, sampling: .greedy(maxTokens: 4)) {}
            }
        }

        @Test func chatAPIKeepsCacheAcrossTurns() async throws {
            let engine = try await loadedEngine()
            var messages: [ChatMessage] = [.user("Podaj stolicę Francji jednym słowem.")]
            let system = "Odpowiadaj bardzo krótko."
            let first = try await collect(engine.chat(.init(messages: messages, systemPrompt: system, sampling: .greedy(maxTokens: 32))))
            #expect(first.answer.contains("Paryż"))
            #expect(first.result.rawModelTurn.hasPrefix(GemmaPromptBuilder.Token.emptyThought))

            messages += [.assistant(first.answer, raw: first.result.rawModelTurn), .user("A Hiszpanii?")]
            let second = try await collect(engine.chat(.init(messages: messages, systemPrompt: system, sampling: .greedy(maxTokens: 32))))
            #expect(second.answer.contains("Madryt"))
            #expect(second.result.stats.promptTokens < 20)
            #expect(second.result.stats.droppedMessages == 0)
        }

        @Test func chatTrimsHistoryThatDoesNotFit() async throws {
            let engine = try await loadedEngine()
            let filler = String(repeating: "To jest długi akapit wypełniający historię rozmowy. ", count: 20) // ~200 tokens
            var messages: [ChatMessage] = []
            for i in 0..<30 {
                messages.append(.user("Wiadomość \(i). \(filler)"))
                messages.append(.assistant("Rozumiem \(i)."))
            }
            messages.append(.user("Ile to 3+4? Odpowiedz tylko liczbą."))
            var progress: [Double] = []
            for try await case .prefillProgress(let p) in engine.chat(.init(messages: messages, sampling: .greedy(maxTokens: 1))) { progress.append(p) }
            #expect(progress.count >= 2 && progress == progress.sorted() && progress.last == 1.0, "\(progress)")
            await engine.resetCache()
            let out = try await collect(engine.chat(.init(messages: messages, sampling: .greedy(maxTokens: 8))))
            print("trim stats=\(out.result.stats)")
            #expect(out.answer.contains("7"))
            #expect(out.result.stats.droppedMessages > 0)
            #expect(out.result.stats.promptTokens < 4096)
        }

        @Test func visionRecognisesColour() async throws {
            let engine = try await loadedEngine()
            try await engine.loadVision(mmprojURL: testModelURL!.deletingLastPathComponent().appending(path: "mmproj-F16.gguf"))
            let red = try #require(TestImages.solid(width: 640, height: 480, red: 230, green: 20, blue: 20))
            let request = ChatRequest(messages: [.user("Jaki kolor ma ten obrazek? Odpowiedz jednym słowem.", images: [red])], sampling: .greedy(maxTokens: 16))
            let first = try await collect(engine.chat(request))
            print("vision answer=\(first.answer.debugDescription) stats=\(first.result.stats)")
            #expect(first.answer.lowercased().contains("czerwon"))
            #expect(first.result.stats.promptTokens > 100, "image should contribute vision tokens")

            // Follow-up text turn reuses the cache, including the image tokens.
            let follow = request.messages + [.assistant(first.answer, raw: first.result.rawModelTurn), .user("Przetłumacz ten kolor na angielski, jednym słowem.")]
            let second = try await collect(engine.chat(.init(messages: follow, sampling: .greedy(maxTokens: 16))))
            #expect(second.answer.lowercased().contains("red"))
            #expect(second.result.stats.reusedTokens == first.result.stats.promptTokens + first.result.stats.generatedTokens)

            await engine.unloadVision()
            #expect(await !engine.isVisionLoaded)
        }

        @Test func imageWithoutVisionThrows() async throws {
            let engine = try await loadedEngine()
            let img = try #require(TestImages.solid(width: 64, height: 64, red: 0, green: 0, blue: 255))
            await #expect(throws: EngineError.visionNotLoaded) {
                for try await _ in engine.chat(.init(messages: [.user("Co to?", images: [img])])) {}
            }
        }

        /// Keep last: the suite runs serialized in declaration order. Freeing the model before process exit
        /// also avoids ggml-metal's "rsets->data count == 0" assert in its static destructor.
        @Test func unloadReleasesModel() async throws {
            _ = try await loadedEngine()
            await Self.engine.unload()
            #expect(await !Self.engine.isLoaded)
            #expect(await Self.engine.cachedTokenCount == 0)
        }
    }
}
