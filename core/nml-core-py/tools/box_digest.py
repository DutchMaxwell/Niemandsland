"""Per-file result digests, farm-independent (GATE Q C4, NML-1073).

`tools/throughput.py`'s determinism checks compare digests INSIDE one run
(single process vs. its own parallel workers). This tool is the other half:
it prints `selfplay.result_digest` for every `core_s<seed>.json` a harvest
already wrote, so a box's output can be diffed against the laptop's without
either machine reaching the other — copy both digest listings somewhere they
can meet (a paste, a shared file) and run `diff` on them. No servers, no farm
access.

USAGE:
    python tools/box_digest.py <dir>

Prints one `seed=<seed> digest=<hex>` line per `core_s*.json` file in <dir>,
sorted by seed. `wall_seconds` (the one Python-only timing field —
`selfplay.DIGEST_EXCLUDED_FIELDS`) is excluded automatically, so a box's
harvest and the laptop's own run of the same seed digest equal even though
each ran at its own wall-clock speed.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import selfplay as sp  # noqa: E402

FILE_RE = re.compile(r"^core_s(\d+)\.json$")


def digests_in(d: Path) -> list[tuple[int, str]]:
    rows = []
    for p in sorted(d.iterdir()):
        m = FILE_RE.match(p.name)
        if not m:
            continue
        with open(p, encoding="utf-8") as f:
            result = json.load(f)
        rows.append((int(m.group(1)), sp.result_digest(result)))
    rows.sort(key=lambda r: r[0])
    return rows


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: box_digest.py <dir>", file=sys.stderr)
        return 2
    d = Path(argv[0])
    if not d.is_dir():
        print("not a directory: %s" % d, file=sys.stderr)
        return 2
    rows = digests_in(d)
    if not rows:
        print("no core_s*.json files in %s" % d, file=sys.stderr)
        return 2
    for seed, digest in rows:
        print("seed=%d digest=%s" % (seed, digest))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
