import Foundation
import Testing
@testable import GemmaKit

struct MemoryPromptTests {
    @Test(arguments: [("gemma4_prompts", PromptFormat.gemma4_12B), ("gemma4_e_prompts", PromptFormat.gemma4_E)])
    func memoryToolsMatchOfficialTemplate(_ fixtureName: String, _ format: PromptFormat) {
        let fixtures = ToolPromptTests.fixtures(fixtureName)
        let prompt = GemmaPromptBuilder.render([.system("Sys."), .user("Zapamiętaj to.")], enableThinking: false, format: format,
                                               tools: ToolDeclaration.memoryTools + [.webSearch])
        #expect(prompt == fixtures["memory_tools"])
    }

    @Test func indexListsNamesAndDescriptionsOnly() {
        let text = MemoryInstructions.text(index: [
            MemoryEntry(name: "pies", description: "Imię i rasa psa użytkownika."),
            MemoryEntry(name: "adres <|turn>", description: "Adres zamieszkania."),
        ])
        #expect(text.contains("- pies: Imię i rasa psa użytkownika."))
        #expect(!text.contains("<|turn>"), "names are sanitized")
        #expect(MemoryInstructions.text(index: []).contains("(pamięć jest pusta)"))
        let many = (0..<100).map { MemoryEntry(name: "m\($0)", description: "d") }
        #expect(MemoryInstructions.text(index: many).components(separatedBy: "\n- ").count == MemoryInstructions.maxListed + 1) // text before the first item + items
    }
}

struct MemoryLookupTests {
    let names = ["Adres domowy", "pies", "Rozmiar butów", "Ulubiona kawa"]

    @Test(arguments: [
        ("adres domowy", "Adres domowy"), ("ADRES-DOMOWY", "Adres domowy"), ("adres domowy.", "Adres domowy"),
        ("rozmiar butow", "Rozmiar butów"), ("Pies", "pies"), ("ulubiona  kawa", "Ulubiona kawa"),
    ])
    func matchesTolerantly(_ query: String, _ expected: String) {
        #expect(MemoryLookup.match(query, in: names) == expected)
    }

    @Test func noFalseMatch() {
        #expect(MemoryLookup.match("kot", in: names) == nil)
        #expect(MemoryLookup.match("", in: names) == nil)
    }

    @Test func recognisesExplicitMemoryCommands() {
        for text in ["Zapamiętaj, że mój pies ma na imię Burek.", "zapamietaj: kod do bramy 1234", "Proszę, zapomnij mój adres.",
                     "Remember that I like tea.", "Please forget my address", "Hej, zapamiętaj to."] {
            #expect(MemoryCommand.isExplicit(text), "\(text)")
        }
        for text in ["Czy pamiętasz, jak ma na imię mój pies?", "Nie zapamiętuj tego.", "Jak zapamiętać daty z historii?",
                     "Zapamiętałem już wszystko.", "Do you remember my dog?"] {
            #expect(!MemoryCommand.isExplicit(text), "\(text)")
        }
    }

    @Test func suggestsRelatedNames() {
        #expect(MemoryLookup.suggestions(for: "mój adres", in: names) == ["Adres domowy"])
        #expect(MemoryLookup.suggestions(for: "buty", in: names).isEmpty || MemoryLookup.suggestions(for: "buty", in: names) == ["Rozmiar butów"])
        #expect(MemoryLookup.suggestions(for: "rozmiar", in: names) == ["Rozmiar butów"])
    }
}

/// The three real models use the memory tools as intended.
extension RealModelTests {
    @Suite(.serialized)
    struct MemoryIntegrationTests {
        static let variants = ToolCallingIntegrationTests.variants
        static let index = [
            MemoryEntry(name: "pies", description: "Imię i rasa psa użytkownika."),
            MemoryEntry(name: "adres domowy", description: "Adres zamieszkania użytkownika — przydatny przy dostawach i pytaniach o dojazd."),
        ]

        /// The app's default system prompt and sampling (T=1): greedy-only tests once hid that the small
        /// models skipped or faked tool calls at the user's temperature.
        private func system(_ index: [MemoryEntry]) -> String {
            "Jesteś pomocnym asystentem. Odpowiadaj w języku, w którym pisze użytkownik.\n\n" + MemoryInstructions.text(index: index)
        }

        private func run(_ engine: LlamaEngine, _ request: ChatRequest) async throws -> (answer: String, result: GenerationResult) {
            var answer = ""
            var result: GenerationResult?
            for try await event in engine.chat(request) {
                if case .chunk(.answer(let s)) = event { answer += s }
                if case .finished(let r) = event { result = r }
            }
            return (answer, try #require(result))
        }

        private func request(_ text: String, index: [MemoryEntry]) -> ChatRequest {
            ChatRequest(messages: [.user(text)], systemPrompt: system(index), sampling: SamplingParameters(temperature: 1, topK: 64, topP: 0.95, maxTokens: 120), tools: ToolDeclaration.memoryTools)
        }

        @Test(arguments: variants)
        func savesReadsAndForgets(_ variant: ModelVariant) async throws {
            let engine = LlamaEngine()
            try await engine.load(modelURL: SmallModelTests.modelsDir.appending(path: variant.model.fileName))
            do { try await check(engine, variant) } catch { await engine.unload(); throw error }
            await engine.unload()
        }

        private func check(_ engine: LlamaEngine, _ variant: ModelVariant) async throws {
            // Save without a name → the model names it and writes a description.
            let auto = try await run(engine, request("Zapamiętaj, że mój pies ma na imię Burek i jest jamnikiem.", index: []))
            let save = try #require(auto.result.toolCall, "\(variant.id): no memory_save")
            print("\(variant.id) save=\(save)")
            #expect(save.name == "memory_save")
            #expect(!(save.arguments["name"] ?? "").isEmpty)
            #expect(!(save.arguments["description"] ?? "").isEmpty)
            #expect(save.arguments["content"]?.contains("Burek") == true)

            // Save with a given name → that name is used.
            let named = try await run(engine, request("Zapamiętaj pod nazwą „rozmiar butów”: noszę rozmiar 44.", index: []))
            #expect(named.result.toolCall?.name == "memory_save")
            #expect(MemoryLookup.match(named.result.toolCall?.arguments["name"] ?? "", in: ["rozmiar butów"]) != nil)

            // Read by description, then answer from the loaded content.
            let req = request("Jak ma na imię mój pies?", index: Self.index)
            let read = try await run(engine, req)
            let call = try #require(read.result.toolCall, "\(variant.id): no memory_read")
            #expect(call.name == "memory_read")
            #expect(MemoryLookup.match(call.arguments["name"] ?? "", in: ["pies"]) == "pies")
            let answer = try await run(engine, req.continuing(after: read.result, toolName: call.name,
                                                               toolResponse: "Treść wspomnienia „pies”: Pies użytkownika ma na imię Pimpek i jest beaglem."))
            print("\(variant.id) answer=\(answer.answer.debugDescription)")
            #expect(answer.answer.contains("Pimpek"), "the answer must come from memory, not a guess")

            // Unrelated question → no memory access.
            let plain = try await run(engine, request("Ile to 2+2? Odpowiedz liczbą.", index: Self.index))
            #expect(plain.result.toolCall == nil)
            #expect(plain.answer.contains("4"))

            // Forget.
            let forget = try await run(engine, request("Zapomnij mój adres domowy.", index: Self.index))
            #expect(forget.result.toolCall?.name == "memory_delete")
            #expect(MemoryLookup.match(forget.result.toolCall?.arguments["name"] ?? "", in: ["adres domowy"]) != nil)
        }
    }
}
