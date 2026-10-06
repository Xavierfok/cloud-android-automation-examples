#!/usr/bin/env bash
# Run Espresso / instrumented tests on a network-adb phone without Gradle.
#
# If you build with Gradle you can skip this file entirely; AGP honours
# ANDROID_SERIAL, so this is enough:
#   ANDROID_SERIAL="$ADB_HOST:$ADB_PORT" ./gradlew connectedDebugAndroidTest
#
# This script is for when the APKs come from somewhere else (a build artifact,
# another job) and you only have adb on the runner.
#
# Env:
#   ADB_HOST, ADB_PORT
#   APP_APK        e.g. app/build/outputs/apk/debug/app-debug.apk
#   TEST_APK       e.g. app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
#   TEST_PACKAGE   e.g. com.example.app.test
#   RUNNER         default androidx.test.runner.AndroidJUnitRunner
#
# Guide: https://cloudf.one/blog/cloud-phone-espresso
set -euo pipefail

: "${ADB_HOST:?}" "${ADB_PORT:?}" "${APP_APK:?}" "${TEST_APK:?}" "${TEST_PACKAGE:?}"
target="${ADB_HOST}:${ADB_PORT}"
runner="${RUNNER:-androidx.test.runner.AndroidJUnitRunner}"
log="${OUT_DIR:-./artifacts}/instrument.txt"
mkdir -p "$(dirname "$log")"

adb -s "$target" install -r "$APP_APK"
adb -s "$target" install -r -t "$TEST_APK"

# -w waits for the run to finish, -r gives raw output we can grep.
# Remote phones are slower than a USB one; keep the timeout generous.
if command -v timeout >/dev/null; then TO=(timeout 1800); else TO=(); fi
${TO[@]+"${TO[@]}"} adb -s "$target" shell am instrument -w -r "${TEST_PACKAGE}/${runner}" | tee "$log"

if grep -qE "FAILURES!!!|INSTRUMENTATION_FAILED|shortMsg=Process crashed" "$log"; then
  echo "instrumented tests failed" >&2
  exit 1
fi
if ! grep -q "INSTRUMENTATION_CODE: -1" "$log"; then
  echo "instrumentation did not finish cleanly, see ${log}" >&2
  exit 1
fi
echo "instrumented tests passed"
