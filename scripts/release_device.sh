#!/usr/bin/env bash
# Close remote debug and give the phone's control lock back.
# Safe to run twice, and safe to run when the lock step never succeeded,
# which is why CI calls it under `if: always()`.
#
# Env: STF_TOKEN, DEVICE_SERIAL, optional STF_API (default https://cloudf.one/api/v1)
set -uo pipefail

: "${STF_TOKEN:?set STF_TOKEN}"
: "${DEVICE_SERIAL:?set DEVICE_SERIAL}"
API="${STF_API:-https://cloudf.one/api/v1}"
AUTH="Authorization: Bearer ${STF_TOKEN}"

if [ -n "${ADB_HOST:-}" ] && [ -n "${ADB_PORT:-}" ] && command -v adb >/dev/null; then
  adb disconnect "${ADB_HOST}:${ADB_PORT}" >/dev/null 2>&1
fi

for path in "user/devices/${DEVICE_SERIAL}/remoteConnect" "user/devices/${DEVICE_SERIAL}"; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "$AUTH" "${API}/${path}")
  echo "DELETE /${path} -> HTTP ${code}" >&2
done
exit 0
