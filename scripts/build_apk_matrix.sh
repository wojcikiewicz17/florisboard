#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
: "${BUILD_TRACK:=release}"
: "${OUT_DIR:=out/apk}"
: "${USE_DOCKER_REPRO:=0}"
: "${SIGN_WITH_DEBUG_KEY:=1}"
mkdir -p "$OUT_DIR"
capitalize() { printf '%s' "$1" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}'; }
BUILD_TASK="assemble$(capitalize "$BUILD_TRACK")"
if [[ "$USE_DOCKER_REPRO" == "1" ]]; then
  ./utils/repr_build/run.sh assemble "$BUILD_TRACK" "$OUT_DIR"
  exit 0
fi
./gradlew --no-daemon :app:fetchAssets ":app:${BUILD_TASK}"
APK_DIR="app/build/outputs/apk/${BUILD_TRACK}"
UNSIGNED_APK="$(find "$APK_DIR" -maxdepth 2 -type f -name '*.apk' | head -n1)"
[[ -n "$UNSIGNED_APK" ]] || { echo "No APK generated in $APK_DIR" >&2; exit 1; }
cp "$UNSIGNED_APK" "$OUT_DIR/$(basename "${UNSIGNED_APK%.apk}")-unsigned.apk"
if [[ "$SIGN_WITH_DEBUG_KEY" == "1" ]]; then
  BUILD_TOOLS_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}/build-tools"
  APKSIGNER="$(find "$BUILD_TOOLS_DIR" -type f -name apksigner 2>/dev/null | sort | tail -n1 || true)"
  [[ -n "$APKSIGNER" ]] || { echo "apksigner not found; skipping signed artifact" >&2; exit 0; }
  DEBUG_KS="$HOME/.android/debug.keystore"
  if [[ ! -f "$DEBUG_KS" ]]; then
    mkdir -p "$HOME/.android"
    keytool -genkeypair -v -storetype PKCS12 -keystore "$DEBUG_KS" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
  fi
  SIGNED_APK="$OUT_DIR/$(basename "${UNSIGNED_APK%.apk}")-debug-signed.apk"
  "$APKSIGNER" sign --ks "$DEBUG_KS" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$SIGNED_APK" "$UNSIGNED_APK"
  "$APKSIGNER" verify --verbose "$SIGNED_APK"
fi
