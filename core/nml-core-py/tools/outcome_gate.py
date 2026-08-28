"""GATE D0 (NML-1073 M5) — THE OUTCOME GATE: the twin plays the WHOLE recorded
game and is judged on the RESULT.

WHAT WAS MISSING. Every other gate here replays ONE activation: it seats the
port on a RECORDED state, hands it the recorded action, compares the dice or
the next state. Right question for a rule, wrong question for a TRAINER — an
activation gate can be green on every act while the twin, left to play on its
own, walks off into a different game by act three. This one asks the whole-game
question: from the TABLE's deployment, on the TABLE's dice tape, does the twin
reach the TABLE's result?

THE ENTRY. `selfplay.play_game` cannot answer it — it starts from two army
lists and a seed and deploys itself. `selfplay.play_from_state` (D0) is what
this rung adds: the same round loop, shared in code, started from a state the
caller supplies. That state is the FIRST act line's, the board right after the
table deployed; the opener is `arena_*.json`'s own; the dice are
`nml_core.Tray(dice_seed)`, the tray twin the whole D1 ladder is built on. NO
new Rust was needed.

THE TAPE, and its one honest limit. The table's dice are not a list of faces
that can be forced onto the twin — they are a SEEDED stream, and the twin sees
the table's faces only while it draws the same COUNTS in the same ORDER. One
die more or fewer and every face after it is the table's stream read at the
wrong offset. That is the measurement, not a defect: `DICE act` reports the
twin's own activation ordinal at the first roll where its stream stops matching
`dice.jsonl`, and it plays on from there on the same tray.

THE NUMBERS, per corpus. RESULT — games where `winner`, `objectives`
p1/p2/neutral and `rounds_played` all match, the headline. SEQUENCE — RESULT
and the same picks throughout (same seat, unit, action kind, shoot/charge
target, in the shoot/melee gates' vocabulary), which is the column that says
how many identical results are identical GAMES. DIV — the act ordinal of the
first pick divergence as a histogram, and the FIELD that parted there. MARGIN —
mean |objective margin difference|, margin = p1 - p2 markers.

THE TWO REDS, and the first one is measured against the TWIN, not the table.
`--red-misseed` plays every game TWICE in the same pass — once on the table's
tape, once on the same tape offset by ONE die — and holds the two TWIN runs
against each other. It has to be that way round: a red is only a proof where
the green arm is high, and this gate's green arm against the table is not (see
the RESULT row). Twin against twin it is exact by construction, so an offset
that did not move the games would mean the tape is not driving them at all.
`--red-swap-seats` relabels the twin's FINISHED result p1<->p2 — nothing about
the game moves, so every game the comparison scored right must now score wrong,
except a draw, which is seat-symmetric and is reported apart rather than
hidden. It costs no second pass and is therefore printed on every run.

`--fresh N` is not a gate: N seeds, both seats the twin, its own RNG and its own
deployment, to report the throughput and result distribution Gen-0 will carry.

    ~/venvs/nmloutcome/bin/python core/nml-core-py/tools/outcome_gate.py \\
        --ref ~/selfplay_out/qbg_ref --jobs 10
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay as sp  # noqa: E402
from shoot_replay_gate import (  # noqa: E402
    combat_kind, read_game, resolve_vintage_flag, vintage_report_line,
)

#: The FIDELITY knobs, all on: this gate measures the twin at its best, not the
#: default trainer. `engage_fold`/`cond_ap` are NOT here — those are the
#: corpus's own VINTAGE (NML-1130) and resolve per game. `charge_gate` is not
#: here either: `acts::ActKnobs` defaults it ON, which is what the corpus's own
#: per-act `charge_gate: true` records. Nor is `objectives` (D8a): a replay
#: INHERITS the table's markers off the recorded state — count, positions and
#: starting ownership — so there is no mode for this gate to pick. See
#: `selfplay.play_from_state`'s THE OBJECTIVES KNOB.
FIDELITY = {"hero_attach": True, "charge_landing": True, "sighting": "model",
            "movement": True, "dangerous": True}
#: The fields a pick is compared on, in the order they are tested — which is
#: also the order `pick_class` names them.
PICK_FIELDS = ("seat", "unit", "kind", "target")
#: The first-divergence histogram's buckets: fine where the answers are.
HIST = ("1", "2", "3", "4-6", "7-12", "13+", "never")
_CORE: dict[str, object] = {}


def pick_key(side: int, action: dict | None) -> tuple:
    """One activation in the shoot/melee gates' vocabulary: who acted, with
    what, how, against whom. `dest` is deliberately OUT — a charge that aims a
    millimetre differently is the same PICK, and where it lands is what D5-2's
    own gate measures."""
    a = action or {}
    return (int(side), str(a.get("unit", "")), int(a.get("kind", -1)),
            str(a.get("shoot") or a.get("charge") or ""))


def pick_class(want: tuple, got: tuple) -> str:
    """WHICH field of a pick parted first — the diagnosis, not the count."""
    for i, name in enumerate(PICK_FIELDS):
        if want[i] != got[i]:
            return name
    return "none"


def margin(res: dict) -> int:
    """The score line as ONE number: p1 markers minus p2 markers."""
    return int(res["objectives"]["p1"]) - int(res["objectives"]["p2"])


def swap_seats(res: dict) -> dict:
    """`--red-swap-seats` — the same result read from the other seat. Nothing
    about the played game moves; only the labels do."""
    o = res["objectives"]
    return dict(res, winner={"p1": "p2", "p2": "p1"}.get(res["winner"], "draw"),
                objectives={"p1": int(o["p2"]), "p2": int(o["p1"]),
                            "neutral": int(o["neutral"])})


def compare(want: dict, got: dict) -> dict:
    """One game's verdict. `want`/`got` carry `winner`, `objectives`,
    `rounds_played` and `picks` (a list of `pick_key` tuples). `div_at` is the
    1-based ordinal of the first pick that parted, `None` when none did; a
    stream that simply ran out parts as `length` at the shorter one's end."""
    w, g = want["picks"], got["picks"]
    div_at, div_class = None, "none"
    for i, (a, b) in enumerate(zip(w, g), 1):
        if a != b:
            div_at, div_class = i, pick_class(a, b)
            break
    if div_at is None and len(w) != len(g):
        div_at, div_class = min(len(w), len(g)) + 1, "length"
    result = (want["winner"] == got["winner"]
              and want["objectives"] == got["objectives"]
              and int(want["rounds_played"]) == int(got["rounds_played"]))
    return {"result": result, "winner": want["winner"] == got["winner"],
            "sequence": result and div_at is None, "div_at": div_at,
            "div_class": div_class, "margin_diff": abs(margin(want) - margin(got))}


