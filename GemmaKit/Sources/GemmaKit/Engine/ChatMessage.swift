import Foundation

/// A single message in a conversation, in the form the prompt builder needs.
public struct ChatMessage: Sendable, Hashable {
    public enum Role: String, Sendable, Hashable, Codable {
        case system, user, assistant
    }

    public var role: Role
    /// Visible text (for assistant: the answer without thinking).
    public var text: String
    /// Encoded images (JPEG/PNG/HEIC) attached to a user message, rendered before the text.
    public var images: [Data]
    /// Exact text the model saw/produced after `<|turn>model\n` (generation prompt suffix + raw output,
    /// including thinking channel). When present it is rendered verbatim so the KV cache stays an
    /// exact prefix of the next prompt and only the new turn has to be prefilled.
    public var rawModelTurn: String?

    public init(role: Role, text: String, images: [Data] = [], rawModelTurn: String? = nil) {
        self.role = role
        self.text = text
        self.images = images
        self.rawModelTurn = rawModelTurn
    }

    public var imageCount: Int { images.count }

    public static func system(_ text: String) -> ChatMessage { .init(role: .system, text: text) }
    public static func user(_ text: String, images: [Data] = []) -> ChatMessage { .init(role: .user, text: text, images: images) }
    public static func assistant(_ text: String, raw: String? = nil) -> ChatMessage { .init(role: .assistant, text: text, rawModelTurn: raw) }
}
