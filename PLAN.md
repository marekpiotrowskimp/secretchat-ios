# SecretChat — plan projektu

Czat z modelem **Gemma 4 12B** działającym w 100% lokalnie na iPhone 17 Pro Max (12 GB RAM).

> Dokument żywy: aktualizowany po każdej fazie (status, wyniki testów, zmiany planu).

## Status

| Faza | Status |
|---|---|
| 0 — spike wykonalności | ✅ — zmierzone na iPhone 17 Pro Max (patrz Pomiary) |
| 1 — rdzeń czatu | ✅ |
| 2 — pobieranie modelu | ✅ |
| 3 — historia + Markdown | ✅ |
| 4 — obrazy (vision) | ✅ |
| 5 — ustawienia + tryb myślenia | ✅ |
| 6 — szlify (pamięć/termika/tło, PL/EN, ikona, archiwum Release) | ✅ · TestFlight wymaga rekordu w App Store Connect |
| 7 — wybór modelu (12B / E4B / E2B) z rekomendacją dla telefonu | ✅ · E2B zmierzony tylko na Macu (telefon był zablokowany) |
| 8 — wyszukiwanie w internecie za zgodą (+ poprawka zdjęć, wzory LaTeX) | ✅ na Macu/symulatorze · ⏳ prawdziwe wyszukiwanie na iPhonie |
| 9 — czytanie odpowiedzi na głos | ✅ |
| 10 — dyktowanie i tryb głosowy | ✅ |
| 11 — pamięć długotrwała między rozmowami | ✅ |

## Decyzje

| Obszar | Wybór |
|---|---|
| Modele | **Gemma 4 12B / E4B / E2B (QAT, UD-Q4_K_XL)** — wybór w aplikacji, rekomendacja wg RAM telefonu (12 / 8 / 6 GB). Pierwotnie: **Gemma 4 12B-it QAT**, wyłącznie. `unsloth/gemma-4-12B-it-qat-GGUF` → `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` (6,72 GB, Apache 2.0). Fallback pamięciowy (ten sam model): `unsloth/gemma-4-12b-it-GGUF` IQ4_XS (6,38 GB) → Q3_K_M (5,69 GB) — zmiana w `ModelCatalog`. |
| Vision | `mmproj-F16.gguf` (0,18 GB), ładowany leniwie, zwalniany przy memory warning. |
| Silnik | **llama.cpp `b11345`**, xcframework **budowany ze źródeł** (ios, ios-simulator, macos) — oficjalny zip nie ma symulatora. Metal + mmap, `swa_full=false`, vision przez `mtmd`. |
| UI | SwiftUI, iOS 26, Swift 6 (strict concurrency, MainActor domyślnie), PL + EN (String Catalog). |
| Dane | SwiftData (Conversation / StoredMessage / MessageAttachment z external storage). Wszystko lokalnie. |
| Model w aplikacji | Background `URLSession`, wznawianie (resume data), SHA-256, `isExcludedFromBackup`, import z Documents (Pliki/devicectl). |
| Konto | Team `JMMW48F6X4`, entitlement `increased-memory-limit` ✅. `extended-virtual-addressing` odrzucony przez automatyczny provisioning — niepotrzebny przy mmap, do włączenia w portalu tylko jeśli pomiary pokażą problem. |
| Kontekst | 4K domyślnie, 8K/16K w ustawieniach. Przy przepełnieniu pomijane najstarsze tury (cięcie do 70% budżetu, żeby rzadko powtarzać pełny prefill). |

## Architektura

```
GemmaKit (Swift Package, testowany na macOS)
├─ Engine/
│   ├─ LlamaEngine        actor na własnej kolejce; load/unload, loadVision, chat(), generate(), stopGeneration()
│   │                      KV cache reuse: jeśli nowy prompt zaczyna się od już przetworzonego tekstu → prefill tylko sufiksu
│   ├─ GemmaPromptBuilder  format Gemma 4 1:1 z szablonem Jinja z GGUF (fixtures w testach)
│   ├─ ContextWindow       przycinanie historii do budżetu tokenów
│   ├─ ModelOutputParser   rozdział <|channel>thought…<channel|> / odpowiedź po tokenach specjalnych + UTF8Accumulator
│   ├─ ImageDecoder        HEIC/JPEG/PNG → RGB (sRGB) dla mtmd; miniatury JPEG do zapisu
│   └─ EngineTypes         konfiguracja, sampling, statystyki, zdarzenia, błędy (PL/EN)
├─ ModelStore/            katalog modeli, pobieranie w tle, weryfikacja, import
├─ Markdown/              parser bloków (kod, listy, tabele, cytaty) odporny na streaming
└─ Diagnostics/           footprint, os_proc_available_memory, termika

SecretChat (iOS)
├─ App/        SecretChatApp (SwiftData, scenePhase → stop w tle), AppDelegate (background URLSession),
│              AppModel (store + silnik + memory warning + termika), AppSettings (UserDefaults)
├─ Data/       modele SwiftData
└─ Features/   Onboarding (pobieranie), Conversations (lista), Chat (VM, widok, Markdown, kompozytor ze zdjęciami),
               Settings, Diagnostics (benchmarki na urządzeniu)
```

Kluczowy pomysł: każda odpowiedź zapisuje `rawModelTurn` — dokładny tekst tury modelu (z tokenami specjalnymi). Kolejny prompt odtwarza historię bajt w bajt, więc jest przedłużeniem tego, co już siedzi w KV cache → następna tura przetwarza tylko nową wiadomość użytkownika (na iPhonie: ułamek sekundy zamiast kilkudziesięciu sekund).

## Testy

