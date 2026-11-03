import Foundation
import GemmaKit
import Observation
import SwiftData

/// Drives one conversation: sends messages, streams the answer, persists results.
@Observable
final class ChatViewModel {
    enum Phase: Equatable {
        case idle
        /// Model is being loaded into memory.
        case loadingModel
        /// Prompt is being processed (fraction known only for long prompts).
        case prefill(Double?)
        case thinking
        case answering
        /// The model asked to search the web; waiting for the user's decision.
        case awaitingWebConsent(query: String)
        case searching(query: String, step: WebResearcher.Progress?)
    }

    /// At most this many searches per answer (protects against search loops).
    static let maxSearchesPerAnswer = 2

    let conversation: Conversation
    private let app: AppModel
    private let context: ModelContext

    var draft = ""
    var draftImages: [Data] = []
    private(set) var phase: Phase = .idle
    private(set) var streamingAnswer = ""
    private(set) var streamingThinking = ""
    private(set) var errorMessage: String?
    private(set) var lastTrimmedMessages = 0
    /// Shown when a search failed (the model still answers, from its own knowledge).
    private(set) var webNotice: String?

    private var consent: CheckedContinuation<Bool, Never>?
    /// "Nie pytaj mnie w tej rozmowie": later searches in this open conversation skip the consent card.
    /// Never stored — a new conversation (or reopening this one) asks again.
    private(set) var webApprovedForConversation = false
    /// Identifies the answer being streamed, for reading it aloud as it is written.
    private var streamID = UUID()
    private var stopRequested = false

    init(conversation: Conversation, app: AppModel, context: ModelContext) {
        self.conversation = conversation
        self.app = app
        self.context = context
    }

