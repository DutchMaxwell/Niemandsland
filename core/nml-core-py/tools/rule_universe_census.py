"""Rule universe census (PLAN A1, 2026-08-31): every army-book rule name vs
every layer that must know it.

Walks the private army-book snapshot (`--books <dir>` with `gf/` and `aof/`
subdirectories; never committed, never embedded) and cross-references each
distinct rule name against the four layers that must know it:

  1. registry  - the table registry's data (scripts/solo/rules_registry.gd):
                 the system's assets/solo/rules_mechanics_<system>.json, over
                 the common block plus every faction block. Reports the entry's
                 `primitive`; an entry with `"primitive": null` is registered
                 but unautomated (UNMAPPED-registered - rules_registry.gd:
                 has_primitive is false for it); no entry at all = UNMAPPED.
  2. mechanics - does any entry for the name exist in that map at all?
  3. core      - the fast core (core/nml-core/src/*.rs; rules.rs itself is the
                 lookup/parser twin and carries no resolver arms):
                   PORTED  - the name or one of its registry primitives appears
                             as an identifier or string literal in non-test
                             code beyond the parser (a resolver arm or a
                             rules_of_primitive consumer);
                   PARTIAL - no arm, but the effect reaches the core only
                             through a precomputed channel: the loader's
                             MOVE_PRIMITIVES move-band pass (list_to_profile.py)
                             or the conditional-AP pass (an entry param
                             `condition`/`on6_ap`);
                   MISSING - no evidence (noted when Rust docs name it).
  4. encoder   - a slot in data/encoder_rule_vocab_v1.json (v5, unit band or
                 weapon band).

PRIVATE-SAFE: the books are read at runtime from wherever `--books` points;
nothing about their content is baked into this file. Outputs carry rule names
and faction names only - safe to run against the private snapshot.

RED knob `--hide <primitive>`: every name aliased to that primitive loses its
primitive-derived port evidence; the core-ported covered count must drop by
exactly the names that were ported through it. One line proves the counter is
live.

Exit code is 0 whenever the census ran (this is an instrument, not a gate);
usage errors exit 2.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SYSTEMS = ("gf", "aof")

STATUS_RANK = {"PORTED": 2, "PARTIAL": 1, "MISSING": 0}


def base_rule_name(rule: str) -> str:
    """rules_registry.gd:base_rule_name - "Tough(3)" -> "Tough" (also strips
    the " (spell)" grant mark: everything before the first paren, trimmed)."""
    return rule.strip().split("(")[0].strip()


def snake_variants(name: str) -> set[str]:
    """Token forms a Rust arm could use for `name`: "Hit & Run" ->
    {"hit_and_run", "hitrun"}; "Counter-Attack" -> {"counter_attack",
    "counterattack"}; single words stay single words."""
    s = name.lower()
    s = re.sub(r"\s*&\s*", " and ", s)
    parts = [p for p in re.split(r"[^a-z0-9]+", s) if p]
    if not parts:
        return set()
    return {"_".join(parts), "".join(parts)}


# ------------------------------------------------------------------ books


def walk_rule_names(node, out: list) -> None:
    """Every `specialRules` array anywhere in the JSON - units, weapons,
    upgrades, wherever they nest - contributes one sighting per entry."""
    if isinstance(node, dict):
        rules = node.get("specialRules")
        if isinstance(rules, list):
            for entry in rules:
                if isinstance(entry, dict):
                    name = base_rule_name(str(entry.get("name", "")))
                    if name:
                        out.append(name)
        for value in node.values():
            walk_rule_names(value, out)
    elif isinstance(node, list):
        for item in node:
            walk_rule_names(item, out)


def load_books(books_dir: Path) -> list[dict]:
    """Each book: {faction, system, names[]}. Files without `specialRules`
    (a `_common`-style shared file) contribute nothing by construction."""
    books = []
    for system in SYSTEMS:
        for path in sorted((books_dir / system).glob("*.json")):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError) as exc:
                print(f"warning: unreadable book {path.name}: {exc}", file=sys.stderr)
                continue
            names: list = []
            walk_rule_names(data, names)
            books.append(
                {
                    "faction": str(data.get("name") or path.stem),
                    "system": str(data.get("gameSystem") or system),
                    "names": names,
                }
            )
    return books


# ------------------------------------------------------------------ registry


def load_mechanics(repo: Path, system: str) -> dict:
    """name -> {primitives: set, entry: bool, cond_ap: bool} over the common
    block plus every faction block of rules_mechanics_<system>.json (an absent
    file is the registry's empty map: data refines, never breaks)."""
    path = Path(repo) / "assets" / "solo" / f"rules_mechanics_{system}.json"
    info: dict = {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return info
    blocks = [data.get("common") or {}]
    blocks += list((data.get("factions") or {}).values())
    for block in blocks:
        if not isinstance(block, dict):
            continue
        for name, entry in block.items():
            slot = info.setdefault(
                name, {"primitives": set(), "entry": False, "cond_ap": False}
            )
            slot["entry"] = True
            primitive = entry.get("primitive") if isinstance(entry, dict) else None
            if isinstance(primitive, str) and primitive:
                slot["primitives"].add(primitive)
            params = entry.get("params") if isinstance(entry, dict) else None
            if isinstance(params, dict) and ("condition" in params or "on6_ap" in params):
                slot["cond_ap"] = True
    return info


def load_vocab(repo: Path) -> dict:
    path = Path(repo) / "data" / "encoder_rule_vocab_v1.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {"unit": set(), "weapon": set()}
    return {
        "unit": set(data.get("unit") or []),
        "weapon": set(data.get("weapon") or []),
    }


def move_primitives(repo: Path) -> set:
    """The loader's move-band pass primitives, parsed from
    list_to_profile.py:MOVE_PRIMITIVES - never hard-coded here."""
    path = Path(repo) / "core" / "nml-core-py" / "python" / "list_to_profile.py"
    try:
        text = path.read_text()
    except OSError:
        return set()
    m = re.search(r"MOVE_PRIMITIVES\s*=\s*\(([^)]*)\)", text, re.S)
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))


