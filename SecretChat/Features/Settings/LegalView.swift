import SwiftUI

/// Settings → Licenses & legal: what the app is built from and under which terms.
/// Apache 2.0 (Gemma 4) and MIT (llama.cpp, SwiftMath) require a copy of the license and the
/// authors' notices to travel with the software — the full texts are bundled in Resources/Licenses.
struct LegalView: View {
    struct Component: Identifiable {
        let name: String
        let author: String
        let license: String
        let file: String
        let url: URL
        var id: String { name }
    }

    static let components: [Component] = [
        .init(name: "Gemma 4 (12B, E4B, E2B)", author: "Google LLC", license: "Apache License 2.0",
              file: "license-apache-2.0", url: URL(string: "https://ai.google.dev/gemma/docs/gemma_4_license")!),
        .init(name: "llama.cpp / ggml", author: "The ggml authors", license: "MIT",
              file: "license-llama.cpp", url: URL(string: "https://github.com/ggml-org/llama.cpp")!),
        .init(name: "miniaudio", author: "David Reid", license: "Public Domain / MIT No Attribution",
              file: "license-miniaudio", url: URL(string: "https://miniaud.io")!),
        .init(name: "stb_image", author: "Sean Barrett", license: "MIT / Public Domain",
              file: "license-stb", url: URL(string: "https://github.com/nothings/stb")!),
        .init(name: "SwiftMath", author: "Computer Inspirations", license: "MIT",
              file: "license-swiftmath", url: URL(string: "https://github.com/mgriebling/SwiftMath")!),
        .init(name: "Latin Modern Math", author: "GUST e-foundry", license: "GUST Font License",
              file: "license-gust-font", url: URL(string: "https://www.gust.org.pl/projects/e-foundry/lm-math")!),
    ]

    var body: some View {
        List {
            Section {
                Text("Odpowiedzi generuje model sztucznej inteligencji działający na tym telefonie. Mogą zawierać błędy — sprawdzaj ważne informacje.")
            } header: {
                Text("Sztuczna inteligencja")
            }

            Section {
                ForEach(Self.components) { component in
                    NavigationLink {
                        LicenseTextView(component: component)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: component.name).font(.body.weight(.semibold))
                            Text(verbatim: "\(component.author) · \(component.license)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Model i biblioteki")
            } footer: {
                Text("Pliki modeli Gemma 4 nie są częścią aplikacji: pobierasz je bezpośrednio z Hugging Face (wersje GGUF przygotowane przez Unsloth, licencja Apache 2.0).")
            }

            Section {
                Text("Gemma jest znakiem towarowym Google LLC. SecretChat nie jest powiązany z Google ani przez Google sponsorowany.")
            } header: {
                Text("Znaki towarowe")
            }

            Section {
                Text("Tylko gdy włączysz wyszukiwanie i zatwierdzisz zapytanie: DuckDuckGo, Wikipedia (treści na licencji CC BY-SA — źródła są podawane przy odpowiedzi) albo Brave Search z Twoim własnym kluczem, na warunkach Brave Search API.")
            } header: {
                Text("Usługi internetowe")
            }
        }
        .secretBackground()
        .navigationTitle("Licencje i informacje prawne")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseTextView: View {
    let component: LegalView.Component

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: component.url) {
                    Label(component.url.host() ?? component.url.absoluteString, systemImage: "safari")
                }
                Text(verbatim: Self.text(component.file))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .secretBackground()
        .navigationTitle(Text(verbatim: component.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    static func text(_ file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "—" }
        return text
    }
}