| Zestaw | Gdzie | Co |
|---|---|---|
| `GemmaKit` (`swift test`) | macOS, prawdziwy model 12B | 51 testów ✅ (+1 sieciowy, `NETWORK_TESTS=1`: prawdziwe pobranie mmproj z HF + SHA ✅): prompt vs Jinja, parser, UTF-8, przycinanie, Markdown, ModelStore (pobieranie/SHA/import), dekoder obrazów, silnik: odpowiedzi PL, KV reuse, thinking, Stop (w generacji i w prefillu), overflow, vision (kolor obrazu + follow-up z cache), unload |
| `SecretChatTests` | symulator iOS, prawdziwy model | 10/10 ✅ — SwiftData (kolejność, tytuły, kaskady, statystyki), ustawienia, ChatViewModel end-to-end: 2 tury z cache, Stop z zapisem częściowej odpowiedzi, zdjęcie, tryb myślenia |
| `SecretChatUITests` | symulator iOS | 2/2 ✅ — pełny przepływ po polsku (nowa rozmowa → odpowiedź → Markdown → lista → ustawienia) + lokalizacja EN, zrzuty ekranu |
| `scripts/gen_strings.py` | build | pokrycie tłumaczeń (błąd przy brakującym EN) |
| Archiwum Release | `xcodebuild archive` | build produkcyjny na urządzenie |

Symulator: wirtualizowany Metal okazał się bezużyteczny dla ggml (13 min bez żadnego tokenu) → w symulatorze silnik liczy wyłącznie na CPU Maca (`gpuLayers=0`, ~7 tok/s), na urządzeniu Metal. Zrzuty ekranu z testów UI: `build/screens/` (po `xcresulttool export attachments`).

## Pomiary

**Mac M4 Pro (punkt odniesienia):** pp512 299 tok/s, tg128 31,5 tok/s, footprint po załadowaniu 1,69 GB (mmap), z vision 2,19 GB.

**Pamięć KV (16K kontekstu):** `swa_full=true` 5376 MiB → `swa_full=false` **736 MiB**. 40 z 48 warstw to sliding window 1024 — trzymają tylko ostatnie 1024 tokeny. Dzięki temu 16K jest realne na telefonie.

**Prognoza iPhone 17 Pro Max:** ~8–10 tok/s generowania (przepustowość pamięci A19 Pro ~77 GB/s vs 273 GB/s M4 Pro), prefill ~60–100 tok/s.

**iPhone 17 Pro Max (zmierzone 2026-10-02, kontekst 4K, KV q8_0):**

| Model | Test | Prefill | Generowanie | Footprint procesu |
|---|---|---|---|---|
| 12B | benchmark (632 tok) | 183–200 tok/s | **8,0–8,4 tok/s** | 0,81–0,86 GB |
| 12B | obraz (234 tok) | 91 tok/s | **9,0 tok/s** | 0,93 GB |
| E4B | benchmark (628 tok) | 506 tok/s | **21,5 tok/s** | 1,35 GB |
| E4B | obraz (253 tok) | 174 tok/s | **21,9 tok/s** | 1,30 GB |
| E2B | — | do zmierzenia | — | — |

Footprint jest mały, bo wagi są mmapowane (Metal „Mapped” buffers). Ograniczeniem jest **limit GPU `recommendedMaxWorkingSetSize` = 8,59 GB**, nie RAM procesu: 12B (6,39 GB wag) + KV + bufory + obraz go przekraczało.

Pozostało do zmierzenia na telefonie: E2B (`GEMMA_AUTORUN=vision,bench`, `-selectedModelID gemma-4-e2b`), test 10 min (termika), kontekst 8K/16K.

## Faza 7 — wybór modelu

- `ModelCatalog.variants`: 12B (wymaga 12 GB RAM, telefony: iPhone 17 Pro / Pro Max / Air), E4B (8 GB: iPhone 15 Pro, 16, 16 Pro, 16e, 17), E2B (6 GB: iPhone 13 Pro, 14, 15).
- `DeviceProfile.current`: RAM z `ProcessInfo.physicalMemory` zaokrąglony w górę do pojemności katalogowej + nazwa modelu z identyfikatora (`iPhone18,2` → iPhone 17 Pro Max).
- Rekomendacja = największy model, którego wymaganie spełnia telefon; jest zaznaczony domyślnie i oznaczony „Najlepszy dla Twojego telefonu”. Za duże modele: pomarańczowe ostrzeżenie „Twój telefon może nie podołać…” + „Zalecany telefon: …”, a pobranie wymaga potwierdzenia (z opcją przejścia na rekomendowany). Telefon poniżej minimum (4 GB) dostaje czerwone ostrzeżenie.
- Moduł obrazów opcjonalny (E-modele: 0,99 GB, bo zawiera też audio); można go dograć z „+” w czacie albo w Ustawienia → Model.
- Format promptu wykrywany z szablonu w GGUF (`PromptFormat.detect`): 12B prefilluje pusty kanał myślenia, E-modele nie — oba zweryfikowane fixtures z oryginalnych szablonów Jinja.
- Testy: `DeviceFitTests` (RAM → rekomendacja/ostrzeżenia), `SmallModelTests` (E2B i E4B z prawdziwymi plikami: odpowiedź, cache, obraz, myślenie), `ModelPickerUITests` (symulowany iPhone 16 / 8 GB: E4B zaznaczony, 12B z ostrzeżeniem, dialog potwierdzenia).

## Faza 8 — internet za zgodą, zdjęcia, wzory