# ------------------------------------------------------------------ rust scan

CFG_TEST_RE = re.compile(r"#\s*\[\s*cfg\s*\(\s*test")
RAW_STR_RE = re.compile(r'r(#*)"')


def scan_rust_file(path: Path) -> tuple[dict, list]:
    """One .rs file -> ({token: (relpath, line)}, [comment texts]).

    Tokens are the lowercased identifiers of non-comment, non-test code plus
    the snake forms of its string literals: a resolver arm shows up as the
    primitive's name (a rules_of_primitive call site), a field, or a literal.
    #[cfg(test)] regions are skipped - a test literal is not a resolver arm.
    Raw strings, // and (nested) /* */ comments are handled; single quotes
    (lifetimes, char literals) stay code, which can add a stray 1-char token
    at worst - no rule name is 1 char."""
    tokens: dict = {}
    comments: list = []
    try:
        text = path.read_text()
    except OSError:
        return tokens, comments
    rel = path.relative_to(path.parents[3]).as_posix()

    i, n = 0, len(text)
    line = 1
    depth = 0
    skip_depth: int | None = None
    buf: list = []

    def flush(end_line: int) -> None:
        if buf:
            tokens.setdefault("".join(buf).lower(), (rel, end_line))
            buf.clear()

    def record_literal(literal: str, at_line: int) -> None:
        for variant in snake_variants(literal):
            tokens.setdefault(variant, (rel, at_line))

    while i < n:
        c = text[i]
        if c == "\n":
            flush(line)
            line += 1
            i += 1
            continue
        if skip_depth is None:
            if c == "#":
                m = CFG_TEST_RE.match(text, i)
                if m:
                    flush(line)
                    skip_depth = depth
                    i = m.end()
                    continue
            if c.isalpha() or c == "_" or (buf and c.isdigit()):
                buf.append(c)
                i += 1
                continue
            flush(line)
            if c == '"':
                j = i + 1
                while j < n and text[j] != '"':
                    if text[j] == "\\":
                        j += 1
                    elif text[j] == "\n":
                        line += 1
                    j += 1
                record_literal(text[i + 1 : min(j, n)], line)
                i = j + 1
                continue
            if c == "r":
                m = RAW_STR_RE.match(text, i)
                if m:
                    closer = '"' + m.group(1)
                    end = text.find(closer, m.end())
                    literal = text[m.end() : end if end >= 0 else n]
                    record_literal(literal, line)
                    line += literal.count("\n")
                    i = (end + len(closer)) if end >= 0 else n
                    continue
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                j = text.find("\n", i)
                comments.append((rel, line, text[i : j if j >= 0 else n]))
                i = j if j >= 0 else n
                continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                nest, j = 0, i
                while j < n:
                    if text.startswith("/*", j):
                        nest += 1
                        j += 2
                    elif text.startswith("*/", j):
                        nest -= 1
                        j += 2
                        if nest == 0:
                            break
                    else:
                        if text[j] == "\n":
                            line += 1
                        j += 1
                comments.append((rel, line, text[i:j]))
                i = j
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
            continue
        # inside a #[cfg(test)] region: parse structure, record nothing
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = j if j >= 0 else n
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            nest, j = 0, i
            while j < n:
                if text.startswith("/*", j):
                    nest += 1
                    j += 2
                elif text.startswith("*/", j):
                    nest -= 1
                    j += 2
                    if nest == 0:
                        break
                else:
                    if text[j] == "\n":
                        line += 1
                    j += 1
            i = j
            continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n":
                    line += 1
                j += 1
            i = j + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth <= skip_depth:
                skip_depth = None
        i += 1
    flush(line)
    return tokens, comments


