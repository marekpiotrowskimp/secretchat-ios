#!/usr/bin/env python3
"""Builds the String Catalogs (pl source + en) from strings the compiler extracted.

Usage: scripts/gen_strings.py — it builds the app with SWIFT_EMIT_LOC_STRINGS=YES into its own
DerivedData folder (so other builds can't leave stale/empty extraction data), then writes the
catalogs. It exits with an error when a string has no English translation, so it doubles as a
localization coverage check.
"""
import glob, json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DERIVED_DATA = ROOT / "build/DerivedData-strings"
DERIVED = DERIVED_DATA / "Build/Intermediates.noindex"

build = subprocess.run(
    ["xcodebuild", "-project", "SecretChat.xcodeproj", "-scheme", "SecretChat", "-destination", "generic/platform=iOS",
     "-derivedDataPath", str(DERIVED_DATA), "SWIFT_EMIT_LOC_STRINGS=YES", "CODE_SIGNING_ALLOWED=NO", "build"],
    cwd=ROOT, capture_output=True, text=True,
)
if build.returncode != 0:
    sys.exit("build failed:\n" + "\n".join(l for l in build.stdout.splitlines() if "error:" in l))

EN = {
    # SecretChat
    "%@ z %@": "%1$@ of %2$@",
    "%lld tok": "%lld tok",
    "%@ tok/s": "%@ tok/s",
    "%@ s": "%@ s",
    "%lld.": "%lld.",
    "%lldK": "%lldK",
    "Anuluj": "Cancel",
    "Benchmark (~500 + 256 tok)": "Benchmark (~500 + 256 tok)",
    "Biblioteka zdjęć": "Photo Library",
    "Brak rozmów": "No Conversations",
    "Czytam…": "Reading…",
    "Diagnostyka": "Diagnostics",
    "Diagnostyka i testy wydajności": "Diagnostics & Benchmarks",
    "Do pobrania: %@ · wolne: %@": "To download: %1$@ · free: %2$@",
    "Dodaj zdjęcie": "Add Photo",
    "Dostępne do limitu": "Available Before Limit",
    "Długość kontekstu": "Context Length",
    "Dłuższy kontekst zużywa więcej pamięci i spowalnia odpowiedzi w długich rozmowach. Zmiana przeładuje model.":
        "A longer context uses more memory and slows down answers in long conversations. Changing it reloads the model.",
    "Footprint": "Footprint",
    "Gemma 4 12B działa lokalnie na tym iPhonie. Możesz też wysłać zdjęcie.":
        "Gemma 4 12B runs locally on this iPhone. You can also send a photo.",
    "Gemma 4 12B na Twoim iPhonie": "Gemma 4 12B on Your iPhone",
    "SecretChat": "SecretChat",
    "Generowanie": "Generation",
    "Gotowe": "Done",
    "Ile tokenów rozmowy model pamięta. Starsze wiadomości są pomijane, gdy się nie mieszczą.":
        "How many tokens of the conversation the model remembers. Older messages are left out when they don't fit.",
    "Instrukcja, którą model dostaje na początku każdej rozmowy.": "The instruction the model receives at the start of every conversation.",
    "Jesteś pomocnym asystentem. Odpowiadaj w języku, w którym pisze użytkownik.":
        "You are a helpful assistant. Reply in the language the user writes in.",
    "Kontekst": "Context",
    "Kopiuj": "Copy",
    "Log": "Log",
    "Maks. długość odpowiedzi": "Max Answer Length",
    "Model": "Model",
    "Model działa w całości na urządzeniu — rozmowy nie opuszczają telefonu. Najpierw trzeba jednorazowo pobrać pliki modelu.":
        "The model runs entirely on device — conversations never leave your phone. First, download the model files once.",
    "Model językowy": "Language Model",
    "Model nie zwrócił odpowiedzi.": "The model returned no answer.",
    "Model najpierw rozumuje (widoczne w zwijanym bloku), potem odpowiada. Lepsze wyniki przy trudnych pytaniach, ale wolniej.":
        "The model reasons first (shown in a collapsible block), then answers. Better results on hard questions, but slower.",
    "Moduł obrazów": "Vision Module",
    "Myśli…": "Thinking…",
    "Nazwa": "Name",
    "Nie pobrano": "Not downloaded",
    "Nie załadowany": "Not loaded",
    "Nowa rozmowa": "New Conversation",
    "O czym porozmawiamy?": "What shall we talk about?",
    "Pamięć i termika": "Memory & Thermals",
    "Pamięć rozmowy": "Conversation Memory",
    "Pisze…": "Writing…",
    "Pobieranie przez sieć komórkową": "Download over Cellular",
    "Pobierz model": "Download Model",
    "Pozwól pobierać przez sieć komórkową": "Allow downloading over cellular",
    "Prompt systemowy": "System Prompt",
    "Przerwij": "Stop",
    "Przetwarzanie rozmowy…": "Processing conversation…",
    "Przeładuj model": "Reload Model",
    "Przywróć domyślny": "Restore Default",
    "Przywróć zalecane (Gemma)": "Restore Recommended (Gemma)",
    "Rozmiar na dysku": "Size on Disk",
    "Rozmowy": "Conversations",
    "Rozmowy zostaną zachowane. Aby znów czatować, trzeba będzie pobrać model ponownie.":
        "Conversations are kept. To chat again you will need to download the model again.",
    "Rozumowanie": "Reasoning",
    "Skopiowano": "Copied",
    "Sprawdzanie sumy kontrolnej…": "Verifying checksum…",
    "Spróbuj ponownie": "Try Again",
    "Stan termiczny": "Thermal State",
    "Status": "Status",
    "Statystyki pod odpowiedzią": "Stats Below Answers",
    "Telefon jest gorący — generowanie zwalnia.": "The phone is hot — generation is slowing down.",
    "Temperatura": "Temperature",
    "Test ciągły 10 min": "Sustained Test 10 min",
    "Test obrazu": "Image Test",
    "Testy": "Tests",
    "Top-k": "Top-k",
    "Top-p": "Top-p",
    "Tryb myślenia": "Thinking Mode",
    "Ustawienia": "Settings",
    "Usunąć pliki modelu (%@)?": "Delete model files (%@)?",
    "Usuń": "Delete",
    "Usuń pliki modelu": "Delete Model Files",
    "Usuń zdjęcie": "Remove Photo",
    "W pamięci": "In memory",
    "Wersja": "Version",
    "Wiadomość": "Message",
    "Wstrzymaj": "Pause",
    "Wstrzymano": "Paused",
    "Wszystko działa offline. Rozmowy i zdjęcia są przechowywane tylko na tym urządzeniu.":
        "Everything works offline. Conversations and photos are stored only on this device.",
    "Wypełnij kontekst (80%)": "Fill Context (80%)",
    "Wyślij": "Send",
    "Wyświetlanie": "Display",
    "Wznów pobieranie": "Resume Download",
    "Zacznij nową rozmowę z Gemmą. Wszystko działa offline.": "Start a new conversation with Gemma. Everything works offline.",
    "Zalecane Wi-Fi. Pobieranie trwa dalej, gdy aplikacja jest w tle.": "Wi-Fi recommended. The download continues while the app is in the background.",
    "Zamknij": "Close",
    "Zapisz": "Save",
    "Zatrzymaj": "Stop",
    "Załaduj moduł obrazów": "Load Vision Module",
    "Zdjęcie": "Photo",
    "Zmień nazwę": "Rename",
    "Zrób zdjęcie": "Take Photo",
    "kod": "code",
    "Ładowanie %lld%%": "Loading %lld%%",
    "Ładowanie modelu do pamięci…": "Loading the model into memory…",
    "•": "•",
    # Model picker
    "%@ potrzebuje %lld GB RAM, a ten telefon ma %lld GB. Zalecany telefon: %@.": "%1$@ needs %2$lld GB of RAM, but this phone has %3$lld GB. Recommended phone: %4$@.",
    "%lld GB RAM": "%lld GB RAM",
    "Dla telefonów: %@": "For phones: %@",
    "Gemma 4 na Twoim iPhonie": "Gemma 4 on Your iPhone",
    "Jakość": "Quality",
    "Jakość %lld z 3": "Quality %lld of 3",
    "Model działa w całości na urządzeniu — rozmowy nie opuszczają telefonu. Wybierz model i pobierz go jednorazowo.":
        "The model runs entirely on device — conversations never leave your phone. Pick a model and download it once.",
    "Model potrzebuje %lld GB RAM, a ten telefon ma %lld GB. Aplikacja może się zamykać albo działać bardzo wolno.":
        "The model needs %1$lld GB of RAM, but this phone has %2$lld GB. The app may close unexpectedly or run very slowly.",
    "Najlepszy dla Twojego telefonu": "Best for Your Phone",
    "Pobieranie modułu obrazów…": "Downloading vision module…",
    "Pobierz %@": "Download %@",
    "Pobierz mimo to": "Download Anyway",
    "Pobierz moduł obrazów (%@)": "Download Vision Module (%@)",
    "Pobierz moduł obrazów (+%@)": "Download Vision Module (+%@)",
    "Pobranie": "Download",
    "Pobrany": "Downloaded",
    "Pozwala wysyłać zdjęcia. +%@": "Lets you send photos. +%@",
    "Rozmowy zostaną zachowane.": "Conversations are kept.",
    "Szybkość": "Speed",
    "Ta rozmowa zawiera zdjęcia. Pobierz moduł obrazów (przycisk + albo Ustawienia → Model).":
        "This conversation contains photos. Download the vision module (+ button or Settings → Model).",
    "Ten model może być za duży dla Twojego telefonu": "This model may be too large for your phone",
    "Ten telefon ma mniej pamięci, niż potrzebuje nawet najmniejszy model. Czat może działać niestabilnie. Zalecany jest iPhone z co najmniej 6 GB RAM (np. iPhone 13 Pro, iPhone 14, iPhone 15).":
        "This phone has less memory than even the smallest model needs. Chat may be unstable. An iPhone with at least 6 GB of RAM is recommended (e.g. iPhone 13 Pro, iPhone 14, iPhone 15).",
    "Twój telefon może nie podołać temu modelowi": "Your phone may not handle this model",
    "Twój telefon: %@ · %lld GB RAM": "Your phone: %1$@ · %2$lld GB RAM",
    "Twój telefon: %lld GB RAM": "Your phone: %lld GB RAM",
    "Usunąć %@?": "Delete %@?",
    "Używaj %@": "Use %@",
    "Używany": "In Use",
    "Wybierz %@": "Choose %@",
    "Wymaga": "Requires",
    "Zalecany telefon: %@": "Recommended phone: %@",
    "~%lld–%lld tok/s": "~%1$lld–%2$lld tok/s",
    "Przerwano odpowiedź: telefonowi zaczęło brakować pamięci. Zamknij inne aplikacje albo wybierz mniejszy model.":
        "Answer stopped: the phone was running out of memory. Close other apps or choose a smaller model.",
    "Eksperymentalny na tym telefonie": "Experimental on this phone",
    "Komfortowo działa na: %@": "Runs comfortably on: %@",
    "Na czas pisania odpowiedzi model zajmuje ok. %@ GB pamięci z %lld GB — telefon może wtedy zwalniać, a inne aplikacje mogą być zamykane.":
        "While writing an answer the model uses about %1$@ GB of the phone's %2$lld GB — the phone may slow down and other apps may be closed.",
    "Ten model jest eksperymentalny na Twoim telefonie": "This model is experimental on your phone",
    "W trakcie odpowiedzi %@ zajmuje ok. %@ GB z %lld GB pamięci telefonu — może zwalniać telefon i zamykać inne aplikacje. Komfortowo: %@.":
        "While answering, %1$@ uses about %2$@ GB of the phone's %3$lld GB — it may slow the phone down and close other apps. Comfortable on: %4$@.",
    "iPhone z 16 GB RAM": "an iPhone with 16 GB RAM",
    # Memory
    "Brak w pamięci: %@": "Not in memory: %@",
    "Dodaj wspomnienie": "Add Memory",
    "Jedno zdanie: czego dotyczy i kiedy się przyda. Na tej podstawie model decyduje, czy sięgnąć po treść.":
        "One sentence: what it's about and when it helps. The model decides from this whether to load the content.",
    "Kiedy się przyda": "When it's useful",
    "Krótka, po niej model wczytuje wspomnienie.": "Short — the model loads the memory by this name.",
    "Model może zapamiętywać informacje między rozmowami („Zapamiętaj…”, „Zapomnij…”). Każde wspomnienie ma nazwę, opis i treść; model widzi nazwy i opisy, a treść wczytuje tylko, gdy jest potrzebna. Wszystko zostaje na tym telefonie.":
        "The model can remember things between conversations (“Remember…”, “Forget…”). Each memory has a name, a description and content; the model sees names and descriptions and loads content only when needed. Everything stays on this phone.",
    "Nazwa": "Name",
    "Nowe wspomnienie": "New Memory",
    "Opis": "Description",
    "Ostatnio użyte": "Last Used",
    "Pamięć": "Memory",
    "Pamięć długotrwała": "Long-Term Memory",
    "Pamięć jest pusta": "Memory Is Empty",
    "Nie pytaj mnie w tej rozmowie": "Don't ask me again in this conversation",
    "Zapytanie »%@« trafi do %@, a odwiedzone strony zobaczą adres IP Twojego telefonu. Kolejne wyszukiwania w tej rozmowie odbędą się bez pytania.": "The query “%1$@” will be sent to %2$@, and the pages visited will see your phone's IP address. Further searches in this conversation will happen without asking.",
    "Wyszukiwanie bez pytania w tej rozmowie": "Searching without asking in this conversation",
    "Pytaj ponownie": "Ask again",
    "Rozmowa jest długa — %lld najstarszych wiadomości nie mieści się już w pamięci modelu. Możesz wydłużyć kontekst w Ustawieniach (Pamięć rozmowy) albo zacząć nową rozmowę.": "This conversation is long — the %lld oldest messages no longer fit in the model's memory. You can increase the context in Settings (Conversation memory) or start a new conversation.",
    "Styl odpowiedzi": "Response Style",
    "Jak model ma do Ciebie mówić: zwięźle, szczegółowo, przyjaźnie… albo po swojemu.": "How the model talks to you: concise, detailed, friendly… or your own way.",
    "Zrównoważony": "Balanced",
    "Zwięzły": "Concise",
    "Szczegółowy": "Detailed",
    "Przyjazny": "Friendly",
    "Nauczyciel": "Teacher",
    "Rzeczowy": "Professional",
    "Z humorem": "Playful",
    "Własny": "Custom",
    "Domyślny sposób odpowiadania modelu.": "The model's default way of answering.",
    "Krótko i na temat: 1–3 zdania, bez wstępów.": "Short and to the point: 1–3 sentences, no preamble.",
    "Dokładne wyjaśnienia z przykładami i kontekstem.": "Thorough explanations with examples and context.",
    "Ciepło, na „ty”, jak dobry znajomy.": "Warm and casual, like a good friend.",
    "Krok po kroku, z analogiami i pytaniem na koniec.": "Step by step, with analogies and a question at the end.",
    "Formalnie, neutralnie i precyzyjnie, bez emoji.": "Formal, neutral and precise, no emoji.",
    "Z żartem i luzem, ale z poprawnymi informacjami.": "Witty and relaxed, but with correct information.",
    "Opisz własnymi słowami, jak model ma do Ciebie mówić.": "Describe in your own words how the model should talk to you.",
    "Styl obowiązuje we wszystkich rozmowach, od następnej odpowiedzi. Nie musisz już za każdym razem pisać, jak model ma odpowiadać.": "The style applies to all conversations from the next answer on. No need to tell the model how to answer every time.",
    "Własny styl": "Custom style",
    "Jak model ma do Ciebie mówić?": "How should the model talk to you?",
    "Możesz też wybrać przykład i go poprawić. Limit %lld znaków (%lld użyte).": "You can also pick an example and edit it. Limit: %1$lld characters (%2$lld used).",
    "Mów do mnie na „ty”, krótko i konkretnie. Kod pokazuj bez długich objaśnień.": "Talk to me casually, short and to the point. Show code without long explanations.",
    "Tłumacz wszystko tak, jakbym miał 12 lat, z prostymi przykładami.": "Explain everything as if I were 12, with simple examples.",
    "Odpowiadaj jak doświadczony mentor: szczerze, wskaż słabe punkty mojego pomysłu.": "Answer like an experienced mentor: be honest and point out the weak spots of my idea.",
    "Licencje i informacje prawne": "Licenses & Legal",
    "Sztuczna inteligencja": "Artificial Intelligence",
    "Odpowiedzi generuje model sztucznej inteligencji działający na tym telefonie. Mogą zawierać błędy — sprawdzaj ważne informacje.": "Answers are generated by an AI model running on this phone. They may contain mistakes — check important information.",
    "Model i biblioteki": "Model & Libraries",
    "Pliki modeli Gemma 4 nie są częścią aplikacji: pobierasz je bezpośrednio z Hugging Face (wersje GGUF przygotowane przez Unsloth, licencja Apache 2.0).": "Gemma 4 model files are not part of the app: you download them directly from Hugging Face (GGUF versions prepared by Unsloth, Apache 2.0 license).",
    "Znaki towarowe": "Trademarks",
    "Gemma jest znakiem towarowym Google LLC. SecretChat nie jest powiązany z Google ani przez Google sponsorowany.": "Gemma is a trademark of Google LLC. SecretChat is not affiliated with or sponsored by Google.",
    "Usługi internetowe": "Internet Services",
    "Tylko gdy włączysz wyszukiwanie i zatwierdzisz zapytanie: DuckDuckGo, Wikipedia (treści na licencji CC BY-SA — źródła są podawane przy odpowiedzi) albo Brave Search z Twoim własnym kluczem, na warunkach Brave Search API.": "Only when you turn on search and approve a query: DuckDuckGo, Wikipedia (content licensed CC BY-SA — sources are listed with the answer) or Brave Search with your own key, under the Brave Search API terms.",
    "Modele Gemma 4 udostępnia Google na licencji Apache 2.0. Pliki są pobierane z Hugging Face.": "Gemma 4 models are provided by Google under the Apache 2.0 license. Files are downloaded from Hugging Face.",
    "Licencja modelu": "Model License",
    "Model zapyta o zgodę przed każdym wyszukiwaniem. Gdy wyszukiwarka zablokuje zapytanie, użyjemy Wikipedii. Klucz Brave jest zapisany w pęku kluczy na tym urządzeniu. To Twój klucz — korzystasz z niego na warunkach Brave Search API (plan musi pozwalać na użycie wyników przez AI).": "The model asks before every search. If the search engine blocks the query, Wikipedia is used. The Brave key is stored in this device’s keychain. It is your key — you use it under the Brave Search API terms (your plan must allow AI use of the results).",
    "Powiedz w czacie np. „Zapamiętaj, że mój pies ma na imię Burek” albo dodaj wspomnienie ręcznie.":
        "Say in the chat e.g. “Remember that my dog is called Rex” or add a memory manually.",
    "Sprawdziłem pamięć.": "I checked my memory.",
    "Treść": "Content",
    "Usunąć wszystkie wspomnienia (%lld)?": "Delete all memories (%lld)?",
    "Usuń wspomnienie": "Delete Memory",
    "Usuń wszystkie": "Delete All",
    "Usuń wszystkie wspomnienia": "Delete All Memories",
    "Utworzono": "Created",
    "Użyto %lld×": "Used %lld×",
    "Użyto pamięci: %@": "Used memory: %@",
    "Wspomnienia są zapisane tylko na tym telefonie. Model widzi w każdej nowej rozmowie listę nazw i opisów, a treść wczytuje tylko wtedy, gdy jest potrzebna.":
        "Memories are stored only on this phone. In every new conversation the model sees the list of names and descriptions and loads content only when needed.",
    "Wspomnienie": "Memory",
    "Zapamiętano: %@": "Remembered: %@",
    "Zapamiętałem: „%@”.": "Remembered: “%@”.",
    "Zapisane wspomnienia": "Saved Memories",
    "Zapomniano: %@": "Forgotten: %@",
    "Zapomniałem: „%@”.": "Forgotten: “%@”.",
    "Zaktualizowano w pamięci: %@": "Updated in memory: %@",
    "Zaktualizowałem wspomnienie „%@”.": "Updated the memory “%@”.",
    # SecretChat branding
    "Model działa w całości na tym iPhonie. Rozmowa nie opuszcza telefonu.": "The model runs entirely on this iPhone. The conversation never leaves your phone.",
    "eksperymentalny": "experimental",
    "Zdjęcia": "Photos",
    "Aplikacja działa w pełni offline": "The app works fully offline",
    "Internet na żądanie": "Internet on request",
    "Model działa w całości na Twoim iPhonie — bez kont, bez chmury, bez śledzenia. Rozmowy nie opuszczają telefonu. Wybierz model i pobierz go jednorazowo.":
        "The model runs entirely on your iPhone — no accounts, no cloud, no tracking. Conversations never leave your phone. Pick a model and download it once.",
    "Prywatny czat AI. Bez internetu.": "Private AI chat. No internet.",
    "Rozmowa zostaje na tym iPhonie — model działa bez internetu. Możesz też wysłać zdjęcie.":
        "The conversation stays on this iPhone — the model works without the internet. You can also send a photo.",
    "SecretChat działa offline. Jeśli się zgodzisz, tylko to zapytanie zostanie wysłane do wyszukiwarki (%@), a aplikacja otworzy 2–3 strony z wyników. Reszta rozmowy nie opuści telefonu.":
        "SecretChat works offline. If you agree, only this query is sent to the search engine (%@), and the app opens 2–3 result pages. The rest of the conversation stays on your phone.",
    "SecretChat działa offline. Rozmowy i zdjęcia są przechowywane tylko na tym urządzeniu.": "SecretChat works offline. Conversations and photos are stored only on this device.",
    "SecretChat jest zaprojektowany do pracy bez internetu": "SecretChat is designed to work without the internet",
    "W pełni offline": "Fully Offline",
    "Wyszukiwanie w internecie włączone, tylko za zgodą": "Internet search on, only with your consent",
    "Zacznij nową rozmowę. Wszystko działa offline — nic nie opuszcza telefonu.": "Start a new conversation. Everything works offline — nothing leaves your phone.",
    "Brak dostępu do mikrofonu. Włącz go w Ustawieniach iOS → SecretChat.": "No microphone access. Turn it on in iOS Settings → SecretChat.",
    "Brak zgody na rozpoznawanie mowy. Włącz ją w Ustawieniach iOS → SecretChat.": "Speech recognition is not allowed. Turn it on in iOS Settings → SecretChat.",
    # Dictation
    "Angielski": "English",
    "Automatyczny (język telefonu)": "Automatic (phone language)",
    "Czytaj odpowiedzi w trybie głosowym": "Read Answers in Voice Mode",
    "Czytam odpowiedź — potem znów słucham": "Reading the answer — then I'll listen again",
    "Dyktowanie": "Dictation",
    "Dyktuj": "Dictate",
    "Język dyktowania": "Dictation Language",
    "Mikrofon wyłączony — model odpowiada": "Microphone off — the model is answering",
    "Pauza wyśle wiadomość · „wyczyść” · „koniec dyktowania”": "A pause sends the message · “clear” · “stop dictation”",
    "Po %@ s ciszy": "After %@ s of silence",
    "Polski": "Polish",
    "Powiedz „wyślij” · „wyczyść” · „koniec dyktowania”": "Say “send” · “clear” · “stop dictation”",
    "Słucham…": "Listening…",
    "Tryb głosowy": "Voice Mode",
    "Tryb głosowy wyłączony po dłuższej ciszy.": "Voice mode turned off after a long silence.",
    "Tylko po słowie „wyślij”": "Only when I say “send”",
    "Wysyłanie w trybie głosowym": "Sending in Voice Mode",
    "Wyłącz tryb głosowy": "Turn Off Voice Mode",
    "Włączam mikrofon…": "Turning on the microphone…",
    "Zakończ": "End",
    "Zakończ dyktowanie": "Stop Dictating",
    "🎤 w polu wiadomości dyktuje tekst. Tryb głosowy (przycisk fali w czacie) sam włącza mikrofon, gdy czat czeka na wiadomość, i wyłącza go, gdy model odpowiada lub czyta. Komendy: „wyślij”, „wyczyść”, „koniec dyktowania”. Rozpoznawanie mowy działa na telefonie, bez internetu.":
        "🎤 in the message field dictates text. Voice mode (the wave button in the chat) turns the microphone on when the chat is waiting for you and off while the model answers or reads. Commands: “send”, “clear”, “stop dictation”. Speech recognition runs on the phone, offline.",
    "Brak dostępu do mikrofonu. Włącz go w Ustawieniach iOS → SecretChat.": "No microphone access. Turn it on in iOS Settings → SecretChat.",
    "Brak zgody na rozpoznawanie mowy. Włącz ją w Ustawieniach iOS → SecretChat.": "Speech recognition is not allowed. Turn it on in iOS Settings → SecretChat.",
    "Dyktowanie w tym języku (%@) nie jest dostępne offline na tym urządzeniu.": "Dictation in this language (%@) isn't available offline on this device.",
    "Mikrofon jest zajęty przez inną aplikację.": "The microphone is in use by another app.",
    # Read aloud
    "Automatyczny (najlepszy dostępny)": "Automatic (best available)",
    "Cześć! Tak brzmią odpowiedzi czytane na głos. Wzór $a^2 + b^2 = c^2$ też przeczytam.":
        "Hi! This is how answers sound when read aloud. I can read the formula $a^2 + b^2 = c^2$ too.",
    "Czytaj na głos": "Read Aloud",
    "Czytaj odpowiedzi automatycznie": "Read Answers Automatically",
    "Czytanie na głos": "Read Aloud",
    "Głos": "Voice",
    "Odpowiedzi czyta syntezator mowy iOS, bez internetu. Kod i rozumowanie są pomijane. Lepsze głosy (★) można pobrać w ustawieniach iOS: Dostępność → Treść mówiona → Głosy.":
        "Answers are read by the iOS speech synthesizer, offline. Code and reasoning are skipped. Better voices (★) can be downloaded in iOS Settings: Accessibility → Spoken Content → Voices.",
    "Posłuchaj próbki": "Play Sample",
    "Tempo czytania": "Speaking Rate",
    "Zatrzymaj czytanie": "Stop Reading",
    # Web search
    "Brave Search (klucz API)": "Brave Search (API key)",
    "Czy na pewno przeszukać internet?": "Search the internet?",
    "Czytam strony z wyników (%lld)…": "Reading result pages (%lld)…",
    "Domyślnie nic nie opuszcza Twojego telefonu. Gdy włączysz wyszukiwanie:": "By default nothing leaves your phone. When you turn search on:",
    "SecretChat działa offline. Jeśli się zgodzisz, tylko to zapytanie zostanie wysłane do wyszukiwarki (%@), a aplikacja otworzy 2–3 strony z wyników. Reszta rozmowy nie opuści telefonu.":
        "SecretChat works offline. If you agree, only this query is sent to the search engine (%@), and the app opens 2–3 result pages. The rest of the conversation stays on your phone.",
    "SecretChat jest zaprojektowany do pracy bez internetu": "SecretChat is designed to work without the internet",
    "Internet": "Internet",
    "Jeśli zdjęcie jest tylko w iCloud, sprawdź połączenie i spróbuj ponownie.": "If the photo is only in iCloud, check your connection and try again.",
    "Klucz Brave Search API": "Brave Search API key",
    "Model chce przeszukać internet": "The model wants to search the internet",
    "Model może zaproponować wyszukiwanie, gdy nie zna odpowiedzi (np. aktualne wydarzenia, pogoda, ceny).":
        "The model may suggest a search when it doesn't know the answer (e.g. current events, weather, prices).",
    "Nie udało się wczytać zdjęcia": "Couldn't load the photo",
    "Nie, odpowiedz bez internetu": "No, answer without the internet",
    "OK": "OK",
    "Odpowiedzi z internetu oznaczymy 🌐 i podamy źródła.": "Answers from the internet are marked 🌐 and list their sources.",
    "Odpowiedź z internetu": "Answer from the internet",
    "Odpowiedź z internetu · źródła: %lld": "Answer from the internet · sources: %lld",
    "Po zgodzie zapytanie trafi do %@, a aplikacja otworzy 2–3 strony z wyników. Te serwisy zobaczą adres IP telefonu.":
        "After you agree, the query goes to %@ and the app opens 2–3 result pages. Those sites will see your phone's IP address.",
    "Rozumiem, włącz wyszukiwanie": "I Understand, Turn On Search",
    "Szukaj…": "Search…",
    "Szukam w internecie…": "Searching the internet…",
    "Tak, szukaj w internecie": "Yes, Search the Internet",
    "Treść rozmowy, zdjęcia i historia nie są wysyłane.": "Your conversation, photos and history are not sent.",
    "Wyszukiwanie w internecie": "Internet Search",
    "Wyszukiwarka": "Search Engine",
    "Wyłączone — aplikacja nie łączy się z internetem (poza pobieraniem modelu).": "Off — the app doesn't connect to the internet (except to download the model).",
    "Za każdym razem zapytamy, czy na pewno — i pokażemy dokładne zapytanie.": "Every time, we'll ask if you're sure — and show the exact query.",
    "Zapytanie »%@« trafi do %@, a odwiedzone strony zobaczą adres IP Twojego telefonu.": "The query “%1$@” will be sent to %2$@, and the visited pages will see your phone's IP address.",
    "Zapytanie: »%@«": "Query: “%@”",
    "Zostaw wyłączone": "Keep It Off",
    "[%lld]": "[%lld]",
    "»%@«": "“%@”",
    # GemmaKit — web
    "%@ tymczasowo zablokował wyszukiwanie (zabezpieczenie przed botami).": "%@ temporarily blocked the search (bot protection).",
    "Brak klucza API wyszukiwarki.": "Missing search API key.",
    "Brak połączenia z internetem.": "No internet connection.",
    "Brak wyników wyszukiwania.": "No search results.",
    "Wyszukiwarka zwróciła błąd HTTP %lld.": "The search engine returned HTTP error %lld.",
    # GemmaKit
    "Błąd inferencji (kod %d).": "Inference error (code %d).",
    "Model nie jest załadowany.": "The model is not loaded.",
    "Moduł obrazów nie jest załadowany.": "The vision module is not loaded.",
    "Nie udało się odczytać obrazu.": "Could not read the image.",
    "Nie udało się przetworzyć obrazu (kod %d).": "Could not process the image (code %d).",
    "Nie udało się przetworzyć tekstu.": "Could not process the text.",
    "Nie udało się utworzyć kontekstu (za mało pamięci?).": "Could not create the context (not enough memory?).",
    "Nie udało się załadować modelu.": "Could not load the model.",
    "Nie udało się załadować modułu obrazów.": "Could not load the vision module.",
    "Nieprawidłowy rozmiar pliku (%lld zamiast %lld B).": "Wrong file size (%1$lld instead of %2$lld B).",
    "Serwer zwrócił błąd HTTP %lld.": "The server returned HTTP error %lld.",
    "Suma kontrolna się nie zgadza — plik uszkodzony.": "Checksum mismatch — the file is corrupted.",
    "Wiadomość jest za długa: potrzeba %lld tokenów, kontekst mieści %lld.":
        "The message is too long: it needs %1$lld tokens, the context holds %2$lld.",
}

