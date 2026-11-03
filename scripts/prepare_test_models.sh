#!/bin/zsh
# Creates build/test-models: symlinks to .models/*.gguf plus verified-hash markers, so the app
# (simulator / tests, via GEMMA_MODEL_DIR) treats the models as downloaded without copying 7 GB.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/test-models
typeset -A SHA=(
  gemma-4-12B-it-qat-UD-Q4_K_XL.gguf 90fd44e29e0d7cffeb0fd00dc73cfdab9ed0b0e95306ecf7821ea634c940c370
  mmproj-F16.gguf ecc4e93128da8363b7dbf2193eab98cf1142353f52ceaa0c95c0872997aaadd3
)
for f in ${(k)SHA}; do
  [[ -f .models/$f ]] || { echo "missing .models/$f (run scripts/bootstrap.sh --model)" >&2; exit 1; }
  ln -sf "$PWD/.models/$f" "build/test-models/$f"
  printf %s "${SHA[$f]}" > "build/test-models/$f.sha256"
done
echo "build/test-models ready"
