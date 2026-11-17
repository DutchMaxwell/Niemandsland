#!/usr/bin/env python3
"""Static census of the GDScript table: how many lines are left, and who still calls them.

tools/table_census.json maps groups to "file:function" ids (a whole file when the id has
no ':'). Per id: lines (function = its column-0 `func` up to the next top-level
declaration; whole file = its line count) and callers: `name(` call sites (plus
Callable/call("name") references) in scripts/ + tools/ (prod) and test/ (test). The
report ends with `TABLE LINES LEFT: N`, committed as test/one_core/table_census.txt. The committed report carries
two numbers per row (lines, prod callers); the printed report adds the test-caller column, so a test edit never
moves the file. The manifest's planner_tags
list EVERY column-0 function of the planner files under exactly one tag of tag_vocabulary; the report prints the
function count and code lines per tag (no trailing blank/comment lines) just above the counter, which is unchanged.

  python3 tools/table_census.py            print the report
  python3 tools/table_census.py --write    rewrite the committed report (lines and prod callers only)
  python3 tools/table_census.py --runtime census.json   print the report + the soak's table share of AI volleys
                                           (+ the SHADOW section when the soak ran with NML_CORE_SHADOW=1)
  python3 tools/table_census.py --check    exit 1 if the report is stale (lines and prod callers; test-caller counts
                                           are printed but never compared or committed), if a planner function has no tag, or if a prod caller appears that
                                           allowed_callers does not list ("file:function" or "@group"). A listed
                                           caller that is gone is fine on purpose.
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

    def code_span(self, name):
        """span without the blank and column-0 comment lines before the next declaration (they belong to that one)."""
        start = next(i for i, n in self.funcs if n == name)
        end = start + self.span(name)
        while end - 1 > start and (not self.lines[end - 1].strip() or self.lines[end - 1].startswith("#")):
            end -= 1
        return end - start

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


def planner_tags(root, manifest):
    """Return (rows, problems). rows: tag -> [functions, lines]. A column-0 function of a planner_tags file with no tag,
    two tags or a tag outside tag_vocabulary is a problem; a tagged name that is gone is an error, like in groups."""
    vocab, rows, bad = set(manifest.get("tag_vocabulary", "").split()), {}, []
    for file, tags in sorted(manifest.get("planner_tags", {}).items()):
        src, seen = Source(root / file, file), {}
        for tag, names in sorted(tags.items()):
            if tag not in vocab:
                bad.append(f"{file} uses the unknown planner tag {tag!r} (tag_vocabulary)")
            for name in names.split():
                if src.span(name) is None:
                    raise SystemExit(f"table census: {file}:{name} not found (a deleted function leaves the manifest in the same diff)")
                if name in seen:
                    bad.append(f"{file}:{name} carries two planner tags ({seen[name]}, {tag})")
                seen[name] = tag
                row = rows.setdefault(tag, [0, 0])
                row[0], row[1] = row[0] + 1, row[1] + src.code_span(name)
        bad += [f"{file}:{n} has no planner tag (add it to planner_tags in tools/table_census.json)" for _, n in src.funcs if n not in seen]
    return rows, bad


def render(rows, tags=None):
    out, total = [], 0
    for group in sorted({r[0] for r in rows}):
        mine = [r for r in rows if r[0] == group]
        out += [" ".join(map(str, r)) for r in mine]
        out.append(f"{group} TOTAL " + " ".join(str(sum(r[k] for r in mine)) for k in (2, 3, 4)))
        total += sum(r[2] for r in mine)
    for tag, (n, lines) in sorted((tags or {}).items()):
        out.append(f"planner_tag {tag} {n} {lines}")
    if tags:
        out.append(f"planner_tag TOTAL {sum(n for n, _ in tags.values())} {sum(ln for _, ln in tags.values())}")
    return "\n".join(out + [f"TABLE LINES LEFT: {total}"]) + "\n"


def prod_only(text):
    """The report without its test-caller column: the text `--write` commits. A test added or removed must not
    move the committed file nor turn --check red; the printed report keeps the column."""
    return "".join(" ".join(p[:-1] if len(p) == 5 else p) + "\n" for p in (ln.split() for ln in text.splitlines()))


def group_of(reason):
    """The rule group a reason belongs to, shooter or target side: "weapon_rule:AP" / "target_weapon_rule:AP" -> "AP"."""
    reason = reason.removeprefix("target_")
    return reason.partition(":")[2] if ":" in reason else reason


def runtime_report(path):
    """The soak's census.json (tools/table_census_soak.sh): the share of AI volleys the table resolved, the top 15
    reasons and reason sets, and what allowing GROUPS would unlock. A volley is unlocked once every reason it has belongs
    to an allowed group (`no_handle` only follows from the others and is left out). Real volleys carry many groups, so
    "one group alone" is mostly 0; the last block allows the most common groups first and shows the cumulative share."""
    data = json.loads(path.read_text())
    legacy = data.get("legacy", {}).get("ai_volley", {})
    total = int(data.get("ai_volleys", legacy.get("_all", 0) + data.get("core_ai_runs", 0)))
    row = lambda n, label: f"  {100.0 * n / total if total else 0.0:5.1f} %  {n:6d}  {label}"
    best = lambda counts, k=15: sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:k]
    sets = {tuple(k.split("|")): n for k, n in data.get("legacy_sets", {}).get("ai_volley", {}).items()}
    need = {k: {group_of(r) for r in k if r != "no_handle"} for k in sets}   # reason set -> the groups it needs
    out = [f"RUNTIME AI VOLLEYS ON TABLE: {100.0 * legacy.get('_all', 0) / total if total else 0.0:.1f} %"]
    out += [row(n, r) for r, n in best({r: n for r, n in legacy.items() if r != "_all"})]
    if sets:
        alone, freq, widths = {}, {}, {}
        for k, n in sets.items():
            widths[len(need[k])] = widths.get(len(need[k]), 0) + n
            for g in need[k]:
                freq[g] = freq.get(g, 0) + n
                alone[g] = alone.get(g, 0) + (n if len(need[k]) == 1 else 0)
        order = [g for g, _ in best(freq, len(freq))]
        ones = [row(n, g) for g, n in best(alone) if n]
        out += ["UNLOCKED IF THIS GROUP ALONE WERE ALLOWED:"] + (ones or [f"  (none: no volley needs fewer than {min(widths)} groups)"])
        out += ["VOLLEYS BY NUMBER OF GROUPS THEY NEED:"] + [row(n, f"{w} group(s)") for w, n in sorted(widths.items())]
        out += ["MOST COMMON GROUPS ALLOWED FIRST (cumulative unlocked):"]
        for i in sorted({*range(1, 16), 20, 30, 40, 50} & set(range(1, len(order) + 1))):
            out.append(row(sum(n for k, n in sets.items() if need[k] <= set(order[:i])), f"+ {order[i - 1]} (group {i})"))
        out += ["TOP REASON SETS (no_handle left out):"]
        out += [row(n, " + ".join(r for r in k if r != "no_handle") or "(no_handle only)") for k, n in best(sets)]
    return "\n".join(out) + "\n" + shadow_report(data.get("shadow", []))


def shadow_report(rows):
    """C-5: the shadow run's volleys (NML_CORE_SHADOW=1, `CoreShadow` records {equal, first_diff, labels, unported}):
    the equal share, mismatches by their first differing part, rule groups by lift (mismatch rate of the volleys that
    carry the group / of those that do not), DENY CANDIDATES (groups none of whose volleys match) and UNEXPLAINED
    (mismatching volleys that carry no group: a core difference no rule label accounts for). Empty without records."""
    if not rows:
        return ""
    n, bad = len(rows), [r for r in rows if not r.get("equal")]
    pct = lambda k, of: f"{100.0 * k / of if of else 0.0:5.1f} %"
    groups = lambda r: {group_of(x) for x in r.get("labels", []) if x != "no_handle"}
    out = [f"SHADOW: {n} volleys replayed in the core, {n - len(bad)} equal ({pct(n - len(bad), n).strip()})",
           "MISMATCHES BY FIRST DIFF:"]
    diffs = {}
    for r in bad:
        diffs[r.get("first_diff", "?")] = diffs.get(r.get("first_diff", "?"), 0) + 1
    out += [f"  {pct(k, n)}  {k:6d}  {d}" for d, k in sorted(diffs.items(), key=lambda kv: (-kv[1], kv[0]))]
    stats = {}
    for r in rows:
        for g in groups(r):
            s = stats.setdefault(g, [0, 0])
            s[0], s[1] = s[0] + 1, s[1] + (not r.get("equal"))
    total_bad = len(bad)

    def lift(g):
        with_n, with_bad = stats[g]
        rest_n, rest_bad = n - with_n, total_bad - with_bad
        rate_with, rate_rest = with_bad / with_n, (rest_bad / rest_n if rest_n else 0.0)
        return rate_with / rate_rest if rate_rest else float("inf") if rate_with else 0.0
    ranked = sorted(stats, key=lambda g: (-lift(g), -stats[g][1], g))
    out += ["RULE GROUPS BY LIFT (volleys, mismatching, mismatch rate, lift):"]
    out += [f"  {stats[g][0]:6d}  {stats[g][1]:6d}  {pct(stats[g][1], stats[g][0])}  {lift(g):6.2f}  {g}"
            for g in ranked[:20]]
    out += ["RULE GROUPS BY MISMATCHING VOLLEYS:"]
    out += [f"  {stats[g][1]:6d} of {stats[g][0]:6d}  {g}"
            for g in sorted(stats, key=lambda g: (-stats[g][1], g))[:15] if stats[g][1]]
    deny = sorted(g for g in stats if stats[g][0] == stats[g][1])
    out += ["DENY CANDIDATES (no volley with the group matches): " + (", ".join(deny) or "(none)")]
    loose = [r for r in bad if not groups(r)]
    out += [f"UNEXPLAINED (mismatching, no rule group): {len(loose)}"]
    out += [f"  {r.get('first_diff', '?')}  unported={','.join(r.get('unported', [])) or '-'}" for r in loose[:10]]
    return "\n".join(out) + "\n"


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
    manifest = json.loads((args.manifest or args.root / "tools/table_census.json").read_text())
    rows, bad = census(args.root, manifest)
    tags, untagged = planner_tags(args.root, manifest)
    text = render(rows, tags)
    for problem in untagged:
        print(f"::error::{problem}")
    if untagged and (args.write or args.check):
        return 1
    want = prod_only(text)
    if args.write:
        txt_path.write_text(want)
    elif args.check:
        old = txt_path.read_text() if txt_path.exists() else ""
        stale = prod_only(old) != want   # lines and prod callers only; test counts are printed, never committed
        if stale:
            print("::error::table census counter is stale - run: python3 tools/table_census.py --write")
            sys.stdout.writelines(difflib.unified_diff(prod_only(old).splitlines(1), want.splitlines(1),
                                                       "committed", "current"))
        for callee, caller in bad:
            print(f"::error::new caller of {callee}: {caller} (not in allowed_callers of tools/table_census.json)")
        return int(stale or bool(bad))
    else:
        sys.stdout.write(text + (runtime_report(args.runtime) if args.runtime else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
