#!/usr/bin/env python
"""GATE D4 (NML-1073 M5) — hero attachment in the Godot-free trainer against the
ARENA's own recording.

The table derives attachment from the LIST: `BattleSim.capture`
(battle_sim.gd:1352-1369) indexes every unit by its `OPRApiClient.OPRUnit`
`selection_id` and joins each unit whose `join_to_unit` names one, because an
imported or AI army never runs the multiplayer attach path (NML-1081). The fast
trainer's loader dropped both fields, so every corpus it ever wrote has
`attached: []` / `attached_to: ""` on every unit — and the hosts' PROFILE field
`attached_hero_rules` empty with them. `selfplay.play_game(hero_attach="table")`
derives them; this gate says the derivation is the table's.

WHAT IS HELD, per game, per side:

  (1) ALIGNMENT — the multiset of unit IDENTITIES (name, quality, defense, model
      count, wounds) must agree between the arena header's `profiles` and the
      trainer's loader. This is the gate's own instrument check: nothing below
      means anything if the two are not looking at the same roster.

  (2) THE ATTACHMENT GRAPH — for every unit, a descriptor of
      (its identity, the identities of its `attached` heroes, its `attached_to`
      host's identity). The comparison is over the MULTISET of descriptors, not
      an index, because the arena spawns a joined hero right after its host
      while the trainer keeps roster order, and because a list may field two
      units with the same name. Equal multisets = the two graphs are the same
      graph under identity labels.

  (3) THE PROFILE EFFECT — `attached_hero_rules`, the one profile field the
      table derives from attachment (`BattleSim._attached_hero_rules`
      battle_sim.gd:1653-1660, quantified by `AiEv.rule_on_all_models`). Its
      ARITY per host is the bar: how many alive heroes vote on that host's
      unit-wide rules. The CONTENT of each entry is reported but NOT gated — the
      arena's hero carries the runtime rules its item grants and its own auras
      added (`Furious`, `Fast`, ...), which the Godot-free list loader does not
      model yet; that gap is the rules loader's, not this rung's, and gating it
      here would be gating someone else's bug.

The arena reading is the FIRST act's recorded state plus the header's profiles.
The pairing and the seed come from the DIRECTORY NAME, never from inside the
file, so a reference laid down for one pairing cannot be compared against
another's armies.

RED PROOF: `--mode off` runs the SAME comparison with the trainer's default
(no attachment at all). Every game that carries a joined hero must go red; the
gate prints how many do, and refuses to call a vacuous run a proof.

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/hero_attach_gate.py \\
        --ref ~/selfplay_out/qb_ref --lists ~/nml-mission/farm/ai_lists
    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/hero_attach_gate.py \\
        --ref ~/selfplay_out/qb_ref --lists ~/nml-mission/farm/ai_lists --mode off
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import selfplay as sp  # noqa: E402

#: `<p1>_vs_<p2>_s<seed>` — `p1` NON-greedy, as in `qa_gate.py`.
GAME_DIR = re.compile(r"^(?P<p1>.+?)_vs_(?P<p2>.+)_s(?P<seed>\d+)$")

#: The unit label both corpora agree on. NOT the whole profile: the arena's
#: `special_rules`, `move_bands`, `item_grants` and `base_radius` carry runtime
#: grants and real per-model base radii that the Godot-free loader does not
#: produce, and `unit_id` is a runtime token on one side and a roster index on
#: the other.
IDENT_FIELDS = ("name", "quality", "defense", "model_count")


def ident(profile: dict) -> tuple:
    return tuple(profile[k] for k in IDENT_FIELDS) + (tuple(profile["wounds_max"]),)


def games(ref_dir: Path, seeds: set[int] | None, pairing: str) -> list[tuple]:
    """Every `<p1>_vs_<p2>_s<seed>` directory with an `acts.jsonl`."""
    out: list[tuple] = []
    for d in sorted(ref_dir.iterdir()):
        if not d.is_dir():
            continue
        m = GAME_DIR.match(d.name)
        if not m or not (d / "acts.jsonl").is_file():
            continue
        seed = int(m.group("seed"))
        if seeds is not None and seed not in seeds:
            continue
        pair = "%s_vs_%s" % (m.group("p1"), m.group("p2"))
        if pairing and pairing not in pair:
            continue
        out.append((pair, m.group("p1"), m.group("p2"), seed, d))
    return out


def arena_reading(game_dir: Path) -> tuple[dict, dict]:
    """The header's `profiles` and the FIRST act's per-unit state. Raises on a
    file still being written — the caller counts those rather than half-reads
    them (`qb_ref` grows while this gate runs)."""
    with open(game_dir / "acts.jsonl", encoding="utf-8") as f:
        header = json.loads(f.readline())
        act = json.loads(f.readline())
    return header["profiles"], act["state"]["units"]


def arena_graph(profiles: dict, units: dict) -> dict[int, list[tuple]]:
    """The arena's descriptors, per side: `(ident, attached idents, host ident,
    attached_hero_rules arity)` — one per unit."""
    out: dict[int, list[tuple]] = {1: [], 2: []}
    for key, su in units.items():
        p = profiles[key]
        out[int(su["player"])].append(
            (
                ident(p),
                tuple(sorted(ident(profiles[h]) for h in su.get("attached", []))),
                ident(profiles[su["attached_to"]]) if su.get("attached_to") else None,
                len(p.get("attached_hero_rules", [])),
            )
        )
    return out


def trainer_graph(units1: list, units2: list, attached: dict, attached_to: dict) -> dict:
    """The same descriptors off the trainer's loader + `derive_attachment`."""
    by_id = {u["unit_id"]: u for u in units1 + units2}
    out: dict[int, list[tuple]] = {1: [], 2: []}
    for side, us in ((1, units1), (2, units2)):
        for u in us:
            key = u["unit_id"]
            host = attached_to.get(key, "")
            out[side].append(
                (
                    ident(u),
                    tuple(sorted(ident(by_id[h]) for h in attached.get(key, []))),
                    ident(by_id[host]) if host else None,
                    len(u.get("attached_hero_rules", [])),
                )
            )
    return out


def hero_rules(profiles: dict, units: dict) -> Counter:
    """`(host ident, its attached_hero_rules as written)` — the CONTENT tally,
    reported and not gated (see the module docstring)."""
    c: Counter = Counter()
    for key, su in units.items():
        rules = profiles[key].get("attached_hero_rules", [])
        if rules:
            c[(ident(profiles[key]), tuple(tuple(r) for r in rules))] += 1
    return c


def trainer_hero_rules(units1: list, units2: list) -> Counter:
    c: Counter = Counter()
    for u in units1 + units2:
        rules = u.get("attached_hero_rules", [])
        if rules:
            c[(ident(u), tuple(tuple(r) for r in rules))] += 1
    return c


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of <p1>_vs_<p2>_s<seed> dirs")
    ap.add_argument(
        "--lists",
        default=str(Path("~/nml-mission/farm/ai_lists").expanduser()),
        help="directory the army list JSONs live in",
    )
    ap.add_argument(
        "--mode",
        choices=list(sp.HERO_ATTACH_MODES),
        default="table",
        help="'table' is the gate; 'off' is the RED PROOF and must fail",
    )
    ap.add_argument("--pairing", default="", help="only pairings containing this substring")
    ap.add_argument("--seeds", default="", help='e.g. "27-46" or "1,4,9"; default all')
    a = ap.parse_args(argv)

    lists = Path(a.lists).expanduser()
    seeds = None
    if a.seeds:
        seeds = set()
        for part in a.seeds.split(","):
            if "-" in part:
                lo, hi = part.split("-", 1)
                seeds.update(range(int(lo), int(hi) + 1))
            else:
                seeds.add(int(part))
    found = games(Path(a.ref).expanduser(), seeds, a.pairing)
    if not found:
        print("no reference games under %s" % a.ref)
        return 1

    total = equal = joined = unreadable = misaligned = 0
    missing: list[str] = []
    units_seen = heroes = 0
    ahr_exact = ahr_total = 0
    per_pairing: dict[str, list] = {}
    first: tuple | None = None
    for pair, p1, p2, seed, d in found:
        army1, army2 = lists / ("%s.json" % p1), lists / ("%s.json" % p2)
        if not (army1.exists() and army2.exists()):
            missing.append(pair)
            continue
        try:
            profiles, aunits = arena_reading(d)
        except (ValueError, KeyError, IndexError):
            unreadable += 1
            continue

        units1, units2 = sp.load_army(army1, 1), sp.load_army(army2, 2)
        attached: dict = {}
        attached_to: dict = {}
        if sp.resolve_hero_attach(a.mode):
            selections = dict(sp.load_selections(army1, 1))
            selections.update(sp.load_selections(army2, 2))
            attached, attached_to = sp.derive_attachment(units1 + units2, selections)
            by_id = {u["unit_id"]: u for u in units1 + units2}
            for u in units1 + units2:
                u["attached_hero_rules"] = [
                    by_id[h]["special_rules"] for h in attached[u["unit_id"]]
                ]

        total += 1
        book = per_pairing.setdefault(pair, [0, 0])
        book[0] += 1
        arena, got = arena_graph(profiles, aunits), trainer_graph(units1, units2, attached, attached_to)
        game_joined = any(g[1] for side in arena.values() for g in side)
        joined += game_joined
        units_seen += len(aunits)
        heroes += sum(1 for side in arena.values() for g in side if g[2] is not None)

        # (1) the instrument check, then (2) the graph.
        ok = True
        for side in (1, 2):
            if Counter(g[0] for g in arena[side]) != Counter(g[0] for g in got[side]):
                misaligned += 1
                ok = False
                if first is None:
                    first = (d.name, side, "ROSTER", sorted(Counter(g[0] for g in arena[side]).items()),
                             sorted(Counter(g[0] for g in got[side]).items()))
                break
        if ok:
            for side in (1, 2):
                ac, tc = Counter(arena[side]), Counter(got[side])
                if ac != tc:
                    ok = False
                    if first is None:
                        diff = sorted(set(ac) | set(tc), key=repr)
                        d0 = [k for k in diff if ac[k] != tc[k]][0]
                        first = (d.name, side, "GRAPH", "arena x%d %r" % (ac[d0], d0),
                                 "trainer x%d" % tc[d0])
                    break
        if ok:
            equal += 1
            book[1] += 1

        # (3) the content tally — reported, never gated.
        ac, tc = hero_rules(profiles, aunits), trainer_hero_rules(units1, units2)
        ahr_total += sum(ac.values())
        ahr_exact += sum((ac & tc).values())

    print()
    for pair in sorted(per_pairing):
        n, ok = per_pairing[pair]
        print("%-52s %3d/%-3d games attachment-equal" % (pair, ok, n))
    if missing:
        print("\nNO ARMY LIST for %d game(s): %s" % (len(missing), sorted(set(missing))))
    if unreadable:
        print("\n%d game(s) skipped: acts.jsonl still being written" % unreadable)
    if first:
        print("\nFIRST MISMATCH  %s  side %d  %s\n  arena   %s\n  trainer %s" % first)
    print(
        "\nunits compared %d, joined heroes %d, games with a joined hero %d/%d"
        % (units_seen, heroes, joined, total)
    )
    print(
        "attached_hero_rules: %d host entries in the arena, %d of them byte-equal in the "
        "trainer (the rest are the loader's runtime-grant gap, not gated)" % (ahr_total, ahr_exact)
    )
    if misaligned:
        print("ROSTER MISALIGNED on %d game(s) — the instrument check, not the rule" % misaligned)

    label = "GATE D4" if a.mode == "table" else "RED D4 (hero_attach=off)"
    print(
        "\n%s: %d/%d games with the arena's attachment graph, unit for unit"
        % (label, equal, total)
    )
    if a.mode == "off":
        if not joined:
            print("VACUOUS: not one reference game joins a hero — this red proof proves nothing")
            return 1
        # A red proof PASSES when every game that HAS a joined hero diverged.
        return 0 if equal == total - joined else 1
    return 0 if total and equal == total else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
