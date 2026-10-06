#!/usr/bin/env bash
# Install an APK on a cloudf.one phone over the REST API, no adb needed.
# Handy when you don't have the adb tunnel, or from a machine that can't run WireGuard.
#
# Accepts .apk, and split bundles (.apks, .xapk, zip of apks). Capped at 512 MB,
# one install per phone at a time, 30 an hour per account (per cloudf.one/developers).
#
# Env: STF_TOKEN, DEVICE_SERIAL, APK_PATH, optional STF_API
set -euo pipefail

: "${STF_TOKEN:?}" "${DEVICE_SERIAL:?}" "${APK_PATH:?}"
API="${STF_API:-https://cloudf.one/api/v1}"

curl -sS --fail-with-body -X POST \
  -H "Authorization: Bearer ${STF_TOKEN}" \
  -F "file=@${APK_PATH}" \
  "${API}/devices/${DEVICE_SERIAL}/install"
echo
