import Foundation
import GemmaKit
import SwiftData
import Testing
@testable import SecretChat

/// Dictation and hands-free voice mode with the real model; speech input is injected
/// (`DictationService.fakeAudio`) — recognition itself is tested on real audio in GemmaKit / on device.
@MainActor
@Suite(.serialized, .enabled(if: modelsAvailable, "model files not available"))
struct VoiceModeTests {
    let app = ChatViewModelTests.app
    let context: ModelContext

    init() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        app.dictation.fakeAudio = true
        app.settings.webSearchEnabled = false
        app.settings.speechAutoRead = false
        app.settings.voiceModeReadsAloud = false
        app.settings.autoSendDelay = 1.0
        app.settings.maxTokens = 32
    }

    private func makeModel() -> ChatViewModel {
        let conversation = Conversation()
        context.insert(conversation)
        return ChatViewModel(conversation: conversation, app: app, context: context)
    }

    private func wait(_ what: String, timeout: Double = 180, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else { Issue.record("timeout waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func manualDictationFillsFieldAndSendsOnCommand() async throws {
        let model = makeModel()
        model.draft = "Pytanie:"
        model.toggleDictation()
        try await wait("listening") { model.isDictating }
        app.dictation.inject("ile to 2+2")
        #expect(model.draft == "Pytanie: ile to 2+2", "existing text is kept, dictation appended")
        app.dictation.inject("ile to 2+2? Odpowiedz liczbą, wyślij")
        try await wait("answer") { model.conversation.orderedMessages.last?.role == .assistant && !model.isBusy }
        #expect(model.conversation.orderedMessages.first?.text == "Pytanie: ile to 2+2? Odpowiedz liczbą")
        #expect(model.conversation.orderedMessages.last?.text.contains("4") == true)
        #expect(!model.isDictating, "manual dictation does not restart by itself")
    }

    @Test func voiceModeLoopListensSendsPausesAndResumes() async throws {
        let model = makeModel()
        model.setVoiceMode(true)
        try await wait("listening") { model.isDictating }
        let starts = app.dictation.startCount

        app.dictation.inject("Ile to 3+4? Odpowiedz liczbą.")
        // Sent after the pause, mic off while the model answers.
        try await wait("sent") { model.isBusy }
        #expect(!model.isDictating, "the microphone must be off while the model answers")
        try await wait("answer + listening again") { !model.isBusy && model.isDictating }
        #expect(model.conversation.orderedMessages.last?.text.contains("7") == true)
        #expect(app.dictation.startCount == starts + 1, "listening resumed automatically")

        // Spoken command ends voice mode.
        app.dictation.inject("koniec dyktowania")
        try await wait("voice mode off") { !model.voiceMode && !model.isDictating }
        #expect(model.conversation.messages.count == 2, "the command itself is not sent")
    }

    @Test func clearCommandEmptiesTheField() async throws {
        let model = makeModel()
        model.setVoiceMode(true)
        try await wait("listening") { model.isDictating }
        app.dictation.inject("bez sensu, wyczyść")
        try await wait("cleared and listening") { model.draft.isEmpty && model.isDictating }
        #expect(model.conversation.messages.isEmpty)
        model.setVoiceMode(false)
        try await wait("off") { !model.isDictating }
    }

    @Test func voiceModeTurnsOffAfterSilence() async throws {
        ChatViewModel.voiceModeIdleTimeout = 1.5
        defer { ChatViewModel.voiceModeIdleTimeout = 45 }
        let model = makeModel()
        model.setVoiceMode(true)
        try await wait("listening") { model.isDictating }
        try await wait("timed out", timeout: 10) { !model.voiceMode && !model.isDictating }
        #expect(model.voiceNotice != nil)
    }
}
