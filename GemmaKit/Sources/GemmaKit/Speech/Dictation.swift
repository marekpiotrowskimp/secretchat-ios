@preconcurrency import AVFoundation
import Foundation
import Speech

/// Spoken commands at the end of a dictation ("…, wyślij").
public enum DictationCommand: Sendable, Equatable {
    case send
    case clear
    case stopListening

    private static let phrases: [(String, DictationCommand)] = [
        // Longest first, so "wyślij wiadomość" wins over "wyślij".
        ("wyślij wiadomość", .send), ("wyślij to", .send), ("wyślij", .send),
        ("send the message", .send), ("send message", .send), ("send it", .send), ("send", .send),
        ("wyczyść wszystko", .clear), ("wyczyść", .clear), ("skasuj wszystko", .clear), ("clear all", .clear), ("clear", .clear),
        ("koniec dyktowania", .stopListening), ("przestań słuchać", .stopListening), ("przestań słuchać mnie", .stopListening),
        ("stop listening", .stopListening), ("stop dictation", .stopListening),
    ]

    /// Splits a transcript into the text to keep and a trailing command, if any. A command only
    /// counts as the last words of the transcript, so "wyślij mi przepis" stays ordinary text.
    public static func extract(from transcript: String) -> (text: String, command: DictationCommand?) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        for (phrase, command) in phrases.sorted(by: { $0.0.count > $1.0.count }) {
            guard normalized.hasSuffix(phrase) else { continue }
            // Whole words only: the phrase must start the transcript or follow a separator.
            let before = normalized.dropLast(phrase.count)
            guard before.isEmpty || before.last.map({ $0.isWhitespace || $0.isPunctuation }) == true else { continue }
            let keep = cutTrailingWords(trimmed, count: phrase.split(separator: " ").count)
            return (keep.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:-–—"))), command)
        }
        return (trimmed, nil)
    }

    /// Removes the last `count` words (and the punctuation around them) from the original text.
    private static func cutTrailingWords(_ text: String, count: Int) -> String {
        var starts: [String.Index] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, _ in
            starts.append(range.lowerBound)
        }
        guard starts.count >= count else { return "" }
        return String(text[..<starts[starts.count - count]])
    }
}

/// Live transcript: confirmed text plus the tentative tail that may still change.
public struct DictationTranscript: Sendable, Equatable {
    public var finalized: String = ""
    public var volatile: String = ""

    public init(finalized: String = "", volatile: String = "") {
        self.finalized = finalized
        self.volatile = volatile
    }

    public var text: String {
        [finalized, volatile].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public enum DictationError: Error, Equatable, LocalizedError {
    case unsupportedLanguage(String)
    case microphoneDenied
    case speechDenied
    case audioUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let id): String(localized: "Dyktowanie w tym języku (\(id)) nie jest dostępne offline na tym urządzeniu.", bundle: .module)
        case .microphoneDenied: String(localized: "Brak dostępu do mikrofonu. Włącz go w Ustawieniach iOS → SecretChat.", bundle: .module)
        case .speechDenied: String(localized: "Brak zgody na rozpoznawanie mowy. Włącz ją w Ustawieniach iOS → SecretChat.", bundle: .module)
        case .audioUnavailable: String(localized: "Mikrofon jest zajęty przez inną aplikację.", bundle: .module)
        }
    }
}

/// On-device speech-to-text for one dictation (Apple's DictationTranscriber via SpeechAnalyzer).
/// Feed microphone buffers with `append`, read `updates`, call `finish` for the final text.
public final class DictationSession: @unchecked Sendable {
    public let locale: Locale
    /// Format the analyzer wants; microphone buffers are converted to it.
    public let audioFormat: AVAudioFormat
    public let updates: AsyncStream<DictationTranscript>

    private let analyzer: SpeechAnalyzer
    private let transcriber: DictationTranscriber
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let updatesContinuation: AsyncStream<DictationTranscript>.Continuation
    private var analyzeTask: Task<Void, Error>?
    private var resultsTask: Task<DictationTranscript, Never>?
    private var converter: AVAudioConverter?

    /// The locale to dictate in (offline), or nil if this device cannot transcribe the language offline.
    public static func supportedLocale(for preferred: Locale) async -> Locale? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: preferred) else { return nil }
        let installed = await DictationTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) } ? locale : nil
    }

    public init(locale: Locale) async throws {
        self.locale = locale
        transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.audioUnavailable
        }
        audioFormat = format
        analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)

        let (inputStream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.input = input
        let (updates, updatesContinuation) = AsyncStream<DictationTranscript>.makeStream()
        self.updates = updates
        self.updatesContinuation = updatesContinuation

        let analyzer = analyzer
        analyzeTask = Task { _ = try await analyzer.analyzeSequence(inputStream) }
        let transcriber = transcriber
        resultsTask = Task {
            var transcript = DictationTranscript()
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        transcript.finalized = [transcript.finalized, text].filter { !$0.isEmpty }.joined(separator: " ")
                        transcript.volatile = ""
                    } else {
                        transcript.volatile = text
                    }
                    updatesContinuation.yield(transcript)
                }
            } catch {}
            updatesContinuation.finish()
            return transcript
        }
    }

    /// Microphone audio (any format; converted to `audioFormat`).
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    /// Ends the audio and returns the final transcript.
    public func finish() async -> DictationTranscript {
        input.finish()
        _ = try? await analyzeTask?.value
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        return await resultsTask?.value ?? DictationTranscript()
    }

    public func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == audioFormat { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: audioFormat)
        }
        guard let converter else { return nil }
        let ratio = audioFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: capacity) else { return nil }
        // The input block runs synchronously inside convert(), on this thread.
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    /// Transcribes an audio file (used by tests and diagnostics).
    public static func transcribe(file url: URL, locale: Locale) async throws -> String {
        let file = try AVAudioFile(forReading: url)
        let session = try await DictationSession(locale: locale)
        let frames = AVAudioFrameCount(4096)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            session.append(buffer)
        }
        return await session.finish().text
    }
}
