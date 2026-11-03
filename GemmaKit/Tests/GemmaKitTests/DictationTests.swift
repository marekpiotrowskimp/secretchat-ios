import Foundation
import Speech
import Testing
@testable import GemmaKit

struct DictationCommandTests {
    @Test(arguments: [
        ("Jaka jest pogoda w Krakowie, wyślij", "Jaka jest pogoda w Krakowie", DictationCommand.send),
        ("Jaka jest pogoda w Krakowie? Wyślij.", "Jaka jest pogoda w Krakowie?", .send),
        ("Napisz wiersz o morzu wyślij wiadomość", "Napisz wiersz o morzu", .send),
        ("What is the capital of France, send it", "What is the capital of France", .send),
        ("bez sensu wyczyść", "bez sensu", .clear),
        ("Koniec dyktowania.", "", .stopListening),
        ("Dobra, przestań słuchać", "Dobra", .stopListening),
    ])
    func trailingCommands(_ transcript: String, _ text: String, _ command: DictationCommand) {
        let result = DictationCommand.extract(from: transcript)
        #expect(result.text == text)
        #expect(result.command == command)
    }

    @Test(arguments: [
        "Wyślij mi przepis na pierogi",     // command word not at the end
        "Jak wysłać list do urzędu?",
        "Napisz, co znaczy słowo przesyłka", // contains "sł…", not a command
        "Pomyśl o tym jak o resend",         // "send" inside a word
    ])
    func ordinaryTextIsKept(_ transcript: String) {
        let result = DictationCommand.extract(from: transcript)
        #expect(result.command == nil)
        #expect(result.text == transcript)
    }

    @Test func transcriptJoinsFinalAndVolatile() {
        #expect(DictationTranscript(finalized: "Ala ma", volatile: " kota").text == "Ala ma kota")
        #expect(DictationTranscript(finalized: "", volatile: "").text == "")
    }
}

/// Real on-device recognition of an audio file produced by `say` (English: macOS has no offline Polish model;
/// Polish is verified on the iPhone).
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/say")))
struct DictationRecognitionTests {
    @Test func transcribesSpokenSentence() async throws {
        let locale = try #require(await DictationSession.supportedLocale(for: Locale(identifier: "en_US")), "en_US dictation model not installed")
        let url = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID()).aiff")
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, "What is the capital of France? Send it."]
        try say.run()
        say.waitUntilExit()

        let text = try await DictationSession.transcribe(file: url, locale: locale)
        print("transcribed=\(text.debugDescription)")
        #expect(text.lowercased().contains("capital of france"))
        let parsed = DictationCommand.extract(from: text)
        #expect(parsed.command == .send)
        #expect(parsed.text.lowercased().hasPrefix("what is the capital of france"))
    }
}
