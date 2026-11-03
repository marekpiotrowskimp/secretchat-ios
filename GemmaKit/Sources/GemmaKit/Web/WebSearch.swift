import Foundation

/// Network access, injectable for tests.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

public struct SearchResult: Sendable, Hashable, Codable {
    public var title: String
    public var url: URL
    public var snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public enum WebSearchError: Error, Equatable, LocalizedError {
    case blocked(engine: String)
    case http(Int)
    case missingAPIKey
    case noResults
    case offline

    public var errorDescription: String? {
        switch self {
        case .blocked(let engine): String(localized: "\(engine) tymczasowo zablokował wyszukiwanie (zabezpieczenie przed botami).", bundle: .module)
        case .http(let code): String(localized: "Wyszukiwarka zwróciła błąd HTTP \(code).", bundle: .module)
        case .missingAPIKey: String(localized: "Brak klucza API wyszukiwarki.", bundle: .module)
        case .noResults: String(localized: "Brak wyników wyszukiwania.", bundle: .module)
        case .offline: String(localized: "Brak połączenia z internetem.", bundle: .module)
        }
    }
}

public protocol WebSearchProvider: Sendable {
    var name: String { get }
    func search(_ query: String) async throws -> [SearchResult]
}

enum Web {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    /// Wikimedia's User-Agent policy asks API clients to identify themselves instead of posing as a browser.
    static let appUserAgent = "SecretChat/1.0 (iOS; on-device AI chat, searches only on user request)"

    static func get(_ url: URL, client: HTTPClient, headers: [String: String] = [:], timeout: TimeInterval = 10) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.preferredLanguages.prefix(2).joined(separator: ","), forHTTPHeaderField: "Accept-Language")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WebSearchError.http(0) }
            return (data, http)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw WebSearchError.offline
        }
    }
}

// MARK: - DuckDuckGo (no key)

/// DuckDuckGo's HTML endpoint. Unofficial: it can answer with a bot challenge instead of results,
/// which is detected and reported as `.blocked` so a fallback can take over.
public struct DuckDuckGoSearch: WebSearchProvider {
    public let name = "DuckDuckGo"
    let client: HTTPClient
    let region: String

    public init(client: HTTPClient = URLSession.shared, region: String = "pl-pl") {
        self.client = client
        self.region = region
    }

    public func search(_ query: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "kl", value: region)]
        let (data, http) = try await Web.get(components.url!, client: client)
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 202 || http.statusCode == 403 ? WebSearchError.blocked(engine: name) : WebSearchError.http(http.statusCode)
        }
        let results = try Self.parse(String(decoding: data, as: UTF8.self))
        guard !results.isEmpty else { throw WebSearchError.noResults }
        return results
    }

    static func parse(_ html: String) throws -> [SearchResult] {
        if html.contains("anomaly-modal") || html.contains("bots use DuckDuckGo too") {
            throw WebSearchError.blocked(engine: "DuckDuckGo")
        }
        var results: [SearchResult] = []
        // Each organic result: <a … class="result__a" href="URL">TITLE</a> … <a class="result__snippet" …>SNIPPET</a>
        for block in html.components(separatedBy: "class=\"result__a\"").dropFirst() {
            guard let href = HTML.attribute("href", in: block),
                  let url = resolve(href),
                  let titleHTML = HTML.between(">", "</a>", in: block) else { continue }
            let snippetHTML = block.components(separatedBy: "class=\"result__snippet\"").dropFirst().first
                .flatMap { HTML.between(">", "</a>", in: $0) } ?? ""
            let title = HTML.text(from: titleHTML)
            guard !title.isEmpty, !url.host()!.contains("duckduckgo.com") else { continue } // skip ads
            results.append(SearchResult(title: title, url: url, snippet: HTML.text(from: snippetHTML)))
        }
        return results
    }

    /// Links are either direct or `//duckduckgo.com/l/?uddg=<encoded target>`.
    static func resolve(_ href: String) -> URL? {
        let decoded = HTML.decodeEntities(href)
        if decoded.contains("duckduckgo.com/l/"),
           let components = URLComponents(string: decoded.hasPrefix("//") ? "https:" + decoded : decoded),
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return URL(string: target)
        }
        guard let url = URL(string: decoded), url.scheme == "https" || url.scheme == "http", url.host() != nil else { return nil }
        return url
    }
}

