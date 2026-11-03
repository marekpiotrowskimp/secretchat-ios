import Foundation
import Synchronization
import Testing
@testable import GemmaKit

private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Serves canned responses by URL substring and records every request (to prove nothing leaks).
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    struct Route { let match: String; let status: Int; let body: Data; let contentType: String }
    let routes: [Route]
    let requests = Mutex<[URLRequest]>([])

    init(_ routes: [Route]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.withLock { $0.append(request) }
        let url = request.url!.absoluteString
        guard let route = routes.first(where: { url.contains($0.match) }) else {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: ["Content-Type": route.contentType])!
        return (route.body, response)
    }

    var requestedURLs: [String] { requests.withLock { $0.map { $0.url!.absoluteString } } }
}

struct WebSearchTests {
    @Test func duckDuckGoParsesOrganicResultsAndSkipsAds() throws {
        let html = String(decoding: try fixture("ddg_results", "html"), as: UTF8.self)
        let results = try DuckDuckGoSearch.parse(html)
        #expect(results.map(\.url.absoluteString) == [
            "https://pl.wikipedia.org/wiki/Gerlach",
            "https://www.tatry.pl/rysy?a=1&b=2", // decoded from the uddg redirect
            "https://www.tpn.pl/zwiedzaj/szlaki",
        ])
        #expect(results[0].title == "Gerlach – Wikipedia, wolna encyklopedia")
        #expect(results[0].snippet.hasPrefix("Gerlach (2655 m n.p.m.) – najwyższy szczyt Tatr"))
        #expect(results[1].title == "Rysy – najwyższy szczyt Polski")
        #expect(results[2].snippet.contains("Tatrach & warunkach"))
    }

    @Test func duckDuckGoParsesRealResponse() throws {
        let html = String(decoding: try fixture("ddg_results_live", "html"), as: UTF8.self) // captured 2026-10-02
        let results = try DuckDuckGoSearch.parse(html)
        #expect(results.count >= 8)
        #expect(results.allSatisfy { !$0.title.isEmpty && $0.url.host()?.contains("duckduckgo") == false })
        #expect(results.allSatisfy { !$0.title.contains("<") && !$0.snippet.contains("<") && !$0.snippet.contains("&amp;") })
        #expect(results.contains { $0.url.host()?.contains("wikipedia.org") == true })
        #expect(results.filter { !$0.snippet.isEmpty }.count >= results.count - 1)
    }

    @Test func duckDuckGoBotChallengeIsReportedAsBlocked() throws {
        let html = String(decoding: try fixture("ddg_challenge", "html"), as: UTF8.self) // real response
        #expect(throws: WebSearchError.blocked(engine: "DuckDuckGo")) { try DuckDuckGoSearch.parse(html) }
    }

    @Test func wikipediaParsesRealAPIResponse() throws {
        let results = try WikipediaSearch(language: "pl").parse(try fixture("wikipedia_search", "json"))
        #expect(results.first?.title == "Gerlach")
        #expect(results.first?.url.absoluteString == "https://pl.wikipedia.org/wiki/Gerlach")
        #expect(results.first?.snippet.contains("najwyższy szczyt Tatr") == true)
        #expect(results.allSatisfy { !$0.snippet.contains("<span") })
        #expect(results.contains { $0.url.absoluteString.contains("Starorobocia%C5%84ski_Wierch") })
    }

    @Test func braveParsesJSON() throws {
        let json = #"{"web":{"results":[{"title":"Rysy <strong>2499</strong>","url":"https://a.pl/rysy","description":"Szczyt &amp; szlak"}]}}"#
        let results = try BraveSearch.parse(Data(json.utf8))
        #expect(results == [SearchResult(title: "Rysy 2499", url: URL(string: "https://a.pl/rysy")!, snippet: "Szczyt & szlak")])
    }

    @Test func braveWithoutKeyFailsWithoutNetwork() async throws {
        let http = FakeHTTP([])
        await #expect(throws: WebSearchError.missingAPIKey) { try await BraveSearch(apiKey: "", client: http).search("x") }
        #expect(http.requestedURLs.isEmpty)
    }

    @Test func fallbackUsesWikipediaWhenDuckDuckGoIsBlocked() async throws {
        let http = FakeHTTP([
            .init(match: "duckduckgo.com", status: 200, body: try fixture("ddg_challenge", "html"), contentType: "text/html"),
            .init(match: "wikipedia.org/w/api.php", status: 200, body: try fixture("wikipedia_search", "json"), contentType: "application/json"),
        ])
        let chain = FallbackSearch([DuckDuckGoSearch(client: http), WikipediaSearch(client: http, language: "pl")])
        let (results, engine) = try await chain.search("najwyższy szczyt Tatr")
        #expect(engine == "Wikipedia")
        #expect(results.first?.title == "Gerlach")
        #expect(http.requestedURLs.count == 2)
    }

    @Test func pageReaderKeepsArticleTextOnly() throws {
        let html = String(decoding: try fixture("page_article", "html"), as: UTF8.self)
        #expect(PageReader.title(of: html) == "Rysy – przewodnik | Tatry.pl")
        let text = PageReader.readableText(of: html)
        #expect(text.hasPrefix("## Rysy – najwyższy szczyt Polski\nRysy mają wysokość 2499 m n.p.m."))
        #expect(text.contains("## Bezpieczeństwo"))
        #expect(text.contains("łańcuchy"))
        for junk in ["Strona główna", "Reklama", "tracking", "not text", "Krótko.", "Ukryty komentarz", "prawa zastrzeżone"] {
            #expect(!text.contains(junk), "\(junk)")
        }
        #expect(text.components(separatedBy: "Rysy mają wysokość").count == 2, "duplicate paragraph dropped")
    }

    @Test func pageReaderHandlesRealWikipediaPage() throws {
        let html = String(decoding: try fixture("page_wikipedia", "html"), as: UTF8.self)
        let text = PageReader.readableText(of: html)
        #expect(text.contains("2499"))
        #expect(text.count > 2000)
        #expect(!text.contains("<"))
    }

    @Test func entities() {
        #expect(HTML.decodeEntities("a &amp; b &lt;c&gt; &#8211; &#x1F600; &amp;lt;") == "a & b <c> – 😀 &lt;")
    }
}