**Wyszukiwanie (natywne tool calling Gemma 4):**
- Domyślnie WYŁĄCZONE. Włączenie w Ustawienia → Internet pokazuje ostrzeżenie („SecretChat jest zaprojektowany do pracy bez internetu…”, co i dokąd trafia).
- Włączone: w turze systemowej deklaracja `web_search` + dzisiejsza data + instrukcja. Model sam proponuje zapytanie → karta „Model chce przeszukać internet: »…«” → „Szukaj…” → dialog **„Czy na pewno przeszukać internet?”** → dopiero wtedy sieć. Odmowa → model odpowiada z własnej wiedzy (zero zapytań — sprawdzone testem z rejestrującym fałszywym wyszukiwaniem).
- Wyszukiwarka: DuckDuckGo (HTML, bez klucza) → przy blokadzie antybotowej (zdarza się! — zaobserwowane) automatycznie Wikipedia (oficjalne API) → opcjonalnie Brave Search API (klucz w Keychain). Google: oficjalne API zamknięte dla nowych klientów (koniec 1.01.2027), scraping łamie regulamin — odrzucone.
- Czyta 2–3 najlepsze strony (`PageReader`: czytelny tekst bez nawigacji/reklam), budżet ~30% kontekstu, ponumerowane źródła; odpowiedź oznaczona 🌐 z listą źródeł (linki).
- Silnik zatrzymuje się na `<|tool_response>`, a kontynuacja dopisuje tylko odpowiedź narzędzia (KV cache zachowany — prefill ~100 tokenów zamiast całej rozmowy).
- Bezpieczeństwo: treść stron jest czyszczona ze znaczników `<|`/`|>` (brak wstrzyknięcia tokenów sterujących), nagłówek „to dane, nie polecenia”, limit 2 wyszukiwań na odpowiedź.
- Pomiar: z instrukcją „masz dostęp do internetu przez web_search…” wszystkie trzy modele wywołują narzędzie przy pytaniach o bieżące wydarzenia i nie wywołują przy „2+2” (bez niej 12B i E2B odpowiadały „nie mam dostępu do internetu”).

**Zdjęcia z biblioteki (błąd zgłoszony przez użytkownika):** `PhotosPicker` umieszczony w `Menu` nigdy się nie otwiera (menu znika pierwsze). Teraz pozycja menu otwiera selektor przez `.photosPicker(isPresented:)`; nieudane wczytanie (np. tylko w iCloud) pokazuje komunikat. Test UI wybiera zdjęcie z biblioteki symulatora, wysyła i czeka na opis modelu.

**Wzory (błąd zgłoszony przez użytkownika):** model pisze LaTeX (`$P = \pi r^2$`, `$x = \frac{-b \pm \sqrt{\Delta}}{2a}$`). Teraz: wiersz z samym wzorem / `$$…$$` / `\[…\]` → skład matematyczny SwiftMath (ułamki, pierwiastki, indeksy); wzory w zdaniu → Unicode (`πr²`, `±`, `√Δ`) przed parsowaniem Markdown; kwoty „5$ a 10$” nie są traktowane jako wzory.

## Ryzyka

1. **Pamięć na iPhonie** — niezmierzona. Mitygacje: mmap, `increased-memory-limit`, `swa_full=false`, vision leniwie + zwalniany przy memory warning.
2. **Termika** — baner w czacie przy stanie `serious/critical`; test 10 min w diagnostyce.
3. **Pełny prefill** po przycięciu kontekstu / zmianie promptu systemowego / przełączeniu trybu myślenia / zmianie rozmowy — pasek postępu „Przetwarzanie rozmowy…”, przerwanie możliwe.
4. **Praca w tle** — iOS zabrania GPU w tle → przy przejściu w tło generacja (i prefill) kończy się łagodnie, częściowa odpowiedź zostaje zapisana.

## Dziennik postępu

### 2026-10-02 — Faza 0
- Model + llama.cpp pobrane, SHA-256 OK; sanity check `llama-completion` po polsku OK; szablon czatu odczytany z GGUF.
- `LlamaEngine`, `GemmaPromptBuilder`, parser wyjścia, aplikacja z ekranem diagnostyki, `increased-memory-limit` działa.
- Wnioski: ggml-metal asertuje przy wyjściu z niezwolnionym modelem → `unload()`; `llama_decode` na Metal jest asynchroniczne → `llama_synchronize` przed pomiarem.

### 2026-10-02 — Fazy 1–6
- **Silnik:** `chat()` z przycinaniem kontekstu, `stopGeneration()` (też w trakcie prefillu), postęp prefillu, vision przez mtmd (obrazy w KV cache przeżywają kolejne tury), `swa_full=false` (7× mniej pamięci KV przy 16K).
- **ModelStore:** pobieranie w tle z wznawianiem, SHA-256, sidecar `.sha256` (bez ponownego hashowania 7 GB przy starcie), import z Documents.
- **Aplikacja:** onboarding pobierania, lista rozmów (bez pustych), czat ze streamingiem, Markdown (kod z kopiowaniem, tabele, listy), zdjęcia (biblioteka + aparat, kompresja do 1536 px JPEG), tryb myślenia (przełącznik w pasku + zwijany blok), statystyki, ustawienia, baner termiczny, memory warning → zwolnienie vision, Stop przy przejściu w tło, blokada równoległych generacji.
- **Szlify:** ikona (bez alfy), kolor akcentu, PL/EN (111 tekstów), opis uprawnienia aparatu PL/EN, archiwum Release OK (12 MB).
- **Weryfikacja:** GemmaKit 51/51, aplikacja 10/10 (w tym 4 end-to-end z modelem 12B: dwie tury z cache, Stop, zdjęcie, tryb myślenia), UI 2/2 (PL przepływ + EN), pokrycie tłumaczeń 100%, archiwum Release OK, realne pobranie z HF OK.
- **Znalezione i naprawione w trakcie:** Metal w symulatorze nie działa (→ CPU); pusta odpowiedź modelu była niewidoczna (→ komunikat + „Spróbuj ponownie”); separator dziesiętny w statystykach nie był lokalizowany; konwersja kolorów DeviceRGB → sRGB w dekoderze obrazów; Stop nie przerywał prefillu (ryzyko crasha GPU w tle); możliwość wysłania wiadomości w drugiej rozmowie podczas generowania; puste rozmowy na liście; szum CoreData przy pierwszym starcie.

