import Foundation

/// Turns a Markdown answer into text for a speech synthesizer: no Markdown syntax, no citation
/// markers, formulas read as words, code blocks skipped (reading code aloud is useless).
public enum SpeechText {
    public enum Language: String, Sendable {
        case polish = "pl", english = "en"

        init(code: String?) {
            self = code?.hasPrefix("en") == true ? .english : .polish
        }
    }

    public static func plain(fromMarkdown markdown: String, language: Language) -> String {
        var parts: [String] = []
        for block in MarkdownParser.parse(markdown) {
            switch block {
            case .paragraph(let text), .quote(let text):
                parts.append(inline(text, language))
            case .heading(_, let text):
                parts.append(sentence(inline(text, language)))
            case .listItem(_, let text, _):
                parts.append(sentence(inline(text, language)))
            case .math(let latex):
                parts.append(sentence(speakMath(LaTeX.toUnicode(latex), language)))
            case .code(_, _, let isComplete):
                if isComplete { parts.append(language == .polish ? "(Pominięto blok kodu.)" : "(Code block omitted.)") }
            case .table(let header, let rows):
                for row in rows {
                    let cells = zip(header, row).map { "\(inline($0, language)): \(inline($1, language))" }
                    parts.append(sentence(cells.joined(separator: ", ")))
                }
            case .rule:
                continue
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Ends a fragment with a period so the synthesizer pauses between list items and headings.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?:;…".contains(last) else { return text }
        return text + "."
    }

    static func inline(_ text: String, _ language: Language) -> String {
        // Inline math → words, before Markdown stripping touches "*" or "_".
        var s = replacingInlineMath(text, language)
        // Links [title](url) → title; bare URLs are not worth reading out.
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        // Citation markers [1], [2, 3].
        s = s.replacingOccurrences(of: #"\s?\[\d+(?:\s*,\s*\d+)*\]"#, with: "", options: .regularExpression)
        // Emphasis, inline code, strikethrough.
        for marker in ["**", "__", "~~", "`"] { s = s.replacingOccurrences(of: marker, with: "") }
        s = s.replacingOccurrences(of: #"(?<![\p{L}\p{N}])[*_](?=\S)|(?<=\S)[*_](?![\p{L}\p{N}])"#, with: "", options: .regularExpression)
        return HTML.collapse(s)
    }

    private static func replacingInlineMath(_ text: String, _ language: Language) -> String {
        // Reuse the inline-math detector, but speak the result instead of displaying it.
        let marker = "\u{E000}"
        var spoken: [String] = []
        let withMarkers = LaTeXInlineScanner.replace(in: text) { latex in
            spoken.append(speakMath(LaTeX.toUnicode(latex), language))
            return marker
        }
        var out = ""
        var iterator = spoken.makeIterator()
        for ch in withMarkers {
            if String(ch) == marker { out += iterator.next() ?? "" } else { out.append(ch) }
        }
        return out
    }

    /// Unicode math (as produced by `LaTeX.toUnicode`) → words.
    public static func speakMath(_ math: String, _ language: Language) -> String {
        let words = language == .polish ? polishMath : englishMath
        var out = ""
        for ch in math {
            if let word = words[ch] {
                out += " \(word) "
            } else {
                out.append(ch)
            }
        }
        return HTML.collapse(out)
    }

    private static let polishMath: [Character: String] = [
        "²": "do kwadratu", "³": "do sześcianu", "√": "pierwiastek z", "±": "plus minus", "×": "razy", "·": "razy",
        "÷": "podzielić przez", "/": "przez", "=": "równa się", "≠": "różne od", "≈": "w przybliżeniu", "≤": "mniejsze lub równe",
        "≥": "większe lub równe", "<": "mniejsze od", ">": "większe od", "+": "plus", "-": "minus", "−": "minus",
        "π": "pi", "Δ": "delta", "α": "alfa", "β": "beta", "γ": "gamma", "θ": "theta", "λ": "lambda", "μ": "mi",
        "σ": "sigma", "Σ": "suma", "∞": "nieskończoność", "→": "dąży do", "∫": "całka", "%": "procent", "°": "stopni",
    ]

    private static let englishMath: [Character: String] = [
        "²": "squared", "³": "cubed", "√": "square root of", "±": "plus or minus", "×": "times", "·": "times",
        "÷": "divided by", "/": "over", "=": "equals", "≠": "is not equal to", "≈": "approximately", "≤": "is at most",
        "≥": "is at least", "<": "is less than", ">": "is greater than", "+": "plus", "-": "minus", "−": "minus",
        "π": "pi", "Δ": "delta", "α": "alpha", "β": "beta", "γ": "gamma", "θ": "theta", "λ": "lambda", "μ": "mu",
        "σ": "sigma", "Σ": "sum", "∞": "infinity", "→": "tends to", "∫": "integral", "%": "percent", "°": "degrees",
    ]
}

/// Incremental reader for streamed answers: hands out complete sentences as the text grows,
/// so speech can start before the answer is finished.
public struct SpeechStreamer: Sendable {
    public let language: SpeechText.Language
    /// How much of the Markdown source has already been turned into speech.
    private var consumed = 0

    public init(language: SpeechText.Language) {
        self.language = language
    }

    /// Feed the whole answer so far; returns newly completed text to speak (nil if none yet).
    public mutating func feed(_ markdown: String) -> String? {
        let source = Array(markdown)
        guard consumed < source.count else { return nil }
        let pending = String(source[consumed...])
        guard let end = Self.lastSafeBoundary(in: pending) else { return nil }
        let chunk = String(pending[..<end])
        consumed += chunk.count
        let spoken = SpeechText.plain(fromMarkdown: chunk, language: language)
        return spoken.isEmpty ? nil : spoken
    }

    /// The rest, once the answer is complete.
    public mutating func finish(_ markdown: String) -> String? {
        let source = Array(markdown)
        guard consumed < source.count else { return nil }
        let rest = String(source[consumed...])
        consumed = source.count
        let spoken = SpeechText.plain(fromMarkdown: rest, language: language)
        return spoken.isEmpty ? nil : spoken
    }

    /// End of the last complete sentence or line that is not inside an open code fence or formula.
    static func lastSafeBoundary(in text: String) -> String.Index? {
        var boundary: String.Index?
        var inFence = false
        var inDisplayMath = false
        var dollarCount = 0
        var lineStart = true
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if lineStart, text[i...].hasPrefix("```") { inFence.toggle() }
            if text[i...].hasPrefix("$$") { inDisplayMath.toggle(); i = text.index(i, offsetBy: 2); lineStart = false; continue }
            if c == "$" { dollarCount += 1 }
            let next = text.index(after: i)
            let atBreak = c == "\n" || (".!?".contains(c) && next < text.endIndex && text[next].isWhitespace)
            if atBreak, !inFence, !inDisplayMath, dollarCount % 2 == 0 {
                boundary = next
            }
            lineStart = c == "\n"
            i = next
        }
        return boundary
    }
}

/// Finds inline math (`$…$`, `\(…\)`) with the same rules as `LaTeX.replacingInlineMath`.
enum LaTeXInlineScanner {
    static func replace(in text: String, _ transform: (String) -> String) -> String {
        var out = ""
        var rest = Substring(text)
        while let range = nextMath(in: rest) {
            out += rest[..<range.outer.lowerBound]
            out += transform(String(rest[range.inner]))
            rest = rest[range.outer.upperBound...]
        }
        return out + rest
    }

    private static func nextMath(in s: Substring) -> (outer: Range<Substring.Index>, inner: Range<Substring.Index>)? {
        var search = s.startIndex
        while search < s.endIndex {
            if let open = s[search...].range(of: "\\("), let close = s[open.upperBound...].range(of: "\\)"),
               s[search...].firstIndex(of: "$").map({ open.lowerBound < $0 }) ?? true {
                return (open.lowerBound..<close.upperBound, open.upperBound..<close.lowerBound)
            }
            guard let dollar = s[search...].firstIndex(of: "$") else { return nil }
            let contentStart = s.index(after: dollar)
            if contentStart < s.endIndex, !s[contentStart].isWhitespace, s[contentStart] != "$",
               let close = s[contentStart...].firstIndex(of: "$"), close > contentStart,
               !s[s.index(before: close)].isWhitespace,
               !(s.index(after: close) < s.endIndex && s[s.index(after: close)].isNumber),
               !s[contentStart..<close].contains("\n") {
                return (dollar..<s.index(after: close), contentStart..<close)
            }
            search = contentStart
        }
        return nil
    }
}
