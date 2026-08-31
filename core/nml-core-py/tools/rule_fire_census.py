"""Rule fire census (PLAN A2, 2026-08-31): per rule, how often it FIRED in the
locked reference corpora and whether the twin's existing replay gates covered
those acts.

WHAT "FIRED" MEANS HERE — and what it cannot mean. The recorder has no
per-effect fire log: what it records is the rules LIVE on the board per
activation. `scripts/solo/act_recorder.gd` stamps every act line with the
DYNAMIC half of every unit's profile (`_stamp_gate_reads` -> `prof`:
`special_rules`, `attached_hero_rules`, `item_grants`) — the exact rule
vocabulary the search read for that act — and writes the STATIC half once per
game into the header (`profiles`: unit rules, weapon `rules`). This census
counts FIRED = live during N activations: the base-named rule appeared on at
least one alive unit of the act (per-act `prof` stamp, or the unit's static
weapon rules while it is alive). The one place a real per-effect fire IS
recorded is the dice tape: since NML-1104 the recorded `roll_kind` names the
rule behind its die — Regeneration, Fearless, No Retreat, Ravage, Battleborn
(morale and dangerous terrain are a condition and a terrain property, not book
rules). Those rules additionally get their true per-die fire count.

GATE CROSS-REFERENCE, without re-running any replay. The three replay gates
already ran over both corpora (D1's dice gate is the rung that joins them):

  dice_stream   - every recorded roll of the rule's own `roll_kind` was part
                  of the stream check, which replays the tape roll for roll.
                  VERDICT "identical": the rule's effect is recorded per die
                  and was compared per die. The stream gate's green/red state
                  is its own report; this tool measures only that every die
                  is on the tape.
  melee_replay  - B5b's class: CHARGE acts with a target (`pick.action.kind`
                  3 + `charge`). Their rolls, tally and next-state were
                  replayed and compared. VERDICT "covered" — per-act identity
                  is that gate's own corpus report, not recomputed here (the
                  corpora carry no per-act gate reports).
  shoot_replay  - B4's class: HOLD/ADVANCE acts with a shoot target (kinds
                  0/1 + `shoot`). Same treatment, same honesty.
  unverified    - no replay gate re-computes the effect: movement bands,
                  deployment, planner EV, spells, objectives, auras.

The class comes from a documented name/primitive keyword heuristic (see
MELEE_TOKENS / SHOOT_TOKENS) — a labelling, not ground truth; the RED knob
exists to prove it is wired to the counts. For the two replay classes a cheap
per-act re-check runs from the corpus itself: an act is gate-comparable only
where dice.jsonl carries a roll under the act's INTERLEAVED ordinal (the
table fought there); an act with no roll is the NML-1117 zero-volley case and
is reported as not gate-comparable rather than silently counted covered.

PRIVATE-SAFE: the corpus paths are taken at runtime (`--qbg`, `--qag`) and
never baked in; outputs carry rule names and counts only. Exit code is 0
whenever the census ran (an instrument, not a gate); usage errors exit 2.

    python core/nml-core-py/tools/rule_fire_census.py \
        --qbg ~/selfplay_out/qbg_ref --qag ~/selfplay_out/qag_ref \
        --coverage ~/nml-mission/plans/RULE_COVERAGE_2026-08-31.json \
        --out-json ... --out-md ...
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

#: NML-1104: recorded `roll_kind` -> the book rule whose die it is. Morale and
#: dangerous terrain are a game condition and a terrain property — counted as
#: dice kinds, but no rule name owns them.
ROLL_KIND_OF_RULE = {
    "Regeneration": "regeneration",
    "Fearless": "fearless",
    "No Retreat": "no_retreat",
    "Ravage": "ravage",
    "Battleborn": "battleborn",
}
RULE_OF_ROLL_KIND = {v: k for k, v in ROLL_KIND_OF_RULE.items()}

#: B4/B5's act classes, exactly as dice_gate.py imports them from the rungs:
#: SHOOTING_KINDS (HOLD/ADVANCE with a shoot target) and CHARGE_KIND.
SHOOTING_KINDS = (0, 1)
CHARGE_KIND = 3
CLASSES = ("dice_stream", "melee_replay", "shoot_replay", "unverified")

#: Class heuristic — matched against the rule name AND its registry primitive
#: (lowercase, substring). A rule can sit in several families; its PRIMARY
#: class takes the first match in CLASSES order. Anything unmatched stays
#: "unverified" — the honest default, since a replay gate covers a rule's
#: acts only where it re-computes the rule's math.
MELEE_TOKENS = (
    "melee", "charge", "counter", "takedown", "repel ambushers",
    "heavy impact", "storm attack", "shroud",
)
SHOOT_TOKENS = (
    "shoot", "shot", "ranged", "blast", "rending", "deadly", "poison",
    "reliable", "indirect", "precise", "bane", "lacerate", "shielded",
    "stealth", "evasive", "crack", "tear", "shatter", "disintegrate",
    "strafing", "breath", "ap",
)


def base_rule_name(rule: str) -> str:
    """rules_registry.gd:base_rule_name - "Tough(3)" -> "Tough"."""
    return rule.strip().split("(")[0].strip()


def _has_token(text: str, token: str) -> bool:
    """Whole-word substring: "ap" must hit "AP(1)" but never sit inside
    "rapid"."""
    return re.search(rf"(?<![a-z]){re.escape(token)}(?![a-z])", text) is not None


def families_of(name: str, primitive: str) -> list[str]:
    """Families a rule's name or primitive lands in, primary first."""
    text = f"{name} {primitive}".lower()
    out = []
    if name in ROLL_KIND_OF_RULE:
        out.append("dice_stream")
    if any(_has_token(text, t) for t in MELEE_TOKENS):
        out.append("melee_replay")
    if any(_has_token(text, t) for t in SHOOT_TOKENS):
        out.append("shoot_replay")
    if not out:
        out.append("unverified")
    return out


