"""使えるシミュレータの中から、いちばん新しい iOS の iPhone (Pro・Max 以外を優先) の UDID を出す。"""
import json
import re
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
best = None
for runtime, items in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in items:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        preference = 2 if ("Pro" in name and "Max" not in name) else 1 if "Max" not in name else 0
        key = (version, preference, name)
        if best is None or key > best[0]:
            best = (key, device["udid"])
print(best[1] if best else "")
