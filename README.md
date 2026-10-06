# cloud-android-automation-examples

Small, working scripts for driving a real Android phone that isn't on your desk. Everything goes through adb over the network: plain shell, Appium, Maestro, Espresso, scrcpy, and a GitHub Actions job that ties them together.

I run [cloudf.one](https://cloudf.one), which rents real Android phones on Singapore SIMs, so the defaults point there. The adb parts work with any phone you can reach with `adb connect host:port`: a handset on your LAN after `adb tcpip 5555`, your own [DeviceFarmer STF](https://github.com/DeviceFarmer/stf) rack, or a hosted one. The lock/release scripts work against any STF instance if you set `STF_API`.

## What's in here

| file | what it does | longer write-up |
|---|---|---|
| `scripts/adb_connect.sh` | connect over the network, retry until the phone is really `device`, explain `unauthorized` | [GitHub Actions guide](https://cloudf.one/blog/cloud-phone-github-actions-ci) |
| `scripts/adb_smoke.sh` | model, Android version, carrier, battery, screenshot, optional install + launch with crash check | [ADB scripting guide](https://cloudf.one/blog/cloud-phone-adb-scripting) |
| `scripts/lock_device.sh` / `release_device.sh` | take and give back a phone's lock over the STF REST API, open remote debug, print the adb port | [ADB scripting guide](https://cloudf.one/blog/cloud-phone-adb-scripting) |
| `scripts/run_instrumented.sh` | Espresso / instrumented tests with only adb on the box | [Espresso guide](https://cloudf.one/blog/cloud-phone-espresso) |
| `scripts/install_apk_rest.sh` | install an APK over cloudf.one's REST API, no adb at all | [developer docs](https://cloudf.one/developers) |
| `appium/smoke_test.py` | UiAutomator2 session with timeouts sized for a remote phone | [Appium guide](https://cloudf.one/blog/cloud-phone-appium-setup) |
| `maestro/settings_flow.yaml` | a read-only Maestro flow you can swap your app into | [Maestro guide](https://cloudf.one/blog/cloud-phone-maestro-ui-testing) |
| `.github/workflows/real-device-tests.yml` | tunnel up, lock, connect, test, always release | [GitHub Actions guide](https://cloudf.one/blog/cloud-phone-github-actions-ci) |

Mirroring the screen is one command, so there's no file for it; see [scrcpy](#scrcpy) below.

## Getting adb to the phone

Any phone: if `adb connect HOST:PORT` followed by `adb devices` shows it as `device`, every script here works. Set `ADB_HOST` and `ADB_PORT` and skip to the quick start.

On cloudf.one, be aware of one thing before you build on this. **adb over the internet isn't open to everyone yet.** The panel's ingress is HTTP and websockets only, so the `cloudf.one:PORT` address STF hands you isn't reachable from outside on its own. What works is a WireGuard tunnel scoped to your own phone. It's live, but by invitation and only on some phones so far. Message [@xavierfok](https://t.me/xavierfok) or email hello@cloudf.one and I'll tell you straight whether yours can take it. Without the tunnel you still get the browser console and the REST API (device list, locks, APK install), which is what `install_apk_rest.sh` uses.

Once you're on the tunnel:

1. Import the WireGuard config from the adb tunnel page in your account and switch it on.
2. Add `~/.android/adbkey.pub` in the phone console under Settings > Keys. STF only accepts an adb key that belongs to whoever holds the phone right now.
3. Open remote debug in the console, or run `scripts/lock_device.sh`, which calls `POST /user/devices/{serial}/remoteConnect` for you. You get back `cloudf.one:PORT`.
4. Connect to `10.77.0.1:PORT`, same port. That's `ADB_HOST=10.77.0.1`.

## Quick start

```bash
cp .env.example .env        # fill it in, it's gitignored
set -a; . ./.env; set +a

export "$(bash scripts/lock_device.sh)"  # exports ADB_PORT; skip this if you're not on STF
bash scripts/adb_connect.sh
bash scripts/adb_smoke.sh               # prints device facts, saves artifacts/before.png

APK_PATH=app-debug.apk APP_PACKAGE=com.example.app bash scripts/adb_smoke.sh

bash scripts/release_device.sh          # when you're done
```

The scripts want bash, curl and python3 (used only to parse JSON). On macOS, `brew install coreutils` gets you `timeout`; without it the scripts still run, just without a cap on hung adb calls.

## Appium

```bash
npm i -g appium && appium driver install uiautomator2
pip install -r appium/requirements.txt     # Python 3.10+
appium &
python appium/smoke_test.py
```

The default run opens Settings and scrolls to About phone, so it works on any phone and changes nothing. Set `APP_PACKAGE` and `APP_ACTIVITY` to run against your own app.

Two settings carry most of the weight. `udid` has to be the exact `host:port` adb uses. And the timeouts get raised to 60 s, because the defaults assume a USB cable and a 20 s `adbExecTimeout` over a link with 80 ms round trips fails in ways that look like bugs in your app. Running several phones at once? Give each session its own `SYSTEM_PORT`, otherwise the UiAutomator2 bridges collide and the sessions hang.

## Maestro

```bash
maestro --device "$ADB_HOST:$ADB_PORT" test maestro/settings_flow.yaml
```

## Espresso

With Gradle, AGP picks the device from `ANDROID_SERIAL`:

```bash
ANDROID_SERIAL="$ADB_HOST:$ADB_PORT" ./gradlew connectedDebugAndroidTest
```

If the APKs come from another job and you only have adb, `scripts/run_instrumented.sh` installs both and runs `am instrument`, failing on `FAILURES!!!` or a crashed process.

## scrcpy

```bash
scrcpy --serial "$ADB_HOST:$ADB_PORT" --max-size 1024 --video-bit-rate 4M --max-fps 30
```

Start low. If it stutters, drop the bitrate before the resolution. The [scrcpy guide](https://cloudf.one/blog/cloud-phone-scrcpy-control) covers codecs and keyboard input.

## GitHub Actions

`.github/workflows/real-device-tests.yml` is manual-trigger only so forks don't go red on every push. Add these repository secrets, then run it from the Actions tab:

| secret | value |
|---|---|
| `STF_TOKEN` | access token from the phone console, Settings > Access tokens |
| `DEVICE_SERIAL` | the phone's serial (`GET /api/v1/devices` lists yours) |
| `WG_CONFIG` | the whole WireGuard `.conf` for that phone |
| `ADB_PRIVATE_KEY` / `ADB_PUBLIC_KEY` | an adb keypair whose `.pub` you registered in the console |

The adb key is the step people miss. A hosted runner is a brand-new machine every time, so adb generates a brand-new key, and STF refuses it. Make one keypair, register it once, and store both halves as secrets.

The job uses a concurrency group, so two pushes queue for the phone instead of corrupting each other's state, and the release and tunnel-down steps run under `if: always()` so a failed test still gives the phone back.

## Things that bite

- `offline` straight after `adb connect` usually just means the tunnel wasn't up yet. `adb_connect.sh` retries with a backoff.
- `adb server version doesn't match`: your platform-tools are old. Update them.
- A browser tab with the phone open holds the same lock the API takes. Close it, or let `lock_device.sh` notice you already hold it.
- One WireGuard config per phone. Running it on your laptop and in CI at the same moment makes the two fight over the peer.
- Never set a screen lock, PIN or pattern on a hosted phone. Nobody can clear it remotely.
- On cloudf.one specifically: Wi-Fi stays off (traffic goes out over the SIM, that's the point), sideloading on the phone itself is blocked so installs go through adb or the API, and calls and SMS are off limits under the [terms](https://cloudf.one/terms).

## License

MIT, see [LICENSE](LICENSE). Use it for anything.
