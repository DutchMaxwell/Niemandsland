#!/usr/bin/env python3
"""Static census of the GDScript table: how many lines are left, and who still calls them.

tools/table_census.json maps groups to "file:function" ids (a whole file when the id has
no ':'). Per id: lines (function = its column-0 `func` up to the next top-level
declaration; whole file = its line count) and callers: `name(` call sites (plus
Callable/call("name") references) in scripts/ + tools/ (prod) and test/ (test). The
report ends with `TABLE LINES LEFT: N`, committed as test/one_core/table_census.txt.

  python3 tools/table_census.py            print the report
  python3 tools/table_census.py --write    rewrite the committed report
  python3 tools/table_census.py --runtime census.json   print the report + the soak's table share of AI volleys
  python3 tools/table_census.py --check    exit 1 if the report is stale, or if a prod caller
                                           appears that allowed_callers does not list ("file:function"
                                           or "@group"). A listed caller that is gone is fine on purpose.
"""
import argparse
import bisect
import difflib
import json
import re
import sys
from pathlib import Path

FUNC = re.compile(r"^(?:static\s+)?func\s+(\w+)")
TOP = re.compile(r"^(?:static\b|func\b|class\b|const\b|var\b|signal\b|enum\b|extends\b|@)")
CALLISH = re.compile(r"\b(?:call|call_deferred|callv|Callable|bind)\b")


def strip_comment(line):
    quote = None
    for i, ch in enumerate(line):
        if quote:
            quote = None if ch == quote and line[i - 1] != "\\" else quote
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


class Source:
    def __init__(self, path, rel):
        self.rel = rel
        self.lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        self.code = [strip_comment(ln) if "#" in ln else ln for ln in self.lines]
        self.text = "\n".join(self.code)
        self.funcs = [(i, m.group(1)) for i, ln in enumerate(self.lines) if (m := FUNC.match(ln))]

    def span(self, name):
        start = next((i for i, n in self.funcs if n == name), None)
        if start is None:
            return None
        return next((i for i in range(start + 1, len(self.lines)) if TOP.match(self.lines[i])), len(self.lines)) - start

    def enclosing(self, i):
        k = bisect.bisect_right([s for s, _ in self.funcs], i) - 1
        return self.funcs[k][1] if k >= 0 else "<file>"


def census(root, manifest):
    """Return (rows, new callers). rows: (group, id, lines, prod, test)."""
    sources = {}
    for sub in ("scripts", "tools", "test"):
        for p in sorted((root / sub).rglob("*.gd")):
            sources[p.relative_to(root).as_posix()] = Source(p, p.relative_to(root).as_posix())
    members = {i: g for g, ids in manifest["groups"].items() for i in ids}
    allowed = manifest.get("allowed_callers", {})
    rows, bad = [], set()
    for group, ids in sorted(manifest["groups"].items()):
        for ident in sorted(ids):
            file, _, name = ident.partition(":")
            src = sources.get(file)
            if src is None or (name and src.span(name) is None):
                raise SystemExit(f"table census: {ident} not found (a deleted function leaves the manifest in the same diff)")
            n = {True: 0, False: 0}  # is-prod -> count
            if not name:
                klass = next((m.group(1) for ln in src.lines if (m := re.match(r"class_name\s+(\w+)", ln))), "(?!)")
                pat = re.compile(r"\b%s\b|res://%s" % (klass, re.escape(file)))
                for rel, other in sources.items():
                    if rel != file and pat.search(other.text):
                        n[not rel.startswith("test/")] += 1
                rows.append((group, ident, len(src.lines), n[True], n[False]))
                continue
            call, ref = re.compile(r"\b%s\(" % name), re.compile(r"[\"']%s[\"']" % name)
            for rel, other in sources.items():
                for i, code in enumerate(other.code if name in other.text else ()):
                    if (m := FUNC.match(code)) and m.group(1) == name:
                        continue
                    if call.search(code) or (ref.search(code) and CALLISH.search(code)):
                        n[not rel.startswith("test/")] += 1
                        caller = f"{rel}:{other.enclosing(i)}"
                        ok = {caller, "@" + members.get(caller, "\0")} & set(allowed.get(ident, []))
                        if not rel.startswith("test/") and not ok:
                            bad.add((ident, caller))
            rows.append((group, ident, src.span(name), n[True], n[False]))
    return rows, sorted(bad)


def render(rows):
    out, total = [], 0
    for group in sorted({r[0] for r in rows}):
        mine = [r for r in rows if r[0] == group]
        out += [" ".join(map(str, r)) for r in mine]
        out.append(f"{group} TOTAL " + " ".join(str(sum(r[k] for r in mine)) for k in (2, 3, 4)))
        total += sum(r[2] for r in mine)
    return "\n".join(out + [f"TABLE LINES LEFT: {total}"]) + "\n"


def runtime_report(path):
    """The soak's census.json (tools/table_census_soak.sh): the share of AI volleys the table resolved, top 15 reasons."""
    data = json.loads(path.read_text())
    legacy = data.get("legacy", {}).get("ai_volley", {})
    total = int(data.get("ai_volleys", legacy.get("_all", 0) + data.get("core_ai_runs", 0)))
    pct = lambda n: 100.0 * n / total if total else 0.0
    top = sorted(((r, n) for r, n in legacy.items() if r != "_all"), key=lambda kv: (-kv[1], kv[0]))[:15]
    return "\n".join([f"RUNTIME AI VOLLEYS ON TABLE: {pct(legacy.get('_all', 0)):.1f} %"]
                     + [f"  {pct(n):5.1f} %  {n:6d}  {r}" for r, n in top]) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument("--manifest", type=Path)
    ap.add_argument("--txt", type=Path)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    ap.add_argument("--runtime", type=Path, help="soak census.json: append the runtime table share to the printed report")
    args = ap.parse_args(argv)
    if args.runtime and (args.write or args.check):
        ap.error("--runtime only extends the printed report (it is not deterministic, never committed)")
    txt_path = args.txt or args.root / "test/one_core/table_census.txt"
    rows, bad = census(args.root, json.loads((args.manifest or args.root / "tools/table_census.json").read_text()))
    text = render(rows)
    if args.write:
        txt_path.write_text(text)
    elif args.check:
        old = txt_path.read_text() if txt_path.exists() else ""
        if old != text:
            print("::error::table census counter is stale - run: python3 tools/table_census.py --write")
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(1), text.splitlines(1), "committed", "current"))
        for callee, caller in bad:
            print(f"::error::new caller of {callee}: {caller} (not in allowed_callers of tools/table_census.json)")
        return int(old != text or bool(bad))
    else:
        sys.stdout.write(text + (runtime_report(args.runtime) if args.runtime else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