def scan_rust(repo: Path) -> tuple[dict, list]:
    """All of core/nml-core/src except rules.rs - the lookup/parser twin has no
    resolver arms, only the data-driven lookup every arm shares."""
    tokens: dict = {}
    comments: list = []
    src = Path(repo) / "core" / "nml-core" / "src"
    for path in sorted(src.rglob("*.rs")):
        if path.name == "rules.rs":
            continue
        t, c = scan_rust_file(path)
        for k, v in t.items():
            tokens.setdefault(k, v)
        comments.extend(c)
    return tokens, comments


def comment_index(comments: list) -> str:
    """One lowercase string of all Rust comments with (file:line) markers, so
    a doc-mention lookup is one substring search per rule name."""
    parts = []
    for rel, _line, ctext in comments:
        parts.append(ctext.replace("\x00", "").lower())
        parts.append(f"\x00{rel}:{_line}\n")
    return "".join(parts)


def mention_of(name: str, joined: str) -> str | None:
    idx = joined.find(name.lower())
    if idx < 0:
        return None
    end = joined.find("\x00", idx)
    if end < 0:
        return None
    nl = joined.find("\n", end)
    return joined[end + 1 : nl if nl >= 0 else len(joined)]


def core_status_for(name: str, mech: dict, tokens: dict, bands: set, hide: str | None):
    """(status, note) for one (name, system)."""
    prims = set(mech.get("primitives", set()))
    variants = snake_variants(name)
    if hide and hide in prims:
        prims.discard(hide)
        variants -= snake_variants(hide)
    name_hit = None
    for v in sorted(variants):
        if v in tokens:
            name_hit = (v, tokens[v])
            break
    prim_hit = None
    for p in sorted(prims):
        for v in sorted(snake_variants(p)):
            if v in tokens:
                prim_hit = (p, v, tokens[v])
                break
        if prim_hit:
            break
    if name_hit or prim_hit:
        if name_hit:
            v, where = name_hit
            return "PORTED", f"name token '{v}' at {where[0]}:{where[1]}"
        p, v, where = prim_hit
        return "PORTED", f"primitive '{p}' token '{v}' at {where[0]}:{where[1]}"
    notes = []
    if prims & bands:
        notes.append("move-band pass only")
    if mech.get("cond_ap"):
        notes.append("conditional-AP pass (EV path) only")
    if notes:
        return "PARTIAL", " + ".join(notes)
    return "MISSING", ""


def build_universe(books: list[dict]) -> dict:
    universe: dict = {}
    for book in books:
        s = book["system"]
        if s not in SYSTEMS:
            continue
        for name in book["names"]:
            u = universe.setdefault(
                name,
                {"systems": set(), "occ": 0, "occ_by_system": {}, "factions_by_system": {}},
            )
            u["systems"].add(s)
            u["occ"] += 1
            u["occ_by_system"][s] = u["occ_by_system"].get(s, 0) + 1
            u["factions_by_system"].setdefault(s, set()).add(book["faction"])
    return universe