# Info.plist strings
INFO_PLIST = {
    "NSMicrophoneUsageDescription": (
        "Mikrofon służy do dyktowania wiadomości. Mowa jest rozpoznawana na telefonie i nie jest nigdzie wysyłana.",
        "The microphone is used to dictate messages. Speech is recognized on the phone and never sent anywhere.",
    ),
    "NSCameraUsageDescription": (
        "Aparat służy do robienia zdjęć, które wysyłasz do modelu. Zdjęcia nie opuszczają telefonu.",
        "The camera is used to take photos you send to the model. Photos never leave your phone.",
    ),
}

TARGETS = {
    "SecretChat": ROOT / "SecretChat/Resources/Localizable.xcstrings",
    "GemmaKit": ROOT / "GemmaKit/Sources/GemmaKit/Resources/Localizable.xcstrings",
}


def catalog(entries):
    return {
        "sourceLanguage": "pl",
        "strings": {
            key: {"localizations": {"en": {"stringUnit": {"state": "translated", "value": value}}}}
            for key, value in sorted(entries.items())
        },
        "version": "1.0",
    }


missing = []
for target, out in TARGETS.items():
    keys = set()
    files = glob.glob(str(DERIVED / f"{target}.build/**/*.stringsdata"), recursive=True)
    if not files:
        sys.exit(f"No .stringsdata for {target} — build with SWIFT_EMIT_LOC_STRINGS=YES first")
    for f in files:
        for entries in json.load(open(f)).get("tables", {}).values():
            keys.update(e["key"] for e in entries)
    if len(keys) < 5:
        sys.exit(f"Only {len(keys)} strings extracted for {target} — refusing to overwrite {out.name}")
    missing += [f"{target}: {k!r}" for k in sorted(keys) if k not in EN]
    out.write_text(json.dumps(catalog({k: EN.get(k, k) for k in keys}), ensure_ascii=False, indent=2) + "\n")
    print(f"{target}: {len(keys)} strings → {out.relative_to(ROOT)}")

info = {
    "sourceLanguage": "pl",
    "strings": {
        key: {"localizations": {
            "pl": {"stringUnit": {"state": "translated", "value": pl}},
            "en": {"stringUnit": {"state": "translated", "value": en}},
        }}
        for key, (pl, en) in INFO_PLIST.items()
    },
    "version": "1.0",
}
(ROOT / "SecretChat/Resources/InfoPlist.xcstrings").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")

if missing:
    sys.exit("Missing English translations:\n  " + "\n  ".join(missing))
print("All strings translated ✅")
