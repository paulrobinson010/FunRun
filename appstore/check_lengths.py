"""Check appstore/metadata.md against App Store Connect's limits.

Each limited field in the metadata is stored as an indented block under
its heading; this pulls those blocks out and measures them.
"""

import re
import sys

LIMITS = {
    "Name": 30,
    "Subtitle": 30,
    "Promotional text": 170,
    "Keywords": 100,
    "Description": 4000,
    "What's New": 4000,
    "Beta App Description": 4000,
    "What to Test": 4000,
}

text = open("appstore/metadata.md").read()
blocks = {}
current = None
for line in text.splitlines():
    heading = re.match(r"#+\s+(.*?)(?:\s*\([^)]*\))?\s*$", line)
    if heading:
        current = heading.group(1).strip()
        continue
    if current and line.startswith("    "):
        blocks.setdefault(current, []).append(line[4:])

failures = 0
for field, limit in LIMITS.items():
    body = "\n".join(blocks.get(field, [])).strip()
    if not body:
        print(f"{field:22s} MISSING")
        failures += 1
        continue
    # Only the first block matters where alternatives are listed.
    length = len(body)
    status = "ok" if length <= limit else "OVER LIMIT"
    if length > limit:
        failures += 1
    print(f"{field:22s} {length:>5}/{limit:<5} {status}")

sys.exit(1 if failures else 0)
