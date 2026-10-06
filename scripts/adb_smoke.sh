#!/usr/bin/env bash
# A small smoke test over network adb: print what the phone is, grab a
# screenshot, and optionally install and launch your build.
#
# Env:
#   ADB_HOST, ADB_PORT   the phone (run adb_connect.sh first)
#   APK_PATH             optional, an .apk to install (-r keeps app data)
#   APP_PACKAGE          optional, package to launch after install
#   OUT_DIR              where screenshots and logcat go (default ./artifacts)
#
# Guide: https://cloudf.one/blog/cloud-phone-adb-scripting
set -euo pipefail

: "${ADB_HOST:?set ADB_HOST}"
: "${ADB_PORT:?set ADB_PORT}"
target="${ADB_HOST}:${ADB_PORT}"
out="${OUT_DIR:-./artifacts}"
mkdir -p "$out"

# cap every adb call: one hung command over a network link can stall a job for
# hours. `timeout` is GNU coreutils (on macOS: brew install coreutils).
if command -v timeout >/dev/null; then TO=(timeout 120); else TO=(); fi
a() { ${TO[@]+"${TO[@]}"} adb -s "$target" "$@"; }
prop() { a shell getprop "$1" | tr -d '\r'; }

echo "model:    $(prop ro.product.manufacturer) $(prop ro.product.model)"
echo "android:  $(prop ro.build.version.release) (sdk $(prop ro.build.version.sdk))"
echo "carrier:  $(prop gsm.operator.alpha)"
echo "network:  $(prop gsm.network.type)"
echo "battery:  $(a shell dumpsys battery | tr -d '\r' | awk -F': ' '/ level:/{print $2"%"}')"

# wake the screen so the screenshot is not black. Never set a lock screen on a
# hosted phone; most providers cannot recover one remotely.
a shell input keyevent KEYCODE_WAKEUP
a exec-out screencap -p > "${out}/before.png"
echo "screenshot: ${out}/before.png"

if [ -n "${APK_PATH:-}" ]; then
  echo "installing ${APK_PATH}"
  a install -r "$APK_PATH"
fi

if [ -n "${APP_PACKAGE:-}" ]; then
  a logcat -c
  # monkey with one event = "launch the app's main activity" without knowing its name
  a shell monkey -p "$APP_PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null
  sleep 6
  a exec-out screencap -p > "${out}/after-launch.png"
  a logcat -d -t 300 > "${out}/logcat.txt"
  if grep -q "FATAL EXCEPTION" "${out}/logcat.txt"; then
    echo "app crashed on launch, see ${out}/logcat.txt" >&2
    exit 1
  fi
  echo "launched ${APP_PACKAGE}, screenshot: ${out}/after-launch.png"
fi
