#!/usr/bin/env python3
"""Generate the names-only army-book carrier fixture of the modeled-rule guard.

    python3 tools/book_rule_carriers.py <books_dir> [--out test/fixtures/book_rule_carriers_v36.json] [--snapshot LABEL]

`<books_dir>` is in the NML_ARMY_BOOKS_DIR format: `<system>/<armyId>.json` (a `<slug>__<armyId>.json` name works too) plus
`<system>/_common.json`, the core-rulebook rule list, whose names are excluded. Slugs come from the public
`assets/solo/army_books_index.json`. Output: per book, the distinct rule names its units carry. Names only (THIRD_PARTY.md).
"""
import argparse
import glob
import json
import os

SYSTEMS = ("aof", "gf")
INDEX_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "solo", "army_books_index.json")


def rule_names_of(obj, acc: set) -> None:
    """Collect the names of `ArmyBookRule` entries from an items / gains / weapons structure (recursive)."""
    if isinstance(obj, list):
        for entry in obj:
            rule_names_of(entry, acc)
    elif isinstance(obj, dict):
        if obj.get("type") == "ArmyBookRule" and obj.get("name"):
            acc.add(obj["name"])
        for key in ("content", "specialRules", "gains", "rules", "items", "weapons"):
            rule_names_of(obj.get(key), acc)


def book_rule_names(book: dict) -> set:
    """Every rule name any unit of `book` carries: its own, item, weapon and upgrade-granted rules."""
    packages = {p["uid"]: p for p in book.get("upgradePackages", [])}
    names: set = set()
    for unit in book.get("units", []):
        rule_names_of(unit.get("items", []), names)
        names.update(r["name"] for r in unit.get("rules", []))
        names.update(r["name"] for w in unit.get("weapons", []) for r in w.get("specialRules", []))
        for uid in unit.get("upgrades", []):
            rule_names_of([o.get("gains", []) for s in packages.get(uid, {}).get("sections", []) for o in s.get("options", [])], names)
    return names


def build(books_dir: str, snapshot: str) -> dict:
    index = json.load(open(INDEX_PATH, encoding="utf-8"))
    source = "python3 tools/book_rule_carriers.py <books_dir> (NML_ARMY_BOOKS_DIR format: <system>/<armyId>.json + <system>/_common.json)"
    out: dict = {"_meta": {"what": "per army book, the distinct rule names its units carry, core-rulebook names excluded (names only)",
                           "snapshot": snapshot, "source": source,
                           "used_by": "core/nml-core/src/tests/unit/v36_data_rows/f5c_modeled_guard.rs"}}
    for system in SYSTEMS:
        core = {r["name"] for r in json.load(open(os.path.join(books_dir, system, "_common.json"), encoding="utf-8"))["rules"]}
        out[system] = {}
        for path in sorted(glob.glob(os.path.join(books_dir, system, "*.json"))):
            stem = os.path.basename(path)[: -len(".json")]
            book = json.load(open(path, encoding="utf-8"))
            if stem.startswith("_") or not book.get("units"):
                continue   # _common.json, or an empty shell (no units): nothing carried, and the index does not list it
            entry = index.get(system, {}).get(stem.rsplit("__", 1)[-1])
            if entry is None:
                raise SystemExit("%s: armyId is not in assets/solo/army_books_index.json" % path)
            out[system][entry["faction_folder"]] = sorted(book_rule_names(book) - core)
    return out


def write(data: dict, path: str) -> None:
    """One line per book keeps the fixture reviewable and its diff small."""
    blocks = [' "_meta": ' + json.dumps(data["_meta"], ensure_ascii=False)] + [
        ' "%s": {\n%s\n }' % (s, ",\n".join("  %s: %s" % (json.dumps(b), json.dumps(n, ensure_ascii=False))
                                            for b, n in sorted(data[s].items()))) for s in SYSTEMS]
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("{\n" + ",\n".join(blocks) + "\n}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("books_dir")
    parser.add_argument("--out", default="test/fixtures/book_rule_carriers_v36.json")
    parser.add_argument("--snapshot", default="")
    args = parser.parse_args()
    write(build(args.books_dir, args.snapshot), args.out)
