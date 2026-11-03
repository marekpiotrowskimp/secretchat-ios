import AVFoundation
import GemmaKit
import Observation
import Speech

/// Microphone → on-device speech recognition (one dictation at a time, app-wide).
@MainActor
@Observable
final class DictationService {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript = DictationTranscript()
    /// Input level 0…1 for the listening indicator.
    private(set) var level: Float = 0
    /// Last time speech was heard or the transcript changed — drives auto-send after a pause.
    private(set) var lastActivity = Date.distantPast
    private(set) var startedAt = Date.distantPast

    private let settings: AppSettings
    private var session: DictationSession?
    private var microphone: MicrophoneCapture?
    private var updatesTask: Task<Void, Never>?
    private var onUpdate: ((DictationTranscript) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isListening: Bool { state == .listening || state == .starting }

    /// The locale dictation uses: the setting, or the phone's language.
    var preferredLocale: Locale {
        switch settings.dictationLanguage {
        case .polish: Locale(identifier: "pl_PL")
        case .english: Locale(identifier: "en_US")
        case .automatic: Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? Locale(identifier: "pl_PL")
        }
    }

    #if DEBUG
    /// Tests: no microphone or recognizer — transcripts come from `inject`.
    var fakeAudio = false
    private(set) var startCount = 0

    func inject(_ text: String) {
        guard state == .listening else { return }
        transcript = DictationTranscript(finalized: text)
        lastActivity = .now
        onUpdate?(transcript)
    }
    #endif

    func start(onUpdate: @escaping (DictationTranscript) -> Void) async {
        guard !isListening else { return }
        state = .starting
        transcript = DictationTranscript()
        self.onUpdate = onUpdate
        #if DEBUG
        startCount += 1
        if fakeAudio {
            startedAt = .now
            lastActivity = .now
            state = .listening
            return
        }
        #endif
        do {
            try await requestPermissions()
            guard let locale = await DictationSession.supportedLocale(for: preferredLocale) else {
                throw DictationError.unsupportedLanguage(preferredLocale.identifier)
            }
            let session = try await DictationSession(locale: locale)
            try startAudio(feeding: session)
            self.session = session
            startedAt = .now
            lastActivity = .now
            state = .listening
            playCue(start: true)
            updatesTask = Task { [weak self] in
                for await update in session.updates {
                    guard let self else { return }
                    if update.text != self.transcript.text { self.lastActivity = .now }
                    self.transcript = update
                    self.onUpdate?(update)
                }
            }
        } catch {
            stopAudio()
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops listening and returns the final transcript.
    @discardableResult
    func finish() async -> DictationTranscript {
        #if DEBUG
        if fakeAudio, state == .listening {
            state = .idle
            onUpdate = nil
            return transcript
        }
        #endif
        guard let session else {
            if case .failed = state {} else { state = .idle }
            return transcript
        }
        self.session = nil
        stopAudio()
        let final = await session.finish()
        updatesTask?.cancel()
        transcript = final
        onUpdate = nil
        state = .idle
        playCue(start: false)
        return final
    }

    func cancel() async {
        guard let session else { state = .idle; onUpdate = nil; return }
        self.session = nil
        stopAudio()
        await session.cancel()
        updatesTask?.cancel()
        onUpdate = nil
        transcript = DictationTranscript()
        state = .idle
    }

    func clearFailure() {
        if case .failed = state { state = .idle }
    }

    // MARK: Audio

    private func startAudio(feeding session: DictationSession) throws {
        let microphone = MicrophoneCapture()
        try microphone.start { [weak self] buffer, level in
            session.append(buffer)
            Task { @MainActor in self?.heard(level) }
        }
        self.microphone = microphone
    }

    private func heard(_ level: Float) {
        self.level = level
        if level > 0.08 { lastActivity = .now } // speaking, even before words are recognized
    }

    private func stopAudio() {
        microphone?.stop()
        microphone = nil
        level = 0
    }

    /// Only the microphone. The old SFSpeechRecognizer authorization is *not* requested: its system
    /// dialog says speech "will be sent to Apple", which is not true for the on-device
    /// DictationTranscriber used here (and it is not needed — see DictationWithoutSpeechAuthTests).
    private func requestPermissions() async throws {
        if !(await AVAudioApplication.requestRecordPermission()) { throw DictationError.microphoneDenied }
    }

    /// Short system sounds + haptic so you know when the phone listens (no need to look).
    private func playCue(start: Bool) {
        AudioServicesPlaySystemSound(start ? 1113 : 1114) // begin / end recording tones
        UIImpactFeedbackGenerator(style: start ? .medium : .light).impactOccurred()
    }
}

import AudioToolbox
import UIKit