def load_mechanics(repo: Path) -> dict:
    """name -> primitive over both systems' mechanics maps (the corpora are
    one GF corpus and one AoF corpus; a name can carry either's entry)."""
    out: dict = {}
    for system in ("gf", "aof"):
        path = repo / "assets" / "solo" / f"rules_mechanics_{system}.json"
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        blocks = [data.get("common") or {}]
        blocks += list((data.get("factions") or {}).values())
        for block in blocks:
            if not isinstance(block, dict):
                continue
            for name, entry in block.items():
                primitive = ""
                if isinstance(entry, dict) and isinstance(entry.get("primitive"), str):
                    primitive = entry["primitive"]
                out.setdefault(name, primitive)
    return out


def load_coverage(path: Path | None) -> dict:
    """PLAN A1's universe: name -> book occurrences (occ_by_system summed),
    empty when the file is absent — the mechanics maps then stand in."""
    if path is None:
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    rows = {}
    for name, row in (data.get("rows") or {}).items():
        obs = row.get("occ_by_system") or {}
        rows[name] = int(row.get("occ", 0)) or sum(int(v) for v in obs.values())
    return rows


def unit_rule_set(profile: dict) -> set:
    """A header profile's static rules: unit rules + hero grants + item
    grants + weapon rules, base-named."""
    out = {base_rule_name(r) for r in profile.get("special_rules") or []}
    for hero in profile.get("attached_hero_rules") or []:
        out |= {base_rule_name(r) for r in hero}
    out |= {base_rule_name(r) for r in profile.get("item_grants") or []}
    for weapon in profile.get("weapons") or []:
        out |= {base_rule_name(r) for r in weapon.get("rules") or []}
    out.discard("")
    return out


