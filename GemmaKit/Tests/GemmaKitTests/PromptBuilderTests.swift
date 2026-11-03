import Foundation
import Testing
@testable import GemmaKit

/// Compares `GemmaPromptBuilder` against fixtures rendered from the official Jinja template
/// (scripts/gen_prompt_fixtures.py).
struct PromptBuilderTests {
    static let fixtures: [String: String] = {
        let url = Bundle.module.url(forResource: "gemma4_prompts", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }()

    @Test func userOnly() {
        let out = GemmaPromptBuilder.render([.user("Cześć!")], enableThinking: false)
        #expect(out == Self.fixtures["user_only"])
    }

    @Test func systemAndThinking() {
        let out = GemmaPromptBuilder.render([.system("Jesteś pomocny."), .user("Ile to 2+2?")], enableThinking: true)
        #expect(out == Self.fixtures["system_user_thinking"])
    }

    @Test func multiTurnTrimsUserText() {
        let out = GemmaPromptBuilder.render([
            .system("Odpowiadaj krótko."),
            .user("Hej"),
            .assistant("Cześć! W czym pomóc?"),
            .user("  Opowiedz żart.  "),
        ], enableThinking: false)
        #expect(out == Self.fixtures["multi_turn"])
    }

    @Test func imagePlaceholder() {
        let out = GemmaPromptBuilder.render([.user("Co jest na zdjęciu?", images: [Data()])], enableThinking: false)
        #expect(out == Self.fixtures["image"])
    }

    @Test func thinkingWithoutSystem() {
        let out = GemmaPromptBuilder.render([.user("Pomyśl.")], enableThinking: true)
        #expect(out == Self.fixtures["thinking_only_no_system"])
    }

    @Test func assistantThinkingIsStripped() {
        let out = GemmaPromptBuilder.render([
            .user("A"),
            .assistant("<|channel>thought\nhmm<channel|>Odpowiedź"),
        ], enableThinking: false, addGenerationPrompt: false)
        #expect(out == "<bos><|turn>user\nA<turn|>\n<|turn>model\nOdpowiedź<turn|>\n")
    }

    /// The raw model turn must be rendered verbatim so the previous prompt + output is an exact prefix.
    @Test func rawModelTurnKeepsPromptAPrefix() {
        let history: [ChatMessage] = [.user("Hej")]
        let firstPrompt = GemmaPromptBuilder.render(history, enableThinking: false)
        let rawOutput = "Cześć!"
        let raw = GemmaPromptBuilder.generationPrefix(enableThinking: false) + rawOutput
        let next = GemmaPromptBuilder.render(history + [.assistant("Cześć!", raw: raw), .user("Co słychać?")], enableThinking: false)
        #expect(next.hasPrefix(firstPrompt + rawOutput))
    }

    // MARK: E2B / E4B template

    static let eFixtures: [String: String] = {
        let url = Bundle.module.url(forResource: "gemma4_e_prompts", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }()

    @Test func eTemplateMatchesOfficialRendering() {
        let f = PromptFormat.gemma4_E
        #expect(GemmaPromptBuilder.render([.user("Cześć!")], enableThinking: false, format: f) == Self.eFixtures["user_only"])
        #expect(GemmaPromptBuilder.render([.system("Jesteś pomocny."), .user("Ile to 2+2?")], enableThinking: true, format: f) == Self.eFixtures["system_user_thinking"])
        #expect(GemmaPromptBuilder.render([
            .system("Odpowiadaj krótko."), .user("Hej"), .assistant("Cześć! W czym pomóc?"), .user("  Opowiedz żart.  "),
        ], enableThinking: false, format: f) == Self.eFixtures["multi_turn"])
        #expect(GemmaPromptBuilder.render([.user("Co jest na zdjęciu?", images: [Data()])], enableThinking: false, format: f) == Self.eFixtures["image"])
        #expect(GemmaPromptBuilder.render([.user("Pomyśl.")], enableThinking: true, format: f) == Self.eFixtures["thinking_only_no_system"])
    }

    @Test func formatIsDetectedFromEmbeddedTemplates() throws {
        func template(_ name: String) throws -> String {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "jinja", subdirectory: "Fixtures"))
            return try String(contentsOf: url, encoding: .utf8)
        }
        #expect(PromptFormat.detect(fromTemplate: try template("gemma4_chat_template")) == .gemma4_12B)
        #expect(PromptFormat.detect(fromTemplate: try template("gemma4_e_chat_template")) == .gemma4_E)
        #expect(PromptFormat.detect(fromTemplate: nil) == .gemma4_12B)
    }
}
