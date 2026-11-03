# SecretChat

A chat app running **Gemma 4 12B** entirely on an iPhone (iPhone 17 Pro Max, iOS 26). No server and no internet connection — apart from a one-time model download.

- Model: `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` (Gemma 4 12B-it, QAT 4-bit, 6.7 GB) + `mmproj-F16.gguf` (vision, 0.18 GB)
- Engine: [llama.cpp](https://github.com/ggml-org/llama.cpp) `b11345` (Metal, mmap, mtmd for images)
- UI: SwiftUI + SwiftData, Polish and English localization

Design decisions, measurements and the development log (in Polish): [PLAN.md](PLAN.md).

## Features

- Token-by-token streaming with a Stop button (the partial answer is kept)
- Multiple conversations (SwiftData) with automatic titles, renaming and deletion
- Markdown rendering: headings, lists, tables, quotes, code blocks with a copy button
- Photos from the library or camera (Gemma 4 vision)
- Thinking mode with a collapsible "Reasoning" block
- Settings: system prompt, temperature / top-p / top-k / answer length, 4K/8K/16K context, live stats (tokens/s, RAM)
- Background model download with resume and SHA-256 verification
- Diagnostics screen: benchmark, context fill, image test, 10-minute thermal test

## Requirements

- Apple Silicon Mac, Xcode 26.2+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), CMake (`brew install cmake`)
- iPhone 17 Pro Max (12 GB RAM) running iOS 26 with Developer Mode enabled
- Apple Developer account (the `increased-memory-limit` entitlement is required)

## Getting started

```sh
scripts/bootstrap.sh --model     # builds llama.xcframework (~10 min) and downloads the model (~6.9 GB) into .models/
xcodegen generate                # generates SecretChat.xcodeproj
open SecretChat.xcodeproj        # or use the terminal commands below
```

On a device connected by cable:

```sh
scripts/device.sh install        # Debug build + install
scripts/device.sh push-model     # optional: copy the model over the cable instead of downloading it in the app
scripts/device.sh launch
scripts/device.sh pull-log       # results from the Diagnostics screen (Documents/diagnostics.log)
```

You can also drop the model into the SecretChat folder using the Files app or Finder — the app moves and verifies it on launch.

## Tests

```sh
cd GemmaKit && swift test                      # engine + logic on macOS (integration tests use .models/)

scripts/prepare_test_models.sh                 # model links for the simulator
xcodebuild test -project SecretChat.xcodeproj -scheme SecretChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'   # app + UI tests (the simulator runs on CPU — slow)

xcodebuild -project SecretChat.xcodeproj -scheme SecretChat -destination generic/platform=iOS \
  SWIFT_EMIT_LOC_STRINGS=YES build && scripts/gen_strings.py      # refresh translations (fails on a missing translation)
```

## Project structure

```
GemmaKit/            Swift package: LlamaEngine, Gemma 4 prompt format, context trimming, output/Markdown
                     parser, ModelStore (downloads), diagnostics — tested on macOS
SecretChat/          iOS app (SwiftUI): chat, conversation list, settings, onboarding, diagnostics
SecretChatTests/     app tests (SwiftData, settings, ChatViewModel against the real model)
SecretChatUITests/   UI tests (XCUITest) — full chat flow in Polish + English localization
scripts/             bootstrap, device, test models, fixture/translation/icon generation
```

## TestFlight

`xcodebuild archive` succeeds (Release). Uploading requires an app record in App Store Connect
(bundle ID `com.marekpiotrowski.SecretChat`), then: Xcode → Organizer → Distribute App → TestFlight.

## License

Code: MIT — see [LICENSE](LICENSE). Model weights are not part of this repository; Gemma is distributed under the [Gemma Terms of Use](https://ai.google.dev/gemma/terms). llama.cpp is MIT-licensed.
