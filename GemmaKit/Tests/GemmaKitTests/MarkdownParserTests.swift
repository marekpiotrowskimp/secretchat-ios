import Testing
@testable import GemmaKit

struct MarkdownParserTests {
    @Test func paragraphsSplitOnBlankLines() {
        #expect(MarkdownParser.parse("Ala ma **kota**.\nDruga linia.\n\nNowy akapit.") == [
            .paragraph("Ala ma **kota**.\nDruga linia."),
            .paragraph("Nowy akapit."),
        ])
    }

    @Test func headingsAndRule() {
        #expect(MarkdownParser.parse("# Tytuł\n## Pod\n---\n#bez spacji") == [
            .heading(level: 1, text: "Tytuł"),
            .heading(level: 2, text: "Pod"),
            .rule,
            .paragraph("#bez spacji"),
        ])
    }

    @Test func codeFenceWithLanguage() {
        let md = "Przykład:\n```swift\nlet x = 1\n\nprint(x)\n```\nKoniec"
        #expect(MarkdownParser.parse(md) == [
            .paragraph("Przykład:"),
            .code(language: "swift", code: "let x = 1\n\nprint(x)", isComplete: true),
            .paragraph("Koniec"),
        ])
    }

    @Test func unterminatedFenceWhileStreaming() {
        #expect(MarkdownParser.parse("```python\ndef f():\n    return 1") == [
            .code(language: "python", code: "def f():\n    return 1", isComplete: false),
        ])
    }

    @Test func listsBulletNumberedAndNested() {
        let md = "- jeden\n- dwa\n  - zagnieżdżony\n1. pierwszy\n2) drugi\n-nie lista"
        #expect(MarkdownParser.parse(md) == [
            .listItem(marker: .bullet, text: "jeden", indent: 0),
            .listItem(marker: .bullet, text: "dwa", indent: 0),
            .listItem(marker: .bullet, text: "zagnieżdżony", indent: 1),
            .listItem(marker: .number(1), text: "pierwszy", indent: 0),
            .listItem(marker: .number(2), text: "drugi", indent: 0),
            .paragraph("-nie lista"),
        ])
    }

    @Test func quotes() {
        #expect(MarkdownParser.parse("> cytat\n> dalej\n\ntekst") == [.quote("cytat\ndalej"), .paragraph("tekst")])
    }

    @Test func table() {
        let md = "| Miasto | Ludność |\n|---|:---:|\n| Kraków | 800 tys. |\n| Gdańsk | 470 tys. |\n\nPo tabeli"
        #expect(MarkdownParser.parse(md) == [
            .table(header: ["Miasto", "Ludność"], rows: [["Kraków", "800 tys."], ["Gdańsk", "470 tys."]]),
            .paragraph("Po tabeli"),
        ])
    }

    @Test func pipeWithoutSeparatorIsParagraph() {
        #expect(MarkdownParser.parse("| a | b |") == [.paragraph("| a | b |")])
    }

    @Test func emptyInput() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("\n\n").isEmpty)
    }
}
