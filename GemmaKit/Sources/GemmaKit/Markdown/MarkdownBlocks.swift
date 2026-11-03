import Foundation

/// Block-level Markdown for chat answers. Inline formatting (bold, italics, `code`, links) is left
/// to `AttributedString(markdown:)`; this splits the text into blocks SwiftUI renders separately.
///
/// Designed for streaming: an unterminated code fence yields a `.code` block with `isComplete == false`.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String?, code: String, isComplete: Bool)
    case listItem(marker: ListMarker, text: String, indent: Int)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
    /// Display math (LaTeX source, without delimiters).
    case math(String)

    public enum ListMarker: Equatable, Sendable {
        case bullet
        case number(Int)
    }
}

public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph.removeAll()
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote.removeAll()
        }
        func flushAll() { flushParagraph(); flushQuote() }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                var closed = false
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { closed = true; break }
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n"), isComplete: closed))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }

            // Display math spanning lines: $$ … $$ or \[ … \].
            if (trimmed == "$$" || trimmed == "\\[") || ((trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[")) && LaTeX.displayMath(inLine: trimmed) == nil) {
                flushAll()
                let close = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                var body = [String(trimmed.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    i += 1
                    if l.hasSuffix(close) {
                        body.append(String(l.dropLast(2)))
                        break
                    }
                    body.append(l)
                }
                let latex = body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !latex.isEmpty { blocks.append(.math(latex)) }
                continue
            }

            // A line that is nothing but a formula.
            if let latex = LaTeX.displayMath(inLine: trimmed) {
                flushAll()
                blocks.append(.math(latex))
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushAll()
                blocks.append(heading)
                i += 1
                continue
            }

            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }

            // Table: header row, separator row, body rows.
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushAll()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }

            if let item = parseListItem(line) {
                flushAll()
                blocks.append(item)
                i += 1
                continue
            }

            flushQuote()
            paragraph.append(trimmed)
            i += 1
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseListItem(_ line: String) -> MarkdownBlock? {
        let indentWidth = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let body = line.drop { $0 == " " || $0 == "\t" }
        let indent = indentWidth / 2

        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return .listItem(marker: .bullet, text: body.dropFirst(2).trimmingCharacters(in: .whitespaces), indent: indent)
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, let n = Int(digits) {
            let after = body.dropFirst(digits.count)
            if let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " {
                return .listItem(marker: .number(n), text: after.dropFirst(2).trimmingCharacters(in: .whitespaces), indent: indent)
            }
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = Substring(line)
        if t.hasPrefix("|") { t = t.dropFirst() }
        if t.hasSuffix("|") { t = t.dropLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
