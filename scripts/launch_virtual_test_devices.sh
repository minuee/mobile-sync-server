#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DEVICE_NAME="${IOS_DEVICE_NAME:-iPhone 17}"
ANDROID_AVD_NAME="${ANDROID_AVD_NAME:-AudioSyncPixel36}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
EMU_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
ADB_BIN="${ADB_BIN:-adb}"

export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/Caskroom/android-platform-tools/37.0.0/platform-tools:/opt/homebrew/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT

printf '=== iOS Simulator boot ===\n'
xcrun simctl boot "$IOS_DEVICE_NAME" >/dev/null 2>&1 || true
open -a Simulator
sleep 5
xcrun simctl list devices booted | sed -n '1,80p'

printf '\n=== Android AVD launch ===\n'
if [ ! -x "$EMU_BIN" ]; then
  echo "Android emulator binary not found: $EMU_BIN" >&2
  exit 1
fi

if ! "$EMU_BIN" -list-avds | grep -qx "$ANDROID_AVD_NAME"; then
  echo "AVD not found: $ANDROID_AVD_NAME" >&2
  exit 1
fi

if ! pgrep -f "emulator.*@$ANDROID_AVD_NAME" >/dev/null 2>&1; then
  nohup "$EMU_BIN" -avd "$ANDROID_AVD_NAME" -no-snapshot >/tmp/${ANDROID_AVD_NAME}.log 2>&1 &
  echo "Launched AVD: $ANDROID_AVD_NAME"
else
  echo "AVD already running: $ANDROID_AVD_NAME"
fi

sleep 20
$ADB_BIN devices

printf '\n=== Flutter devices ===\n'
cd "$REPO_ROOT/mobile_app"
flutter devices