def act_rule_sets(act: dict, header_sets: dict) -> list[set]:
    """One act's per-unit rule sets: the per-act `prof` stamp (the field
    act_recorder.gd writes for every unit of every act) joined with the
    unit's static header set. Alive units only — a dead unit's rules are not
    live on the board."""
    out = []
    for key, unit in (act.get("state") or {}).get("units", {}).items():
        if not int(unit.get("alive", 0) or 0):
            continue
        prof = unit.get("prof") or {}
        rules = set(header_sets.get(key, set()))
        rules |= {base_rule_name(r) for r in prof.get("special_rules") or []}
        for hero in prof.get("attached_hero_rules") or []:
            rules |= {base_rule_name(r) for r in hero}
        rules |= {base_rule_name(r) for r in prof.get("item_grants") or []}
        rules.discard("")
        if rules:
            out.append(rules)
    return out


def census_corpus(corpus: Path) -> dict:
    """One corpus pass: acts-live counts, co-occurrence pairs, act classes,
    dice-kind fires. Single process, sequential, no replay."""
    games = sorted(d for d in corpus.iterdir()
                   if d.is_dir() and (d / "acts.jsonl").exists())
    if not games:
        raise SystemExit(f"no acts.jsonl under {corpus}")
    fired: dict[str, int] = {}
    pairs: dict[tuple, int] = {}
    classes = {c: {"acts": 0, "with_rolls": 0} for c in
               ("shooting", "melee", "other")}
    roll_kinds: dict[str, int] = {}
    acts_total = auto_total = 0
    systems: set = set()
    for gdir in games:
        with (gdir / "acts.jsonl").open() as f:
            header = json.loads(f.readline())
            header_sets = {k: unit_rule_set(p) for k, p in
                           (header.get("profiles") or {}).items()}
            for prof in (header.get("profiles") or {}).values():
                systems.add(str(prof.get("game_system", "?")))
            dice_by_act: dict[int, int] = {}
            if (gdir / "dice.jsonl").exists():
                with (gdir / "dice.jsonl").open() as df:
                    for dline in df:
                        rec = json.loads(dline)
                        kind = str(rec.get("roll_kind", "?"))
                        roll_kinds[kind] = roll_kinds.get(kind, 0) + 1
                        ordinal = int(rec.get("act", -1))
                        dice_by_act[ordinal] = dice_by_act.get(ordinal, 0) + 1
            # The INTERLEAVED activation ordinal (shoot_replay_gate.read_game):
            # auto lines carry their own `act` and bump the counter too.
            ordinal = 0
            for line in f:
                rec = json.loads(line)
                if rec.get("kind") == "auto":
                    ordinal += 1
                    auto_total += 1
                    continue
                ordinal += 1
                acts_total += 1
                action = (rec.get("pick") or {}).get("action") or {}
                act_kind = action.get("kind")
                if act_kind in SHOOTING_KINDS and action.get("shoot"):
                    cls = "shooting"
                elif act_kind == CHARGE_KIND and action.get("charge"):
                    cls = "melee"
                else:
                    cls = "other"
                classes[cls]["acts"] += 1
                classes[cls]["with_rolls"] += int(dice_by_act.get(ordinal, 0) > 0)
                act_rules: set = set()
                for rules in act_rule_sets(rec, header_sets):
                    act_rules |= rules
                    ordered = sorted(rules)
                    for i, a in enumerate(ordered):
                        for b in ordered[i + 1:]:
                            pairs[(a, b)] = pairs.get((a, b), 0) + 1
                # FIRED counts once per ACT — the rule was live on the board
                # during the activation, however many units carried it. The
                # PAIRS above stay per-unit (that is what co-occurrence means).
                for name in act_rules:
                    fired[name] = fired.get(name, 0) + 1
    return {"fired": fired, "pairs": pairs, "classes": classes,
            "roll_kinds": roll_kinds,
            "meta": {"games": len(games), "acts": acts_total,
                     "auto_acts": auto_total, "systems": sorted(systems)}}


