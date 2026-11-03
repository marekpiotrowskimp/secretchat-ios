# SecretChat

Czat z **Gemma 4 12B** działający w całości na iPhonie (iPhone 17 Pro Max, iOS 26). Bez serwera, bez internetu — poza jednorazowym pobraniem modelu.

- Model: `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` (Gemma 4 12B-it, QAT 4-bit, 6,7 GB) + `mmproj-F16.gguf` (obrazy, 0,18 GB)
- Silnik: [llama.cpp](https://github.com/ggml-org/llama.cpp) `b11345` (Metal, mmap, mtmd dla obrazów)
- UI: SwiftUI + SwiftData, lokalizacja PL/EN

Szczegóły decyzji, pomiary i dziennik: [PLAN.md](PLAN.md).

## Funkcje

- Streaming odpowiedzi token po tokenie, przycisk Stop (częściowa odpowiedź zostaje zapisana)
- Historia wielu rozmów (SwiftData), auto-tytuły, zmiana nazwy, usuwanie
- Markdown: nagłówki, listy, tabele, cytaty, bloki kodu z kopiowaniem
- Zdjęcia z biblioteki lub aparatu (Gemma 4 vision)
- Tryb myślenia z rozwijanym blokiem „Rozumowanie”
- Ustawienia: prompt systemowy, temperatura / top-p / top-k / długość odpowiedzi, kontekst 4K/8K/16K, statystyki (tok/s, RAM)
- Pobieranie modelu w tle z wznawianiem i weryfikacją SHA-256
- Ekran diagnostyki: benchmark, wypełnienie kontekstu, test obrazu, 10-minutowy test termiczny

## Wymagania

- Mac z Apple Silicon, Xcode 26.2+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), CMake (`brew install cmake`)
- iPhone 17 Pro Max (12 GB RAM) z iOS 26 i włączonym trybem deweloperskim
- Konto Apple Developer (uprawnienie `increased-memory-limit`)

## Pierwsze uruchomienie

```sh
scripts/bootstrap.sh --model     # buduje llama.xcframework (~10 min) i pobiera model (~6,9 GB) do .models/
xcodegen generate                # tworzy SecretChat.xcodeproj
open SecretChat.xcodeproj         # albo z terminala ↓
```

Na telefon (podłączony kablem):

```sh
scripts/device.sh install        # build Debug + instalacja
scripts/device.sh push-model     # opcjonalnie: wgranie modelu po kablu zamiast pobierania w aplikacji
scripts/device.sh launch
scripts/device.sh pull-log       # wyniki z ekranu Diagnostyka (Documents/diagnostics.log)
```

Model można też wrzucić przez aplikację Pliki / Finder do folderu SecretChat — aplikacja przeniesie go i zweryfikuje przy starcie.

## Testy

```sh
cd GemmaKit && swift test                      # silnik + logika na macOS (testy integracyjne używają .models/)

scripts/prepare_test_models.sh                 # linki do modelu dla symulatora
xcodebuild test -project SecretChat.xcodeproj -scheme SecretChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'   # testy aplikacji + UI (symulator liczy na CPU — wolno)

xcodebuild -project SecretChat.xcodeproj -scheme SecretChat -destination generic/platform=iOS \
  SWIFT_EMIT_LOC_STRINGS=YES build && scripts/gen_strings.py      # odświeżenie tłumaczeń (błąd = brak tłumaczenia)
```

## Struktura

```
GemmaKit/            Swift Package: LlamaEngine, prompt Gemma 4, przycinanie kontekstu, parser
                     wyjścia/Markdown, ModelStore (pobieranie), diagnostyka — testowany na macOS
SecretChat/           aplikacja iOS (SwiftUI): czat, lista rozmów, ustawienia, onboarding, diagnostyka
SecretChatTests/      testy aplikacji (SwiftData, ustawienia, ChatViewModel z prawdziwym modelem)
SecretChatUITests/    testy UI (XCUITest) — pełny przepływ czatu PL + lokalizacja EN
scripts/             bootstrap, device, test-models, generowanie fixtures/tłumaczeń/ikony
```

## TestFlight

`xcodebuild archive` przechodzi (Release). Do wysyłki potrzebny jest rekord aplikacji w App Store Connect
(bundle ID `com.marekpiotrowski.SecretChat`), potem: Xcode → Organizer → Distribute App → TestFlight.
