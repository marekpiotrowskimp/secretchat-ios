# Licencje i ramy prawne — SecretChat

Stan na 2026-10-04. To analiza techniczna, nie porada prawna. Przed publikacją w App Store warto skonsultować punkty z sekcji „Otwarte decyzje” z prawnikiem.

## 1. Model Gemma 4 — licencja Apache 2.0

| Fakt | Źródło |
|---|---|
| Gemma 4 (12B, E4B, E2B) jest wydana na **Apache License 2.0** (od 2 kwietnia 2026; wcześniejsze Gemmy miały własne „Gemma Terms of Use”). | https://ai.google.dev/gemma/docs/gemma_4_license |
| „Gemma Terms of Use” (z polityką zakazanych zastosowań, którą Google mógł jednostronnie zmieniać) **wprost nie dotyczą Gemma 4**: „For Gemma 4 terms, see the Gemma 4 license”. | https://ai.google.dev/gemma/terms (zmiana 1.04.2026) |
| Repozytoria `google/gemma-4-*` i `unsloth/gemma-4-*-qat-GGUF` (z których pobiera aplikacja) mają `license: apache-2.0`, nie są „gated” (bez akceptowania warunków) i **nie mają pliku NOTICE**. | API Hugging Face |

**Co pozwala Apache 2.0:** używać, modyfikować (kwantyzacja = utwór zależny), rozpowszechniać, także komercyjnie, bez opłat. Licencja zawiera też wyraźną licencję patentową.

**Obowiązki (§4) — powstają przy rozpowszechnianiu modelu lub utworu zależnego:**
1. dać odbiorcy kopię licencji Apache 2.0,
2. oznaczyć zmienione pliki,
3. zachować informacje o prawach autorskich, patentach, znakach i autorstwie,
4. jeśli jest plik NOTICE — przekazać jego treść (Gemma 4 go nie ma).

**Jak to wygląda u nas:** aplikacja **nie zawiera** wag modelu — użytkownik pobiera je bezpośrednio z Hugging Face (pliki przygotowane i rozpowszechniane przez Unsloth). Formalnie to nie my rozpowszechniamy model, ale i tak spełniamy obowiązki na wypadek, gdyby model kiedyś był dołączany do aplikacji:
- pełny tekst Apache 2.0 w aplikacji (Ustawienia → Licencje i informacje prawne),
- autor (Google LLC) i link do licencji przy wyborze modelu oraz na ekranie licencji,
- nie zmieniamy plików modelu (wczytujemy GGUF bez modyfikacji).

**Znaki towarowe (§6):** Apache 2.0 nie daje prawa do znaku „Gemma”. Dlatego:
- nazwa aplikacji to **SecretChat** (zmieniona wcześniej z „GemmaChat” — dobrze),
- „Gemma 4 12B” itp. pojawia się tylko opisowo, jako nazwa użytego modelu (użycie nominatywne),
- w aplikacji jest informacja: „Gemma jest znakiem towarowym Google LLC. SecretChat nie jest powiązany z Google ani przez Google sponsorowany.”

**Wniosek:** korzystanie z Gemma 4 w tej aplikacji jest zgodne z licencją. Nie obowiązuje nas lista zakazanych zastosowań z dawnych warunków Gemmy (ale zwykłe prawo — np. AI Act, RODO, prawo autorskie — oczywiście tak).

## 2. Biblioteki dołączone do aplikacji

| Składnik | Licencja | Wymóg | Status |
|---|---|---|---|
| llama.cpp / ggml (z mtmd), b11345 | MIT | informacja o prawach autorskich + tekst licencji w kopiach | ✅ tekst w aplikacji |
| miniaudio (wkompilowane w mtmd) | Public Domain lub MIT-0 | brak | ✅ wymienione |
| stb_image (wkompilowane w mtmd) | MIT lub Public Domain | brak (przy wyborze Public Domain) | ✅ wymienione + tekst |
| SwiftMath 1.7.3 | MIT | informacja + tekst licencji | ✅ tekst w aplikacji |
| Fonty matematyczne SwiftMath (używany: Latin Modern Math) | GUST Font License; pozostałe fonty pakietu: m.in. SIL OFL 1.1 | licencja razem z fontem | ✅ pliki licencji są w pakiecie fontów; GUST także na ekranie licencji |
| nlohmann/json, cpp-httplib (w źródłach llama.cpp) | MIT | — | nie są wkompilowane w aplikację (sprawdzone `nm`) |

