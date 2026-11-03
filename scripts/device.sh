#!/bin/zsh
# Helpers for running SecretChat on a physical iPhone.
#   scripts/device.sh install      – build Debug for device and install
#   scripts/device.sh push-model   – copy the GGUF (+mmproj) from .models/ into the app's Documents
#   scripts/device.sh launch       – start the app
#   scripts/device.sh pull-log     – fetch Documents/diagnostics.log → build/diagnostics.log
# Override the target with DEVICE=<name|udid> (default: first connected iPhone 17 Pro Max).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.marekpiotrowski.SecretChat
MODEL=gemma-4-12B-it-qat-UD-Q4_K_XL.gguf
MMPROJ=mmproj-F16.gguf
APP=build/DerivedData/Build/Products/Debug-iphoneos/SecretChat.app

device() {
  if [[ -n "${DEVICE:-}" ]]; then echo "$DEVICE"; return; fi
  local id
  id=$(xcrun devicectl list devices 2>/dev/null | grep "iPhone 17 Pro Max" | grep -E "available|connected" | grep -v unavailable | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) print $i}' | head -1 || true)
  [[ -n "$id" ]] || { echo "No connected iPhone 17 Pro Max (set DEVICE=...)" >&2; exit 1; }
  echo "$id"
}

CONTAINER=(--domain-type appDataContainer --domain-identifier $BUNDLE_ID)

case "${1:-}" in
  install|push-model|launch|pull-log) DEV=$(device) ;;
esac

case "${1:-}" in
  install)
    xcodegen generate >/dev/null
    xcodebuild -project SecretChat.xcodeproj -scheme SecretChat -configuration Debug \
      -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -allowProvisioningUpdates build \
      | grep -E "error:|BUILD" || true
    xcrun devicectl device install app --device "$DEV" "$APP"
    ;;
  push-model)
    xcrun devicectl device copy to --device "$DEV" "${CONTAINER[@]}" \
      --source ".models/$MODEL" --destination "Documents/$MODEL"
    [[ "${2:-}" == "--mmproj" ]] && xcrun devicectl device copy to --device "$DEV" "${CONTAINER[@]}" \
      --source ".models/$MMPROJ" --destination "Documents/$MMPROJ"
    ;;
  launch)
    xcrun devicectl device process launch --device "$DEV" --terminate-existing $BUNDLE_ID
    ;;
  pull-log)
    mkdir -p build
    xcrun devicectl device copy from --device "$DEV" "${CONTAINER[@]}" \
      --source Documents/diagnostics.log --destination build/diagnostics.log
    cat build/diagnostics.log
    ;;
  *)
    sed -n 2,8p "$0"; exit 1 ;;
esac