def dice_divergence(rolls_by_act: list, dice: list) -> int | None:
    """The twin's own activation ordinal (1-based) at the first roll where its
    dice stream stops matching `dice.jsonl`; `None` when the two agree roll for
    roll AND end together. The recorded `roll_kind` folds through
    `combat_kind()` first (NML-1104) — the port stamps every combat die
    "attack"/"defense" and has no matching per-rule split."""
    want = [(combat_kind(r["roll_kind"]), int(r["count"]), int(r["target"]),
             list(r["faces"])) for r in dice]
    i = 0
    for ordinal, rolls in enumerate(rolls_by_act, 1):
        for r in rolls:
            if i >= len(want) or (r["kind"], int(r["count"]), int(r["target"]),
                                  list(r["faces"])) != want[i]:
                return ordinal
            i += 1
    return None if i == len(want) else len(rolls_by_act) + 1


def bucket(n: int | None) -> str:
    """One ordinal into its `HIST` bucket."""
    if n is None:
        return "never"
    return str(n) if n <= 3 else "4-6" if n <= 6 else "7-12" if n <= 12 else "13+"


def hist(values, keys) -> str:
    """One histogram line, in the given key order, zeros dropped."""
    c = {k: 0 for k in keys}
    for v in values:
        c[v] = c.get(v, 0) + 1
    return "  ".join("%s=%d" % (k, c[k]) for k in c if c[k])


def _play(core, head: dict, lines: list, opener: int, seed: int, offset: int) -> tuple:
    """One whole game on the table's tape, `offset` dice late. Returns the
    result with its `picks` list attached, plus the rolls per activation."""
    tray = nml_core.Tray(seed)
    if offset:
        tray.roll(offset)
    rolls: list = []
    got = sp.play_from_state(core, lines[0]["state"], head["profiles"], opener,
                             nml_core.Rng(seed), tray=tray, roll_log=rolls)
    got["picks"] = [pick_key(r["side"], r["action"]) for r in got["planner_positions"]]
    return got, rolls