def census(qbg: Path, qag: Path, repo: Path, coverage_path: Path | None,
           red_rule: str | None = None) -> dict:
    mechanics = load_mechanics(repo)
    coverage = load_coverage(coverage_path)
    result = {
        "meta": {
            "generated": datetime.datetime.now().isoformat(timespec="seconds"),
            "repo": str(repo),
            "head": git_head(repo),
            "qbg": str(qbg), "qag": str(qag),
            "coverage": str(coverage_path) if coverage_path else "",
            "tool": "core/nml-core-py/tools/rule_fire_census.py",
            "red": red_rule or "",
            "method": {
                "fired": "live during N activations: the per-act prof stamp "
                         "(special_rules / attached_hero_rules / item_grants) "
                         "of any alive unit, or the unit's static header "
                         "weapon rules while alive (act_recorder.gd "
                         "_stamp_gate_reads / header profiles)",
                "dice_fires": "recorded rolls whose roll_kind names the rule "
                              "(NML-1104)",
                "classes": "dice_stream = the rule's own recorded die; "
                           "melee_replay = CHARGE acts with a target; "
                           "shoot_replay = HOLD/ADVANCE acts with a shoot "
                           "target; unverified = no replay gate re-computes "
                           "the effect",
                "heuristic": "name/primitive keyword match (MELEE_TOKENS / "
                             "SHOOT_TOKENS), primary = first match in "
                             "CLASSES order; nothing matched = unverified",
            },
        }
    }
    for label, corpus in (("qbg", qbg), ("qag", qag)):
        result[label] = census_corpus(corpus)
    fired_names = set(result["qbg"]["fired"]) | set(result["qag"]["fired"])
    universe = sorted(set(coverage) | set(mechanics) | fired_names)
    rows = {}
    for name in universe:
        primitive = mechanics.get(name, "")
        fams = families_of(name, primitive)
        primary = "unverified" if red_rule and name == red_rule else fams[0]
        rows[name] = {
            "fired_qbg": result["qbg"]["fired"].get(name, 0),
            "fired_qag": result["qag"]["fired"].get(name, 0),
            "dice_fires_qbg": result["qbg"]["roll_kinds"].get(
                ROLL_KIND_OF_RULE.get(name, ""), 0),
            "dice_fires_qag": result["qag"]["roll_kinds"].get(
                ROLL_KIND_OF_RULE.get(name, ""), 0),
            "primitive": primitive,
            "class": primary,
            "class_green": fams[0],
            "families": fams,
            "in_corpus": name in fired_names,
            "book_occ": coverage.get(name, None),
        }
    result["rows"] = rows
    # the raw pair maps are tuple-keyed — merge to the ranked list, then drop.
    result["pairs"], result["pair_count"] = top_pairs(
        result["qbg"].pop("pairs"), result["qag"].pop("pairs"))
    result["roll_kinds"] = {"qbg": result["qbg"]["roll_kinds"],
                            "qag": result["qag"]["roll_kinds"]}
    result["summary"] = summarize(rows)
    if red_rule:
        if red_rule not in rows:
            raise SystemExit(f"--red-class: no rule named {red_rule!r}")
        green_class = rows[red_rule]["class_green"]
        red = {"rule": red_rule, "true_class": green_class, "moved": {}}
        ok = True
        for label in ("qbg", "qag"):
            corpus = result[label]
            names_green = {n: rows[n]["class_green"] for n in corpus["fired"]}
            names_red = dict(names_green, **{red_rule: "unverified"})
            before = class_acts(names_green, corpus["fired"], green_class)
            after = class_acts(names_red, corpus["fired"], green_class)
            red["moved"][label] = {"before": before, "after": after,
                                   "drop": before - after}
            ok = ok and (before - after) == corpus["fired"].get(red_rule, 0)
        red["ok"] = ok
        result["red"] = red
    return result


