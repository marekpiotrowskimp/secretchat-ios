import AVFoundation
import GemmaKit
import NaturalLanguage
import Observation

/// Reads answers aloud with the on-device speech synthesizer (no network). Either a whole stored
/// message, or a streamed answer sentence by sentence while it is being written.
@MainActor
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    /// The message currently being read (a stored message id, or the id of the answer being streamed).
    private(set) var speakingID: UUID?
    private let synthesizer = AVSpeechSynthesizer()
    private let settings: AppSettings
    private var streamer: SpeechStreamer?
    /// Called when reading ends (finished or stopped) — voice mode resumes listening then.
    var onIdle: (() -> Void)?
    private var pendingUtterances = 0
    /// Utterances handed to the synthesizer (tests check that streaming actually speaks).
    private(set) var utteranceCount = 0
    /// Text of the last utterance (tests / debugging).
    private(set) var lastUtterance = ""

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        synthesizer.delegate = self
    }

    func isSpeaking(_ id: UUID) -> Bool { speakingID == id }

    // MARK: Whole message

    func toggle(_ id: UUID, markdown: String) {
        if speakingID == id { stop() } else { speak(id, markdown: markdown) }
    }

    func speak(_ id: UUID, markdown: String) {
        reset()
        let language = Self.language(of: markdown)
        let text = SpeechText.plain(fromMarkdown: markdown, language: language)
        guard !text.isEmpty else { return }
        speakingID = id
        enqueue(text, language: language)
    }

    func stop() {
        let wasSpeaking = speakingID != nil
        reset()
        deactivateAudioSession()
        if wasSpeaking { onIdle?() }
    }

    /// Stops without signalling idle (used when another reading starts right away).
    private func reset() {
        streamer = nil
        pendingUtterances = 0
        speakingID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    // MARK: Streaming (auto-read)

    /// Starts reading an answer that is still being generated.
    func beginStreaming(id: UUID) {
        reset()
        speakingID = id
        streamer = nil // language is decided from the first sentence
    }

    func streamed(id: UUID, markdown: String) {
        guard speakingID == id else { return }
        if streamer == nil {
            // Wait for enough text to tell Polish from English.
            guard markdown.count > 40 || markdown.contains(where: { ".!?\n".contains($0) }) else { return }
            streamer = SpeechStreamer(language: Self.language(of: markdown))
        }
        if let text = streamer?.feed(markdown), let language = streamer?.language { enqueue(text, language: language) }
    }

    /// The answer is complete (and stored as `storedID`): read the rest and keep the speaking state on it.
    func finishStreaming(id: UUID, storedID: UUID?, markdown: String) {
        guard speakingID == id else { return }
        if streamer == nil { streamer = SpeechStreamer(language: Self.language(of: markdown)) }
        if let text = streamer?.finish(markdown), let language = streamer?.language { enqueue(text, language: language) }
        streamer = nil
        speakingID = storedID ?? id
        if pendingUtterances == 0 { stop() }
    }

    // MARK: Voices

    /// Installed voices for the languages answers come in, best quality first.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("pl") || $0.language.hasPrefix("en") }
            .sorted { ($0.language, -$0.quality.rawValue, $0.name) < ($1.language, -$1.quality.rawValue, $1.name) }
    }

    private func voice(for language: SpeechText.Language) -> AVSpeechSynthesisVoice? {
        if let id = settings.speechVoiceID, let chosen = AVSpeechSynthesisVoice(identifier: id),
           chosen.language.hasPrefix(language.rawValue) {
            return chosen
        }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.rawValue) }
        let preferredRegion = language == .polish ? "pl-PL" : (Locale.current.region?.identifier == "GB" ? "en-GB" : "en-US")
        return candidates.max { a, b in
            (a.quality.rawValue, a.language == preferredRegion ? 1 : 0) < (b.quality.rawValue, b.language == preferredRegion ? 1 : 0)
        } ?? AVSpeechSynthesisVoice(language: preferredRegion)
    }

    static func language(of text: String) -> SpeechText.Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.polish, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english ? .english : .polish
    }

    // MARK: Synthesis

    private func enqueue(_ text: String, language: SpeechText.Language) {
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        // Settings store 0.5…2.0 (×normal); AVSpeech's default rate is 0.5 on a 0…1 scale.
        utterance.rate = Float(min(max(AVSpeechUtteranceDefaultSpeechRate * Float(settings.speechRate),
                                       AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate))
        utterance.postUtteranceDelay = 0.05
        pendingUtterances += 1
        utteranceCount += 1
        lastUtterance = text
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    private func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        // Done when nothing is queued and no more streamed text is expected.
        if pendingUtterances == 0, streamer == nil, speakingID != nil {
            speakingID = nil
            deactivateAudioSession()
            onIdle?()
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback: audible with the silent switch on; duck music instead of stopping it.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
