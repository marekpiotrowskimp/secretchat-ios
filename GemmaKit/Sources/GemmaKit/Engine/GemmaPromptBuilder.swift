import Foundation

/// The small differences between Gemma 4 chat templates.
public struct PromptFormat: Sendable, Hashable {
    /// 12B starts a non-thinking answer with an empty thought channel; E2B/E4B do not.
    public var prefillsEmptyThought: Bool

    public static let gemma4_12B = PromptFormat(prefillsEmptyThought: true)
    public static let gemma4_E = PromptFormat(prefillsEmptyThought: false)

    /// Reads the format from the Jinja chat template stored in the GGUF (`tokenizer.chat_template`).
    public static func detect(fromTemplate template: String?) -> PromptFormat {
        guard let template else { return .gemma4_12B }
        return template.contains(#"{{- '<|channel>thought\n<channel|>' -}}"#) ? .gemma4_12B : .gemma4_E
    }
}

/// Renders conversations in the Gemma 4 chat format.
///
/// Mirrors the official Jinja template shipped in the GGUF (`tokenizer.chat_template`) for the subset
/// we use: system prompt, thinking toggle, user/assistant text turns and image placeholders.
/// Tool calling is intentionally not supported.
public enum GemmaPromptBuilder {
    public enum Token {
        public static let bos = "<bos>"
        public static let turnStart = "<|turn>"
        public static let turnEnd = "<turn|>"
        public static let think = "<|think|>"
        public static let channelStart = "<|channel>"
        public static let channelEnd = "<channel|>"
        public static let image = "<|image|>"
        public static let tool = "<|tool>"
        public static let toolEnd = "<tool|>"
        public static let toolCall = "<|tool_call>"
        public static let toolCallEnd = "<tool_call|>"
        public static let toolResponse = "<|tool_response>"
        public static let toolResponseEnd = "<tool_response|>"
        /// String delimiter inside tool declarations, calls and responses.
        public static let quote = "<|\"|>"
        /// Prefilled after `<|turn>model\n` when thinking is disabled — an empty thought channel.
        public static let emptyThought = "<|channel>thought\n<channel|>"
    }

    /// Text inserted after the final `<|turn>model\n` for a new generation.
    public static func generationPrefix(enableThinking: Bool, format: PromptFormat = .gemma4_12B) -> String {
        enableThinking || !format.prefillsEmptyThought ? "" : Token.emptyThought
    }

    /// - Parameters:
    ///   - tools: functions declared in the system turn (Gemma 4 tool calling).
    ///   - openModelTurn: an unfinished model turn to continue (e.g. after a tool response) —
    ///     rendered after `<|turn>model\n` without closing it, instead of a generation prompt.
    public static func render(
        _ messages: [ChatMessage],
        enableThinking: Bool,
        format: PromptFormat = .gemma4_12B,
        tools: [ToolDeclaration] = [],
        openModelTurn: String? = nil,
        addGenerationPrompt: Bool = true
    ) -> String {
        var out = Token.bos
        var rest = messages[...]

        let system = rest.first?.role == .system ? rest.removeFirst() : nil
        if enableThinking || system != nil || !tools.isEmpty {
            out += "\(Token.turnStart)system\n"
            if enableThinking { out += "\(Token.think)\n" }
            if let system { out += trim(system.text) }
            for tool in tools { out += Token.tool + tool.rendered + Token.toolEnd }
            out += "\(Token.turnEnd)\n"
        }

        for message in rest {
            switch message.role {
            case .system:
                // Only a leading system message is supported by the template; treat others as user text.
                out += "\(Token.turnStart)user\n\(trim(message.text))\(Token.turnEnd)\n"
            case .user:
                out += "\(Token.turnStart)user\n"
                out += String(repeating: Token.image, count: message.imageCount)
                out += trim(message.text)
                out += "\(Token.turnEnd)\n"
            case .assistant:
                out += "\(Token.turnStart)model\n"
                out += message.rawModelTurn ?? stripThinking(message.text)
                out += "\(Token.turnEnd)\n"
            }
        }

        if let openModelTurn {
            out += "\(Token.turnStart)model\n" + openModelTurn
        } else if addGenerationPrompt {
            out += "\(Token.turnStart)model\n" + generationPrefix(enableThinking: enableThinking, format: format)
        }
        return out
    }

    /// Removes `<|channel>…<channel|>` blocks, like the template's `strip_thinking` macro.
    static func stripThinking(_ text: String) -> String {
        var result = ""
        for part in text.components(separatedBy: Token.channelEnd) {
            if let range = part.range(of: Token.channelStart) {
                result += part[..<range.lowerBound]
            } else {
                result += part
            }
        }
        return trim(result)
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
