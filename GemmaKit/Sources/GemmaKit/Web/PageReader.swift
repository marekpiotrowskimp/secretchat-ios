import Foundation

/// Minimal HTML helpers — enough for search result pages and readable-text extraction, without a DOM.
enum HTML {
    static func attribute(_ name: String, in html: some StringProtocol) -> String? {
        guard let start = html.range(of: "\(name)=\"") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func between(_ open: String, _ close: String, in html: some StringProtocol) -> String? {
        guard let start = html.range(of: open) else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: close) else { return nil }
        return String(rest[..<end.lowerBound])
    }

    /// Strips tags, decodes entities, collapses whitespace.
    static func text(from html: String) -> String {
        // Attribute values may contain ">" (e.g. Wikipedia's data-mw JSON), so skip quoted runs.
        let noTags = html.replacingOccurrences(of: #"<(?:[^>"']|"[^"]*"|'[^']*')*>"#, with: " ", options: .regularExpression)
        return collapse(decodeEntities(noTags))
    }

    static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, char) in named { result = result.replacingOccurrences(of: entity, with: char) }
        // Numeric: &#123; &#x1F;
        let pattern = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        let ns = result as NSString
        var out = ""
        var last = 0
        for match in pattern.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let isHex = match.range(at: 1).length > 0
            let digits = ns.substring(with: match.range(at: 2))
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
            }
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static let named: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&bdquo;", "„"), ("&rdquo;", "”"), ("&ldquo;", "“"),
        ("&amp;", "&"), // last, so "&amp;lt;" stays "&lt;"
    ]
}

/// Downloads a web page and extracts its readable text (title, headings, paragraphs, list items).
public struct PageReader: Sendable {
    public static let maxBytes = 2_000_000
    let client: HTTPClient

    public init(client: HTTPClient = URLSession.shared) {
        self.client = client
    }

    public struct Page: Sendable, Hashable {
        public var url: URL
        public var title: String
        public var text: String
    }

    public func read(_ url: URL, timeout: TimeInterval = 8) async throws -> Page {
        let (data, http) = try await Web.get(url, client: client, timeout: timeout)
        guard (200..<300).contains(http.statusCode) else { throw WebSearchError.http(http.statusCode) }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? "text/html"
        guard type.contains("html") || type.contains("text/plain") else { throw WebSearchError.noResults }
        let html = String(decoding: data.prefix(Self.maxBytes), as: UTF8.self)
        return Page(url: url, title: Self.title(of: html), text: Self.readableText(of: html))
    }

    static func title(of html: String) -> String {
        HTML.between("<title>", "</title>", in: html).map(HTML.text(from:)) ?? ""
    }

    /// Main-content heuristics: drop boilerplate containers, keep text blocks long enough to be prose.
    static func readableText(of html: String) -> String {
        var body = html
        // Remove elements whose content is never article text.
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "template", "iframe"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        body = body.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)

        let blockPattern = try! NSRegularExpression(pattern: "<(h[1-3]|p|li|td|blockquote)\\b[^>]*>([\\s\\S]*?)</\\1>", options: .caseInsensitive)
        let ns = body as NSString
        var blocks: [String] = []
        for match in blockPattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let text = HTML.text(from: ns.substring(with: match.range(at: 2)))
            let minimum = tag.hasPrefix("h") ? 3 : 40 // skip menu items, buttons, captions
            guard text.count >= minimum else { continue }
            blocks.append(tag.hasPrefix("h") ? "## \(text)" : text)
        }
        if blocks.isEmpty { return HTML.text(from: body) }
        // Drop exact duplicates (repeated teasers) while keeping order.
        var seen = Set<String>()
        return blocks.filter { seen.insert($0).inserted }.joined(separator: "\n")
    }
}
