import Foundation
import GemmaKit
import SwiftData

/// Every model type stored by the app — use this for every ModelContainer (app and tests),
/// so no container misses a type the view models fetch.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [Conversation.self, StoredMessage.self, MessageAttachment.self, MemoryItem.self]
}

/// Long-term memory: a named piece of knowledge about the user, kept across conversations.
/// Only `name` + `summary` are shown to the model; it loads `content` with memory_read.
@Model
final class MemoryItem {
    var id: UUID = UUID()
    var name: String = ""
    /// One sentence: what it is about and when it helps (the model decides from this whether to read it).
    var summary: String = ""
    var content: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var lastUsedAt: Date?
    var useCount: Int = 0

    init(name: String, summary: String, content: String) {
        self.name = name
        self.summary = summary
        self.content = content
    }

    var entry: MemoryEntry { MemoryEntry(name: name, description: summary) }
}

/// What the model did with memory while writing an answer (shown under the answer).
struct MemoryEvent: Codable, Hashable {
    enum Kind: String, Codable { case saved, updated, read, deleted, missing }
    var kind: Kind
    var name: String

    var confirmation: String {
        switch kind {
        case .saved: String(localized: "Zapamiętałem: „\(name)”.")
        case .updated: String(localized: "Zaktualizowałem wspomnienie „\(name)”.")
        case .deleted: String(localized: "Zapomniałem: „\(name)”.")
        case .read, .missing: String(localized: "Sprawdziłem pamięć.")
        }
    }
}

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.conversation)
    var messages: [StoredMessage] = []
    /// Memory index taken when the conversation started. Kept fixed so the system prompt — and the
    /// model's KV cache — stay valid for the whole conversation; new memories show up in the next one.
    var memoryIndexData: Data?

    init(title: String = "") {
        self.title = title
    }

    var orderedMessages: [StoredMessage] { messages.sorted { $0.order < $1.order } }
    var displayTitle: String { title.isEmpty ? String(localized: "Nowa rozmowa") : title }
    var hasImages: Bool { messages.contains { !$0.attachments.isEmpty } }

    /// Messages in the form the engine expects.
    var chatMessages: [ChatMessage] { orderedMessages.map(\.chatMessage) }

    @discardableResult
    func append(role: ChatMessage.Role, text: String, images: [Data] = []) -> StoredMessage {
        let message = StoredMessage(role: role, text: text, order: (messages.map(\.order).max() ?? -1) + 1)
        message.attachments = images.enumerated().map { MessageAttachment(data: $1, order: $0) }
        messages.append(message)
        updatedAt = .now
        if title.isEmpty, role == .user {
            title = Self.makeTitle(from: text, hasImages: !images.isEmpty)
        }
        return message
    }

    /// First line of the first user message, shortened.
    static func makeTitle(from text: String, hasImages: Bool) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if line.isEmpty { return hasImages ? String(localized: "Zdjęcie") : "" }
        return line.count > 48 ? String(line.prefix(47)).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

@Model
final class StoredMessage {
    var id: UUID = UUID()
    var order: Int = 0
    var roleRaw: String = ChatMessage.Role.user.rawValue
    var text: String = ""
    var thinking: String = ""
    /// Exact model turn text — keeps the engine's KV cache valid for follow-up turns.
    var rawModelTurn: String?
    var statsData: Data?
    /// Set when the answer used web search (the approved queries) …
    var webQuery: String?
    /// … and the pages it was based on.
    var sourcesData: Data?
    var memoryEventsData: Data?
    var createdAt: Date = Date.now
    var conversation: Conversation?

    @Relationship(deleteRule: .cascade, inverse: \MessageAttachment.message)
    var attachments: [MessageAttachment] = []

    init(role: ChatMessage.Role, text: String, order: Int) {
        self.roleRaw = role.rawValue
        self.text = text
        self.order = order
    }

    var role: ChatMessage.Role { ChatMessage.Role(rawValue: roleRaw) ?? .user }
    var images: [Data] { attachments.sorted { $0.order < $1.order }.map(\.data) }

    var stats: GenerationStats? {
        get { statsData.flatMap { try? JSONDecoder().decode(GenerationStats.self, from: $0) } }
        set { statsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var sources: [WebSource] {
        get { sourcesData.flatMap { try? JSONDecoder().decode([WebSource].self, from: $0) } ?? [] }
        set { sourcesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var usedWeb: Bool { webQuery != nil }

    var memoryEvents: [MemoryEvent] {
        get { memoryEventsData.flatMap { try? JSONDecoder().decode([MemoryEvent].self, from: $0) } ?? [] }
        set { memoryEventsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var chatMessage: ChatMessage {
        ChatMessage(role: role, text: text, images: images, rawModelTurn: rawModelTurn)
    }
}

@Model
final class MessageAttachment {
    var order: Int = 0
    @Attribute(.externalStorage) var data: Data = Data()
    var message: StoredMessage?

    init(data: Data, order: Int) {
        self.data = data
        self.order = order
    }
}
