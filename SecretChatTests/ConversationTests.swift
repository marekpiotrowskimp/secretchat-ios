import Foundation
import GemmaKit
import SwiftData
import Testing
@testable import SecretChat

@MainActor
struct ConversationTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    @Test func appendKeepsOrderAndSetsTitle() throws {
        let conversation = Conversation()
        context.insert(conversation)
        conversation.append(role: .user, text: "Jak działa fotosynteza?\nDruga linia")
        conversation.append(role: .assistant, text: "Rośliny…")
        conversation.append(role: .user, text: "A dlaczego liście są zielone?")
        try context.save()

        #expect(conversation.title == "Jak działa fotosynteza?")
        #expect(conversation.orderedMessages.map(\.role) == [.user, .assistant, .user])
        #expect(conversation.orderedMessages.map(\.order) == [0, 1, 2])
    }

    @Test func titleIsShortenedAndImageOnlyGetsDefault() {
        let long = String(repeating: "słowo ", count: 30)
        #expect(Conversation.makeTitle(from: long, hasImages: false).count == 48)
        #expect(Conversation.makeTitle(from: long, hasImages: false).hasSuffix("…"))
        #expect(Conversation.makeTitle(from: "  ", hasImages: true) == String(localized: "Zdjęcie")) // "Photo" on an English simulator
    }

    @Test func chatMessagesCarryImagesAndRawTurn() throws {
        let conversation = Conversation()
        context.insert(conversation)
        let image = Data([0xFF, 0xD8, 0x01])
        conversation.append(role: .user, text: "Co to?", images: [image, image])
        let answer = conversation.append(role: .assistant, text: "Kot.")
        answer.rawModelTurn = "<|channel>thought\n<channel|>Kot."
        try context.save()

        let messages = conversation.chatMessages
        #expect(messages.count == 2)
        #expect(messages[0].images == [image, image])
        #expect(messages[1].rawModelTurn == "<|channel>thought\n<channel|>Kot.")
        #expect(conversation.hasImages)
    }

    @Test func statsRoundTrip() {
        let message = StoredMessage(role: .assistant, text: "x", order: 0)
        let stats = GenerationStats(promptTokens: 10, reusedTokens: 5, generatedTokens: 20, prefillSeconds: 0.5,
                                    decodeSeconds: 2, stopReason: .endOfTurn, peakFootprintBytes: 123)
        message.stats = stats
        #expect(message.stats == stats)
        #expect(message.stats?.decodeTokensPerSecond == 10)
    }

    @Test func deletingConversationCascades() throws {
        let conversation = Conversation()
        context.insert(conversation)
        conversation.append(role: .user, text: "a", images: [Data([1])])
        try context.save()
        context.delete(conversation)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<StoredMessage>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MessageAttachment>()) == 0)
    }
}

@MainActor
struct AppSettingsTests {
    @Test func persistsAndMapsSampling() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppSettingsTests-\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.contextLength == 4096)
        #expect(!settings.thinkingEnabled)

        settings.temperature = 0.3
        settings.topK = 40
        settings.thinkingEnabled = true
        settings.contextLength = 8192

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.temperature == 0.3)
        #expect(reloaded.thinkingEnabled)
        #expect(reloaded.contextLength == 8192)
        #expect(reloaded.sampling.topK == 40)
        #expect(abs(reloaded.sampling.temperature - 0.3) < 0.0001)

        reloaded.resetGeneration()
        #expect(reloaded.sampling.temperature == 1.0 && reloaded.sampling.topK == 64)
    }

    @Test func responseStylePersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppSettingsTests-\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.responseStyle == .balanced)
        #expect(settings.styleInstruction == nil, "balanced adds nothing")

        settings.responseStyle = .concise
        #expect(settings.styleInstruction?.contains("zwięźle") == true)

        settings.responseStyle = .custom
        #expect(settings.styleInstruction == nil, "empty custom style adds nothing")
        settings.customStyle = "Mów jak pirat."
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.responseStyle == .custom)
        #expect(reloaded.styleInstruction?.contains("Mów jak pirat.") == true)
    }
}