// MARK: - Wikipedia (no key, official API)

public struct WikipediaSearch: WebSearchProvider {
    public let name = "Wikipedia"
    let client: HTTPClient
    let language: String

    public init(client: HTTPClient = URLSession.shared, language: String = Locale.current.language.languageCode?.identifier ?? "pl") {
        self.client = client
        self.language = language
    }

    public func search(_ query: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"),
            .init(name: "srsearch", value: query), .init(name: "srlimit", value: "5"),
            .init(name: "format", value: "json"), .init(name: "utf8", value: "1"),
        ]
        let (data, http) = try await Web.get(components.url!, client: client, headers: ["User-Agent": Web.appUserAgent])
        guard (200..<300).contains(http.statusCode) else { throw WebSearchError.http(http.statusCode) }
        let results = try parse(data)
        guard !results.isEmpty else { throw WebSearchError.noResults }
        return results
    }

    func parse(_ data: Data) throws -> [SearchResult] {
        struct Response: Decodable {
            struct Query: Decodable { let search: [Hit] }
            struct Hit: Decodable { let title: String; let snippet: String }
            let query: Query?
        }
        let hits = try JSONDecoder().decode(Response.self, from: data).query?.search ?? []
        return hits.compactMap { hit in
            let path = hit.title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hit.title
            guard let url = URL(string: "https://\(language).wikipedia.org/wiki/\(path)") else { return nil }
            return SearchResult(title: hit.title, url: url, snippet: HTML.text(from: hit.snippet))
        }
    }
}

// MARK: - Brave Search API (key)

public struct BraveSearch: WebSearchProvider {
    public let name = "Brave Search"
    let client: HTTPClient
    let apiKey: String

    public init(apiKey: String, client: HTTPClient = URLSession.shared) {
        self.apiKey = apiKey
        self.client = client
    }

    public func search(_ query: String) async throws -> [SearchResult] {
        guard !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "count", value: "8")]
        let (data, http) = try await Web.get(components.url!, client: client, headers: [
            "X-Subscription-Token": apiKey, "Accept": "application/json",
        ])
        switch http.statusCode {
        case 200..<300: break
        case 401, 403, 422: throw WebSearchError.missingAPIKey
        case 429: throw WebSearchError.blocked(engine: name)
        default: throw WebSearchError.http(http.statusCode)
        }
        let results = try Self.parse(data)
        guard !results.isEmpty else { throw WebSearchError.noResults }
        return results
    }

    static func parse(_ data: Data) throws -> [SearchResult] {
        struct Response: Decodable {
            struct Web: Decodable { let results: [Hit] }
            struct Hit: Decodable { let title: String; let url: URL; let description: String? }
            let web: Web?
        }
        return (try JSONDecoder().decode(Response.self, from: data).web?.results ?? []).map {
            SearchResult(title: HTML.text(from: $0.title), url: $0.url, snippet: HTML.text(from: $0.description ?? ""))
        }
    }
}

// MARK: - Fallback chain

/// Tries providers in order; returns the first non-empty result set and which engine produced it.
public struct FallbackSearch: Sendable {
    public let providers: [WebSearchProvider]

    public init(_ providers: [WebSearchProvider]) {
        self.providers = providers
    }

    public func search(_ query: String) async throws -> (results: [SearchResult], engine: String) {
        var lastError: Error = WebSearchError.noResults
        for provider in providers {
            do {
                return (try await provider.search(query), provider.name)
            } catch WebSearchError.offline {
                throw WebSearchError.offline // no point trying the next one
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
