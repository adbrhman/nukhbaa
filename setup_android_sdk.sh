#!/usr/bin/env bash
set -euo pipefail

SDK_ROOT="$HOME/android-sdk"
CMDLINE_DIR="$SDK_ROOT/cmdline-tools"
TMP_DIR="$HOME/.android-sdk-install"

echo "=============================================="
echo " NUKHBAA — ANDROID SDK SETUP"
echo "=============================================="

echo
echo "[1/7] Checking prerequisites..."

command -v curl >/dev/null || {
  echo "ERROR: curl is missing."
  exit 1
}

command -v unzip >/dev/null || {
  echo "ERROR: unzip is missing."
  exit 1
}

command -v java >/dev/null || {
  echo "ERROR: Java is missing."
  exit 1
}

echo "Java:"
java -version 2>&1 | head -1

echo
echo "[2/7] Creating Android SDK directory..."

mkdir -p "$CMDLINE_DIR"
mkdir -p "$TMP_DIR"

echo
echo "[3/7] Downloading official Android Command-line Tools..."

URL="https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip"
ZIP="$TMP_DIR/commandlinetools.zip"

if [ ! -f "$ZIP" ]; then
  curl -fL --retry 3 --retry-delay 2 \
    "$URL" \
    -o "$ZIP"
else
  echo "Archive already downloaded:"
  echo "$ZIP"
fi

echo
echo "[4/7] Installing Command-line Tools..."

rm -rf "$CMDLINE_DIR/latest"

mkdir -p "$CMDLINE_DIR/latest"

unzip -q "$ZIP" -d "$TMP_DIR/extracted"

cp -a "$TMP_DIR/extracted/cmdline-tools/." \
  "$CMDLINE_DIR/latest/"

SDKMANAGER="$CMDLINE_DIR/latest/bin/sdkmanager"

if [ ! -x "$SDKMANAGER" ]; then
  echo "ERROR: sdkmanager was not installed correctly."
  exit 1
fi

echo
echo "sdkmanager:"
"$SDKMANAGER" --version

echo
echo "[5/7] Installing Android SDK components..."

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"

export PATH="$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$SDK_ROOT/build-tools/latest:$PATH"

yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null || true

"$SDKMANAGER" --sdk_root="$SDK_ROOT" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0"

echo
echo "[6/7] Configuring Flutter..."

"$HOME/flutter/bin/flutter" config \
  --android-sdk "$SDK_ROOT"

echo
echo "[7/7] Verifying Android toolchain..."

"$HOME/flutter/bin/flutter" doctor -v

echo
echo "=============================================="
echo " ANDROID SDK SETUP COMPLETE"
echo "=============================================="

echo
echo "SDK:"
echo "$SDK_ROOT"

echo
echo "Add these lines to your shell environment:"
echo
echo "export ANDROID_HOME=\"$SDK_ROOT\""
echo "export ANDROID_SDK_ROOT=\"$SDK_ROOT\""
echo "export PATH=\"\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH\""

echo
echo "Next step:"
echo "cd /home/dev/nukhbaa-backup-1787537565"
echo "flutter build apk --debug -t lib/elite_preview/elite_preview.dart"

echo