def build_rows(universe, mechanics, tokens, bands, vocab, mentions, hide=None) -> dict:
    rows = {}
    AURA_SUFFIX = " Aura"

    def one_system(name, s, u):
        mech = mechanics[s].get(
            name, {"primitives": set(), "entry": False, "cond_ap": False}
        )
        status, note = core_status_for(name, mech, tokens, bands, hide)
        if status == "MISSING":
            where = mention_of(name, mentions)
            if where:
                note = (note + "; " if note else "") + f"named in Rust docs ({where})"
        primitives = sorted(mech["primitives"])
        primitive_label = (
            "|".join(primitives)
            if primitives
            else ("UNMAPPED-registered" if mech["entry"] else "UNMAPPED")
        )
        band = (
            "unit" if name in vocab["unit"]
            else ("weapon" if name in vocab["weapon"] else "")
        )
        return {
            "primitive": primitive_label,
            "mechanics_entry": mech["entry"],
            "cond_ap_param": mech["cond_ap"],
            "core": status,
            "core_note": note,
            "encoder_slot": bool(band),
            "encoder_band": band,
        }

    # Pass 1: every non-aura name. Pass 2: "X Aura" names - the import expands
    # them to X on both sides (opr_army_manager.gd:_expand_auras and the
    # loader's twin), so their core status is X's; their own mechanics entry
    # stays primitive-null BY DESIGN (that is why the label keeps the aura
    # pointer). An aura whose base is not itself a book rule stays as judged.
    for name, u in universe.items():
        if name.endswith(AURA_SUFFIX):
            continue
        rows[name] = {
            "systems": sorted(u["systems"]),
            "occ": u["occ"],
            "occ_by_system": dict(u["occ_by_system"]),
            "factions_by_system": {s: sorted(f) for s, f in u["factions_by_system"].items()},
            "per_system": {s: one_system(name, s, u) for s in sorted(u["systems"])},
        }
    for name, u in universe.items():
        if not name.endswith(AURA_SUFFIX):
            continue
        base = name[: -len(AURA_SUFFIX)]
        per_system = {}
        for s in sorted(u["systems"]):
            ps = one_system(name, s, u)
            base_row = rows.get(base)
            if base_row is not None and s in base_row["per_system"]:
                base_ps = base_row["per_system"][s]
                ps["core"] = base_ps["core"]
                ps["core_note"] = (
                    f"aura of '{base}' (expanded at import): {base_ps['core_note']}"
                )
            elif base in universe:
                ps["core_note"] = (
                    f"aura of '{base}' (expanded at import); base not a book rule"
                    f" in this system"
                )
            per_system[s] = ps
        rows[name] = {
            "systems": sorted(u["systems"]),
            "occ": u["occ"],
            "occ_by_system": dict(u["occ_by_system"]),
            "factions_by_system": {s: sorted(f) for s, f in u["factions_by_system"].items()},
            "per_system": per_system,
        }
    return rows


def parse_audit(path: Path | None) -> dict:
    """The known MISSING rows of plans/RULES_AUDIT_2026-08-31.md: the GF sec.3
    table rows and the AoF sec.4 hard-zero primitive list. Lenient - a file
    that does not parse yields empty lists, never a crash."""
    out = {"gf": [], "aof": []}
    if path is None:
        return out
    try:
        text = path.read_text()
    except OSError:
        return out
    for m in re.finditer(r"^\|\s*\d+\s*\|\s*\*\*(.+?)\*\*", text, re.M):
        name = re.sub(r"\s*\(.*$", "", m.group(1)).strip()
        if name and name not in out["gf"]:
            out["gf"].append(name)
    lines = text.splitlines()
    for idx, ln in enumerate(lines):
        if "**Hard zero" in ln:
            for follow in lines[idx + 1 : idx + 4]:
                if follow.startswith(("- ", "|", "#")) or not follow.strip():
                    continue
                for piece in follow.split(","):
                    name = piece.strip().rstrip(".").strip()
                    if name and not name.startswith("*") and name not in out["aof"]:
                        out["aof"].append(name)
                break
            break
    return out


def best_core(row: dict) -> str:
    return max(
        (ps["core"] for ps in row["per_system"].values()),
        key=lambda st: STATUS_RANK[st],
    )


