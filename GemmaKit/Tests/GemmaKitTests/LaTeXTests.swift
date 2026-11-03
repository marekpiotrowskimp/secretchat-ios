import Testing
@testable import GemmaKit

struct LaTeXTests {
    @Test(arguments: [
        (#"P = \pi r^2"#, "P = πr²"),
        (#"x = \frac{-b \pm \sqrt{\Delta}}{2a}"#, "x = (-b ± √Δ)/(2a)"),
        (#"\Delta = b^2 - 4ac"#, "Δ = b² - 4ac"),
        (#"a^2 + b^2 = c^2"#, "a² + b² = c²"),
        (#"17 \times 23 = 391"#, "17 × 23 = 391"),
        (#"E = mc^{2}"#, "E = mc²"),
        (#"x_1, x_2"#, "x₁, x₂"),
        (#"\sqrt[3]{8} = 2"#, "³√8 = 2"),
        (#"\frac{1}{2}"#, "1/2"),
        (#"\frac{a+b}{c}"#, "(a+b)/c"),
        (#"e^{i\pi} + 1 = 0"#, "e^(iπ) + 1 = 0"),
        (#"\sum_{i=1}^{n} i"#, "Σᵢ₌₁ⁿ i"),
        (#"\text{pole} = a \cdot b"#, "pole = a · b"),
        (#"\left( x + 1 \right)^2 \geq 0"#, "( x + 1 )² ≥ 0"),
        (#"v = 10\,\text{m/s}"#, "v = 10 m/s"),
        (#"50\%"#, "50%"),
    ])
    func unicode(_ latex: String, _ expected: String) {
        #expect(LaTeX.toUnicode(latex) == expected)
    }

    @Test func inlineMathInSentence() {
        #expect(LaTeX.replacingInlineMath(in: "gdzie $r$ to promień, a $\\Delta = b^2 - 4ac$.") == "gdzie r to promień, a Δ = b² - 4ac.")
        #expect(LaTeX.replacingInlineMath(in: "**Pierwiastki ($ax^2 + bx + c = 0$):**") == "**Pierwiastki (ax² + bx + c = 0):**")
        #expect(LaTeX.replacingInlineMath(in: "wzór \\(a^2\\) działa") == "wzór a² działa")
    }

    @Test func dollarAmountsAreNotMath() {
        for text in ["To kosztuje 5$ a tamto 10$.", "Cena: $5 i $10", "Mam $ 20 i $ 30.", "$100-$200 za noc"] {
            #expect(LaTeX.replacingInlineMath(in: text) == text, "\(text)")
        }
    }

    @Test func displayLineDetection() {
        #expect(LaTeX.displayMath(inLine: "   $x = \\frac{1}{2}$") == "x = \\frac{1}{2}")
        #expect(LaTeX.displayMath(inLine: "$$a^2 + b^2 = c^2$$") == "a^2 + b^2 = c^2")
        #expect(LaTeX.displayMath(inLine: "\\[ E = mc^2 \\]") == "E = mc^2")
        #expect(LaTeX.displayMath(inLine: "$a$ i $b$") == nil)
        #expect(LaTeX.displayMath(inLine: "kosztuje $5") == nil)
    }
}

struct MarkdownMathTests {
    /// The real answer Gemma 4 12B gave for "wzór na pole koła, równanie kwadratowe, Pitagoras".
    @Test func realModelAnswer() {
        let md = """
        Oto żądane wzory:

        1. **Pole koła:**
           $P = \\pi r^2$
           *(gdzie $r$ to promień)*

        2. **Pierwiastki równania kwadratowego ($ax^2 + bx + c = 0$):**
           $x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}$
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks.contains(.math("P = \\pi r^2")))
        #expect(blocks.contains(.math("x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}")))
        #expect(blocks.contains(.listItem(marker: .number(1), text: "**Pole koła:**", indent: 0)))
        #expect(blocks.contains(.paragraph("*(gdzie $r$ to promień)*"))) // inline math converted at render time
    }

    @Test func multiLineDisplayMath() {
        let md = "Wynik:\n$$\nx = \\frac{a}{b}\n$$\nKoniec"
        #expect(MarkdownParser.parse(md) == [.paragraph("Wynik:"), .math("x = \\frac{a}{b}"), .paragraph("Koniec")])
        #expect(MarkdownParser.parse("\\[\n a^2 \n\\]") == [.math("a^2")])
    }
}
