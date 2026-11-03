#!/bin/zsh
# Fetches build/test dependencies that are not committed:
#   - llama.cpp XCFramework  → GemmaKit/Frameworks/llama.xcframework
#     built from source (ios, ios-simulator, macos; ~10 min) — the release zip has no simulator slice;
#     scripts/patches/*.patch are applied first (delete the framework to rebuild after adding a patch)
#   - llama.cpp macOS tools  → Vendor/tools/llama (llama-bench, llama-completion)
#   - Gemma 4 12B QAT GGUF   → .models/ (only with --model; ~6.9 GB)
set -euo pipefail
cd "$(dirname "$0")/.."

LLAMA_TAG=b11345
HF=https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main
MODEL_SHA=90fd44e29e0d7cffeb0fd00dc73cfdab9ed0b0e95306ecf7821ea634c940c370
MMPROJ_SHA=ecc4e93128da8363b7dbf2193eab98cf1142353f52ceaa0c95c0872997aaadd3

if [[ ! -d GemmaKit/Frameworks/llama.xcframework ]]; then
  if [[ ! -d Vendor/llama.cpp-src ]]; then
    git clone -q --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp.git Vendor/llama.cpp-src
  fi
  # Local fixes on top of the tag (each patch documents why); skipped when already applied.
  for patch in scripts/patches/*.patch; do
    if git -C Vendor/llama.cpp-src apply --check "$PWD/$patch" 2>/dev/null; then
      git -C Vendor/llama.cpp-src apply "$PWD/$patch"
    elif ! git -C Vendor/llama.cpp-src apply --reverse --check "$PWD/$patch" 2>/dev/null; then
      echo "Patch $patch does not apply to llama.cpp $LLAMA_TAG" >&2; exit 1
    fi
  done
  (cd Vendor/llama.cpp-src && ./build-xcframework.sh ios-sim ios-device macos > ../xcframework-build.log 2>&1)
  mkdir -p GemmaKit/Frameworks && cp -R Vendor/llama.cpp-src/build-apple/llama.xcframework GemmaKit/Frameworks/
fi

if [[ ! -d Vendor/tools/llama ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/m.tar.gz" "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-bin-macos-arm64.tar.gz"
  mkdir -p Vendor/tools && tar xzf "$tmp/m.tar.gz" -C "$tmp" && mv "$tmp/llama-$LLAMA_TAG" Vendor/tools/llama
  xattr -dr com.apple.quarantine Vendor/tools/llama 2>/dev/null || true
  rm -rf "$tmp"
fi

if [[ "${1:-}" == "--model" ]]; then
  mkdir -p .models
  fetch() { curl -fL -C - -o ".models/$1" "$HF/$1"; echo "$2  .models/$1" | shasum -a 256 -c -; }
  fetch gemma-4-12B-it-qat-UD-Q4_K_XL.gguf $MODEL_SHA
  fetch mmproj-F16.gguf $MMPROJ_SHA
fi
echo "bootstrap OK"
