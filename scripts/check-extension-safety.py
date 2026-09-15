#!/usr/bin/env python3
"""BOREAL_DIALER_EXTENSION_SAFETY_v217

Fails the build early when a file under Sources/Shared references a symbol that
only the main app target compiles.

project.yml compiles Sources/Shared into BorealDialerLiveActivity, which does not
get Sources/Networking. v210 put an APIClient call in Shared; swiftc only reported
it 90 seconds into the extension's compile, in a 4000-line log. This catches it in
under a second, before xcodebuild starts.
"""
import pathlib
import re
import sys

SHARED = pathlib.Path("Sources/Shared")
# Symbols defined in app-only source roots.
APP_ONLY_ROOTS = ["Sources/Networking", "Sources/Auth", "Sources/Voice", "Sources/Contacts"]


def app_only_symbols() -> set[str]:
    found = set()
    for root in APP_ONLY_ROOTS:
        for f in pathlib.Path(root).rglob("*.swift"):
            for m in re.finditer(
                r'^(?:public |internal |final |)*(?:class|struct|enum|actor)\s+(\w+)',
                f.read_text(), re.M,
            ):
                found.add(m.group(1))
    return found


# BOREAL_DIALER_WIDGET_SELF_CONTAINED_v226
# project.yml gives these targets a single source directory and nothing else, so
# anything they reference must be defined inside it. v211 called a Sources/Shared
# type from WatchWidget and the error only surfaced 90 seconds into the watch
# build.
ISOLATED_TARGETS = {
    "WatchWidget": ["Sources/Shared", "Sources/Networking", "Sources/Voice", "UI"],
}
# UI also defines a model named TimelineEntry, but the widget's TimelineEntry is
# the WidgetKit protocol. Exclude that intentional SDK-name collision.
ISOLATED_TARGET_ALLOWLIST = {
    "WatchWidget": {"TimelineEntry"},
}


def symbols_defined_in(root: str) -> set[str]:
    found = set()
    for f in pathlib.Path(root).rglob("*.swift"):
        for m in re.finditer(
            r'^(?:public |internal |final |)*(?:class|struct|enum|actor)\s+(\w+)',
            f.read_text(), re.M,
        ):
            found.add(m.group(1))
    return found


def check_isolated_targets() -> list[str]:
    problems = []
    for target_dir, forbidden_roots in ISOLATED_TARGETS.items():
        if not pathlib.Path(target_dir).exists():
            continue
        forbidden = set()
        for root in forbidden_roots:
            if pathlib.Path(root).exists():
                forbidden |= symbols_defined_in(root)
        own = symbols_defined_in(target_dir)
        forbidden -= own
        forbidden -= ISOLATED_TARGET_ALLOWLIST.get(target_dir, set())
        for f in pathlib.Path(target_dir).rglob("*.swift"):
            text = f.read_text()
            for sym in forbidden:
                if re.search(rf'\b{re.escape(sym)}\b', text):
                    problems.append(f"  {f} -> {sym} (not compiled into this target)")
    return problems


def main() -> int:
    if not SHARED.exists():
        return 0
    symbols = app_only_symbols()
    bad = []
    for f in SHARED.rglob("*.swift"):
        text = f.read_text()
        for sym in symbols:
            if re.search(rf'\b{re.escape(sym)}\b', text):
                bad.append((str(f), sym))
    isolated = check_isolated_targets()
    if isolated:
        print("Isolated targets referencing code they do not compile:\n")
        for line in isolated:
            print(line)
        print(
            "\nThese targets have one source directory in project.yml. Duplicate the\n"
            "value you need (an app-group key, a literal) rather than importing the type."
        )
        return 1

    if bad:
        print("Files in Sources/Shared referencing app-only symbols:\n")
        for path, sym in bad:
            print(f"  {path} -> {sym}")
        print(
            "\nSources/Shared is compiled into the app extensions, which do not\n"
            "compile " + ", ".join(APP_ONLY_ROOTS) + ".\n"
            "Move the code that needs it into an app-only source root and extend\n"
            "the shared type from there."
        )
        return 1
    print(f"Sources/Shared is extension-safe ({len(symbols)} app-only symbols checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