def summarize(rows: dict) -> dict:
    def count(pred) -> int:
        return sum(1 for r in rows.values() if pred(r))

    summary = {
        "total": len(rows),
        "registry_primitive": count(
            lambda r: any(
                not ps["primitive"].startswith("UNMAPPED")
                for ps in r["per_system"].values()
            )
        ),
        "mechanics_entry": count(
            lambda r: any(ps["mechanics_entry"] for ps in r["per_system"].values())
        ),
        "core_ported": count(lambda r: best_core(r) == "PORTED"),
        "core_partial": count(lambda r: best_core(r) == "PARTIAL"),
        "core_missing": count(lambda r: best_core(r) == "MISSING"),
        "encoder_slot": count(
            lambda r: any(ps["encoder_slot"] for ps in r["per_system"].values())
        ),
        "all_layers": count(
            lambda r: all(
                not ps["primitive"].startswith("UNMAPPED")
                and ps["mechanics_entry"]
                and ps["core"] == "PORTED"
                and ps["encoder_slot"]
                for ps in r["per_system"].values()
            )
        ),
    }
    by_system = {}
    for s in SYSTEMS:
        sub = [(n, r) for n, r in rows.items() if s in r["per_system"]]
        by_system[s] = {
            "names": len(sub),
            "registry_primitive": sum(
                1 for _n, r in sub if not r["per_system"][s]["primitive"].startswith("UNMAPPED")
            ),
            "mechanics_entry": sum(1 for _n, r in sub if r["per_system"][s]["mechanics_entry"]),
            "core_ported": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "PORTED"),
            "core_partial": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "PARTIAL"),
            "core_missing": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "MISSING"),
            "encoder_slot": sum(1 for _n, r in sub if r["per_system"][s]["encoder_slot"]),
        }
    summary["by_system"] = by_system
    return summary


def ranked_lists(rows: dict) -> dict:
    """Core-MISSING and core-PARTIAL names per system, ranked by occurrences
    in that system (the BLOCK B port order)."""
    out = {}
    for s in SYSTEMS:
        buckets = {"MISSING": [], "PARTIAL": []}
        for name, r in rows.items():
            ps = r["per_system"].get(s)
            if ps is None or ps["core"] not in buckets:
                continue
            buckets[ps["core"]].append(
                {
                    "name": name,
                    "occ": r["occ_by_system"].get(s, 0),
                    "primitive": ps["primitive"],
                    "mechanics_entry": ps["mechanics_entry"],
                    "encoder_slot": ps["encoder_slot"],
                    "factions": len(r["factions_by_system"].get(s, [])),
                    "note": ps["core_note"],
                }
            )
        for bucket in buckets.values():
            bucket.sort(key=lambda e: (-e["occ"], e["name"]))
        out[s] = buckets
    return out


def compute_offenders(books: list[dict], rows: dict) -> list:
    """Factions ranked by unported occurrences (core != PORTED), worst rules
    attached - the BLOCK B per-faction port list."""
    out = []
    for book in books:
        if book["system"] not in SYSTEMS:
            continue
        per_name: dict = {}
        for name in book["names"]:
            per_name[name] = per_name.get(name, 0) + 1
        unported = []
        for name, occ in per_name.items():
            row = rows.get(name)
            if row is None:
                continue
            st = row["per_system"].get(book["system"], {}).get("core", "MISSING")
            if st != "PORTED":
                unported.append({"name": name, "core": st, "occ": occ})
        unported.sort(key=lambda e: (-e["occ"], e["name"]))
        out.append(
            {
                "faction": book["faction"],
                "system": book["system"],
                "occ_total": sum(per_name.values()),
                "occ_unported": sum(u["occ"] for u in unported),
                "worst": unported[:5],
            }
        )
    out.sort(key=lambda f: (-f["occ_unported"], f["faction"]))
    return out


