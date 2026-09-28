"""WAVE C GATE (NML-1010, C9-gate step C9.5) — THE REFEREE REPLAY.

The table's `rounds.jsonl` (AiActRecorder.round_end) holds per round the board BEFORE its
round-end referee ran (`pre`) and the ledger it left (`post`). The core replays each `pre`
through `selfplay._round_end` and must reach `post` exactly — same board in, so the bar is
100 % and a mismatch is a referee disagreement, never play drift."""

# `--red-skip-carry` drops the carry step and must part rounds on a bundle with pickups; a
# carry bundle with fewer than `--min-pickups` pickups is INCONCLUSIVE (too little carry seen
# to certify it). Exit 0 = PASS (or RED held), 1 = FAIL, 2 = INCONCLUSIVE.

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay as sp  # noqa: E402

FIELDS = ("owners", "carried_by", "destroyed", "vp")


def _ledger(owners, carriers, markers, vp) -> dict:
    return {"owners": [int(o) for o in owners], "carried_by": carriers,
            "destroyed": [bool(m.get("destroyed", False)) for m in markers],
            "vp": None if vp is None else [int(v) for v in vp]}


def table_ledger(post: dict, round_vp: bool) -> dict:
    """The table's `post`, carriers by unit key ("" = none)."""
    mm = post.get("markers_meta") or []
    return _ledger(post.get("owners") or [], [str(m.get("carried_by", "")) for m in mm], mm,
                   post.get("vp") if round_vp else None)


def core_ledger(core, pre: dict, round_no: int, skip_carry: bool) -> dict:
    """The core's round-end referee on the table's `pre` board, carriers mapped to keys."""
    state = core.state_of(pre)
    keys = state.keys()
    led = sp._ledger_of(state)
    state, owners = sp._round_end(core, state, [int(o.get("owner", 0)) for o in pre["objectives"]],
                                  led, round_no, skip_carry=skip_carry)
    mm = led["markers_meta"]
    carriers = [keys[int(m.get("carried_by", -1))] if int(m.get("carried_by", -1)) >= 0 else ""
                for m in mm]
    return _ledger(owners, carriers, mm, led["vp"] if led["scoring"] == "round_vp" else None)


def judge_game(core, d: Path, mission: str, skip_carry: bool = False) -> dict:
    """One game, every round end compared field by field; a game stamped with another
    mission or without one round line per played round is refused, never skipped."""
    arena = json.loads(next(d.glob("arena_*.json")).read_text())
    stamped = str((arena.get("mission") or {}).get("name", "duel"))
    f = d / "rounds.jsonl"
    recs = [json.loads(x) for x in f.read_text().splitlines() if x.strip()] if f.exists() else []
    if stamped != mission or not recs or len(recs) != int(arena.get("rounds_played", -1)):
        return {"name": d.name, "refused": "stamped %s, %d round lines for %s rounds"
                % (stamped, len(recs), arena.get("rounds_played"))}
    core.set_header(json.loads((d / "acts.jsonl").read_text().splitlines()[0]))
    rows, prev = [], [""] * len(recs[0]["pre"].get("markers_meta") or [])
    for rec in recs:
        pre = [str(m.get("carried_by", "")) for m in rec["pre"].get("markers_meta") or []]
        want = table_ledger(rec["post"], rec["pre"].get("scoring") == "round_vp")
        got = core_ledger(core, rec["pre"], int(rec["round"]), skip_carry)
        rows.append({"round": int(rec["round"]), "want": want, "got": got,
                     "parted": [k for k in FIELDS if want[k] != got[k]],
                     "pickups": sum(1 for a, b in zip(pre, want["carried_by"]) if not a and b),
                     "drops": sum(1 for a, b in zip(prev, pre) if a and not b)})
        prev = want["carried_by"]
    return {"name": d.name, "rounds": rows,
            "carry": any(m.get("carry") for m in recs[0]["pre"].get("markers_meta") or [])}


def report(mission: str, ref: Path, games: list, red: bool, min_pickups: int) -> int:
    rounds = [r for g in games for r in g.get("rounds", [])]
    same = sum(1 for r in rounds if not r["parted"])
    pickups = sum(r["pickups"] for r in rounds)
    refused = [g for g in games if "refused" in g]
    print("MISSION REFEREE GATE [%s]%s over %d games of %s" % (
        mission, " RED skip-carry" if red else "", len(games), ref.name))
    print("  ROUNDS  : %d/%d round ends identical (owners + carried_by + destroyed + vp under "
          "round_vp); GAMES %d/%d; refused %d" % (same, len(rounds), sum(
              1 for g in games if g.get("rounds") and not any(r["parted"] for r in g["rounds"])),
              len(games), len(refused)))
    print("  PARTED  : " + "  ".join("%s=%d" % (k, sum(1 for r in rounds if k in r["parted"]))
                                     for k in FIELDS))
    print("  COVERAGE: %d pickups, %d drops (the table's own record)%s" % (
        pickups, sum(r["drops"] for r in rounds),
        "; first refused %s — %s" % (refused[0]["name"], refused[0]["refused"]) if refused else ""))
    bad = [(g["name"], r) for g in games for r in g.get("rounds", []) if r["parted"]]
    if bad:
        name, r = bad[0]
        k = r["parted"][0]
        print("  first   : %s round %d [%s] table %s vs core %s"
              % (name, r["round"], k, r["want"][k], r["got"][k]))
    if red:
        held = pickups > 0 and same < len(rounds)
        print("  RED     : " + ("held — the comparison sees carry" if held
                                else "FAILED — skipping the carry step moved nothing"))
        return 0 if held else 1
    verdict, rc = ("FAIL", 1) if refused or not rounds or same != len(rounds) else \
        ("INCONCLUSIVE (%d pickups < %d)" % (pickups, min_pickups), 2) \
        if any(g.get("carry") for g in games) and pickups < min_pickups else ("PASS", 0)
    print("  VERDICT : " + verdict)
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of recorded arena game dirs")
    ap.add_argument("--mission", required=True, help="catalog id every game must be stamped with")
    ap.add_argument("--red-skip-carry", action="store_true", help="RED: no carry step")
    ap.add_argument("--min-pickups", type=int, default=5)
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    a = ap.parse_args(argv)
    ref, core = Path(a.ref).expanduser(), nml_core.load(a.repo)
    dirs = sorted(d for d in ref.iterdir() if d.is_dir() and any(d.glob("arena_*.json")))
    games = [judge_game(core, d, a.mission, a.red_skip_carry) for d in dirs]
    return report(a.mission, ref, games, a.red_skip_carry, a.min_pickups)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