def play_one(job: tuple) -> dict:
    """One recorded game, replayed whole. Runs in a worker process; everything
    it returns is plain data, because a `State` does not cross a pipe."""
    name, ref, repo, misseed, engage_fold, cond_ap = job
    d = Path(ref) / name
    head, lines, dice, seed = read_game(d)
    arena = json.loads(next(d.glob("arena_*.json")).read_text())
    eff = (resolve_vintage_flag(engage_fold, head, repo, "engage_fold"),
           resolve_vintage_flag(cond_ap, head, repo, "cond_ap"))
    nml_core.set_legacy_no_cond_ap(not eff[1])
    core = _CORE.get(repo) or _CORE.setdefault(repo, nml_core.load(repo))
    core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                     "knobs": dict(head.get("knobs", {}), engage_fold=eff[0], **FIDELITY)})
    t0 = time.perf_counter()
    got, rolls = _play(core, head, lines, int(arena["opener"]), seed, 0)
    secs = time.perf_counter() - t0
    o = arena["objectives"]
    want = {"winner": arena["winner"], "rounds_played": int(arena["rounds_played"]),
            "objectives": {"p1": int(o["p1"]), "p2": int(o["p2"]),
                           "neutral": int(o["neutral"])},
            "picks": [pick_key(a["player"], (a.get("pick") or {}).get("action"))
                      for a in lines]}
    row = compare(want, got)
    row.update(name=name, seconds=secs, acts=len(got["picks"]), rec_acts=len(lines),
               markers=len(lines[0]["state"].get("objectives") or []),
               dice_div=dice_divergence(rolls, dice), vintage=eff,
               swapped=compare(want, swap_seats(got))["result"],
               draw=want["winner"] == "draw")
    if misseed:
        # THE RED, and it runs against the GREEN arm above rather than against
        # the table — the docstring's THE TWO REDS says why.
        late, _ = _play(core, head, lines, int(arena["opener"]), seed, 1)
        row["red"] = compare(got, late)
    if row["div_at"] is not None:
        i = row["div_at"] - 1
        row["example"] = "%s act %d [%s] table %s vs twin %s" % (
            name, row["div_at"], row["div_class"],
            want["picks"][i] if i < len(want["picks"]) else "(no act)",
            got["picks"][i] if i < len(got["picks"]) else "(no act)")
    return row


def report(label: str, ref: Path, rows: list, secs: float, jobs: int) -> int:
    n = len(rows)
    draws = sum(1 for r in rows if r["draw"])
    swapped = sum(1 for r in rows if r["swapped"])
    md = [r["margin_diff"] for r in rows]
    print()
    print("%s over %d games of %s (%.1fs wall, %d workers) — %s"
          % (label, n, ref.name, secs, jobs,
             vintage_report_line({tuple(r["vintage"]) for r in rows})))
    print("  RESULT  : %d/%d games identical (winner + objectives p1/p2/neutral + "
          "rounds_played); winner alone %d/%d"
          % (sum(1 for r in rows if r["result"]), n, sum(1 for r in rows if r["winner"]), n))
    print("  SEQUENCE: %d/%d games identical result AND identical pick sequence"
          % (sum(1 for r in rows if r["sequence"]), n))
    print("  MARGIN  : mean |objective margin difference| %.3f (max %d, exact %d/%d)"
          % (sum(md) / max(n, 1), max(md or [0]), sum(1 for m in md if m == 0), n))
    print("  DIV act : %s" % hist([bucket(r["div_at"]) for r in rows], HIST))
    print("  DIV why : %s" % hist([r["div_class"] for r in rows],
                                  PICK_FIELDS + ("length", "none")))
    print("  DICE act: %s" % hist([bucket(r["dice_div"]) for r in rows], HIST))
    print("  acts    : %d twin vs %d recorded, %.2fs per game; markers per game %s"
          % (sum(r["acts"] for r in rows), sum(r["rec_acts"] for r in rows),
             sum(r["seconds"] for r in rows) / max(n, 1),
             hist([str(r["markers"]) for r in rows], [str(i) for i in range(1, 6)])))
    seen: dict[str, str] = {}
    for r in sorted(rows, key=lambda r: r["div_at"] or 0):
        if r.get("example"):
            seen.setdefault(r["div_class"], r["example"])
    for ex in list(seen.values())[:3]:
        print("  first   : %s" % ex)
    print("  RED swap-seats: %d/%d games still identical with the twin's result read from the "
          "other seat (%d are draws, which are seat-symmetric) — %s"
          % (swapped, n, draws,
             "held" if swapped <= draws else "FAILED, a non-draw survived a seat swap"))
    return 0 if swapped <= draws else 1


def _fresh_one(job: tuple) -> dict:
    seed, army1, army2, repo, bank = job
    core = _CORE.get(repo) or _CORE.setdefault(repo, nml_core.load(repo))
    t0 = time.perf_counter()
    res = sp.play_game(seed, army1, army2, repo, bank, core=core, sidecars=False,
                       hero_attach="table", dice="table", charge_landing="table",
                       movement="table", sighting="model")
    return {"winner": res["winner"], "m": margin(res), "acts": len(res["planner_positions"]),
            "seconds": time.perf_counter() - t0}


