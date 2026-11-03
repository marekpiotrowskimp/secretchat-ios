#if DEBUG
import Foundation
import GemmaKit

/// Offline stand-in for UI tests and previews (`GEMMA_FAKE_WEB=1`): no network, fixed sources.
struct FakeWebResearcher: WebResearching {
    var facts = "Legia Warszawa wygrała z Lechem Poznań 3:1 (1 października 2026). Bramki: Kowalski 2, Nowak."

    func research(_ query: String, budget: Int, progress: @escaping @Sendable (WebResearcher.Progress) async -> Void) async throws -> WebResearch {
        await progress(.searching)
        try await Task.sleep(for: .milliseconds(300))
        await progress(.reading(pages: 2))
        try await Task.sleep(for: .milliseconds(300))
        let sources = [
            WebSource(index: 1, title: "Legia – Lech 3:1", url: URL(string: "https://sport.example.pl/legia-lech")!),
            WebSource(index: 2, title: "Ekstraklasa – wyniki", url: URL(string: "https://wyniki.example.pl/ekstraklasa")!),
        ]
        let response = WebSearchInstructions.responseHeader + "\n\n[1] \(sources[0].title) — \(sources[0].url)\n\(facts)\n\n[2] \(sources[1].title) — \(sources[1].url)\nTabela i wyniki kolejki."
        return WebResearch(query: query, engine: "Test", sources: sources, toolResponse: response)
    }
}
#endif
