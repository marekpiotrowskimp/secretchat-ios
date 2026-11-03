import Foundation

/// Math in model answers. Gemma writes LaTeX: `$…$` inline, `$$…$$` / `\[…\]` as blocks.
/// Blocks are typeset by the app (SwiftMath); inline math is turned into readable Unicode
/// (`\frac{-b \pm \sqrt{\Delta}}{2a}` → `(-b ± √Δ)/(2a)`), so it flows inside a sentence.
public enum LaTeX {
    // MARK: Inline math in text

    /// Replaces inline math (`$…$`, `\(…\)`) in Markdown text with Unicode.
    /// Dollar amounts ("5$ albo $10") are left alone: like TeX, an opening `$` must be followed and a
    /// closing `$` preceded by a non-space, and a closing `$` must not be followed by a digit.
    public static func replacingInlineMath(in text: String) -> String {
        var result = replacingDelimited(text, open: "\\(", close: "\\)")
        guard result.contains("$") else { return result }

        var out = ""
        var rest = Substring(result)
        while let open = rest.firstIndex(of: "$") {
            out += rest[..<open]
            let afterOpen = rest.index(after: open)
            // "$$" inside a paragraph: treat as display math written inline.
            let isDouble = afterOpen < rest.endIndex && rest[afterOpen] == "$"
            let contentStart = isDouble ? rest.index(after: afterOpen) : afterOpen
            let delimiter = isDouble ? "$$" : "$"
            guard contentStart < rest.endIndex, !rest[contentStart].isWhitespace,
                  let close = rest[contentStart...].range(of: delimiter),
                  close.lowerBound > contentStart,
                  !rest[rest.index(before: close.lowerBound)].isWhitespace,
                  !(close.upperBound < rest.endIndex && rest[close.upperBound].isNumber),
                  !rest[contentStart..<close.lowerBound].contains("\n")
            else {
                out += rest[open..<afterOpen]
                rest = rest[afterOpen...]
                continue
            }
            out += toUnicode(String(rest[contentStart..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        out += rest
        result = out
        return result
    }

    private static func replacingDelimited(_ text: String, open: String, close: String) -> String {
        guard text.contains(open) else { return text }
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: open), let end = rest[start.upperBound...].range(of: close) {
            out += rest[..<start.lowerBound]
            out += toUnicode(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return out + rest
    }

    /// If the whole (trimmed) line is a single math expression, returns its LaTeX source.
    public static func displayMath(inLine line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("$", "$"), ("\\(", "\\)")] {
            guard t.count > open.count + close.count, t.hasPrefix(open), t.hasSuffix(close) else { continue }
            let inner = String(t.dropFirst(open.count).dropLast(close.count))
            guard !inner.isEmpty, !inner.contains("$"), !inner.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if open == "$" { guard !inner.first!.isWhitespace, !inner.last!.isWhitespace else { continue } }
            return inner.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: LaTeX → Unicode

    public static func toUnicode(_ latex: String) -> String {
        var parser = Parser(Array(latex))
        let text = parser.parseSequence(until: nil)
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func parseSequence(until terminator: Character?) -> String {
            var out = ""
            while i < chars.count {
                let c = chars[i]
                if let terminator, c == terminator { i += 1; return out }
                switch c {
                case "\\": out += parseCommand()
                case "{": i += 1; out += parseSequence(until: "}")
                case "}": i += 1 // stray
                case "^": i += 1; out += script(parseArgument(), map: superscripts, fallback: "^")
                case "_": i += 1; out += script(parseArgument(), map: subscripts, fallback: "_")
                case "~": i += 1; out += " "
                case "&": i += 1; out += " " // alignment
                default: i += 1; out.append(c)
                }
            }
            return out
        }

        /// A single token or a `{group}`.
        mutating func parseArgument() -> String {
            skipSpaces()
            guard i < chars.count else { return "" }
            if chars[i] == "{" { i += 1; return parseSequence(until: "}") }
            if chars[i] == "\\" { return parseCommand() }
            defer { i += 1 }
            return String(chars[i])
        }

        mutating func parseOptional() -> String? {
            skipSpaces()
            guard i < chars.count, chars[i] == "[" else { return nil }
            i += 1
            return parseSequence(until: "]")
        }

        mutating func skipSpaces() {
            while i < chars.count, chars[i] == " " { i += 1 }
        }

        mutating func parseCommand() -> String {
            i += 1 // backslash
            guard i < chars.count else { return "" }
            // Control symbols: \, \; \! \% \{ \\ …
            if !chars[i].isLetter {
                let symbol = chars[i]
                i += 1
                switch symbol {
                case ",", ";", ":", " ": return " "
                case "!": return ""
                case "\\": return " "
                default: return String(symbol)
                }
            }
            var name = ""
            while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
            // A space after a command word only terminates it — drop it when a letter-like symbol is
            // directly followed by a variable (`\pi r` → "πr"), keep it around operators (`\times 3`).
            if i + 1 < chars.count, chars[i] == " ", chars[i + 1].isLetter, letterLike.contains(name) { i += 1 }

            switch name {
            case "frac", "dfrac", "tfrac":
                let numerator = parseArgument(), denominator = parseArgument()
                return "\(wrap(numerator))/\(wrap(denominator))"
            case "sqrt":
                let degree = parseOptional()
                let radicand = parseArgument()
                let root = degree.map { script($0, map: superscripts, fallback: "") } ?? ""
                return root + "√" + (isAtomic(radicand) ? radicand : "(\(radicand))")
            case "text", "textrm", "mathrm", "mathbf", "textbf", "mathit", "textit", "mathsf", "mathtt", "operatorname", "mbox", "boldsymbol":
                return parseArgument()
            case "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "displaystyle", "limits", "nolimits":
                return ""
            case "quad", "qquad": return " "
            case "begin", "end":
                _ = parseArgument() // environment name (aligned, cases…)
                return " "
            case "overline", "bar": return parseArgument() + "\u{0305}"
            case "vec": return parseArgument() + "\u{20D7}"
            case "hat": return parseArgument() + "\u{0302}"
            case "dot": return parseArgument() + "\u{0307}"
            default:
                return symbols[name] ?? name
            }
        }

        func script(_ text: String, map: [Character: Character], fallback: String) -> String {
            let mapped = text.compactMap { map[$0] }
            if mapped.count == text.count, !text.isEmpty { return String(mapped) }
            return fallback.isEmpty ? text : fallback + (text.count == 1 ? text : "(\(text))")
        }

        func isAtomic(_ s: String) -> Bool {
            s.count <= 1 || s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || superscripts.values.contains($0) }
        }

        /// Fraction parts: "2a" must become "(2a)" or "…/2a" reads as (…/2)·a; plain numbers stay bare.
        func wrap(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.count <= 1 || t.allSatisfy({ $0.isNumber || $0 == "." }) ? t : "(\(t))"
        }
    }

    /// Commands that print a letter (Greek, functions): a following space separates them from a variable.
    private static let letterLike: Set<String> = Set(symbols.keys.filter { key in
        guard let value = symbols[key] else { return false }
        return value.allSatisfy(\.isLetter)
    })

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ", "a": "ᵃ", "b": "ᵇ",
        "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "k": "ᵏ", "m": "ᵐ", "t": "ᵗ", "T": "ᵀ", "*": "*", "′": "′",
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "n": "ₙ",
        "m": "ₘ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "x": "ₓ",
    ]

    private static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators & relations
        "pm": "±", "mp": "∓", "times": "×", "cdot": "·", "div": "÷", "ast": "∗", "circ": "∘",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝",
        "ll": "≪", "gg": "≫",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "Leftarrow": "⇐", "leftrightarrow": "↔",
        "Leftrightarrow": "⇔", "implies": "⇒", "iff": "⇔", "mapsto": "↦",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "cup": "∪", "cap": "∩", "emptyset": "∅",
        "forall": "∀", "exists": "∃", "neg": "¬", "land": "∧", "lor": "∨",
        "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "Σ", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮",
        "degree": "°", "circledast": "⊛", "angle": "∠", "perp": "⊥", "parallel": "∥", "triangle": "△",
        "ldots": "…", "cdots": "⋯", "dots": "…", "prime": "′",
        "lim": "lim", "log": "log", "ln": "ln", "exp": "exp", "sin": "sin", "cos": "cos", "tan": "tan", "cot": "cot",
        "arcsin": "arcsin", "arccos": "arccos", "arctan": "arctan", "max": "max", "min": "min", "det": "det",
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
    ]
}
