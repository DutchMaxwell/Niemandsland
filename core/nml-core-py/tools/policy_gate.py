#!/usr/bin/env python
"""GATE NML-1158b step 7 (design §5 gate 1) — the crate's ORDER mode against
GODOT's own, per recorded menu.

`plan.rs`'s PHASE-2 re-rank (step 5) and its GDScript twin
(`AiPlanner._reorder_within_unit`, step 6) are two independent ports of the
same rule: within each unit's own already-sorted PHASE-2 slots, fill them
with that unit's own candidates ranked by the policy net's logit. This gate
says the two ports land on the EXACT same pool.

WHAT IS HELD, per act: `trace.pool_idx` (which candidates get rolled, in pool
order — the functional effect: "the net proposes what gets rolled out",
design §4) and `trace.scored` (the full ranked array, idx/unit/kind/score —
catches a divergence at the SOURCE, before build_pool ever sees it). Every
act's recorded corpus never carries a policy_mode=order pick — the recorders
have only ever run "off" — so, same as `fitted_gate.py`, the table's own
answer is REPLAYED, not read off disk, in two steps that touch no shipping
file:

  1. `--doctor` stamps `statics.policy_mode = "order"` onto every act of a
     recorded corpus. `tools/act_recheck.gd` restores `AiPlanner.policy_mode`
     from exactly that field, and arms `PolicyOrder`'s net from
     NML_POLICY_PATH — nothing else about the doctored copy moves.
  2. `NML_POLICY_PATH=<net> tools/act_recheck.gd file=<doctored>
     write=<replay> n=<N>` — the LIVE GDScript search, writing its own pick +
     trace per act.

    P=core/nml-core-py/tools/policy_gate.py; V=~/venvs/nmlpolicy/bin/python
    NET=~/nml-mission/netlab/nets/policy_v1.json
    $V $P --doctor <in>/acts.jsonl --out <g>/acts.jsonl
    NML_POLICY_PATH=$NET godot --headless --path <wt> \\
        -s res://tools/act_recheck.gd -- file=<g>/acts.jsonl \\
        write=<g>/replay.jsonl n=999
    $V $P --game <g> --net $NET --repo <wt>

The gate reads the STATE from the doctored `acts.jsonl` and re-plans it
through the crate's OWN `plan_with_rollout` under `policy_mode=order` (the
same knob `act_recheck.gd` restored for the reference); the table's answer
comes from `replay.jsonl`, paired by position — same non-assumption
`fitted_gate.py` makes: two acts at the same list position are proven to be
the same act, not merely trusted to be.

RED PROOF: `--red-scale X` (X < 0 is the useful case) multiplies the crate's
OWN policy net's logit by X before the reorder (`Core.load_policy_net(scale=)`,
`policy::Policy.scale`). Unlike `fitted_gate.py`'s magnitude lever, this gate
compares a PERMUTATION: a positive scale never moves an order (it is a
monotonic rescale), so the red proof is a SIGN flip — it reverses whichever
of a unit's own candidates the net preferred, which the identity comparison
below catches wherever a unit's menu carries two candidates the net does not
tie.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import nml_core

#: `OPRApiClient.OPRUnit`'s blank quality/defense — what a replay's stand-in
#: `GameUnit` answers for board columns 10/11 (fitted_gate.py's own note).
SOURCE_DATA_QUALITY = 4
SOURCE_DATA_DEFENSE = 4


def acts_of(path: Path) -> tuple[dict, list[dict]]:
    """The header line and every `kind == "act"` line of an act corpus."""
    lines = [json.loads(x) for x in path.read_text().splitlines() if x.strip()]
    return lines[0], [a for a in lines[1:] if a.get("kind") == "act"]


def doctor(src: Path, dst: Path) -> int:
    """Copy `src` to `dst` with `statics.policy_mode = "order"` on every act.
    The corpus is otherwise BYTE-preserved line by line."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with open(dst, "w", encoding="utf-8") as out:
        for raw in src.read_text().splitlines():
            if not raw.strip():
                continue
            rec = json.loads(raw)
            if rec.get("kind") == "act":
                rec.setdefault("statics", {})["policy_mode"] = "order"
                n += 1
                out.write(json.dumps(rec) + "\n")
            else:
                out.write(raw + "\n")
    return n


def _order_rows(trace: dict) -> tuple[list[int], list[tuple[int, str, int]]]:
    """`pool_idx` verbatim, and `scored` reduced to (idx, unit, kind) — the
    ORDER (design §5 gate 1: "the pool ORDER... EXACTLY equals the crate's").
    The `score` field rides `trace.scored` too, but it is `AiMissionEval`'s
    HAND leaf — G4/`fitted_gate.py`'s own gate already holds that number to
    its own bar, and this corpus exposes an UNRELATED pre-existing hand-eval
    drift on some round>=2 acts (verified orthogonal to policy_mode: the
    SAME crate score comes back under policy_mode=off) that this gate must
    not misreport as an ORDER mismatch.
    """
    pool = [int(x) for x in trace.get("pool_idx", [])]
    scored = [
        (int(r["idx"]), str(r["unit"]), int(r["kind"]))
        for r in trace.get("scored", [])
    ]
    return pool, scored


