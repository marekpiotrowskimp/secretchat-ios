import Testing
@testable import GemmaKit

struct SpeechTextTests {
    @Test func stripsMarkdownAndCitations() {
        let md = "## Wynik\nLegia **wygrała** z *Lechem* 3:1 [1]. Więcej: [strona](https://x.pl) i `kod` [2, 3]."
        #expect(SpeechText.plain(fromMarkdown: md, language: .polish) == "Wynik.\nLegia wygrała z Lechem 3:1. Więcej: strona i kod.")
    }

    @Test func listsAndTablesBecomeSentences() {
        let md = "- jeden\n- dwa\n\n| Miasto | Ludność |\n|---|---|\n| Kraków | 800 tys. |"
        #expect(SpeechText.plain(fromMarkdown: md, language: .polish) == "jeden.\ndwa.\nMiasto: Kraków, Ludność: 800 tys.")
    }

    @Test func formulasAreReadAsWords() {
        let md = "1. **Pole koła:**\n   $P = \\pi r^2$\n   *(gdzie $r$ to promień)*"
        #expect(SpeechText.plain(fromMarkdown: md, language: .polish)
            == "Pole koła:\nP równa się pi r do kwadratu.\n(gdzie r to promień)")
        #expect(SpeechText.plain(fromMarkdown: "$a^2 + b^2 = c^2$", language: .english) == "a squared plus b squared equals c squared.")
        #expect(SpeechText.plain(fromMarkdown: "Cena: 5$ i 10$.", language: .polish) == "Cena: 5$ i 10$.") // money stays
    }

    @Test func codeIsSkipped() {
        let md = "Przykład:\n```swift\nlet x = 1\n```\nKoniec."
        #expect(SpeechText.plain(fromMarkdown: md, language: .polish) == "Przykład:\n(Pominięto blok kodu.)\nKoniec.")
    }
}

struct SpeechStreamerTests {
    @Test func speaksCompleteSentencesAsTheyArrive() {
        var streamer = SpeechStreamer(language: .polish)
        #expect(streamer.feed("Ala ma") == nil)
        #expect(streamer.feed("Ala ma kota. A kot") == "Ala ma kota.")
        #expect(streamer.feed("Ala ma kota. A kot ma Alę! I tyle") == "A kot ma Alę!")
        #expect(streamer.finish("Ala ma kota. A kot ma Alę! I tyle") == "I tyle")
        #expect(streamer.finish("Ala ma kota. A kot ma Alę! I tyle") == nil)
    }

    @Test func waitsForClosedFormulaAndCodeFence() {
        var streamer = SpeechStreamer(language: .polish)
        #expect(streamer.feed("Wzór $x = 1. y") == nil, "inside an open formula")
        #expect(streamer.feed("Wzór $x = 1. y$ działa. ") == "Wzór x równa się 1. y działa.")

        var code = SpeechStreamer(language: .polish)
        #expect(code.feed("```\nlet a = 1. let b = 2.\n") == nil, "inside an open code fence")
        #expect(code.feed("```\nlet a = 1. let b = 2.\n```\nGotowe. ") == "(Pominięto blok kodu.)\nGotowe.")
    }

    @Test func everythingIsSpokenExactlyOnce() {
        let answer = "Pierwsze zdanie. Drugie zdanie!\n- punkt jeden\n- punkt dwa\nOstatnie"
        var streamer = SpeechStreamer(language: .polish)
        var spoken: [String] = []
        for end in answer.indices.dropFirst() {
            if let s = streamer.feed(String(answer[..<end])) { spoken.append(s) }
        }
        if let s = streamer.finish(answer) { spoken.append(s) }
        let joined = spoken.joined(separator: "\n")
        for fragment in ["Pierwsze zdanie.", "Drugie zdanie!", "punkt jeden.", "punkt dwa.", "Ostatnie"] {
            #expect(joined.components(separatedBy: fragment).count == 2, "\(fragment) in \(spoken)")
        }
    }
}