def reconcile_audit(audit: dict, rows: dict, tokens: dict) -> list:
    """Each audit row -> the census's own finding for the names (or primitives)
    it names. CONFIRMED = census agrees MISSING; CHANGED = ported on this tree;
    mechanic rows have no book rule name and are judged by core token evidence."""
    findings = []
    for system in ("gf", "aof"):
        for row_name in audit.get(system, []):
            alias = row_name.split("/")[0].strip()
            finding = {
                "system": system,
                "audit_row": row_name,
                "audit_claim": "MISSING",
                "matches": [],
                "core_token": [],
                "verdict": "",
            }
            names = set()
            for n in rows:
                if n.lower() == row_name.lower() or n.lower() == alias.lower():
                    names.add(n)
                for ps in rows[n]["per_system"].values():
                    if alias.lower() in [p.lower() for p in ps["primitive"].split("|")]:
                        names.add(n)
            for n in sorted(names):
                r = rows[n]
                for s in sorted(r["per_system"]):
                    ps = r["per_system"][s]
                    if (
                        n.lower() == row_name.lower()
                        or n.lower() == alias.lower()
                        or alias.lower() in [p.lower() for p in ps["primitive"].split("|")]
                    ):
                        finding["matches"].append(
                            {"name": n, "system": s, "occ": r["occ_by_system"].get(s, 0), "core": ps["core"]}
                        )
            for v in sorted(snake_variants(row_name)):
                if v in tokens:
                    w = tokens[v]
                    finding["core_token"].append(f"{v} at {w[0]}:{w[1]}")
            if not finding["core_token"]:
                # mechanic-row fallback: the row's leading word may still name
                # real core code ("split fire" -> the split_plan arm, NML-1150)
                first = re.split(r"[^a-z0-9]+", alias.lower())[0]
                if first and first in tokens and len(first) > 3:
                    w = tokens[first]
                    finding["core_token"].append(f"first-word '{first}' at {w[0]}:{w[1]}")
            statuses = {m["core"] for m in finding["matches"]}
            if "PORTED" in statuses:
                finding["verdict"] = "CHANGED - ported on this tree"
            elif "PARTIAL" in statuses:
                finding["verdict"] = "PARTIAL on this tree"
            elif statuses:
                finding["verdict"] = "CONFIRMED missing"
            elif finding["core_token"]:
                finding["verdict"] = "mechanic row - no book rule name; core token present"
            else:
                finding["verdict"] = "mechanic row - no book rule name, no core token"
            findings.append(finding)
    return findings


# ------------------------------------------------------------------ outputs