def check(game: Path, net: str, repo: str, scale: float, tally: dict, firsts: list) -> None:
    """One replayed game: the crate's ORDER pool/order vs Godot's, per act."""
    head, acts = acts_of(game / "acts.jsonl")
    _rhead, replay = acts_of(game / "replay.jsonl")
    core = nml_core.load(repo)
    core.set_header(
        {"profiles": head["profiles"], "terrain": head.get("terrain"),
         "knobs": dict(head.get("knobs", {}),
                       rule_vocab_version=nml_core.RULE_VOCAB_VERSION)}
    )
    core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
    core.load_policy_net(net, scale)
    tally["games"] += 1
    for i, act in enumerate(acts[: len(replay)]):
        rep = replay[i]
        if (int(rep["round"]), int(rep["player"])) != (int(act["round"]), int(act["player"])):
            raise SystemExit("[GATE] %s act %d: replay is not the same act" % (game.name, i))
        if str(rep.get("statics", {}).get("policy_mode", "")) != "order":
            tally["not_order"] += 1
            continue
        pick = rep.get("pick") or {}
        if not pick.get("used"):
            tally["unused"] += 1
            continue
        want_pool, want_scored = _order_rows(rep.get("trace", {}))

        statics = dict(act.get("statics", {}), policy_mode="order")
        try:
            state = core.state_of(act["state"])
            got = core.plan_with_rollout(state, int(act["player"]), statics)
        except Exception as exc:  # a state the port declines is NOT a pass
            tally["declined"] += 1
            if len(firsts) < 5:
                firsts.append("%s act %d — DECLINED: %s" % (game.name, i, exc))
            continue
        if not got.get("used"):
            tally["declined"] += 1
            if len(firsts) < 5:
                firsts.append("%s act %d — DECLINED: %s" % (game.name, i, got.get("unsupported")))
            continue

        tally["rows"] += 1
        got_pool, got_scored = _order_rows(got["trace"])
        if got_pool == want_pool and got_scored == want_scored:
            tally["ok"] += 1
        else:
            tally["bad"] += 1
            # Attribute the miss: is it the REORDER, or an upstream HAND-EVAL
            # drift (this act's OWN un-doctored recording — independent of
            # policy_mode/scale — already disagrees with the crate on some
            # candidate's 1-ply score)? A drifted rank is not this gate's bug.
            orig_score = {
                int(r["idx"]): float(r["score"])
                for r in act.get("trace", {}).get("scored", [])
            }
            got_score = {
                int(r["idx"]): float(r["score"]) for r in got["trace"]["scored"]
            }
            drift = any(
                abs(got_score.get(idx, 0.0) - s) > 1e-9 for idx, s in orig_score.items()
            )
            tally["bad_hand_eval_drift" if drift else "bad_order"] += 1
            if len(firsts) < 5:
                firsts.append(
                    "%s act %d round=%d [%s] — pool godot=%s crate=%s"
                    % (game.name, i, int(act["round"]),
                       "hand-eval drift, not ORDER" if drift else "ORDER MISMATCH",
                       want_pool, got_pool)
                )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--doctor", type=Path, help="stamp policy_mode=order onto a recorded acts.jsonl")
    ap.add_argument("--out", type=Path, help="--doctor destination")
    ap.add_argument("--game", type=Path, nargs="*", default=[],
                    help="game dirs carrying acts.jsonl (doctored) + replay.jsonl")
    ap.add_argument("--net", default="", help="the policy_train.py policy_net/1 export")
    ap.add_argument("--repo", default="", help="repo root (assets/ + data/ live here)")
    ap.add_argument("--red-scale", type=float, default=1.0,
                    help="RED PROOF: multiply the crate's policy net's logit by this")
    a = ap.parse_args(argv)

    if a.doctor:
        if not a.out:
            return int(bool(sys.stderr.write("[GATE] --doctor needs --out\n"))) or 2
        n = doctor(a.doctor, a.out)
        print("[GATE] doctored %d acts -> %s" % (n, a.out))
        return 0

    if not a.game or not a.net or not a.repo:
        sys.stderr.write("[GATE] --game, --net and --repo are all required\n")
        return 2

    tally = {"games": 0, "rows": 0, "ok": 0, "bad": 0, "declined": 0,
             "unused": 0, "not_order": 0, "bad_order": 0, "bad_hand_eval_drift": 0}
    firsts: list[str] = []
    for p in a.game:
        check(Path(p), a.net, a.repo, a.red_scale, tally, firsts)

    print("[GATE] net %s scale %g" % (a.net, a.red_scale))
    print("[GATE] games %d | rows %d | ok %d | MISMATCH %d (order %d, hand-eval drift %d) | declined %d"
          % (tally["games"], tally["rows"], tally["ok"], tally["bad"],
             tally["bad_order"], tally["bad_hand_eval_drift"], tally["declined"]))
    print("[GATE] skipped: %d not policy_mode=order, %d pick unused"
          % (tally["not_order"], tally["unused"]))
    for line in firsts:
        print("  " + line)
    if tally["rows"] == 0:
        print("[GATE] VACUOUS — no ORDER row to hold anything against")
        return 1
    if a.red_scale != 1.0:
        # The red arm PASSES when the gate fails: a scaled net that still
        # matched would prove the order never came from the net.
        print("[GATE] RED %s — %d of %d rows moved"
              % ("PROVEN" if tally["bad"] == tally["rows"] else "INCOMPLETE",
                 tally["bad"], tally["rows"]))
        return 0 if tally["bad"] == tally["rows"] else 1
    print("[GATE] %s %d/%d" % ("GREEN" if tally["bad"] == 0 else "RED",
                               tally["ok"], tally["rows"]))
    return 0 if tally["bad"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
