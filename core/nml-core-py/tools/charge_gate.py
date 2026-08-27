"""GATE D2 (NML-1073) — the TABLE's charge-legality gate, act by act, against
the recorded ARENA corpus.

WHAT IS BEING GATED. `tools/arena_match.gd` plays on the real table, and the
table stamps `state["charge_illegal"]` with `SoloController.
charge_candidate_illegal` (solo_controller.gd:1450) before every planner call
(:3002/:3358/:3475/:3704). Both trainers skipped that stamp: `tools/
core_selfplay.gd` never wires it, and the fast Godot-free trainer copied it
field for field, gate and all. `selfplay.charge_gate="table"` wires it — through
the crate's pure twin `gate::charge_illegal` (NML-1073 M2-0c) rather than a
second reading of the rule.

THE TWO CHECKS, on every act of every game under `--ref`:

  STAMP — rebuild the state from the recorded plain form and compare the
  trainer's stamp (`Core.charge_illegal_matrix`, the shape `AiActRecorder.
  _charge_illegal_matrix` records) with the act's recorded `charge_illegal`,
  key set and value. A missing pair, an extra pair and a flipped bool all count
  as one mismatch. Expect 0.

  PICK — replay `plan_with_rollout` on that same recorded state WITH the stamp
  and compare `unit_key` + the action field by field against the recorded pick.
  The search knobs come from the act corpus's OWN header (the arena ran
  NML_TOP_K=2 NML_HORIZON=1), so the only knob this tool moves is `charge_gate`
  and the only thing a divergence can be about is the gate.

WHAT THIS IS NOT. The arena also rolls REAL dice and runs table rules the
trainer does not have yet, so a whole GAME still diverges; that is a later rung.
Act-level stamp equality and pick-with-stamp equality are D2's bar, and they are
measured per act on states the table itself produced.

RED PROOF: `--mode off`. The trainer then stamps nothing (an invalid Callable
stamps `{}` in GDScript too), so every recorded pair must go red and the picks
must part company wherever a charge was on the menu that the table refused.

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/charge_gate.py \\
        --ref ~/selfplay_out/qb_ref --repo .
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402

import selfplay as sp  # noqa: E402

#: `AiPlanner` action kinds — `BattleSim.CHARGE` (battle_sim.gd), the one the
#: red proof counts.
CHARGE = 3
#: `dest` is an f32 written at full precision on both sides, so this is a
#: formality: the replay has to land on the recorded value exactly.
EPS = 1e-9


def acts_of(path: Path) -> tuple[dict, list[dict]]:
    """The header line and the act lines of one `acts.jsonl`. A file whose first
    line is not the header is refused rather than half-read."""
    head: dict = {}
    acts: list[dict] = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if i == 0:
                if rec.get("kind") != "header":
                    raise ValueError("%s: first line is not the header" % path)
                head = rec
                continue
            if rec.get("kind") == "act":
                acts.append(rec)
    return head, acts


def stamp_diff(got: dict, want: dict) -> tuple[int, int, str]:
    """(pairs compared, mismatches, first mismatch) between the trainer's stamp
    and the recorded one. The union of the key sets is the denominator, so a
    stamp that simply omits a pair cannot look green."""
    keys = set(got) | set(want)
    bad = 0
    first = ""
    for k in sorted(keys):
        a, b = got.get(k), want.get(k)
        if a is None or b is None or bool(a) != bool(b):
            bad += 1
            if not first:
                first = "%s: trainer %s, table %s" % (k, a, b)
    return len(keys), bad, first


def action_diff(got: dict, want: dict) -> str:
    """Empty when the two actions are the same action — `tests/menu.rs::same`'s
    field list, in the order a mismatch report wants it."""
    if int(got.get("kind", -1)) != int(want.get("kind", -2)):
        return "kind %s != %s" % (got.get("kind"), want.get("kind"))
    if got.get("unit") != want.get("unit"):
        return "unit %s != %s" % (got.get("unit"), want.get("unit"))
    for f in ("shoot", "charge"):
        if got.get(f) != want.get(f):
            return "%s %s != %s" % (f, got.get(f), want.get(f))
    if bool(got.get("patient", False)) != bool(want.get("patient", False)):
        return "patient %s != %s" % (got.get("patient"), want.get("patient"))
    if bool(got.get("wave")) != bool(want.get("wave")):
        return "wave %s != %s" % (got.get("wave"), want.get("wave"))
    gd, wd = got.get("dest"), want.get("dest")
    if (gd is None) != (wd is None):
        return "dest %s != %s" % (gd, wd)
    if gd is not None and any(abs(float(x) - float(y)) > EPS for x, y in zip(gd, wd)):
        return "dest %s != %s" % (gd, wd)
    return ""


def run(ref: Path, repo: str, mode: str, limit: int) -> int:
    gate = sp.resolve_charge_gate(mode)
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "acts.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no acts.jsonl under %s" % ref)
        return 1

    pairs = pair_bad = 0
    acts = acts_stamped = 0
    picks = picks_equal = declined = 0
    illegal_true = 0
    charge_diffs = charge_vetoed = 0
    first_stamp = first_pick = ""
    t0 = time.perf_counter()
    for d in games:
        head, lines = acts_of(d / "acts.jsonl")
        # One Core per GAME: `set_header` rebuilds the profile table and the
        # board, and both change with the pairing and the seed.
        core = nml_core.load(repo)
        core.set_header(
            {
                "profiles": head["profiles"],
                "terrain": head.get("terrain"),
                "knobs": dict(head.get("knobs", {}), charge_gate=gate),
            }
        )
        for n_act, act in enumerate(lines, 1):
            acts += 1
            state = core.state_of(act["state"])
            got = core.charge_illegal_matrix(state)
            want = act.get("charge_illegal", {})
            if want:
                acts_stamped += 1
            illegal_true += sum(1 for v in want.values() if v)
            n, bad, first = stamp_diff(got, want)
            pairs += n
            pair_bad += bad
            if bad and not first_stamp:
                first_stamp = "%s act %d — %s" % (d.name, n_act, first)
            # The recorded pick only IS a `plan_with_rollout` pick when the
            # recorder captured that search's trace; a doctrine pick carries
            # none and is not this gate's business.
            rec = act.get("pick", {})
            if not act.get("trace") or not rec.get("used"):
                continue
            picks += 1
            pick = core.plan_with_rollout(state, int(act["player"]), act["statics"])
            if not pick.get("used"):
                declined += 1
                if not first_pick:
                    first_pick = "%s act %d — declined: %s" % (
                        d.name, n_act, pick.get("unsupported")
                    )
                continue
            why = ""
            if pick["unit_key"] != rec["unit_key"]:
                why = "unit_key %s != %s" % (pick["unit_key"], rec["unit_key"])
            else:
                why = action_diff(pick["action"], rec["action"])
            if why:
                if int(pick["action"].get("kind", -1)) == CHARGE:
                    charge_diffs += 1
                    # And this many of them charge a victim the TABLE's own
                    # stamp calls illegal — the gate refusing that very pair,
                    # not just a picked action that happens to be a charge.
                    # (The stamp answers the ROOT gap and the menu the EDGE
                    # gap, so this is the subset the two agree on, never more.)
                    tgt = pick["action"].get("charge") or ""
                    if want.get("%s|%s" % (pick["unit_key"], tgt)):
                        charge_vetoed += 1
                if not first_pick:
                    first_pick = "%s act %d — %s" % (d.name, n_act, why)
            else:
                picks_equal += 1

    label = "GATE D2" if gate else "RED D2 (charge_gate=off)"
    print()
    print("%s over %d games, %d acts (%.1fs)" % (
        label, len(games), acts, time.perf_counter() - t0))
    print("  stamp : %d/%d pairs equal   (%d mismatches; %d acts carry a stamp; "
          "%d recorded pairs are ILLEGAL)" % (pairs - pair_bad, pairs, pair_bad,
                                              acts_stamped, illegal_true))
    if first_stamp:
        print("          first: %s" % first_stamp)
    print("  pick  : %d/%d equal        (%d declined, %d divergences pick a CHARGE, "
          "%d of them a pair the table's stamp REFUSES)"
          % (picks_equal, picks, declined, charge_diffs, charge_vetoed))
    if first_pick:
        print("          first: %s" % first_pick)
    if not gate:
        # A red proof PASSES when the stamp went red AND the picks parted.
        ok = pair_bad > 0 and picks_equal < picks
        print("  RED %s" % ("held (the gate is load-bearing)" if ok else "FAILED — nothing moved"))
        return 0 if ok else 1
    ok = pairs > 0 and pair_bad == 0 and picks and picks_equal == picks
    print("  %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with acts.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument(
        "--mode",
        choices=list(sp.CHARGE_GATE_MODES),
        default="table",
        help="'table' is the gate; 'off' is the RED PROOF and must go red",
    )
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.mode, a.limit)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
