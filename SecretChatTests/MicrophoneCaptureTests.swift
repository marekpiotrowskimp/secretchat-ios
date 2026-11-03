import AVFoundation
import Synchronization
import Testing
@testable import SecretChat

/// Regression for the dictation crash: the tap block runs on AVFAudio's realtime thread. Started from
/// the main actor (like the app does), a main-actor-isolated tap traps on the first buffer.
@MainActor
@Suite(.serialized)
struct MicrophoneCaptureTests {
    @Test func realMicrophoneBuffersArriveOffTheMainThreadWithoutCrashing() async throws {
        let buffers = Mutex(0)
        let offMain = Mutex(0)
        let capture = MicrophoneCapture()
        do {
            try capture.start { buffer, level in
                buffers.withLock { $0 += 1 }
                if !Thread.isMainThread { offMain.withLock { $0 += 1 } }
                _ = level
            }
        } catch {
            // Simulator without an audio input device: nothing to verify here.
            Issue.record("could not start the microphone: \(error)")
            return
        }
        try await Task.sleep(for: .seconds(1.5))
        capture.stop()
        #expect(buffers.withLock { $0 } > 0, "no audio buffers arrived")
        #expect(offMain.withLock { $0 } > 0, "tap runs on the audio thread")
    }

    @Test func rmsOfSilenceAndTone() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        #expect(MicrophoneCapture.rms(buffer) == 0)
        for i in 0..<1600 { buffer.floatChannelData![0][i] = 0.1 * sin(Float(i) * 0.3) }
        #expect(MicrophoneCapture.rms(buffer) > 0.3)
    }
}

/// The exact path that crashed: DictationService.start() with the real microphone and recognizer.
@MainActor
@Suite(.serialized)
struct LiveDictationServiceTests {
    @Test func startingRealDictationDoesNotCrash() async throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "LiveDictation-\(UUID())")!)
        settings.dictationLanguage = .english
        let locale = await DictationSession.supportedLocale(for: Locale(identifier: "en_US"))
        try #require(locale != nil, "no offline dictation model in this simulator")
        let service = DictationService(settings: settings)
        await service.start { _ in }
        if case .failed(let message) = service.state { Issue.record("start failed: \(message)"); return }
        #expect(service.state == .listening)
        try await Task.sleep(for: .seconds(1.5)) // audio buffers flow through the tap
        await service.finish()
        #expect(service.state == .idle)
    }
}

import GemmaKit
import Speech

/// Proof that on-device dictation does not need SFSpeechRecognizer authorization (whose system
/// dialog claims audio is sent to Apple). Run on a simulator where that permission was never granted.
@MainActor
@Suite(.enabled(if: SFSpeechRecognizer.authorizationStatus() != .authorized,
                "speech permission already granted on this simulator — the proof needs one where it never was"))
struct DictationWithoutSpeechAuthTests {
    @Test func dictationTranscriberWorksWithoutSpeechRecognitionPermission() async throws {
        let locale = try #require(await DictationSession.supportedLocale(for: Locale(identifier: "en_US")))
        let url = try #require(Bundle(for: TestBundleMarker.self).url(forResource: "dictation-en", withExtension: "aiff", subdirectory: "Resources"))
        let text = try await DictationSession.transcribe(file: url, locale: locale)
        print("transcribed without speech permission: \(text.debugDescription)")
        #expect(text.lowercased().contains("tallest mountain"))
        #expect(DictationCommand.extract(from: text).command == .send)
    }
}

final class TestBundleMarker {}
