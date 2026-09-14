#!/usr/bin/env python3
# BOREAL_DIALER_IF_MODIFIER_GUARD_v178
# v174 wrapped four Pickers in `if BorealLine.enabled.count > 1 { ... }` but left
# `.font(.caption2)` attached to the if's closing brace. A SwiftUI modifier applies
# to a view, not to a control-flow statement, so swiftc reports "consecutive
# statements on a line must be separated by ';'" - a message that names neither the
# modifier nor the if. swift-lint passed; ios-build spent three minutes finding it.
#
# This is the third build lost to a reflow of this shape (see also v164, v167).
# The check is a brace-depth scan: flag any `}` that carries, or is immediately
# followed by, a leading-dot modifier when the brace it closes was opened by a
# control-flow keyword.
import re
import sys
import pathlib

OPENER = re.compile(r'^\s*(?:\}\s*else\s+)?(?:if|else|guard|switch|for|while)\b.*\{\s*$')
CLOSER = re.compile(r'^\s*\}\s*\.[A-Za-z_]')
LEADING_DOT = re.compile(r'^\s*\.[A-Za-z_]')


def check(path):
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    stack = []
    bad = []
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        opens = line.count("{") - line.count("}")
        trails = n < len(lines) and LEADING_DOT.match(lines[n])
        if CLOSER.match(line) or (stripped == "}" and trails):
            if stack and stack[-1]:
                bad.append((n, stripped))
        if opens > 0:
            stack.extend([bool(OPENER.match(line))] * opens)
        elif opens < 0:
            for _ in range(-opens):
                if stack:
                    stack.pop()
    return bad


def main(paths):
    failed = False
    for path in paths:
        for n, text in check(path):
            print(
                f"{path}:{n}: error: a modifier is attached to the closing brace of a "
                f"control-flow statement; move it onto the view inside the block - {text}"
            )
            failed = True
    if failed:
        print("")
        print("swiftc reports this as \"consecutive statements on a line must be")
        print("separated by ';'\". Put the modifier on the view, not on the `if`.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