def class_acts(row_class: dict, fired: dict, cls: str) -> int:
    """Acts fired by every rule of one class — the number a mislabel moves."""
    return sum(n for name, n in fired.items() if row_class.get(name) == cls)


def top_pairs(qbg_pairs: dict, qag_pairs: dict, limit: int = 30) -> tuple[list, int]:
    keys = set(qbg_pairs) | set(qag_pairs)
    merged = []
    for a, b in keys:
        g, h = qbg_pairs.get((a, b), 0), qag_pairs.get((a, b), 0)
        merged.append({"pair": [a, b], "qbg": g, "qag": h, "total": g + h})
    merged.sort(key=lambda e: (-e["total"], e["pair"][0], e["pair"][1]))
    return merged[:limit], len(keys)


def summarize(rows: dict) -> dict:
    fired_total = {n: r["fired_qbg"] + r["fired_qag"] for n, r in rows.items()
                   if r["in_corpus"]}
    return {
        "rules_in_universe": len(rows),
        "rules_fired": len(fired_total),
        "fired_ge_20": sum(1 for v in fired_total.values() if v >= 20),
        "fired_1_19": sum(1 for v in fired_total.values() if 1 <= v < 20),
        "zero_fire": len(rows) - len(fired_total),
        "zero_fire_ranked": sorted(
            (n for n, r in rows.items() if not r["in_corpus"]),
            key=lambda n: (-(rows[n]["book_occ"] or 0), n)),
        "class_counts": {c: sum(1 for r in rows.values()
                                if r["in_corpus"] and r["class_green"] == c)
                         for c in CLASSES},
    }


