"""BOREAL_DIALER_CI_SIMULATOR_v682 - helpers for scripts/ci-simulator.sh (CI only).

  from-destinations FILE PLATFORM   newest concrete simulator in `xcodebuild -showdestinations` output
  runtime PLATFORM                  newest available runtime identifier (simctl runtimes JSON on stdin)
  devicetype PLATFORM RUNTIME       newest phone / watch model that runtime supports (same JSON on stdin)
"""
import json
import re
import sys

FAMILY = {"iOS": "iPhone", "watchOS": "Apple Watch"}


def version(text):
    return tuple(int(p) for p in re.findall(r"[0-9]+", text or "")) or (0,)


def from_destinations(path, platform):
    text = open(path, encoding="utf-8", errors="replace").read()
    best = None
    for line in text.splitlines():
        if "platform:" + platform + " Simulator" not in line or "Placeholder" in line:
            continue
        ident = re.search(r"id:([0-9A-Fa-f-]{8,})", line)
        name = re.search(r"name:([^,}]+)", line)
        if not ident or not name or FAMILY[platform] not in name.group(1):
            continue
        os_match = re.search(r"OS:([0-9.]+)", line)
        v = version(os_match.group(1)) if os_match else (0,)
        if best is None or v > best[0]:
            best = (v, ident.group(1))
    return best[1] if best else ""


def runtimes(platform):
    data = json.load(sys.stdin)
    found = [r for r in data.get("runtimes", []) if (r.get("platform") == platform or ("." + platform + "-") in str(r.get("identifier", ""))) and r.get("isAvailable", True)]
    return sorted(found, key=lambda r: version(r.get("version")))


def main(argv):
    cmd = argv[1]
    if cmd == "from-destinations":
        print(from_destinations(argv[2], argv[3]))
    elif cmd == "runtime":
        rs = runtimes(argv[2])
        print(rs[-1]["identifier"] if rs else "")
    elif cmd == "devicetype":
        rs = [r for r in runtimes(argv[2]) if r.get("identifier") == argv[3]]
        types = rs[0].get("supportedDeviceTypes", []) if rs else []
        family = FAMILY[argv[2]]
        names = [t for t in types if str(t.get("name", "")).startswith(family)]
        print(names[-1]["identifier"] if names else "")
    else:
        raise SystemExit("unknown command " + cmd)


if __name__ == "__main__":
    main(sys.argv)
