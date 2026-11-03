import Foundation

/// A cited source shown under an answer.
public struct WebSource: Sendable, Hashable, Codable, Identifiable {
    public var index: Int
    public var title: String
    public var url: URL
    public var id: Int { index }

    public init(index: Int, title: String, url: URL) {
        self.index = index
        self.title = title
        self.url = url
    }
}

/// Result of one approved search: what goes back to the model, and what the UI shows.
public struct WebResearch: Sendable, Hashable {
    public var query: String
    public var engine: String
    public var sources: [WebSource]
    /// Text for the tool response block (header + numbered sources with excerpts).
    public var toolResponse: String

    public init(query: String, engine: String, sources: [WebSource], toolResponse: String) {
        self.query = query
        self.engine = engine
        self.sources = sources
        self.toolResponse = toolResponse
    }
}

/// Anything that can answer a search query for the model (the real researcher, or a fake in tests).
public protocol WebResearching: Sendable {
    func research(_ query: String, budget: Int, progress: @escaping @Sendable (WebResearcher.Progress) async -> Void) async throws -> WebResearch
}

/// Search → read the top pages → numbered excerpts within a character budget.
public struct WebResearcher: WebResearching {
    public enum Progress: Sendable, Equatable {
        case searching
        case reading(pages: Int)
    }

    let search: FallbackSearch
    let reader: PageReader
    let pagesToRead: Int

    public init(search: FallbackSearch, reader: PageReader = PageReader(), pagesToRead: Int = 3) {
        self.search = search
        self.reader = reader
        self.pagesToRead = pagesToRead
    }

    /// Character budget for the tool response, so it fits next to the conversation:
    /// ~30% of the context at ~3 characters per token (4K → ~3700 chars).
    public static func budget(contextLength: Int) -> Int {
        Int(Double(contextLength) * 0.3 * 3)
    }

    public func research(
        _ query: String,
        budget: Int,
        progress: @escaping @Sendable (Progress) async -> Void = { _ in }
    ) async throws -> WebResearch {
        await progress(.searching)
        let (results, engine) = try await search.search(query)

        // Prefer distinct sites and HTML pages; keep the rest as snippet-only sources.
        var picked: [SearchResult] = []
        var hosts = Set<String>()
        for result in results where !result.url.pathExtension.lowercased().hasPrefix("pdf") {
            if hosts.insert(result.url.host() ?? "").inserted { picked.append(result) }
            if picked.count == pagesToRead { break }
        }
        let extras = results.filter { result in !picked.contains(result) }.prefix(2)

        await progress(.reading(pages: picked.count))
        let pages = await withTaskGroup(of: (Int, PageReader.Page?).self) { group in
            for (i, result) in picked.enumerated() {
                group.addTask { (i, try? await reader.read(result.url)) }
            }
            var pages = [PageReader.Page?](repeating: nil, count: picked.count)
            for await (i, page) in group { pages[i] = page }
            return pages
        }

        let ordered = picked + extras
        let sources = ordered.enumerated().map { WebSource(index: $0 + 1, title: $1.title, url: $1.url) }
        let perPage = max(300, (budget - 400) / max(picked.count, 1))
        var sections: [String] = []
        for (i, result) in ordered.enumerated() {
            var section = "[\(i + 1)] \(result.title) — \(result.url.absoluteString)\n"
            if i < pages.count, let page = pages[i], !page.text.isEmpty {
                section += Self.excerpt(page.text, query: query, limit: perPage)
            } else {
                section += result.snippet
            }
            sections.append(section)
        }

        var body = WebSearchInstructions.responseHeader + "\n\n" + sections.joined(separator: "\n\n")
        if body.count > budget { body = String(body.prefix(budget)) + "…" }
        return WebResearch(query: query, engine: engine, sources: sources, toolResponse: body)
    }

    /// The part of the page most relevant to the query: paragraphs ranked by query-word overlap,
    /// then restored to page order and cut to `limit` characters.
    static func excerpt(_ text: String, query: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let words = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 }.map { String($0.prefix(5)) })
        let paragraphs = text.components(separatedBy: "\n")
        let scored = paragraphs.enumerated().map { i, p -> (Int, Int) in
            let lower = p.lowercased()
            let hits = words.filter { lower.contains($0) }.count
            return (i, hits * 100 - i) // relevance first, earlier paragraphs break ties
        }
        var chosen = Set<Int>()
        var used = 0
        for (i, _) in scored.sorted(by: { $0.1 > $1.1 }) {
            let length = paragraphs[i].count + 1
            if used + length > limit { continue }
            chosen.insert(i)
            used += length
        }
        if chosen.isEmpty { return String(text.prefix(limit)) + "…" }
        return chosen.sorted().map { paragraphs[$0] }.joined(separator: "\n")
    }
}