    var isBusy: Bool { phase != .idle }
    var canSend: Bool {
        !isBusy && !app.isGenerating && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftImages.isEmpty)
    }

    // MARK: Actions

    /// Returns the task answering the message (awaited by tests).
    @discardableResult
    func send() -> Task<Void, Never>? {
        guard canSend else { return nil }
        if isDictating {
            monitorTask?.cancel()
            Task { await app.dictation.cancel() } // the text is already in the draft
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        app.speech.stop()
        conversation.append(role: .user, text: text, images: draftImages)
        draft = ""
        draftImages = []
        try? context.save()
        return Task { await respond() }
    }

    /// Retries after an error: answers the last user message again.
    func retry() {
        guard !isBusy, conversation.orderedMessages.last?.role == .user else { return }
        Task { await respond() }
    }

    func stop() {
        stopRequested = true
        if consent != nil { answerWebConsent(false) }
        app.engine.stopGeneration()
    }

    /// The user's answer to "Czy na pewno przeszukać internet?"; `forConversation` = don't ask again here.
    func answerWebConsent(_ approved: Bool, forConversation: Bool = false) {
        if approved, forConversation { webApprovedForConversation = true }
        consent?.resume(returning: approved)
        consent = nil
    }

    /// Back to asking before every search.
    func revokeWebApproval() { webApprovedForConversation = false }

    func dismissError() { errorMessage = nil }

    // MARK: Dictation & voice mode

    /// Hands-free mode: the microphone listens whenever the chat waits for you, the message is sent
    /// after a pause (or on "wyślij"), and it is switched off while the model answers or reads aloud.
    private(set) var voiceMode = false
    /// Why voice mode stopped by itself (silence, error) — shown under the composer.
    private(set) var voiceNotice: String?
    private var dictationBase = ""
    private var dictationAutoSend = false
    private var monitorTask: Task<Void, Never>?
    static var voiceModeIdleTimeout: TimeInterval = 45

    var isDictating: Bool { app.dictation.isListening }

    /// Mic button: start/stop dictating into the text field (no automatic sending).
    func toggleDictation() {
        Task {
            if isDictating { await stopDictation() } else { await startDictation(autoSend: false) }
        }
    }

    func setVoiceMode(_ on: Bool) {
        guard on != voiceMode else { return }
        voiceMode = on
        if on {
            voiceNotice = nil // keep the reason when turning off (silence, error)
            app.speech.onIdle = { [weak self] in self?.resumeVoiceModeIfReady() }
            resumeVoiceModeIfReady()
        } else {
            app.speech.onIdle = nil
            Task { await stopDictation() }
        }
    }

    /// Listen again when the chat is ready for the next message (not answering, not reading aloud).
    func resumeVoiceModeIfReady() {
        guard voiceMode, !isBusy, !app.isGenerating, app.speech.speakingID == nil, !isDictating else { return }
        Task { await startDictation(autoSend: true) }
    }

    private func startDictation(autoSend: Bool) async {
        guard !isBusy else { return }
        app.speech.stop()
        dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        dictationAutoSend = autoSend
        await app.dictation.start { [weak self] transcript in self?.dictated(transcript) }
        if case .failed(let message) = app.dictation.state {
            voiceNotice = message
            if voiceMode { setVoiceMode(false) }
            app.dictation.clearFailure()
            return
        }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in await self?.monitorDictation() }
    }

    private func stopDictation() async {
        monitorTask?.cancel()
        guard isDictating else { return }
        let final = await app.dictation.finish()
        apply(final, final: true)
    }

    /// Live transcript → text field; trailing voice commands act immediately.
    private func dictated(_ transcript: DictationTranscript) {
        apply(transcript, final: false)
    }

    private func apply(_ transcript: DictationTranscript, final: Bool) {
        let (text, command) = DictationCommand.extract(from: transcript.text)
        draft = [dictationBase, text].filter { !$0.isEmpty }.joined(separator: " ")
        guard let command, !final else { return }
        switch command {
        case .send:
            Task { await sendDictated() }
        case .clear:
            dictationBase = ""
            draft = ""
            Task {
                _ = await app.dictation.finish()
                await startDictation(autoSend: dictationAutoSend)
            }
        case .stopListening:
            if voiceMode { setVoiceMode(false) } else { Task { await stopDictation() } }
        }
    }

    private func sendDictated() async {
        monitorTask?.cancel()
        let final = await app.dictation.finish()
        apply(final, final: true)
        guard canSend else { return }
        send()
    }

    /// Auto-send after a pause (voice mode) and switch voice mode off after long silence.
    private func monitorDictation() async {
        while !Task.isCancelled, isDictating {
            try? await Task.sleep(for: .milliseconds(250))
            let silence = Date.now.timeIntervalSince(app.dictation.lastActivity)
            let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let delay = app.settings.autoSendDelay
            if dictationAutoSend, hasText, delay > 0, silence >= delay, app.dictation.transcript.text.isEmpty == false {
                await sendDictated()
                return
            }
            if voiceMode, !hasText, silence >= Self.voiceModeIdleTimeout {
                voiceNotice = String(localized: "Tryb głosowy wyłączony po dłuższej ciszy.")
                setVoiceMode(false)
                return
            }
        }
    }

    // MARK: Generation

    private func respond() async {
        errorMessage = nil
        webNotice = nil
        lastTrimmedMessages = 0
        streamingAnswer = ""
        streamingThinking = ""
        stopRequested = false
        phase = .loadingModel
        app.isGenerating = true
        defer {
            app.isGenerating = false
            phase = .idle
            // Voice mode: listen again once the answer is done (after reading it aloud, if it is read).
            resumeVoiceModeIfReady()
        }

        let pressureStopsBefore = app.memoryPressureStops
        defer {
            if app.memoryPressureStops > pressureStopsBefore {
                webNotice = String(localized: "Przerwano odpowiedź: telefonowi zaczęło brakować pamięci. Zamknij inne aplikacje albo wybierz mniejszy model.")
            }
        }
        let settings = app.settings
        streamID = UUID()
        if settings.speechAutoRead || (voiceMode && settings.voiceModeReadsAloud) { app.speech.beginStreaming(id: streamID) }
        let web = settings.webSearchEnabled
        let memory = settings.memoryEnabled
        var system = settings.systemPrompt
        var tools: [ToolDeclaration] = []
        if memory {
            system += "\n\n" + MemoryInstructions.text(index: memoryIndexForConversation())
            tools += ToolDeclaration.memoryTools
        }
        if web {
            system += "\n\n" + WebSearchInstructions.text()
            tools.append(.webSearch)
        }
        if let style = settings.styleInstruction { system += "\n\n" + style }
        var request = ChatRequest(
            messages: conversation.chatMessages,
            systemPrompt: system,
            enableThinking: settings.thinkingEnabled,
            sampling: settings.sampling,
            tools: tools
        )
        // "Zapamiętaj…" / "Zapomnij…" always starts with a memory call (see MemoryCommand).
        if memory, let last = conversation.orderedMessages.last, last.role == .user {
            request.forceToolCall = MemoryCommand.isExplicit(last.text)
        }

        if conversation.hasImages, !app.isVisionReady {
            errorMessage = String(localized: "Ta rozmowa zawiera zdjęcia. Pobierz moduł obrazów (przycisk + albo Ustawienia → Model).")
            return
        }
        do {
            try await app.prepareEngine(needsVision: conversation.hasImages)
            var searches = 0
            var toolCalls = 0
            var research: [WebResearch] = []
            var memoryEvents: [MemoryEvent] = []
            while true {
                phase = .prefill(nil)
                let result = try await generate(request)
                guard let result else { break }

                // A tool call (memory, or web search with consent): run it and continue the same turn.
                if result.stats.stopReason == .toolCall, let call = result.toolCall, !stopRequested {
                    toolCalls += 1
                    // The model wrote the call as plain text: it was streamed as answer — don't show it.
                    if let written = result.writtenOutCall, streamingAnswer.hasSuffix(written) {
                        streamingAnswer.removeLast(written.count)
                    }
                    let response: String
                    if toolCalls > Self.maxToolCallsPerAnswer {
                        response = "Osiągnięto limit użycia narzędzi. Odpowiedz teraz na podstawie tego, co już wiesz."
                    } else if call.name.hasPrefix("memory_") {
                        response = handleMemory(call, events: &memoryEvents)
                    } else {
                        response = await handle(call, searches: &searches, research: &research)
                    }
                    if stopRequested {
                        finish(with: result, research: research, memoryEvents: memoryEvents)
                        break
                    }
                    request = request.continuing(after: result, toolName: call.name, toolResponse: response)
                    continue
                }
                finish(with: result, research: research, memoryEvents: memoryEvents)
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            if app.speech.isSpeaking(streamID) { app.speech.stop() }
            await app.syncEngineState()
        }
        streamingAnswer = ""
        streamingThinking = ""
    }

    /// One generation pass; streams into `streamingAnswer` / `streamingThinking`.
    private func generate(_ request: ChatRequest) async throws -> GenerationResult? {
        var final: GenerationResult?
        for try await event in app.engine.chat(request) {
            switch event {
            case .prefillProgress(let p):
                phase = .prefill(p)
            case .chunk(.thinking(let s)):
                phase = .thinking
                streamingThinking += s
            case .chunk(.answer(let s)):
                phase = .answering
                streamingAnswer += s
                app.speech.streamed(id: streamID, markdown: streamingAnswer)
            case .chunk(.toolCall):
                break // handled once generation stops
            case .finished(let result):
                final = result
            }
        }
        return final
    }

    /// Produces the tool response for a call: search results, or why there are none.
    private func handle(_ call: ToolCall, searches: inout Int, research: inout [WebResearch]) async -> String {
        guard call.name == ToolDeclaration.webSearch.name else {
            return "Nieznane narzędzie \(call.name)."
        }
        guard searches < Self.maxSearchesPerAnswer else {
            return "Osiągnięto limit wyszukiwań. Odpowiedz na podstawie zebranych już informacji."
        }
        let query = (call.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Puste zapytanie." }
        searches += 1

        let approved: Bool
        if webApprovedForConversation {
            approved = true
        } else {
            phase = .awaitingWebConsent(query: query)
            approved = await withCheckedContinuation { consent = $0 }
        }
        guard approved else {
            return "Użytkownik nie zgodził się na wyszukiwanie w internecie. Odpowiedz na podstawie własnej wiedzy i zaznacz, że informacje mogą być nieaktualne."
        }

        phase = .searching(query: query, step: nil)
        do {
            let result = try await app.researcher.research(query, budget: WebResearcher.budget(contextLength: app.settings.contextLength)) { step in
                await self.setSearchStep(query, step)
            }
            research.append(result)
            return result.toolResponse
        } catch {
            webNotice = error.localizedDescription
            return "Wyszukiwanie nie powiodło się (\(error.localizedDescription)). Odpowiedz na podstawie własnej wiedzy i zaznacz, że informacje mogą być nieaktualne."
        }
    }

    private func setSearchStep(_ query: String, _ step: WebResearcher.Progress) {
        if case .searching = phase { phase = .searching(query: query, step: step) }
    }

    // MARK: Memory

    /// All tool calls per answer (memory + web), so a model can't loop on tools forever.
    static let maxToolCallsPerAnswer = 6

    /// The index fixed at the conversation's first message (see `Conversation.memoryIndexData`).
    private func memoryIndexForConversation() -> [MemoryEntry] {
        if let data = conversation.memoryIndexData, let index = try? JSONDecoder().decode([MemoryEntry].self, from: data) {
            return index
        }
        let index = allMemories().map(\.entry)
        conversation.memoryIndexData = try? JSONEncoder().encode(index)
        return index
    }

    private func allMemories() -> [MemoryItem] {
        let descriptor = FetchDescriptor<MemoryItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let items = (try? context.fetch(descriptor)) ?? []
        // Most recently used first: the prompt lists at most MemoryInstructions.maxListed.
        return items.sorted { ($0.lastUsedAt ?? $0.updatedAt) > ($1.lastUsedAt ?? $1.updatedAt) }
    }

    /// Runs memory_save / memory_read / memory_delete against the local store. No consent needed:
    /// nothing leaves the phone.
    private func handleMemory(_ call: ToolCall, events: inout [MemoryEvent]) -> String {
        let items = allMemories()
        let requested = (call.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = MemoryLookup.match(requested, in: items.map(\.name)).flatMap { name in items.first { $0.name == name } }

        switch call.name {
        case ToolDeclaration.memorySave.name:
            let content = (call.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return "Brak treści do zapamiętania — zapytaj użytkownika, co zapisać." }
            let name = requested.isEmpty ? String(content.prefix(30)) : requested
            let summary = (call.arguments["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing {
                existing.content = content
                if !summary.isEmpty { existing.summary = summary }
                existing.updatedAt = .now
                events.append(MemoryEvent(kind: .updated, name: existing.name))
                try? context.save()
                return "Zaktualizowano wspomnienie „\(existing.name)”. Potwierdź jednym zdaniem, np.: „Zaktualizowałem w pamięci: \(existing.name).”"
            }
            context.insert(MemoryItem(name: name, summary: summary.isEmpty ? content : summary, content: content))
            try? context.save()
            events.append(MemoryEvent(kind: .saved, name: name))
            return "Zapisano wspomnienie „\(name)”. Potwierdź jednym zdaniem, np.: „Zapamiętałem: \(name).”"

        case ToolDeclaration.memoryRead.name:
            guard let existing else {
                events.append(MemoryEvent(kind: .missing, name: requested))
                let near = MemoryLookup.suggestions(for: requested, in: items.map(\.name))
                return near.isEmpty
                    ? "Nie ma wspomnienia o nazwie „\(requested)”. Odpowiedz bez niego."
                    : "Nie ma wspomnienia „\(requested)”. Podobne: \(near.map { "„\($0)”" }.joined(separator: ", "))."
            }
            existing.lastUsedAt = .now
            existing.useCount += 1
            try? context.save()
            events.append(MemoryEvent(kind: .read, name: existing.name))
            return "Treść wspomnienia „\(existing.name)”: \(existing.content)"

        case ToolDeclaration.memoryDelete.name:
            guard let existing else { return "Nie ma wspomnienia o nazwie „\(requested)” — nie ma czego usuwać." }
            let name = existing.name
            context.delete(existing)
            try? context.save()
            events.append(MemoryEvent(kind: .deleted, name: name))
            return "Usunięto wspomnienie „\(name)” — informacja została zapomniana. Potwierdź jednym zdaniem, np.: „Zapomniałem: \(name).”"

        default:
            return "Nieznane narzędzie \(call.name)."
        }
    }

    private func finish(with result: GenerationResult, research: [WebResearch] = [], memoryEvents: [MemoryEvent] = []) {
        lastTrimmedMessages = result.stats.droppedMessages
        var answer = streamingAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking = streamingThinking.trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty, let event = memoryEvents.last, result.stats.stopReason != .cancelled {
            // The memory change happened even if the model stopped without confirming it.
            answer = event.confirmation
        }
        guard !answer.isEmpty || !thinking.isEmpty else {
            // Stopped before the model produced anything: nothing worth keeping. Otherwise tell the user.
            if result.stats.stopReason != .cancelled {
                errorMessage = String(localized: "Model nie zwrócił odpowiedzi.")
            }
            app.speech.finishStreaming(id: streamID, storedID: nil, markdown: "")
            return
        }

        let message = conversation.append(role: .assistant, text: answer)
        message.thinking = thinking
        message.rawModelTurn = result.rawModelTurn
        message.stats = result.stats
        app.speech.finishStreaming(id: streamID, storedID: message.id, markdown: answer)
        message.memoryEvents = memoryEvents
        if !research.isEmpty {
            message.webQuery = research.map(\.query).joined(separator: " · ")
            message.sources = research.flatMap(\.sources)
        }
        try? context.save()
    }
}
