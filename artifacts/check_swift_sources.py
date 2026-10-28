"""Static checks for edited Swift files.

Mirrors the checks AGENTS.md asks for before a commit that touches Swift:
  1. delimiter balance per file, with string literals and comments stripped first
  2. top-level type redeclaration scan, column-0 declarations only

Xcode is not available here, so this is a static check, not a compile.
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

BACKSLASH = chr(92)
QUOTE = chr(34)


def strip_literals_and_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c == QUOTE:
            i += 1
            while i < n and text[i] != QUOTE:
                if text[i] == BACKSLASH:
                    i += 1
                i += 1
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main(paths: list[str]) -> int:
    failed = False
    for path in paths:
        text = Path(path).read_text(encoding="utf-8")
        code = strip_literals_and_comments(text)
        counts = Counter(code)
        for opener, closer in (("{", "}"), ("(", ")"), ("[", "]")):
            ok = counts[opener] == counts[closer]
            failed |= not ok
            print(f"{path}: {opener}{counts[opener]} {closer}{counts[closer]} "
                  f"{'OK' if ok else 'MISMATCH'}")
        tops = re.findall(
            r"(?m)^(?:private |public |internal |final |@\w+\s+)*(struct|class|enum|extension|protocol)\s+(\w+)",
            text,
        )
        dupes = [k for k, v in Counter(f"{t} {n}" for t, n in tops).items() if v > 1]
        # Nested CodingKeys/Entry/Coordinator types repeat legitimately and are indented.
        failed |= bool(dupes)
        print(f"{path}: {len(tops)} top-level types, duplicates: {dupes or 'none'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