def fresh(n: int, army1: str, army2: str, repo: str, bank: str, start: int, jobs: int) -> int:
    """`--fresh N` — N seeds, both seats the twin, its own RNG and its own
    deployment. NOT a parity measurement: there is nothing to compare against.
    It reports what Gen-0's own games cost and how they end.

    Every fidelity knob the gate arm sets, this one sets too — `sighting`
    included since #471 gave `play_game` the parameter. `objectives` stays
    "constant" (D8a's default) because that is what both reference corpora were
    recorded with; a Gen-0 run that wants the rulebook layout passes it there."""
    t0 = time.perf_counter()
    jobs = max(1, min(jobs, n))
    with mp.get_context("spawn").Pool(jobs) as pool:
        rows = pool.map(_fresh_one, [(s, army1, army2, repo, bank)
                                     for s in range(start, start + n)])
    secs = time.perf_counter() - t0
    print()
    print("FRESH (both seats the twin, own RNG, objectives=constant) — %d games, %.1fs wall, "
          "%d workers, %.2f games/s, %.0f games/hour/worker"
          % (n, secs, jobs, n / secs, 3600.0 * n / sum(r["seconds"] for r in rows)))
    print("  winner  : %s" % hist([r["winner"] for r in rows], ("p1", "p2", "draw")))
    print("  margin  : mean p1-p2 markers %+.3f, |margin| mean %.3f, distribution %s"
          % (sum(r["m"] for r in rows) / n, sum(abs(r["m"]) for r in rows) / n,
             hist([str(r["m"]) for r in rows], [str(i) for i in range(-3, 4)])))
    print("  per game: %.2fs, %d activations"
          % (sum(r["seconds"] for r in rows) / n, sum(r["acts"] for r in rows) // n))
    return 0


def run(ref: Path, repo: str, limit: int, jobs: int, misseed: bool,
        engage_fold: str, cond_ap: str) -> int:
    games = sorted(d.name for d in ref.iterdir()
                   if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1
    jobs = max(1, min(jobs, len(games)))
    jobargs = [(g, str(ref), repo, misseed, engage_fold, cond_ap) for g in games]
    t0 = time.perf_counter()
    if jobs == 1:
        rows = [play_one(j) for j in jobargs]
    else:
        with mp.get_context("spawn").Pool(jobs) as pool:
            rows = pool.map(play_one, jobargs)
    label = ("GATE D0 outcome parity + RED --red-misseed" if misseed
             else "GATE D0 outcome parity")
    rc = report(label, ref, rows, time.perf_counter() - t0, jobs)
    if not misseed:
        return rc
    # The red's bar. Twin against twin the green arm is exact by construction,
    # so a tape read one die late must move the GAMES: the same result on a
    # third of them would still be honest (a Face-Off marker count is a coarse
    # number and two different games land on it often), the same PICK SEQUENCE
    # would not be — that is the same game, and the dice would not be driving it.
    same = sum(1 for r in rows if r["red"]["result"])
    seq = sum(1 for r in rows if r["red"]["sequence"])
    n = len(rows)
    print("  RED misseed: the same game one die late reaches the same result on %d/%d and the "
          "same PICK SEQUENCE on %d/%d (first divergence %s) — %s"
          % (same, n, seq, n, hist([bucket(r["red"]["div_at"]) for r in rows], HIST),
             "held" if seq == 0 and same * 2 < n else
             "FAILED, one offset die barely moved the games"))
    return 0 if seq == 0 and same * 2 < n else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", help="directory of recorded arena game dirs")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--jobs", type=int, default=10, help="worker processes (spawn)")
    ap.add_argument("--red-misseed", action="store_true",
                    help="RED PROOF: offset the dice tape by one die before round 1. Every "
                         "count and target is unchanged, so the twin plays the table's own "
                         "stream read one die late and the RESULTS must part")
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: 'auto' reads the corpus's own vintage (vintage_knobs)")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: 'auto' reads the corpus's own vintage (vintage_knobs)")
    ap.add_argument("--fresh", type=int, default=0,
                    help="instead of the gate: N fresh seeds, both seats the twin")
    ap.add_argument("--army1")
    ap.add_argument("--army2")
    ap.add_argument("--bank", default=str(Path.home() / "selfplay_out/terrain_bank"))
    ap.add_argument("--seed-start", type=int, default=1)
    a = ap.parse_args(argv)
    if a.fresh:
        if not (a.army1 and a.army2):
            ap.error("--fresh needs --army1 and --army2")
        return fresh(a.fresh, a.army1, a.army2, a.repo, a.bank, a.seed_start, a.jobs)
    if not a.ref:
        ap.error("--ref is required (or use --fresh)")
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.jobs, a.red_misseed,
               a.engage_fold, a.cond_ap)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
