#!/usr/bin/env bash
# Connect adb to a phone over the network and wait until it is really usable.
#
# The first `adb connect` after a tunnel comes up often returns before the link
# is ready, and the phone shows as "offline". So: connect, check the state,
# back off, try again. A phone that never shows up is a setup failure, not a
# test failure, and this script exits non-zero so CI reports it that way.
#
# Env: ADB_HOST, ADB_PORT, optional ADB_CONNECT_TRIES (default 6)
# Guide: https://cloudf.one/blog/cloud-phone-github-actions-ci
set -uo pipefail

: "${ADB_HOST:?set ADB_HOST (on cloudf.one this is the tunnel address, 10.77.0.1)}"
: "${ADB_PORT:?set ADB_PORT}"
target="${ADB_HOST}:${ADB_PORT}"
tries="${ADB_CONNECT_TRIES:-6}"

for i in $(seq 1 "$tries"); do
  adb connect "$target" >/dev/null 2>&1
  sleep 2
  # read the state from `adb devices`: get-state errors out on an unauthorized
  # phone instead of saying so, and that is the case worth a clear message.
  state=$(adb devices | awk -v t="$target" '$1 == t { print $2 }')
  case "$state" in
    device)
      echo "connected: ${target}"
      exit 0 ;;
    unauthorized)
      echo "adb reached ${target} but the key was refused." >&2
      echo "Register ~/.android/adbkey.pub in the STF console (Settings > Keys) and hold the phone's lock." >&2
      exit 1 ;;
  esac
  echo "attempt ${i}/${tries}: state='${state:-none}', retrying" >&2
  adb disconnect "$target" >/dev/null 2>&1
  sleep $((i * 2))
done

echo "could not reach ${target}. Is the tunnel up, and did remote debug open on that port?" >&2
exit 1