def git_head(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10, check=False,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def summary_lines(res: dict) -> list[str]:
    s = res["summary"]
    lines = [
        "RULE-FIRE universe %d, fired %d (>=20: %d, 1-19: %d, zero: %d)"
        % (s["rules_in_universe"], s["rules_fired"], s["fired_ge_20"],
           s["fired_1_19"], s["zero_fire"]),
        "RULE-FIRE classes: " + ", ".join(
            "%s %d" % (c, s["class_counts"][c]) for c in CLASSES),
        "RULE-FIRE synergy pairs: %d distinct, top %d in the report"
        % (res["pair_count"], min(30, res["pair_count"])),
    ]
    for label in ("qbg", "qag"):
        m = res[label]["meta"]
        c = res[label]["classes"]
        lines.append(
            "RULE-FIRE %s (%s): %d games, %d acts (+%d auto, unstamped); "
            "shooting %d acts/%d with recorded rolls, melee %d/%d, other %d/%d"
            % (label, "+".join(m["systems"]) or "?", m["games"], m["acts"],
               m["auto_acts"], c["shooting"]["acts"], c["shooting"]["with_rolls"],
               c["melee"]["acts"], c["melee"]["with_rolls"],
               c["other"]["acts"], c["other"]["with_rolls"]))
    if res.get("red"):
        r = res["red"]
        lines.append(
            "RED --red-class %s: class %s acts %d -> %d (qbg), %d -> %d (qag)"
            " — drops exactly the rule's fires: %s"
            % (r["rule"], r["true_class"],
               r["moved"]["qbg"]["before"], r["moved"]["qbg"]["after"],
               r["moved"]["qag"]["before"], r["moved"]["qag"]["after"],
               "OK" if r["ok"] else "VIOLATION"))
    return lines


def verdict_of(row: dict) -> str:
    """The honest verdict column: identical / covered / unverified. Always
    reads the GREEN class — a --red-class run mislabels the row's class on
    purpose, and the mislabel must not leak into the verdict column."""
    if row["class_green"] == "dice_stream":
        return "identical"
    if row["class_green"] in ("melee_replay", "shoot_replay"):
        return "covered"
    return "unverified"


def markdown_report(res: dict) -> str:
    s = res["summary"]
    meta = res["meta"]
    out = [
        "# RULE FIRE CENSUS 2026-08-31 - fired per rule vs the replay gates (PLAN A2)",
        "",
        f"Generated {meta['generated']} from {meta['repo']} @ {meta['head']}."
        f" Corpora (private, read at runtime only): `{meta['qbg']}` (qbg, GF),"
        f" `{meta['qag']}` (qag, AoF)."
        + (f" Universe + book occurrences from `{meta['coverage']}` (PLAN A1)."
           if meta["coverage"] else ""),
        "",
        "## Method, and its honesty",
        "",
        "- **FIRED = live during N activations.** The recorder has no per-effect"
        " fire log: `act_recorder.gd` stamps every act line with the DYNAMIC rule"
        " vocabulary of every alive unit (`prof`: special_rules,",
        "  attached_hero_rules, item_grants) and writes the static weapon rules"
        " once per game into the header. A rule FIRED here when it was live on at"
        " least one alive unit of an act — counted ONCE per act, however many"
        " units carried it. The one real per-effect fire count is the dice tape:"
        " `roll_kind` (NML-1104) names the rule behind its die (Regeneration,"
        " Fearless, No Retreat, Ravage, Battleborn) — reported as `dice fires`"
        " alongside presence. The AoF corpus's tape predates the roll_kind stamp"
        " (its kinds are blanket attack/defense), so per-die fires are only"
        " measurable on the GF corpus — qag's zero dice-fire column is a"
        " VINTAGE gap, not a zero-fire claim.",
        "- **Gate classes, no replay re-run.** dice_stream = the rule's own"
        " recorded die (compared per roll by the D1 stream check); melee_replay ="
        " CHARGE acts with a target (B5b); shoot_replay = HOLD/ADVANCE acts with"
        " a shoot target (B4). Everything else is UNVERIFIED by the replay gates"
        " (movement, deployment, planner EV, spells, objectives).",
        "- **Verdicts:** identical = the rule's effect is recorded per die and"
        " was compared per die; covered = the rule's acts sit in a replay class"
        " the gates compared — per-act IDENTITY is that gate's own corpus report,"
        " not re-proven here (no per-act gate reports ship in the corpora);"
        " unverified = no replay gate re-computes the effect.",
        "- **Per-act re-check from the corpus itself:** an act of the two replay"
        " classes is gate-comparable only where dice.jsonl carries a roll under"
        " the act's interleaved ordinal (the table fought there); acts with no"
        " roll are the NML-1117 zero-volley case and count as NOT"
        " gate-comparable.",
        "- **Class labelling is a heuristic** (name/primitive keywords, primary"
        " = first match in CLASSES order) and the RED knob proves it is wired to"
        " the counts. `auto` acts carry no state and are counted but unstamped.",
        "",
        "## Summary",
        "",
        "```",
    ]
    out += summary_lines(res)
    out += ["```", ""]

    if res.get("red"):
        r = res["red"]
        out += [
            "## RED proof",
            "",
            f"`--red-class {r['rule']}` mislabels the rule as unverified. Its"
            f" true class ({r['true_class']}) lost exactly the rule's fired"
            f" acts in both corpora (qbg {r['moved']['qbg']['before']} ->"
            f" {r['moved']['qbg']['after']}, qag {r['moved']['qag']['before']}"
            f" -> {r['moved']['qag']['after']}) — **{'OK' if r['ok'] else 'VIOLATION'}**:"
            " the class column is wired to the counts, a mislabel moves them.",
            "",
        ]

    rows = res["rows"]
    fired_rows = sorted(
        ((n, r) for n, r in rows.items() if r["in_corpus"]),
        key=lambda kv: (-(kv[1]["fired_qbg"] + kv[1]["fired_qag"]), kv[0]))
    out += [
        f"## Rules that fired ({len(fired_rows)})",
        "",
        "`fired` = activations (acts) the rule was live in; `dice fires` ="
        " recorded rolls of the rule's own kind (NML-1104).",
        "",
        "| # | rule | fired qbg | fired qag | dice fires qbg/qag | class | verdict |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for i, (name, r) in enumerate(fired_rows, 1):
        dice = f"{r['dice_fires_qbg']}/{r['dice_fires_qag']}" \
            if (r["dice_fires_qbg"] or r["dice_fires_qag"]) else "-"
        out.append(
            f"| {i} | {name.replace('|', '/')} | {r['fired_qbg']}"
            f" | {r['fired_qag']} | {dice} | {r['class_green']} |"
            f" {verdict_of(r)} |")
    out.append("")

    zero = s["zero_fire_ranked"]
    out += [
        f"## ZERO-FIRE list ({len(zero)}) - never live in either corpus",
        "",
        "Ranked by book occurrences (PLAN A1) — candidates for targeted"
        " recordings, then for the synergy census.",
        "",
        "| # | rule | book occ | registry primitive |",
        "| --- | --- | --- | --- |",
    ]
    for i, name in enumerate(zero, 1):
        r = rows[name]
        occ = "" if r["book_occ"] is None else r["book_occ"]
        out.append(f"| {i} | {name.replace('|', '/')} | {occ}"
                   f" | {(r['primitive'] or 'UNMAPPED').replace('|', '/')} |")
    out.append("")

    out += [
        f"## Top {len(res['pairs'])} rule PAIRS (of {res['pair_count']} distinct)",
        "",
        "Two rules live on the SAME unit in the SAME act (one count per"
        " act-unit) — the synergy census seed.",
        "",
        "| # | pair | acts qbg | acts qag | total |",
        "| --- | --- | --- | --- | --- |",
    ]
    for i, p in enumerate(res["pairs"], 1):
        out.append(
            f"| {i} | {p['pair'][0]} + {p['pair'][1]} | {p['qbg']}"
            f" | {p['qag']} | {p['total']} |")
    out.append("")

    out += [
        "## Roll kinds on the tape (NML-1104)",
        "",
        "| roll_kind | qbg | qag | owning rule |",
        "| --- | --- | --- | --- |",
    ]
    kinds = sorted(set(res["roll_kinds"]["qbg"]) | set(res["roll_kinds"]["qag"]))
    for k in kinds:
        out.append(
            f"| {k} | {res['roll_kinds']['qbg'].get(k, 0)}"
            f" | {res['roll_kinds']['qag'].get(k, 0)}"
            f" | {RULE_OF_ROLL_KIND.get(k, '- (condition / terrain)')} |")
    out.append("")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Rule fire census (PLAN A2): per rule, fired N in the "
                    "reference corpora vs the replay gates that covered it.")
    ap.add_argument("--qbg", required=True,
                    help="GF reference corpus dir (private; read-only)")
    ap.add_argument("--qag", required=True,
                    help="AoF reference corpus dir (private; read-only)")
    ap.add_argument("--repo", default=str(REPO),
                    help="openTTS checkout providing assets/solo (default: this repo)")
    ap.add_argument("--coverage", default=None,
                    help="PLAN A1's RULE_COVERAGE_2026-08-31.json for the "
                         "universe + book occurrences (zero-fire ranking)")
    ap.add_argument("--red-class", default=None, metavar="RULE",
                    help="RED knob: mislabel this rule's class as unverified "
                         "— its true class must lose exactly the rule's fired acts")
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-md", default=None)
    args = ap.parse_args(argv)
    try:
        res = census(
            Path(args.qbg).expanduser(), Path(args.qag).expanduser(),
            Path(args.repo),
            Path(args.coverage).expanduser() if args.coverage else None,
            args.red_class)
    except SystemExit as exc:
        if exc.code and exc.code != 0:
            print(exc, file=sys.stderr)
            return 2
        raise
    for line in summary_lines(res):
        print(line)
    if args.out_json:
        out = Path(args.out_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(res, indent=1, sort_keys=True) + "\n")
    if args.out_md:
        out = Path(args.out_md)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(markdown_report(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())
