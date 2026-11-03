import GemmaKit
import SwiftUI

/// Names, icons and short descriptions of the response styles (the prompt text lives in GemmaKit).
extension ResponseStyle {
    var title: LocalizedStringKey {
        switch self {
        case .balanced: "Zrównoważony"
        case .concise: "Zwięzły"
        case .detailed: "Szczegółowy"
        case .friendly: "Przyjazny"
        case .teacher: "Nauczyciel"
        case .professional: "Rzeczowy"
        case .playful: "Z humorem"
        case .custom: "Własny"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .balanced: "Domyślny sposób odpowiadania modelu."
        case .concise: "Krótko i na temat: 1–3 zdania, bez wstępów."
        case .detailed: "Dokładne wyjaśnienia z przykładami i kontekstem."
        case .friendly: "Ciepło, na „ty”, jak dobry znajomy."
        case .teacher: "Krok po kroku, z analogiami i pytaniem na koniec."
        case .professional: "Formalnie, neutralnie i precyzyjnie, bez emoji."
        case .playful: "Z żartem i luzem, ale z poprawnymi informacjami."
        case .custom: "Opisz własnymi słowami, jak model ma do Ciebie mówić."
        }
    }

    var icon: String {
        switch self {
        case .balanced: "circle.lefthalf.filled"
        case .concise: "text.word.spacing"
        case .detailed: "text.book.closed"
        case .friendly: "face.smiling"
        case .teacher: "graduationcap"
        case .professional: "briefcase"
        case .playful: "theatermasks"
        case .custom: "pencil.and.scribble"
        }
    }
}

/// Settings → Styl odpowiedzi: pick how the model talks to you, once, for every conversation.
struct ResponseStyleView: View {
    @Environment(AppSettings.self) private var settings

    static let customExamples: [String.LocalizationValue] = [
        "Mów do mnie na „ty”, krótko i konkretnie. Kod pokazuj bez długich objaśnień.",
        "Tłumacz wszystko tak, jakbym miał 12 lat, z prostymi przykładami.",
        "Odpowiadaj jak doświadczony mentor: szczerze, wskaż słabe punkty mojego pomysłu.",
    ]

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach(ResponseStyle.allCases) { style in
                    Button {
                        settings.responseStyle = style
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: style.icon)
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).foregroundStyle(Theme.textPrimary)
                                Text(style.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.responseStyle == style {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(settings.responseStyle == style ? .isSelected : [])
                }
            } footer: {
                Text("Styl obowiązuje we wszystkich rozmowach, od następnej odpowiedzi. Nie musisz już za każdym razem pisać, jak model ma odpowiadać.")
            }

            if settings.responseStyle == .custom {
                Section {
                    TextEditor(text: $settings.customStyle)
                        .frame(minHeight: 110)
                        .accessibilityLabel(Text("Własny styl"))
                    ForEach(Self.customExamples.map { String(localized: $0) }, id: \.self) { example in
                        Button {
                            settings.customStyle = example
                        } label: {
                            Label { Text(verbatim: example).font(.footnote) } icon: { Image(systemName: "text.badge.plus") }
                        }
                    }
                } header: {
                    Text("Jak model ma do Ciebie mówić?")
                } footer: {
                    Text("Możesz też wybrać przykład i go poprawić. Limit \(ResponseStyle.customLimit) znaków (\(settings.customStyle.count) użyte).")
                }
            }
        }
        .secretBackground()
        .navigationTitle("Styl odpowiedzi")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.customStyle) { _, text in
            if text.count > ResponseStyle.customLimit { settings.customStyle = String(text.prefix(ResponseStyle.customLimit)) }
        }
    }
}
