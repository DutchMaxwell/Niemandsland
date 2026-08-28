#!/usr/bin/env python3
"""Generate the PUBLIC, text-free army-book index: armyId -> faction slug.

The table resolves a unit's registry key (`faction_folder`) from the Army Forge
army-book NAME, fetched at import time. When that fetch fails the key is lost and
every faction-scoped registry lookup silently collapses to the `common` fallback
(NML-1114). This index pins the mapping locally, so the key never depends on the
network:

    assets/solo/army_books_index.json
    {"<system>": {"<armyId>": {"faction_folder": …, "book_name": …, "version": …}}}

`faction_folder` is the book title's slug — the same slugs
`assets/solo/rules_mechanics_<system>.json` already publishes as faction section
keys (`keep-opr-faction-names` is settled policy), and the guard below refuses to
write a slug the registry does not know. **No rule text, no description, no unit
stats**: those are OPR content and stay out of this repo (THIRD_PARTY.md), which
is why only the three keys above may appear. The API is read ONCE here, at
generation time — never by the game.

    python3 tools/army_books_index.py --lists gf=~/farm/ai_lists_gf --lists aof=~/farm/ai_lists_aof
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import urllib.request

API_BASE = "https://army-forge.onepagerules.com/api"
SYSTEM_IDS = {"gf": 2, "gff": 3, "aof": 4, "aofs": 5, "aofr": 6}
OUT_PATH = "assets/solo/army_books_index.json"
ALLOWED_ENTRY_KEYS = {"faction_folder", "book_name", "version"}


def army_ids_in_pool(list_dir: str) -> set:
    """Every distinct `armyId` referenced by the lists in `list_dir` (units carry it)."""
    ids = set()
    for path in sorted(glob.glob(os.path.join(list_dir, "*.json"))):
        if os.path.basename(path).startswith("_"):
            continue
        with open(path, encoding="utf-8") as handle:
            for unit in json.load(handle).get("units", []):
                army_id = str(unit.get("armyId", "")).strip()
                if army_id:
                    ids.add(army_id)
    return ids


def build_index(pools: dict) -> dict:
    index = {}
    for system, list_dir in sorted(pools.items()):
        section = {}
        for army_id in sorted(army_ids_in_pool(list_dir)):
            url = "%s/army-books/%s?gameSystem=%d" % (API_BASE, army_id, SYSTEM_IDS[system])
            with urllib.request.urlopen(url, timeout=60) as response:
                book = json.load(response)
            name = str(book.get("name", "")).strip()
            if not name:
                raise SystemExit("army book %s/%s has no name" % (system, army_id))
            section[army_id] = {
                # opr_api_client.gd's own normalisation: lower, ' ' and '-' -> '_'.
                "faction_folder": name.lower().replace(" ", "_").replace("-", "_"),
                "book_name": name,
                "version": str(book.get("versionString", "")),
            }
        index[system] = section
    return index


def check_hygiene(index: dict, repo_root: str) -> None:
    """No stray key (a text leak), and every slug is a known registry faction section."""
    for system, section in sorted(index.items()):
        path = os.path.join(repo_root, "assets/solo/rules_mechanics_%s.json" % system)
        with open(path, encoding="utf-8") as handle:
            known = set(json.load(handle).get("factions", {}).keys())
        for army_id, entry in sorted(section.items()):
            extra = sorted(set(entry) - ALLOWED_ENTRY_KEYS)
            if extra:
                raise SystemExit("%s/%s carries forbidden keys: %s" % (system, army_id, extra))
            if entry["faction_folder"] not in known:
                raise SystemExit("%s/%s slug '%s' is no faction section of rules_mechanics_%s.json"
                                 % (system, army_id, entry["faction_folder"], system))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lists", action="append", default=[], metavar="SYSTEM=DIR",
                        help="AI-list pool to read armyIds from, e.g. gf=~/farm/ai_lists_gf")
    args = parser.parse_args()
    pools = {}
    for spec in args.lists:
        system, _, path = spec.partition("=")
        if system not in SYSTEM_IDS or not path:
            raise SystemExit("--lists wants SYSTEM=DIR, SYSTEM in %s" % sorted(SYSTEM_IDS))
        pools[system] = os.path.expanduser(path)
    if not pools:
        raise SystemExit("no --lists given")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    index = build_index(pools)
    check_hygiene(index, repo_root)
    with open(os.path.join(repo_root, OUT_PATH), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(index, indent="\t", sort_keys=True, ensure_ascii=False) + "\n")
    print("army_books_index: wrote %d books to %s" % (sum(len(s) for s in index.values()), OUT_PATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