Teksty: `SecretChat/Resources/Licenses/`. Ekran: `SecretChat/Features/Settings/LegalView.swift`, test UI: `LegalUITests`.

## 3. Usługi internetowe (tylko po włączeniu wyszukiwania i zgodzie na zapytanie)

| Usługa | Ustalenia | Status |
|---|---|---|
| **Wikipedia (API)** | Zasady User-Agent Wikimedia: klient API ma się przedstawiać (nazwa + kontakt), inaczej może zostać zablokowany. Treści na licencji CC BY-SA — wymagają uznania autorstwa. | ✅ własny User-Agent `SecretChat/1.0 (…)`; ✅ źródła z linkami przy każdej odpowiedzi. ⚠️ brak kontaktu w User-Agent (patrz decyzje) |
| **DuckDuckGo (HTML)** | Regulamin i Acceptable Use Policy nie zakazują wprost automatycznych zapytań, ale DDG zastrzega prawo blokowania „wbrew duchowi zasad”. Nie ma oficjalnego API wyników. Aplikacja przedstawia się jako Safari. | ⚠️ szara strefa — działa, ale bez gwarancji; jest automatyczne przejście na Wikipedię |
| **Brave Search API** | Klucz należy do użytkownika (to on jest klientem Brave i akceptuje warunki). Warunki: zakaz trenowania modeli na wynikach i budowania z nich bazy (my ich nie przechowujemy poza odpowiedzią); użycie do „inferencji/groundingu” LLM wymaga planu, który na to pozwala (wg Brave 2026: plan „Search”). | ✅ informacja w ustawieniach przy kluczu |

## 4. Inne ramy prawne (poza licencjami)

- **AI Act (UE), art. 50** — od 2.08.2026 obowiązki przejrzystości: użytkownik ma wiedzieć, że rozmawia z AI (u nas oczywiste + komunikat na ekranie licencji: „Odpowiedzi generuje model sztucznej inteligencji… mogą zawierać błędy”). Obowiązki dostawców modeli ogólnego przeznaczenia (GPAI) spoczywają na Google. Kwestię znakowania treści generowanych przez AI w formacie czytelnym maszynowo warto potwierdzić z prawnikiem przed publikacją.
- **RODO / prywatność** — aplikacja nie wysyła rozmów ani pamięci poza telefon; zapytania do wyszukiwarki idą tylko po zgodzie, bezpośrednio z telefonu do usługi. Ułatwia to etykietę prywatności App Store („Data Not Collected” — do potwierdzenia przy publikacji).
- **App Store** — przy publikacji: kwestionariusz kategorii wiekowej, opis bez sugerowania powiązania z Google, eksport szyfrowania (tylko HTTPS — zwolnienie).

## 5. Otwarte decyzje (dla właściciela projektu)

1. **Kontakt w User-Agent dla Wikipedii** — dopisać stronę WWW lub adres e-mail projektu (nie dodałem żadnego adresu z własnej inicjatywy).
2. **DuckDuckGo** — zostawić (szara strefa) czy w wersji do App Store domyślnie używać Wikipedii / Brave.
3. ~~Bundle ID `com.marekpiotrowski.GemmaChat`~~ — **zrobione 2026-10-04:** projekt, cele, katalogi i bundle ID to teraz SecretChat (`com.marekpiotrowski.SecretChat`). Zostaje nazwa wewnętrzna biblioteki silnika `GemmaKit` (opisuje, że obsługuje modele Gemma; użytkownik jej nie widzi).
