#!/usr/bin/env python3
"""Generate Aura Channel metadata and the explicit table-registry debt manifest.

Use --plan for deterministic, whole-name slices, then --names with that fixed
name list. Existing primitives are never overwritten. Writes require --write.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

PRIORITY = {name + " Aura" for name in (
    "Scout", "Ambush", "Rapid Rush", "Relentless", "Piercing Assault")}
DEFERRED = {"Piercing Fighter Aura", "Piercing Shooter Aura"}


def entries(data):
    yield "common", data["common"]
    yield from sorted(data["factions"].items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--priority", action="store_true")
    mode.add_argument("--names", nargs="+")
    mode.add_argument("--plan", action="store_true")
    mode.add_argument("--audit", action="store_true")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--exclude-names", nargs="+", default=[],
                        help="names reserved by another open slice; also rejected by --names")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    maps = {path: json.loads(path.read_text()) for path in sorted(
        (args.repo / "assets/solo").glob("rules_mechanics_*.json"))}
    if len(maps) != 5 or args.limit < 1:
        parser.error("expected five system maps and a positive slice limit")
    pending = defaultdict(list)
    all_names = set()
    for path, data in maps.items():
        for faction, rules in entries(data):
            for name, entry in sorted(rules.items()):
                all_names.add(name)
                if name in args.exclude_names or not name.endswith(" Aura") or entry.get("primitive"):
                    continue
                base = name.removesuffix(" Aura")
                resolved = rules.get(base, data["common"].get(base, {}))
                if name in DEFERRED or not resolved.get("primitive"):
                    continue
                if entry.get("params"):
                    parser.error(f"unimplemented entry already has params: {path.name}/{faction}/{name}")
                pending[name].append(entry)
    if args.plan:
        batch, count = [], 0
        for name in sorted(pending):
            if batch and count + len(pending[name]) > args.limit:
                print(json.dumps({"names": batch, "entries": count}))
                batch, count = [], 0
            batch.append(name)
            count += len(pending[name])
        if batch:
            print(json.dumps({"names": batch, "entries": count}))
    selected = PRIORITY if args.priority else set(args.names or [])
    if selected - all_names or selected & (DEFERRED | set(args.exclude_names)):
        parser.error("unknown, reserved or deferred resolver families selected")
    changed = 0
    for name in sorted(selected):
        for entry in pending[name]:
            entry["primitive"] = "Aura Channel"
            entry["params"] = {"grants": name.removesuffix(" Aura")}
            changed += 1
    debt = {}
    for data in maps.values():
        for _, rules in entries(data):
            for name, entry in rules.items():
                if not entry.get("primitive"):
                    debt[name] = "remaining aura slice" if name.endswith(" Aura") else "resolver pending"
    for name in DEFERRED & debt.keys():
        debt[name] = "granted base needs a resolver"
    debt["Unique"] = "list-building only; no table effect"
    debt["Sniper REMOVE"] = "snapshot curation; owner removes it from private books"
    outputs = {path: json.dumps(data, ensure_ascii=False, indent=1) + "\n" for path, data in maps.items()}
    manifest = args.repo / "test/fixtures/rules_registry_open.json"
    if manifest.exists() and debt.keys() - json.loads(manifest.read_text()).keys():
        parser.error("new registry debt must be reviewed explicitly before regenerating")
    outputs[manifest] = json.dumps(debt, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    stale = [path for path, text in outputs.items() if not path.exists() or path.read_text() != text]
    if args.write:
        for path in stale:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(outputs[path])
    print(json.dumps({"changed_entries": changed, "open_names": len(debt),
                     "files_differ": len(stale), "written": args.write}, sort_keys=True))
    return 0 if args.write or args.plan or not stale else 1


if __name__ == "__main__":
    raise SystemExit(main())
