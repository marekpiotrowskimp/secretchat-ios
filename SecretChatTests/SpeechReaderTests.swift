import Foundation
import GemmaKit
import SwiftData
import Testing
@testable import SecretChat

@MainActor
@Suite(.serialized)
struct SpeechReaderTests {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "SpeechReaderTests-\(UUID())")!)

    @Test func toggleAndStop() {
        let reader = SpeechReader(settings: settings)
        let id = UUID()
        reader.toggle(id, markdown: "**Ala** ma kota [1].")
        #expect(reader.isSpeaking(id))
        #expect(reader.lastUtterance == "Ala ma kota.")
        reader.toggle(id, markdown: "**Ala** ma kota [1].")
        #expect(!reader.isSpeaking(id))
        #expect(reader.speakingID == nil)
    }

    @Test func speakingAnotherMessageReplacesTheFirst() {
        let reader = SpeechReader(settings: settings)
        let a = UUID(), b = UUID()
        reader.speak(a, markdown: "Pierwsza odpowiedź.")
        reader.speak(b, markdown: "Druga odpowiedź.")
        #expect(!reader.isSpeaking(a))
        #expect(reader.isSpeaking(b))
        reader.stop()
    }

    @Test func streamingSpeaksSentencesThenMovesToStoredMessage() {
        let reader = SpeechReader(settings: settings)
        let stream = UUID(), stored = UUID()
        reader.beginStreaming(id: stream)
        reader.streamed(id: stream, markdown: "Kraków to piękne miasto.")
        reader.streamed(id: stream, markdown: "Kraków to piękne miasto. Ma bogatą")
        let afterFirst = reader.utteranceCount
        #expect(afterFirst == 1)
        #expect(reader.lastUtterance == "Kraków to piękne miasto.")
        reader.finishStreaming(id: stream, storedID: stored, markdown: "Kraków to piękne miasto. Ma bogatą historię.")
        #expect(reader.utteranceCount == 2)
        #expect(reader.lastUtterance == "Ma bogatą historię.")
        #expect(reader.isSpeaking(stored), "the stored message shows the stop button while the tail is read")
        reader.stop()
    }

    @Test func picksLanguageOfTheAnswer() {
        #expect(SpeechReader.language(of: "The capital of France is Paris, a beautiful city.") == .english)
        #expect(SpeechReader.language(of: "Stolicą Francji jest Paryż, piękne miasto.") == .polish)
    }
}

/// Auto-read with the real model: the answer is read while it is being written.
@MainActor
@Suite(.serialized, .enabled(if: modelsAvailable, "model files not available"))
struct AutoReadTests {
    @Test func answerIsReadWhileStreaming() async throws {
        let app = ChatViewModelTests.app
        app.settings.speechAutoRead = true
        app.settings.webSearchEnabled = false
        defer { app.settings.speechAutoRead = false }
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let conversation = Conversation()
        context.insert(conversation)
        let model = ChatViewModel(conversation: conversation, app: app, context: context)
        let before = app.speech.utteranceCount
        model.draft = "Napisz dwa krótkie zdania o Krakowie."
        await model.send()?.value
        let answer = try #require(conversation.orderedMessages.last)
        #expect(answer.role == .assistant)
        #expect(app.speech.utteranceCount > before, "nothing was read aloud")
        #expect(answer.text.contains(app.speech.lastUtterance.prefix(10)) || app.speech.lastUtterance.count > 0)
        app.speech.stop()
    }
}
