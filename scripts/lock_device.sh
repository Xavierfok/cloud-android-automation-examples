#!/usr/bin/env bash
# Take the control lock on one phone and open its remote-debug (adb) port.
#
# Works against any DeviceFarmer STF instance, including cloudf.one.
# On success it prints one line to stdout:   ADB_PORT=<port>
# so in GitHub Actions you can do:           scripts/lock_device.sh >> "$GITHUB_ENV"
#
# Env:
#   STF_TOKEN        access token (STF console > Settings > Access tokens)
#   DEVICE_SERIAL    the phone's serial (GET /api/v1/devices lists yours)
#   STF_API          default https://cloudf.one/api/v1
#   LOCK_TIMEOUT_MS  how long STF keeps the lock if you never release it (default 15 min)
#
# Guide: https://cloudf.one/blog/cloud-phone-adb-scripting
set -euo pipefail

: "${STF_TOKEN:?set STF_TOKEN}"
: "${DEVICE_SERIAL:?set DEVICE_SERIAL}"
API="${STF_API:-https://cloudf.one/api/v1}"
LOCK_MS="${LOCK_TIMEOUT_MS:-900000}"
AUTH="Authorization: Bearer ${STF_TOKEN}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

json_get() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1], ""))' "$1"; }

# 1. take the lock. If we already hold it (say, a browser tab has it open) STF
#    refuses a second lock, so check our own device list before giving up.
code=$(curl -sS -o "$tmp" -w '%{http_code}' -X POST \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"serial\":\"${DEVICE_SERIAL}\",\"timeout\":${LOCK_MS}}" \
  "${API}/user/devices")

if [ "$code" != "200" ]; then
  held=$(curl -fsS -H "$AUTH" "${API}/user/devices" | python3 -c '
import json, sys
serial = sys.argv[1]
devs = json.load(sys.stdin).get("devices", [])
print("yes" if any(d.get("serial") == serial for d in devs) else "no")' "$DEVICE_SERIAL")
  if [ "$held" = "yes" ]; then
    echo "already holding ${DEVICE_SERIAL}, carrying on" >&2
  else
    echo "could not lock ${DEVICE_SERIAL} (HTTP ${code}): $(cat "$tmp")" >&2
    exit 1
  fi
fi

# 2. open remote debug. STF answers with "host:port". The host is the panel's
#    own hostname; behind a tunnel you keep the port and swap the host for the
#    tunnel address (ADB_HOST).
resp=$(curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" -d '{}' \
  "${API}/user/devices/${DEVICE_SERIAL}/remoteConnect")
url=$(printf '%s' "$resp" | json_get remoteConnectUrl)
if [ -z "$url" ]; then
  echo "remoteConnect gave no URL: ${resp}" >&2
  exit 1
fi

echo "remote debug open: ${url}" >&2
echo "ADB_PORT=${url##*:}"
