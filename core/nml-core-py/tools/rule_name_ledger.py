#!/usr/bin/env python3
"""Rule name ledger: emit WHICH GF/AoF rule names the census universe
contains, so a rule audit can be proven complete.

Two audit waves (2026-09-12/13) read GF/AoF rule names against the rulebooks
and confirmed 73 defects, but neither recorded which names it read - the
honest unread remainder was only statable as a range. This tool closes that
gap:

  * Without --audited: emit the universe as TSV to stdout, one row per
    (system, rule), header row `system<TAB>rule`, for the census's systems
    (gf, aof). The universe is the census's own (rule_universe_census.py:
    load_books + build_universe over the private book snapshot) - reused,
    never re-parsed. Before emitting, the row count is checked against the
    census's own per-system distinct-name counts; on a mismatch both numbers
    are printed and the tool exits non-zero rather than emitting a list
    nobody can trust.
  * --audited <file>: read `system<TAB>rule` lines (blank lines and `#`
    comment lines skipped) and print three counts plus the full names in
    each bucket: AUDITED (in both), UNAUDITED (in the universe, not in the
    file), UNKNOWN (in the file, not in the universe - a typo or a renamed
    rule).
  * Exit code: 0 when UNAUDITED and UNKNOWN are both empty, 1 otherwise -
    usable as a gate later. Deliberately NOT wired into CI (it would land
    red on day one: the audits are not complete). Usage errors exit 2.

PRIVATE-SAFE: the books are read at runtime from --books; nothing about
their content is baked into this file. Outputs carry rule names only.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rule_universe_census as census  # noqa: E402


def universe_pairs(books_dir: Path) -> list[tuple[str, str]]:
    """Sorted (system, rule) rows for the census's gf/aof universe, via the
    census's own book walk (load_books + build_universe)."""
    universe = census.build_universe(census.load_books(books_dir))
    return sorted(
        (system, name)
        for name, u in universe.items()
        for system in census.SYSTEMS
        if system in u["systems"]
    )


def census_counts(books_dir: Path) -> dict[str, int]:
    """The census's own distinct-name count per system, computed
    independently of universe_pairs' pair enumeration (name-set membership
    per system, not pair enumeration) - the two paths must agree."""
    universe = census.build_universe(census.load_books(books_dir))
    return {
        s: sum(1 for u in universe.values() if s in u["systems"])
        for s in census.SYSTEMS
    }


def parse_audited(path: Path) -> set[tuple[str, str]]:
    """A file of `system<TAB>rule` lines; blank lines and `#` comments are
    skipped. A malformed line is a usage error (exit 2), never silently
    dropped - a half-parsed audit list would fake completeness."""
    out: set[tuple[str, str]] = set()
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
            raise SystemExit(f"audited line not `system<TAB>rule`: {raw!r}")
        out.add((parts[0].strip(), parts[1].strip()))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Emit the census's GF/AoF rule-name universe and diff it"
        " against an audited list (AUDITED / UNAUDITED / UNKNOWN)."
    )
    ap.add_argument("--books", required=True,
                    help="directory with gf/ and aof/ book JSONs (private; read-only)")
    ap.add_argument("--audited", default=None,
                    help="file of system<TAB>rule lines already audited")
    args = ap.parse_args(argv)
    books_dir = Path(args.books)
    pairs = universe_pairs(books_dir)
    counts = census_counts(books_dir)
    if len(pairs) != sum(counts.values()):
        print(
            f"row count {len(pairs)} != census distinct-name count"
            f" {sum(counts.values())} (per system: {counts})"
            " - not emitting a list nobody can trust",
            file=sys.stderr,
        )
        return 2
    if args.audited is None:
        print("system\trule")
        for system, name in pairs:
            print(f"{system}\t{name}")
        return 0
    audited = parse_audited(Path(args.audited))
    universe = set(pairs)
    buckets = {
        "AUDITED": sorted(audited & universe),
        "UNAUDITED": sorted(universe - audited),
        "UNKNOWN": sorted(audited - universe),
    }
    for label, rows in buckets.items():
        print(f"{label}: {len(rows)}")
        for system, name in rows:
            print(f"{system}\t{name}")
    return 0 if not buckets["UNAUDITED"] and not buckets["UNKNOWN"] else 1


if __name__ == "__main__":
    sys.exit(main())