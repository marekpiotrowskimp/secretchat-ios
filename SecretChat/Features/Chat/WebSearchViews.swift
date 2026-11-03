import GemmaKit
import SwiftUI

/// Shown when the model asks to search: the exact query, what would leave the phone, and a
/// deliberate two-step approval ("Szukaj…" → "Czy na pewno?").
struct WebConsentCard: View {
    let query: String
    let engine: String
    /// (approved, don't ask again in this conversation)
    let onDecision: (Bool, Bool) -> Void
    @State private var confirming = false
    @State private var dontAskAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model chce przeszukać internet", systemImage: "globe")
                .font(.headline)

            Text("»\(query)«")
                .font(.body.italic())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: .rect(cornerRadius: 10))

            Text("SecretChat działa offline. Jeśli się zgodzisz, tylko to zapytanie zostanie wysłane do wyszukiwarki (\(engine)), a aplikacja otworzy 2–3 strony z wyników. Reszta rozmowy nie opuści telefonu.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Nie pytaj mnie w tej rozmowie", isOn: $dontAskAgain)
                .font(.footnote)
                .tint(.orange)

            HStack {
                Button("Nie, odpowiedz bez internetu") { onDecision(false, false) }
                    .buttonStyle(.bordered)
                Button("Szukaj…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding()
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.4)))
        .confirmationDialog("Czy na pewno przeszukać internet?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Tak, szukaj w internecie") { onDecision(true, dontAskAgain) }
            Button("Nie, odpowiedz bez internetu", role: .cancel) { onDecision(false, false) }
        } message: {
            if dontAskAgain {
                Text("Zapytanie »\(query)« trafi do \(engine), a odwiedzone strony zobaczą adres IP Twojego telefonu. Kolejne wyszukiwania w tej rozmowie odbędą się bez pytania.")
            } else {
                Text("Zapytanie »\(query)« trafi do \(engine), a odwiedzone strony zobaczą adres IP Twojego telefonu.")
            }
        }
    }
}

/// "Answer from the internet" badge + the pages it is based on.
struct WebSourcesView: View {
    let query: String
    let sources: [WebSource]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zapytanie: »\(query)«")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sources) { source in
                    Link(destination: source.url) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("[\(source.index)]").monospacedDigit()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.title)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(source.url.host() ?? source.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label(sources.isEmpty ? "Odpowiedź z internetu" : "Odpowiedź z internetu · źródła: \(sources.count)",
                  systemImage: "globe")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

/// Privacy warning shown before web search can be turned on.
struct WebSearchWarningSheet: View {
    let engine: String
    let onEnable: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("SecretChat jest zaprojektowany do pracy bez internetu")
                        .font(.title2.bold())
                    Text("Domyślnie nic nie opuszcza Twojego telefonu. Gdy włączysz wyszukiwanie:")
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Model może zaproponować wyszukiwanie, gdy nie zna odpowiedzi (np. aktualne wydarzenia, pogoda, ceny).", systemImage: "sparkle.magnifyingglass")
                        Label("Za każdym razem zapytamy, czy na pewno — i pokażemy dokładne zapytanie.", systemImage: "hand.raised")
                        Label("Po zgodzie zapytanie trafi do \(engine), a aplikacja otworzy 2–3 strony z wyników. Te serwisy zobaczą adres IP telefonu.", systemImage: "network")
                        Label("Treść rozmowy, zdjęcia i historia nie są wysyłane.", systemImage: "lock")
                        Label("Odpowiedzi z internetu oznaczymy 🌐 i podamy źródła.", systemImage: "globe")
                    }
                    .font(.callout)
                    Button {
                        onEnable()
                        dismiss()
                    } label: {
                        Text("Rozumiem, włącz wyszukiwanie").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    Button("Zostaw wyłączone") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Wyszukiwanie w internecie")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