def git_head(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10, check=False,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def census(books_dir: Path, repo: Path, hide: str | None = None,
           audit_path: Path | None = None) -> dict:
    books = load_books(books_dir)
    if not books:
        raise SystemExit(f"no books found under {books_dir}/gf|aof")
    mechanics = {s: load_mechanics(repo, s) for s in SYSTEMS}
    tokens, comments = scan_rust(repo)
    mentions = comment_index(comments)
    bands = move_primitives(repo)
    vocab = load_vocab(repo)
    universe = build_universe(books)
    rows = build_rows(universe, mechanics, tokens, bands, vocab, mentions)
    summary = summarize(rows)
    result = {
        "meta": {
            "generated": datetime.datetime.now().isoformat(timespec="seconds"),
            "repo": str(repo),
            "head": git_head(repo),
            "books": len(books),
            "books_by_system": {
                s: sum(1 for b in books if b["system"] == s) for s in SYSTEMS
            },
            "books_dir": str(books_dir),
            "hide": hide,
            "audit": str(audit_path) if audit_path else "",
            "tool": "core/nml-core-py/tools/rule_universe_census.py",
            "method": {
                "walk": "specialRules[].name over every book JSON, recursive; base = name before '('",
                "core_ported": "name or registry-primitive token in non-test core/nml-core/src code beyond rules.rs",
                "core_partial": "move-band pass primitive (list_to_profile.py:MOVE_PRIMITIVES) or conditional-AP entry param",
                "core_missing": "no token evidence; 'named in Rust docs' when a comment mentions it",
            },
        },
        "summary": summary,
        "rows": rows,
        "ranked": ranked_lists(rows),
        "offenders": compute_offenders(books, rows),
        "audit_rows": parse_audit(audit_path),
        "audit_reconciliation": reconcile_audit(parse_audit(audit_path), rows, tokens),
        "red": None,
    }
    if hide:
        before = summary["core_ported"]
        rows_hidden = build_rows(universe, mechanics, tokens, bands, vocab, mentions, hide)
        after = summarize(rows_hidden)["core_ported"]
        direct = {
            n for n, r in rows.items()
            if any(
                hide.lower() in [p.lower() for p in ps["primitive"].split("|")]
                for ps in r["per_system"].values()
            )
        }
        # "X Aura" names ride their base through the import-time expansion, so
        # hiding a primitive drops them too when the base is aliased.
        aliased = set(direct)
        for n in rows:
            if n.endswith(" Aura") and n[:-5] in direct and n[:-5] in universe:
                aliased.add(n)
        ported_aliased = sum(1 for n in aliased if best_core(rows[n]) == "PORTED")
        result["red"] = {
            "primitive": hide,
            "before": before,
            "after": after,
            "drop": before - after,
            "aliased": len(aliased),
            "ported_aliased": ported_aliased,
            "ok": (before - after) == ported_aliased,
            "aliased_names": sorted(aliased),
        }
    return result


def summary_lines(res: dict) -> list[str]:
    s = res["summary"]
    t = s["total"]
    lines = [
        f"RULES-COVERAGE registry-primitive : {s['registry_primitive']}/{t}",
        f"RULES-COVERAGE mechanics-entry    : {s['mechanics_entry']}/{t}",
        f"RULES-COVERAGE core-ported        : {s['core_ported']}/{t}  (PARTIAL: {s['core_partial']}, MISSING: {s['core_missing']})",
        f"RULES-COVERAGE encoder-slot       : {s['encoder_slot']}/{t}",
        f"RULES-COVERAGE all-layers         : {s['all_layers']}/{t}",
    ]
    for system in SYSTEMS:
        b = s["by_system"][system]
        n = b["names"]
        lines.append(
            f"RULES-COVERAGE {system} : names {n} - registry {b['registry_primitive']}/{n},"
            f" mechanics {b['mechanics_entry']}/{n}, core {b['core_ported']}/{n},"
            f" encoder {b['encoder_slot']}/{n}"
        )
    if res.get("red"):
        r = res["red"]
        lines.append(
            f"RED --hide {r['primitive']}: core-ported {r['before']} -> {r['after']}"
            f" (drop {r['drop']}); {r['primitive']} aliases: {r['aliased']}"
            f" (ported before: {r['ported_aliased']})"
            f" -> drops exactly its rules: {'OK' if r['ok'] else 'VIOLATION'}"
        )
    return lines


def _cell(value: str) -> str:
    return str(value).replace("|", "/")


def markdown_report(res: dict) -> str:
    s = res["summary"]
    t = s["total"]
    meta = res["meta"]
    out = [
        "# RULE COVERAGE 2026-08-31 - the rule universe vs every layer (PLAN A1)",
        "",
        f"Generated {meta['generated']} from {meta['repo']} @ {meta['head']};"
        f" {meta['books']} books ({meta['books_by_system'].get('gf', 0)} GF,"
        f" {meta['books_by_system'].get('aof', 0)} AoF) at `{meta['books_dir']}`"
        " (private snapshot, read at runtime only).",
        "",
        "## Summary",
        "",
        "```",
    ]
    out += summary_lines(res)
    out += ["```", "", "Board row RULES-COVERAGE = the core-ported line.", ""]

    out += [
        "## Method",
        "",
        "- Walk: every `specialRules[].name` in each book JSON (recursive, so"
        " units/weapons/upgrades count wherever they nest); base name = text"
        " before the first `(` (the registry's own `base_rule_name`).",
        "- Registry/mechanics: the system's `rules_mechanics_<system>.json`,"
        " common + faction blocks. `primitive: null` = registered but"
        " unautomated (UNMAPPED-registered).",
        f"- Core PORTED: name or registry-primitive token in non-test"
        f" `core/nml-core/src` code beyond `rules.rs` (the parser twin)."
        f" PARTIAL: only the loader's move-band pass (`MOVE_PRIMITIVES` in"
        f" `list_to_profile.py`) or the conditional-AP entry param reaches the"
        f" core. MISSING: nothing.",
        "- Encoder: a slot in `data/encoder_rule_vocab_v1.json` (unit or weapon band).",
        "",
    ]

    if res.get("red"):
        r = res["red"]
        out += [
            "## RED proof",
            "",
            f"`--hide {r['primitive']}` forces every alias of the known-ported"
            f" primitive **{r['primitive']}** to lose its primitive-derived port"
            f" evidence. Core-ported covered count: {r['before']} -> {r['after']}"
            f" (drop {r['drop']}); the primitive aliases {r['aliased']} rule"
            f" names, {r['ported_aliased']} of them were PORTED before."
            f" **Drops exactly its rules: {'OK' if r['ok'] else 'VIOLATION'}**"
            f" - the covered count is live, not decorative.",
            "",
        ]

    for system in SYSTEMS:
        rows = res["ranked"][system]["MISSING"]
        out += [
            f"## Core-MISSING - {system.upper()}, ranked by occurrences ({len(rows)} names)",
            "",
            "| # | rule | occ | registry primitive | mechanics | encoder | factions |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for i, e in enumerate(rows, 1):
            out.append(
                f"| {i} | {e['name']} | {e['occ']} | {_cell(e['primitive'])} |"
                f" {'yes' if e['mechanics_entry'] else 'no'} |"
                f" {'yes' if e['encoder_slot'] else 'no'} | {e['factions']} |"
            )
        out.append("")

    partial = sorted(
        (e for system in SYSTEMS for e in res["ranked"][system]["PARTIAL"]),
        key=lambda e: -e["occ"],
    )
    out += [
        f"## PARTIAL - reaches the core only through a precomputed channel ({len(partial)} names)",
        "",
        "| # | rule | system | occ | registry primitive | via | encoder |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for i, e in enumerate(partial[:40], 1):
        system = "gf" if e in res["ranked"]["gf"]["PARTIAL"] else "aof"
        out.append(
            f"| {i} | {e['name']} | {system} | {e['occ']} | {_cell(e['primitive'])} |"
            f" {_cell(e['note'])} | {'yes' if e['encoder_slot'] else 'no'} |"
        )
    out.append("")

    offenders = res["offenders"]
    out += [
        "## Worst factions by unported occurrences",
        "",
        "| # | faction | system | unported occ / total | worst rules (occ) |",
        "| --- | --- | --- | --- | --- |",
    ]
    for i, f in enumerate(offenders[:15], 1):
        worst = ", ".join(f"{w['name']} ({w['occ']})" for w in f["worst"][:4])
        out.append(
            f"| {i} | {f['faction']} | {f['system']} |"
            f" {f['occ_unported']}/{f['occ_total']} | {worst} |"
        )
    out.append("")

    out += [
        "## Reconciliation vs plans/RULES_AUDIT_2026-08-31.md",
        "",
        "| audit row | system | audit claim | census finding | verdict |",
        "| --- | --- | --- | --- | --- |",
    ]
    for f in res["audit_reconciliation"]:
        if f["matches"]:
            finding = "; ".join(
                f"{m['name']} [{m['system']} x{m['occ']}]: {m['core']}"
                for m in f["matches"][:4]
            )
        elif f["core_token"]:
            finding = "; ".join(f["core_token"][:2])
        else:
            finding = "-"
        out.append(
            f"| {f['audit_row']} | {f['system']} | {f['audit_claim']} |"
            f" {_cell(finding)} | {f['verdict']} |"
        )
    out.append("")

    out += [
        f"## Full matrix ({t} names)",
        "",
        "| rule | systems | occ | registry primitive | mechanics | core | encoder |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in sorted(res["rows"]):
        r = res["rows"][name]
        per = r["per_system"]
        prim_vals = {ps["primitive"] for ps in per.values()}
        primitive = next(iter(prim_vals)) if len(prim_vals) == 1 else (
            " / ".join(f"{s}: {ps['primitive']}" for s, ps in sorted(per.items()))
        )
        core_vals = {ps["core"] for ps in per.values()}
        core = next(iter(core_vals)) if len(core_vals) == 1 else (
            " / ".join(f"{ps['core']}({s})" for s, ps in sorted(per.items()))
        )
        mech = "yes" if any(ps["mechanics_entry"] for ps in per.values()) else "no"
        enc = "yes" if any(ps["encoder_slot"] for ps in per.values()) else "no"
        out.append(
            f"| {name} | {'+'.join(r['systems'])} | {r['occ']} |"
            f" {_cell(primitive)} | {mech} | {core} | {enc} |"
        )
    out.append("")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Rule universe census (PLAN A1): army-book rule names vs"
        " registry, fast core and encoder vocab."
    )
    ap.add_argument("--books", required=True,
                    help="directory with gf/ and aof/ book JSONs (private; read-only)")
    ap.add_argument("--repo", default=str(REPO),
                    help="openTTS checkout providing assets/, data/, core/ (default: this repo)")
    ap.add_argument("--hide", default=None, metavar="PRIMITIVE",
                    help="RED knob: treat this known ported primitive as missing")
    ap.add_argument("--audit", default=None,
                    help="path to RULES_AUDIT_2026-08-31.md for the reconciliation section")
    ap.add_argument("--out-json", default=None, help="write the full census JSON here")
    ap.add_argument("--out-md", default=None, help="write the markdown report here")
    args = ap.parse_args(argv)
    try:
        res = census(
            Path(args.books), Path(args.repo), args.hide,
            Path(args.audit) if args.audit else None,
        )
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 2
    for line in summary_lines(res):
        print(line)
    if args.out_json:
        out = Path(args.out_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(res, indent=1) + "\n")
    if args.out_md:
        out = Path(args.out_md)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(markdown_report(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())