### 2026-10-02 — Crash na iPhonie, obrazy na iPhonie, faza 7
- **Crash po pobraniu modelu (zgłoszony przez użytkownika):** weryfikacja SHA-256 czytała plik kawałkami 8 MB, ale każdy kawałek (autoreleased `Data`) żył do końca pętli → haszowanie 6,7 GB zużywało 6,7 GB RAM → iOS zabijał aplikację (na Macu i w symulatorze bez limitu — dlatego „działało”). Poprawka: `autoreleasepool` na kawałek (szczyt 10 MB zamiast 6,7 GB, zmierzone). Dodatkowo przerwana weryfikacja jest wznawiana przy starcie — na telefonie użytkownika plik 6,26 GB zweryfikował się w ~10 s bez ponownego pobierania. Test regresji: haszowanie 1,5 GB nie może zwiększyć pamięci o > 750 MB.
- **Obrazy na iPhonie:** `kIOGPUCommandBufferCallbackErrorOutOfMemory` — przekroczony limit GPU 8,59 GB. Poprawka: KV cache q8_0 (−270 MB) i maks. 256 tokenów obrazu; po błędzie GPU silnik zwalnia model (ggml-metal zostaje w stanie błędu) i następna wiadomość ładuje go od nowa.
- **Testy na prawdziwym iPhonie:** `OnDeviceTests` (XCUITest: czat z 12B → odpowiedź, rekomendacja 12B w wyborze modelu, benchmark w Diagnostyce) + tryb `GEMMA_AUTORUN` (DEBUG) do pomiarów z konsolą `devicectl`.
- **Błąd w narzędziach:** `gen_strings.py` potrafił nadpisać katalog tłumaczeń pustym (stare dane ekstrakcji po innym buildzie) — teraz sam buduje do osobnego DerivedData i odmawia zapisu pustego katalogu. `device.sh` miał błędną składnię zsh przy `copy from/to`.
- **Wyniki:** GemmaKit 62/62, aplikacja 10/10 (symulator, z modelem), UI 3/3 (symulator), na iPhonie: czat + benchmark + obraz OK dla 12B i E4B.

### 2026-10-02 — Faza 8: internet za zgodą, zdjęcia, wzory
- Zaimplementowane jak wyżej; GemmaKit 89/89 (w tym tool calling na 12B/E4B/E2B, parser DuckDuckGo na prawdziwej odpowiedzi i stronie blokady, Wikipedia, Brave, PageReader na prawdziwej stronie Wikipedii, LaTeX→Unicode), `NETWORK_TESTS=1`: prawdziwe DuckDuckGo + łańcuch zapasowy OK.
- Aplikacja (symulator, prawdziwy model): przepływ wyszukiwania — wyłączone / zgoda / odmowa; UI: ostrzeżenie przy włączaniu, karta zgody, „Czy na pewno?”, 🌐 + źródła; zdjęcie z biblioteki → opis; renderowanie wzorów.
- Znalezione po drodze: DuckDuckGo blokuje częste zapytania z jednego IP (stąd Wikipedia jako zapas); `<[^>]+>` nie radzi sobie z `>` w atrybutach Wikipedii (poprawione); E2B przestawał używać narzędzia przy dłuższej instrukcji systemowej (instrukcje o cytowaniu przeniesione do nagłówka odpowiedzi narzędzia).

### 2026-10-03 — Zawieszenia, migotanie ekranu, restart przez watchdog (zgłoszone przez użytkownika)
**Dowody z telefonu** (`build/device-logs/`): `panic-full` — *busy timeout (60 s) … AppleAPFSMediaBSDClient* (dysk zablokowany → watchdog), 4× JetsamEvent z `proc-thrashing` / `vm-compressor-thrashing`, `ExcUserFault_SpringBoard`. Pamięć **wired** systemu: 1,8 GB bez modelu → **7,3–10,7 GB** z 12B, wolne ~60 MB.

**Przyczyna:** ggml-metal domyślnie trzyma wszystkie bufory modelu w *residency sets* i co 5 ms ponawia żądanie rezydencji aż do 3 min po ostatnim obliczeniu — 6,4 GB wag 12B jest stale *wired* (nawet po zwolnieniu modelu!). Pamięć wired GPU nie wlicza się do footprintu aplikacji (0,6 GB), więc iOS nie mógł odzyskać jej zabijając SecretChat — zabijał wszystko inne, wyrzucał kod systemu, a doczytywanie stron zablokowało APFS. To nie było nadpisywanie pamięci przez nasz kod.

**Audyt kodu** (wskaźniki do C, bufory, czasy życia): `llama_decode` kopiuje tokeny do własnego batcha, `mtmd_bitmap_init` kopiuje piksele (memcpy), `withCString`/`withUnsafe…` używane tylko w obrębie wywołań, `ProgressBox` żyje przez `withExtendedLifetime` w czasie ładowania — poprawne. Znalezione ryzyko: usunięcie pliku modelu, gdy jest zmapowany → SIGBUS; teraz silnik jest zawsze zwalniany przed usunięciem plików. (Wcześniej naprawiony wyciek przy SHA-256.)