struct WebResearcherTests {
    private func researcher(_ http: FakeHTTP) -> WebResearcher {
        WebResearcher(search: FallbackSearch([DuckDuckGoSearch(client: http)]), reader: PageReader(client: http))
    }

    private func http() throws -> FakeHTTP {
        FakeHTTP([
            .init(match: "duckduckgo.com", status: 200, body: try fixture("ddg_results", "html"), contentType: "text/html"),
            .init(match: "pl.wikipedia.org/wiki/Gerlach", status: 200, body: try fixture("page_wikipedia", "html"), contentType: "text/html; charset=UTF-8"),
            .init(match: "tatry.pl/rysy", status: 200, body: try fixture("page_article", "html"), contentType: "text/html"),
            .init(match: "tpn.pl", status: 500, body: Data(), contentType: "text/html"),
        ])
    }

    @Test func readsTopPagesAndNumbersSources() async throws {
        let http = try http()
        let steps = Mutex<[WebResearcher.Progress]>([])
        let research = try await researcher(http).research("najwyższy szczyt Tatr", budget: 3600) { p in steps.withLock { $0.append(p) } }

        #expect(steps.withLock { $0 } == [.searching, .reading(pages: 3)])
        #expect(research.engine == "DuckDuckGo")
        #expect(research.sources.map(\.index) == [1, 2, 3])
        #expect(research.sources[1].url.absoluteString == "https://www.tatry.pl/rysy?a=1&b=2")
        #expect(research.toolResponse.hasPrefix(WebSearchInstructions.responseHeader))
        #expect(research.toolResponse.contains("[2] Rysy – najwyższy szczyt Polski — https://www.tatry.pl/rysy?a=1&b=2\n"))
        #expect(research.toolResponse.contains("2499 m n.p.m."))            // page text, not just the snippet
        #expect(research.toolResponse.contains("Informacje o szlakach"))   // page failed → snippet used
        #expect(research.toolResponse.count <= 3601)
        // Only the search engine and the three result pages were contacted.
        #expect(http.requestedURLs.count == 4)
    }

    @Test func budgetScalesWithContext() {
        #expect(WebResearcher.budget(contextLength: 4096) == 3686)
        #expect(WebResearcher.budget(contextLength: 16384) > 14000)
    }

    @Test func excerptPrefersParagraphsAboutTheQuery() {
        let text = (1...30).map { "Akapit \($0) o niczym szczególnym, wypełniacz tekstu na stronie." }.joined(separator: "\n")
            + "\nWysokość Rysów to 2499 metrów nad poziomem morza."
        let excerpt = WebResearcher.excerpt(text, query: "wysokość Rysów", limit: 300)
        #expect(excerpt.contains("2499"))
        #expect(excerpt.count <= 301)
    }
}

/// Live network — opt-in (`NETWORK_TESTS=1`). DuckDuckGo may answer with a bot challenge from
/// datacenter / frequently used IPs; that is accepted, the Wikipedia fallback must still work.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"))
struct LiveWebTests {
    @Test func duckDuckGoOrBlocked() async throws {
        do {
            let results = try await DuckDuckGoSearch().search("najwyższy szczyt Tatr")
            #expect(results.count >= 3)
        } catch WebSearchError.blocked {
            // acceptable: covered by the fallback test below
        }
    }

    @Test func fallbackChainFindsSomething() async throws {
        let research = try await WebResearcher(search: FallbackSearch([DuckDuckGoSearch(), WikipediaSearch(language: "pl")]))
            .research("najwyższy szczyt Tatr", budget: 3600)
        print("live engine=\(research.engine) sources=\(research.sources.map(\.url))")
        #expect(!research.sources.isEmpty)
        #expect(research.toolResponse.contains("2655") || research.toolResponse.contains("Gerlach"))
    }
}
