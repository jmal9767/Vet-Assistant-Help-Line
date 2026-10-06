"""Build output smoke test: cold launch and relaunch on a disposable iPhone simulator."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def run(*args, timeout=120):
    result = subprocess.run(args, check=True, text=True, capture_output=True, timeout=timeout)
    return result.stdout


app = Path(sys.argv[1]).resolve()
bundle_id = "com.jmal9767.VetAssistantHelpLine"
devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
candidate = next((device for runtime, items in devices.items() if ".iOS-" in runtime
                  for device in items if device["name"].startswith("iPhone")), None)
if candidate is None:
    raise RuntimeError("No available iPhone simulator runtime")
runtime = next(key for key, items in devices.items() if candidate in items)
device = run("xcrun", "simctl", "create", "Care Line Launch Check",
             candidate["deviceTypeIdentifier"], runtime).strip()
try:
    # Simulator builds still need CloudKit entitlements for the launch check.
    run("codesign", "--force", "--sign", "-", "--entitlements",
        "VetAssistantHelpLine/VetAssistantHelpLine.entitlements", str(app))
    run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b", timeout=240)
    run("xcrun", "simctl", "install", device, str(app))
    for attempt in range(2):
        output = run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle_id)
        match = re.search(r": (\d+)\s*$", output)
        if match is None:
            raise RuntimeError("Simulator did not report an app PID")
        pid = match.group(1)
        # Observe beyond initial rendering and CloudKit setup, not just successful spawning.
        time.sleep(10)
        services = run("xcrun", "simctl", "spawn", device, "launchctl", "list")
        if not any(line.split()[:1] == [pid] and bundle_id in line for line in services.splitlines()):
            raise RuntimeError(f"App exited after launch {attempt + 1} (PID {pid})")
        print(f"PASS: launch {attempt + 1} remains running", flush=True)
    screenshot = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "careline-launch.png"
    run("xcrun", "simctl", "io", device, "screenshot", str(screenshot))
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
    subprocess.run(["xcrun", "simctl", "delete", device], check=False)