**Pomiary na iPhone 17 Pro Max** (`GEMMA_AUTORUN=memprofile`, wired systemu):

| Wariant | szczyt podczas odpowiedzi | bezczynność | po zwolnieniu | tok/s |
|---|---|---|---|---|
| 12B, residency (stara wersja) | 9,56 GB | **9,39 GB** | **9,38 GB** | 8,4 |
| 12B, bez residency (nowa) | 9,46 GB | 1,70 GB | 1,69 GB | 8,5 |
| 12B, 36/48 warstw GPU | 9,25 GB | 1,65 GB | — | 6,4 (nie warto) |
| E4B, bez residency | 6,61 GB | 1,67 GB | — | 20,9 |
| E2B, bez residency | 4,89 GB | 1,65 GB | — | 40,1 |

**Poprawki:** `GGML_METAL_NO_RESIDENCY` na iOS (pamięć wired tylko podczas liczenia); przerwanie generowania przy krytycznym ciśnieniu pamięci systemu (+ komunikat); zwolnienie silnika przed usunięciem plików.

**Decyzja użytkownika:** na telefonach z 12 GB rekomendowany **E4B**, 12B dostępny jako **eksperymentalny** (szczyt 7,8 GB ponad bazę systemu). Reguła: komfortowo, gdy szczyt ≤ ~45–50% RAM → 12B: 16 GB, E4B: 12 GB, E2B: 8 GB; telefony 8 GB: E2B rekomendowany, E4B eksperymentalny (niezmierzone na urządzeniu — ustawienie ostrożne). Wybór użytkownika (12B) pozostaje.

