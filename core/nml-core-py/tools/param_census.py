#!/usr/bin/env python3
"""Registry param census: for every key under `params` in assets/solo/rules_mechanics_<system>.json,
search for a reader. A reader is a quoted occurrence of the param key in PRODUCTION code (Rust core
minus bin/tests, scripts/*.gd, the py side under core/nml-core-py/python). A key read only by tests,
benchmark binaries (bin/*.rs) or census tools is NOT a reader — that is the Morale case
(RULE_FIDELITY_AUDIT_2026-09-13); such keys are listed separately. Text-only, nothing compiles.
Usage: python3 tools/param_census.py [--gate]   (--gate: exit 1 if any param has no production reader)
"""
from __future__ import annotations

import argparse
import glob as _glob
import json
import os
import sys
from collections import Counter, namedtuple

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
REGISTRY_GLOB = os.path.join(REPO, "assets", "solo", "rules_mechanics_*.json")
PROD_GLOBS = ["core/nml-core/src/**/*.rs", "scripts/**/*.gd", "core/nml-core-py/python/**/*.py"]
NONPROD_GLOBS = ["core/nml-core/src/bin/**/*.rs", "core/nml-core/src/tests/**/*.rs",
                 "core/nml-core-py/tests/**/*.py", "core/nml-core-py/tools/**/*.py",
                 "tools/*.py", "tools/*.gd", "test/*.gd"]
Row = namedtuple("Row", "system rule param readers nonprod")


def _expand(roots):
    """roots are files, directories or glob patterns -> flat list of files."""
    out = []
    for root in roots:
        if os.path.isfile(root):
            out.append(root)
        elif os.path.isdir(root):
            for base, _dirs, files in os.walk(root):
                out.extend(os.path.join(base, f) for f in files)
        else:
            out.extend(p for p in _glob.glob(root, recursive=True) if os.path.isfile(p))
    return sorted(set(out))


def _corpus(roots):
    """file -> list of lines for every file in the given roots."""
    return {p: open(p, encoding="utf-8", errors="replace").read().splitlines() for p in _expand(roots)}


def _hits(corpus, needle):
    quoted = '"%s"' % needle
    return ["%s:%d" % (os.path.relpath(p, REPO), i)
            for p, lines in corpus.items() for i, line in enumerate(lines, 1) if quoted in line]


def registry_rows(registry_glob):
    """(system, rule, param) for every params key; faction scope is flattened into rule scope."""
    rows = []
    for path in sorted(_glob.glob(registry_glob)):
        if "spells_mechanics" in path:
            continue
        data = json.load(open(path, encoding="utf-8"))
        system = data["_meta"]["system"]
        entries = dict(data.get("common", {}))
        for rules in data.get("factions", {}).values():
            entries.update(rules)
        for rule, entry in entries.items():
            rows.extend((system, rule, param) for param in (entry.get("params") or {}))
    return rows


def run(registry_glob=REGISTRY_GLOB, prod_roots=None, nonprod_roots=None):
    prod_roots = prod_roots or _expand([os.path.join(REPO, g) for g in PROD_GLOBS])
    nonprod_roots = nonprod_roots or [os.path.join(REPO, g) for g in NONPROD_GLOBS]
    nonprod_files = set(_expand(nonprod_roots))
    prod_corpus = _corpus([p for p in _expand(prod_roots) if p not in nonprod_files])
    nonprod_corpus = _corpus(nonprod_roots)
    return [Row(system, rule, param, _hits(prod_corpus, param), _hits(nonprod_corpus, param))
            for system, rule, param in sorted(set(registry_rows(registry_glob)))]


def report(rows, out=sys.stdout):
    none_rows = [r for r in rows if not r.readers]
    print("params (unique system/rule/param): %d | distinct keys: %d | no production reader: %d"
          % (len(rows), len({r.param for r in rows}), len(none_rows)), file=out)
    print("\n== NO production reader (%d) ==" % len(none_rows), file=out)
    for r in none_rows:
        tag = " [read only by non-production code: %s]" % ", ".join(r.nonprod) if r.nonprod else ""
        print("%-5s %-42s %-28s NONE%s" % (r.system, r.rule, r.param, tag), file=out)
    print("\n== worst offenders by rule ==", file=out)
    for rule, n in Counter(r.rule for r in none_rows).most_common(10):
        print("%3d  %s" % (n, rule), file=out)
    print("\nNote: a reader here is a quoted key occurrence; keys assembled dynamically or read via a",
          "\ngeneric accessor are invisible to this instrument. Non-production (not readers): tests,",
          "\ncore/nml-core/src/bin (benchmarks), census/gate tools.", file=out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gate", action="store_true", help="exit 1 if any param has no production reader")
    args = ap.parse_args(argv)
    rows = run()
    report(rows)
    return 1 if args.gate and any(not r.readers for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
