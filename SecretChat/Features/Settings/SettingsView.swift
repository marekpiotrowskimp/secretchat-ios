import GemmaKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    private static let sampleID = UUID()
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showWebWarning = false
    @Query private var memories: [MemoryItem]
    private var memoryCount: Int { memories.count }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ResponseStyleView()
                    } label: {
                        Label {
                            LabeledContent { Text(settings.responseStyle.title) } label: { Text("Styl odpowiedzi") }
                        } icon: {
                            Image(systemName: settings.responseStyle.icon)
                        }
                    }
                } footer: {
                    Text("Jak model ma do Ciebie mówić: zwięźle, szczegółowo, przyjaźnie… albo po swojemu.")
                }

                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 90)
                    Button("Przywróć domyślny") { settings.systemPrompt = AppSettings.defaultSystemPrompt }
                        .disabled(settings.systemPrompt == AppSettings.defaultSystemPrompt)
                } header: {
                    Text("Prompt systemowy")
                } footer: {
                    Text("Instrukcja, którą model dostaje na początku każdej rozmowy.")
                }

                Section {
                    Toggle("Tryb myślenia", isOn: $settings.thinkingEnabled)
                } footer: {
                    Text("Model najpierw rozumuje (widoczne w zwijanym bloku), potem odpowiada. Lepsze wyniki przy trudnych pytaniach, ale wolniej.")
                }

                Section("Generowanie") {
                    LabeledSlider(title: "Temperatura", value: $settings.temperature, range: 0...2, step: 0.05)
                    LabeledSlider(title: "Top-p", value: $settings.topP, range: 0.05...1, step: 0.05)
                    Stepper(value: $settings.topK, in: 0...200, step: 8) {
                        LabeledContent("Top-k", value: "\(settings.topK)")
                    }
                    Picker("Maks. długość odpowiedzi", selection: $settings.maxTokens) {
                        ForEach(AppSettings.maxTokenOptions, id: \.self) { Text("\($0) tok").tag($0) }
                    }
                    Button("Przywróć zalecane (Gemma)") { settings.resetGeneration() }
                }

                Section {
                    Picker("Długość kontekstu", selection: $settings.contextLength) {
                        ForEach(AppSettings.contextOptions, id: \.self) { Text("\($0 / 1024)K").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(app.isGenerating)
                } header: {
                    Text("Pamięć rozmowy")
                } footer: {
                    if settings.contextLength > 4096 {
                        Label("Dłuższy kontekst zużywa więcej pamięci i spowalnia odpowiedzi w długich rozmowach. Zmiana przeładuje model.", systemImage: "exclamationmark.triangle")
                    } else {
                        Text("Ile tokenów rozmowy model pamięta. Starsze wiadomości są pomijane, gdy się nie mieszczą.")
                    }
                }

                Section("Wyświetlanie") {
                    Toggle("Statystyki pod odpowiedzią", isOn: $settings.showStats)
                }

                Section {
                    Toggle(isOn: $settings.speechAutoRead) {
                        Label("Czytaj odpowiedzi automatycznie", systemImage: "speaker.wave.2")
                    }
                    LabeledSlider(title: "Tempo czytania", value: $settings.speechRate, range: 0.5...2, step: 0.1)
                    Picker("Głos", selection: $settings.speechVoiceID) {
                        Text("Automatyczny (najlepszy dostępny)").tag(String?.none)
                        ForEach(SpeechReader.availableVoices, id: \.identifier) { voice in
                            Text(verbatim: "\(voice.name) · \(voice.language)\(voice.quality == .premium ? " ★★" : voice.quality == .enhanced ? " ★" : "")")
                                .tag(String?.some(voice.identifier))
                        }
                    }
                    Button("Posłuchaj próbki", systemImage: "play.circle") {
                        app.speech.speak(Self.sampleID, markdown: String(localized: "Cześć! Tak brzmią odpowiedzi czytane na głos. Wzór $a^2 + b^2 = c^2$ też przeczytam."))
                    }
                } header: {
                    Text("Czytanie na głos")
                } footer: {
                    Text("Odpowiedzi czyta syntezator mowy iOS, bez internetu. Kod i rozumowanie są pomijane. Lepsze głosy (★) można pobrać w ustawieniach iOS: Dostępność → Treść mówiona → Głosy.")
                }

                Section {
                    Toggle(isOn: $settings.memoryEnabled) {
                        Label("Pamięć długotrwała", systemImage: "brain.head.profile")
                    }
                    NavigationLink {
                        MemoryListView()
                    } label: {
                        LabeledContent("Zapisane wspomnienia", value: "\(memoryCount)")
                    }
                } header: {
                    Text("Pamięć")
                } footer: {
                    Text("Model może zapamiętywać informacje między rozmowami („Zapamiętaj…”, „Zapomnij…”). Każde wspomnienie ma nazwę, opis i treść; model widzi nazwy i opisy, a treść wczytuje tylko, gdy jest potrzebna. Wszystko zostaje na tym telefonie.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.webSearchEnabled },
                        set: { on in if on { showWebWarning = true } else { settings.webSearchEnabled = false } }
                    )) {
                        Label("Wyszukiwanie w internecie", systemImage: "globe")
                    }
                    if settings.webSearchEnabled {
                        Picker("Wyszukiwarka", selection: $settings.searchProvider) {
                            Text(verbatim: "DuckDuckGo").tag(AppSettings.SearchProvider.duckDuckGo)
                            Text("Brave Search (klucz API)").tag(AppSettings.SearchProvider.brave)
                        }
                        if settings.searchProvider == .brave {
                            SecureField("Klucz Brave Search API", text: $settings.braveAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Internet")
                } footer: {
                    if settings.webSearchEnabled {
                        Text("Model zapyta o zgodę przed każdym wyszukiwaniem. Gdy wyszukiwarka zablokuje zapytanie, użyjemy Wikipedii. Klucz Brave jest zapisany w pęku kluczy na tym urządzeniu. To Twój klucz — korzystasz z niego na warunkach Brave Search API (plan musi pozwalać na użycie wyników przez AI).")
                    } else {
                        Text("Wyłączone — aplikacja nie łączy się z internetem (poza pobieraniem modelu).")
                    }
                }

                Section {
                    Picker("Język dyktowania", selection: $settings.dictationLanguage) {
                        Text("Automatyczny (język telefonu)").tag(AppSettings.DictationLanguage.automatic)
                        Text("Polski").tag(AppSettings.DictationLanguage.polish)
                        Text("Angielski").tag(AppSettings.DictationLanguage.english)
                    }
                    Picker("Wysyłanie w trybie głosowym", selection: $settings.autoSendDelay) {
                        Text("Tylko po słowie „wyślij”").tag(0.0)
                        ForEach(AppSettings.autoSendOptions.filter { $0 > 0 }, id: \.self) { delay in
                            Text("Po \(delay.formatted(.number.precision(.fractionLength(1)))) s ciszy").tag(delay)
                        }
                    }
                    Toggle("Czytaj odpowiedzi w trybie głosowym", isOn: $settings.voiceModeReadsAloud)
                } header: {
                    Text("Dyktowanie")
                } footer: {
                    Text("🎤 w polu wiadomości dyktuje tekst. Tryb głosowy (przycisk fali w czacie) sam włącza mikrofon, gdy czat czeka na wiadomość, i wyłącza go, gdy model odpowiada lub czyta. Komendy: „wyślij”, „wyczyść”, „koniec dyktowania”. Rozpoznawanie mowy działa na telefonie, bez internetu.")
                }

                Section("Model") {
                    NavigationLink {
                        ScrollView {
                            ModelPickerSection().padding()
                        }
                        .navigationTitle("Model")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Model", value: app.selectedVariant.displayName)
                    }
                    .disabled(app.isGenerating)
                    LabeledContent("Status", value: engineStatus)
                    LabeledContent("Moduł obrazów", value: app.isVisionReady ? String(localized: "Pobrany") : String(localized: "Nie pobrano"))
                    Toggle("Pobieranie przez sieć komórkową", isOn: $settings.allowCellularDownload)
                    NavigationLink("Diagnostyka i testy wydajności") { DiagnosticsView() }
                }

                Section {
                    Text("SecretChat działa offline. Rozmowy i zdjęcia są przechowywane tylko na tym urządzeniu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Wersja", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    NavigationLink("Licencje i informacje prawne") { LegalView() }
                }
            }
            .sheet(isPresented: $showWebWarning) {
                WebSearchWarningSheet(engine: app.searchEngineName) { settings.webSearchEnabled = true }
            }
            .secretBackground()
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } }
            }
        }
    }

    private var engineStatus: String {
        switch app.engineState {
        case .idle: String(localized: "Nie załadowany")
        case .loading(let p): String(localized: "Ładowanie \(Int(p * 100))%")
        case .ready: String(localized: "W pamięci")
        case .failed(let message): message
        }
    }
}

private struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: value.formatted(.number.precision(.fractionLength(2))))
            Slider(value: $value, in: range, step: step)
        }
    }
}