### 2026-10-03 — Faza 9: czytanie odpowiedzi na głos
- Syntezator mowy iOS (`AVSpeechSynthesizer`) — offline, bez rozpoznawania mowy (to nie rozmowa głosowa).
- 🔊 pod każdą odpowiedzią (i w menu kontekstowym), przycisk zatrzymania w pasku czatu.
- „Czytaj odpowiedzi automatycznie" (domyślnie wyłączone): `SpeechStreamer` oddaje pełne zdania w trakcie generowania — nigdy w środku otwartego wzoru `$…$` ani bloku kodu.
- `SpeechText`: bez składni Markdown i numerów źródeł, wzory słowami („P równa się pi r do kwadratu"), kod pominięty, rozumowanie nieczytane; język odpowiedzi wykrywany (`NLLanguageRecognizer`, PL/EN) → najlepszy zainstalowany głos; tempo i wybór głosu w ustawieniach.
- Audio w tle (`UIBackgroundModes: audio`), sesja `.playback/.spokenAudio` z przyciszaniem muzyki.
- Testy: GemmaKit 99/99; aplikacja: lektor (przełączanie, strumień, język), auto-czytanie z prawdziwym modelem, UI.

### 2026-10-03 — Faza 10: dyktowanie i tryb głosowy
- Rozpoznawanie mowy: Apple `DictationTranscriber` + `SpeechAnalyzer` (iOS 26), **wyłącznie offline**. Sprawdzone na iPhone 17 Pro Max: `DictationTranscriber` ma zainstalowany `pl_PL` i `en_US` (nowszy `SpeechTranscriber` — tylko `en_US`; na Macu brak polskiego offline). Polskie nagranie rozpoznane na telefonie w 0,1–0,2 s.
- 🎤 w polu wiadomości: dyktowanie na żywo do pola (dopisywane do już wpisanego tekstu, można poprawić przed wysłaniem).
- **Tryb głosowy** (przycisk fali w czacie): mikrofon włącza się sam, gdy czat czeka na wiadomość; wysyła po pauzie (1,5/2,5/4 s lub tylko na „wyślij”); **wyłączony, gdy model odpowiada i gdy czyta odpowiedź** (brak nagrywania lektora); po odpowiedzi znów słucha; po 45 s ciszy wyłącza się sam; karta zgody na internet wymaga dotyku. Opuszczenie czatu kończy tryb (mikrofon nigdy nie działa „w tle”).
- Komendy na końcu wypowiedzi: „wyślij”, „wyczyść”, „koniec dyktowania” (+ angielskie) — tylko jako ostatnie słowa („wyślij mi przepis” to zwykły tekst).
- Sygnały: dźwięk + wibracja przy starcie/końcu słuchania, wskaźnik głośności.
- Testy: komendy (GemmaKit), prawdziwe rozpoznawanie nagrania `say` (Mac, EN) i na iPhonie (PL), pętla trybu głosowego z prawdziwym modelem (wstrzykiwana transkrypcja), UI. GemmaKit 103/103, aplikacja 22/22, UI 9/9.

### 2026-10-03 — Crash mikrofonu, nowa nazwa SecretChat, kolorystyka
- **Crash przy włączaniu mikrofonu** (raport z telefonu: `dispatch_assert_queue_fail` w domknięciu `installTap`, wątek `RealtimeMessenger`): domknięcie utworzone w typie `@MainActor` Swift 6 uznawał za izolowane na wątku głównym, a AVFAudio woła je z wątku audio → SIGTRAP. Przechwytywanie przeniesione do `nonisolated` `MicrophoneCapture` z callbackiem `@Sendable`. Testy: prawdziwy mikrofon poza wątkiem głównym, prawdziwy `DictationService.start()`. Na iPhonie: polska mowa z głośnika rozpoznana na żywo.
- **Zgoda `SFSpeechRecognizer` usunięta:** jej systemowy dialog mówi, że mowa jest wysyłana do Apple, a `DictationTranscriber` jej nie potrzebuje (test na symulatorze bez tej zgody rozpoznaje nagranie). Aplikacja pyta tylko o mikrofon.
- **Nazwa: SecretChat** (nazwa wyświetlana; bundle ID bez zmian, żeby nie stracić danych i pobranych modeli). Hasło: „Prywatny czat AI. Bez internetu.”
- **Kolorystyka „secret”:** zawsze ciemny wygląd, tło nocne (#070B12→#0E1726), karty grafitowe, akcent szmaragdowy (#2BD9A0), dymki użytkownika w gradiencie szmaragdowym; pomarańcz zarezerwowany dla internetu. Znaczek **„🔒 W pełni offline” / „🌐 Internet na żądanie”** na liście rozmów. Nowa ikona: neonowy dymek z kłódką.
- Testy: aplikacja 26/26, UI 9/9, GemmaKit 103/103.

### 2026-10-04 — Faza 11: pamięć długotrwała między rozmowami
- **Wspomnienie = nazwa + opis + treść** (`MemoryItem` w SwiftData, lokalnie na telefonie). Do promptu trafia tylko **indeks „nazwa: opis”** (maks. 40, ostatnio używane najpierw) — po opisie model decyduje, czy wczytać treść.
- Trzy narzędzia (natywne tool calling Gemma 4, zawsze lokalne, bez pytania o zgodę): `memory_save(name, description, content)`, `memory_read(name)`, `memory_delete(name)`. „Zapamiętaj pod nazwą X…” → zapis pod X; bez nazwy model nadaje ją sam. Ta sama nazwa → aktualizacja.
- Instrukcja: „jeśli któreś wspomnienie może pomóc, najpierw wywołaj memory_read — nie zgaduj treści”. Zmierzone na 12B/E4B/E2B: zapis z nazwą i bez, odczyt przy pasującym pytaniu („Jak ma na imię mój pies?” → „Pimpek”), brak odczytu przy „2+2”, usunięcie na „zapomnij”.
- Nazwy dopasowywane tolerancyjnie (wielkość liter, polskie znaki, interpunkcja); przy chybieniu model dostaje podpowiedzi podobnych nazw. Limit 6 wywołań narzędzi na odpowiedź.
- **KV cache:** indeks jest zamrażany per rozmowa (`Conversation.memoryIndexData`) — zapis w trakcie rozmowy nie zmienia promptu systemowego, więc cache zostaje; nowe wspomnienia widać w kolejnych rozmowach (a w bieżącej model zna je z wywołania).
- UI: pod odpowiedzią znaczniki z ikoną (zapisano / zaktualizowano / wczytano / usunięto / brak — z nazwą wspomnienia); Ustawienia → Pamięć: przełącznik (wyłączona = narzędzia niezadeklarowane), lista wspomnień, dodawanie, edycja, usuwanie.
- Bezpieczeństwo: treść wspomnień czyszczona ze znaczników sterujących `<|`/`|>`.
- Testy: GemmaKit (prompt = fixture z Jinja, dopasowanie nazw, integracja z 3 modelami; testy na prawdziwych modelach zgrupowane w jednym szeregowym zestawie `RealModelTests`, by nie walczyły o GPU), aplikacja `MemoryFlowTests` (zapis w jednej rozmowie → odczyt „Burek” w nowej → zapomnienie; cache zachowany przy zapisie; wyłączona pamięć nic nie zapisuje), UI `MemoryUITests`.

### 2026-10-04 — Pamięć na iPhonie nie działała; przewijanie czatu
- **Test na telefonie (E4B) wykrył błąd, którego nie złapały testy:** E4B pisał wywołanie jako zwykły tekst (`memory_save(name='…')`) albo odpowiadał „Zapisuję!” bez zapisu. Przyczyna: testy integracyjne liczyły zachłannie (T=0), a aplikacja losuje z temperaturą użytkownika (T=1). Pomiar przy T=1: E4B zapisywał 14/20, E2B wczytywał pamięć 2/20.
- **Poprawka w silniku:** gdy zadeklarowane są narzędzia, decyzja „wywołać narzędzie czy pisać” (pierwszy token odpowiedzi i pierwszy po zakończeniu myślenia) oraz treść wywołania są wybierane zachłannie; reszta odpowiedzi — z ustawień użytkownika. Dotyczy też wyszukiwania w internecie.
- **Instrukcja pamięci** doprecyzowana („informacje, które użytkownik kazał Ci zapamiętać w poprzednich rozmowach… gdy pytanie dotyczy czegoś z listy, najpierw memory_read… nie pytaj o to użytkownika”) — E2B przy domyślnym prompcie aplikacji pytał użytkownika zamiast czytać pamięć.
- Wynik przy T=1, 10 prób na przypadek, prompt aplikacji: 12B / E4B / E2B — zapis 10/10, odczyt imienia 10/10, odczyt rasy 10/10; „2+2” i „napisz wiersz” — 0 wywołań. Testy integracyjne pamięci i internetu działają teraz w warunkach aplikacji (T=1, domyślny prompt).
- Koszt pamięci zmierzony na iPhonie (E4B): pierwsza wiadomość 452 zamiast 51 tokenów promptu, prefill 0,9 s zamiast 0,3 s; potem cache.
- **Przewijanie (zgłoszone przez użytkownika):** przy kolejnych pytaniach czat potrafił przewinąć się daleko pod wiadomości (pusty ekran). Przyczyna: `LazyVStack` zna tylko szacowaną wysokość nieułożonych wiadomości, więc „dół” liczony był źle przy wysokich odpowiedziach (Markdown, kod, wzory). Teraz zwykły `VStack` (dokładne wysokości), jawne przewinięcie na dół po wysłaniu pytania i po odpowiedzi, przypięcie do dołu przy zmianie rozmiaru. Test UI `ChatScrollUITests` (długa rozmowa, dwa pytania) przed poprawką: pytanie poza ekranem; po poprawce: widoczne.
- Diagnostyka na telefonie: `GEMMA_AUTORUN=memory` (koszt promptu + zapis → odczyt → zapomnienie na prawdziwym modelu).

### 2026-10-04 — Licencje i ramy prawne
- **Gemma 4 = Apache 2.0** (od 2.04.2026); „Gemma Terms of Use” i polityka zakazanych zastosowań wprost nie dotyczą Gemma 4. Repozytoria Google/Unsloth: `apache-2.0`, bez NOTICE, bez akceptowania warunków. Aplikacja nie zawiera wag (pobierane z Hugging Face) — i tak pokazujemy licencję i autora.
- Nowy ekran **Ustawienia → Licencje i informacje prawne**: Gemma 4 (Apache 2.0, pełny tekst), llama.cpp/ggml (MIT), miniaudio, stb_image, SwiftMath (MIT), Latin Modern Math (GUST); informacja o znaku „Gemma” i braku powiązania z Google; komunikat, że odpowiedzi generuje AI. Przy wyborze modelu: licencja + link.
- Wikipedia: własny User-Agent (zasady Wikimedia) zamiast udawania Safari. Brave: informacja, że klucz jest użytkownika i plan musi pozwalać na użycie wyników przez AI.
- Analiza i otwarte decyzje: `docs/LICENCJE.md`. Test UI: `LegalUITests`.

### 2026-10-04 — Pożegnanie z nazwą GemmaChat
- Projekt, cele, schemat, katalogi (`SecretChat/`, `SecretChatTests/`, `SecretChatUITests/`), klasa `SecretChatApp` i **bundle ID `com.marekpiotrowski.SecretChat`** (także usługa Keychain i sesja pobierania w tle). Wewnętrzna biblioteka silnika zostaje `GemmaKit` — opisuje, że obsługuje modele Gemma; użytkownik jej nie widzi.
- Nowy bundle ID = nowa aplikacja na telefonie. Dane przeniesione z poprzedniej instalacji (rozmowy, pamięć, ustawienia, model E4B + moduł obrazów; sumy SHA-256 zgodne) — sprawdzone diagnostyką `GEMMA_AUTORUN=datastats`. Klucz Brave (Keychain) nie przechodzi — trzeba go wpisać ponownie.
- Uwaga przy ręcznym przenoszeniu bazy SwiftData: katalog `.default_SUPPORT/_EXTERNAL_DATA` musi istnieć (nawet pusty), inaczej Core Data rzuca wyjątek przy pierwszym zapytaniu.

### 2026-10-04 — Styl odpowiedzi; ikona lektora
- **Ustawienia → Styl odpowiedzi** (na górze ustawień): Zrównoważony (domyślny, nic nie dodaje), Zwięzły, Szczegółowy, Przyjazny, Nauczyciel, Rzeczowy, Z humorem oraz **Własny** — użytkownik sam opisuje, jak model ma do niego mówić (limit 600 znaków, 3 przykłady do wybrania i poprawienia, tekst czyszczony ze znaczników sterujących). Styl to jedna instrukcja dopisana do promptu systemowego (`ResponseStyle` w GemmaKit, `AppSettings.styledSystemPrompt`); działa we wszystkich rozmowach od następnej odpowiedzi. Aktywny styl widać na ekranie nowej rozmowy.
- Zmierzone przy T=1 na 12B/E4B/E2B („Czym jest fotosynteza?”): Zwięzły ≈ 230–280 znaków zamiast ≈ 2100; Własny „mów jak pirat, zaczynaj od Ahoj!” — wszystkie trzy zaczynają od „Ahoj!”; Rzeczowy bez emoji, Przyjazny/Z humorem z emoji i żartami; pamięć (memory_save) działa przy ustawionym stylu.
- Testy: `ResponseStyleIntegrationTests` (3 modele), `AppSettingsTests`, `conciseStyleShortensTheAnswer` (aplikacja + prawdziwy model), `ResponseStyleUITests`.
- **Ikona lektora** (zgłoszone przez użytkownika): podczas czytania pasek pokazywał przekreślony głośnik (sugerował wyciszenie). Teraz zielony głośnik z animowanymi falami = „czytam”; dotknięcie zatrzymuje (etykieta dostępności „Zatrzymaj czytanie”).

### 2026-10-04 — Awaria w flash attention (Xcode); style psuły pamięć
- **Awaria (zgłoszona ze zrzutem z Xcode):** `MTLDebugComputeCommandEncoder setThreadgroupMemoryLength: length(36864) must be <= 32768`. Błąd llama.cpp b11345: porcja 20–31 tokenów (za duża dla kernela „vec”, za mała dla konwersji KV do f16) szła kernelem na skwantyzowanym KV Q8_0, który dla głowic 512 (warstwy globalne Gemma 4) potrzebuje 36 864 B pamięci wątku przy limicie 32 768 B. Xcode (walidacja Metal) przerywał; bez niej skutek niezdefiniowany (prawdopodobnie wcześniejsze `decodeFailed -3`). Poprawka `scripts/patches/llama-fa-head512-smem.patch` (dla głowic ≥ 512 KV dekwantyzowane do f16 także przy 20–31 tokenach), nakładana przez `bootstrap.sh` (niepasująca poprawka zatrzymuje budowanie). Test `FlashAttentionBatchTests` (porcje 18–34 tokenów, 3 modele) — przed poprawką odtwarzał awarię z `MTL_DEBUG_LAYER=1`; cały GemmaKit przechodzi z walidacją Metal.
- **Style psuły narzędzia:** na iPhonie ze stylem „Zwięzły” E4B pisał `memory_save(...)` tekstem. Pomiar p(`<|tool_call>`) w punkcie decyzji: „Przyjazny” → 0,00 nawet dla 12B; E4B bez stylu tylko 0,48. Poprawki: styl na końcu promptu systemowego (po instrukcjach narzędzi) + zdanie, że styl dotyczy tylko tekstu odpowiedzi; mocniejsza instrukcja pamięci; próg: wywołanie z p ≥ 0,05 jest wybierane (pytania bez narzędzi: p ≤ 0,004); polecenia zaczynające się od „Zapamiętaj/Zapomnij/Remember/Forget” zaczynają odpowiedź od wywołania (`MemoryCommand`, `ChatRequest.forceToolCall`); wywołanie zapisane tekstem jest rozpoznawane (`ToolCall.parseWrittenOut`) i ukrywane w odpowiedzi.
- Wynik: 3 modele × 8 stylów × 10 pytań przy T=1 — 240/240 poprawnych decyzji, 0 zbędnych wywołań. iPhone (E4B, „Zwięzły”, walidacja Metal): zapis → odczyt → zapomnienie OK.
- Znane ograniczenie: E2B z własnym stylem typu mocne odgrywanie postaci („mów jak pirat”) czyta pamięć ~4/10 (zwykłe style i przykłady z aplikacji: 10/10; E4B/12B: 10/10).

### 2026-10-04 — Ekran startowy
- Przy starcie przez chwilę był biały ekran (zgłoszone przez użytkownika): `UILaunchScreen` był pusty, więc iOS pokazywał domyślne białe tło, zanim SwiftUI włączył ciemny wygląd. Teraz ekran startowy ma nocne tło `LaunchBackground` (#070B12 = `Theme.background`) i logo `LaunchLogo` (dymek z kłódką, przezroczyste tło; `swift scripts/make_icon.swift --launch <px> …`). Sprawdzone na symulatorze w jasnym trybie systemu: ciemne tło z logo od pierwszej klatki, płynne przejście do aplikacji.
- Zwykłe buildy nie nadpisują już katalogów tekstów (`SWIFT_EMIT_LOC_STRINGS: NO`; `gen_strings.py` włącza ekstrakcję we własnym buildzie).

### 2026-10-04 — Model „zapominał” wyniki wyszukiwania; „Nie pytaj mnie w tej rozmowie”
- **Zgłoszenie:** po wyszukiwaniu model w kolejnych wiadomościach nie korzystał ze znalezionych informacji.
- **Przyczyna (z bazy na telefonie):** zaraz po turze z wyszukiwaniem kolejne pytanie miało `droppedMessages = 14` przy promptcie ≈ 2,1 tys. tokenów — przycinanie historii (`ContextWindow.fit`) wycinało najstarsze tury w całości, a tura z wyszukiwaniem (największa) wylatywała pierwsza. Aplikacja działała na kontekście 4K: ustawienia **nie przeniosły się** przy zmianie bundle ID (iOS nie przyjął skopiowanego pliku preferencji) — wróciły domyślne (4K, bez myślenia). Przy 4K: budżet ≈ 3 tys., instrukcje pamięci + internetu ≈ 650, tura z wyszukiwaniem ≈ 1,5 tys.
- **Poprawka — kompaktowanie zamiast wycinania** (`ContextWindow.fitCompacting`, `HistoryCompaction`): 1) myślenie usuwane ze starszych tur (jak oficjalny szablon), 2) wyniki wyszukiwania w starszych turach skracane do 700 znaków na źródło (tytuły, numery i początek — gdzie są fakty — zostają; odpowiedź modelu w całości), 3) dopiero gdy to nie wystarcza — wycinanie najstarszych tur. Jeśli po 1–2 rozmowa się mieści, nic nie jest wycinane. `GenerationStats.compactedTurns`; stare statystyki w bazie dekodują się dalej (własne `init(from:)`).
- Nagłówek wyników: „odpowiedz na **to** pytanie na ich podstawie… wyniki nie ograniczają dalszej rozmowy” (wcześniej model po wyszukiwaniu odmawiał odpowiedzi z ogólnej wiedzy: „nie podano w źródłach”).
- Gdy wiadomości jednak wypadają — komunikat pod odpowiedzią (wcześniej `lastTrimmedMessages` nigdzie nie był pokazywany).
- Test `WebFollowUpTests` (E4B, 4K, prompt jak w aplikacji, styl Zwięzły): 3/3 przebiegi — zero wyciętych wiadomości, tura z wyszukiwaniem skrócona, pytanie o fakt z wyników („kto strzelił bramki?”) → „Kowalski (2), Nowak [1]”. Przy 16K i myśleniu problem w ogóle nie występował po 4 turach.
- Znane: E4B po wyszukiwaniu nadal czasem odmawia odpowiedzi z ogólnej wiedzy na pytania niezwiązane z wynikami („nie mam szczegółowych informacji o historii Legii”) — bez wyszukiwania 0/20; do dalszej analizy.
- **„Nie pytaj mnie w tej rozmowie”** (prośba użytkownika): przełącznik w karcie zgody; pierwsza zgoda nadal przez „Czy na pewno?”, kolejne wyszukiwania w tej otwartej rozmowie bez pytania (nadal widać „Szukam…”, 🌐 i źródła). W rozmowie widoczna linia „Wyszukiwanie bez pytania w tej rozmowie — Pytaj ponownie”. Nie zapisywane: nowa rozmowa lub ponowne otwarcie pyta znowu.
