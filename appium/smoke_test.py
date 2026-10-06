"""Appium (UiAutomator2) smoke test against a phone reached over network adb.

By default it opens the system Settings app, scrolls to "About phone", opens it
and saves a screenshot. That works on any stock Android phone and changes
nothing on the device. Point APP_PACKAGE / APP_ACTIVITY at your own app to use
it as a starting template.

Run:
    pip install -r appium/requirements.txt
    npm i -g appium && appium driver install uiautomator2
    appium &                                   # listens on 127.0.0.1:4723
    ADB_HOST=10.77.0.1 ADB_PORT=7401 python appium/smoke_test.py

Guide: https://cloudf.one/blog/cloud-phone-appium-setup
"""

import os
import sys
import time
from pathlib import Path

from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.webdriver.common.appiumby import AppiumBy


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        sys.exit(f"set {name}")
    return value


def build_options() -> UiAutomator2Options:
    opts = UiAutomator2Options()
    opts.platform_name = "Android"
    opts.automation_name = "UiAutomator2"
    # udid must be exactly the serial adb uses, i.e. host:port
    opts.udid = f"{env('ADB_HOST')}:{env('ADB_PORT')}"
    opts.app_package = env("APP_PACKAGE", "com.android.settings")
    opts.app_activity = env("APP_ACTIVITY", ".Settings")
    # a hosted phone keeps its state between runs; don't wipe logins every session
    opts.no_reset = True
    # one UiAutomator2 bridge port per phone, or parallel sessions collide
    opts.system_port = int(env("SYSTEM_PORT", "8201"))
    # defaults assume a USB cable. Over the internet every adb call has real
    # latency, and the default 20 s timeouts fail in ways that look like app bugs.
    opts.adb_exec_timeout = 60_000
    opts.uiautomator2_server_install_timeout = 60_000
    opts.uiautomator2_server_launch_timeout = 60_000
    opts.new_command_timeout = 120
    return opts


def main() -> int:
    out = Path(os.environ.get("OUT_DIR", "artifacts"))
    out.mkdir(parents=True, exist_ok=True)
    appium_url = os.environ.get("APPIUM_URL", "http://127.0.0.1:4723")

    driver = webdriver.Remote(appium_url, options=build_options())
    try:
        caps = driver.capabilities
        print("device:", caps.get("deviceManufacturer"), caps.get("deviceModel"),
              "android", caps.get("platformVersion"))

        if driver.current_package == "com.android.settings":
            about = driver.find_element(
                AppiumBy.ANDROID_UIAUTOMATOR,
                'new UiScrollable(new UiSelector().scrollable(true))'
                '.scrollIntoView(new UiSelector().textContains("About phone"))',
            )
            about.click()
            time.sleep(2)

        shot = out / "appium-smoke.png"
        driver.get_screenshot_as_file(str(shot))
        print("screenshot:", shot)
    finally:
        driver.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
