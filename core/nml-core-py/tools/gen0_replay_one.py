#!/usr/bin/env python3
"""REPLAY-FIDELITY PROOF for the Gen-0 teacher corpus — a check that can FAIL.

Replays a recorded game from `(seed, dice_seed, armies, knobs)` with the
recorded acts FORCED — the planner never touches the game's `rng`, so both
streams stay bit-identical — and at every position compares the core's
candidate MENU with the recorded one field for field, the three f64 dest
coordinates included. The menu is the prefilter's function of the state alone,
so a match pins the state to float precision and the FIRST mismatch names the
activation where the replay left the recording. `top_k=1, horizon=1` keeps it
cheap and still returns `trace.scored`, the 1-ply HAND score the recorder threw
away, so the hand-argmax top-1 baseline falls out for free. Point `PYTHONPATH`
at a `.forge/site` built from the corpus's own commit. Corpus files are READ-ONLY.
"""
import argparse
import contextlib
import json
import os
import sys
import time
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[3])
BANK = os.path.expanduser("~/selfplay_out/terrain_bank")
LISTS = os.path.expanduser("~/nml-mission/farm/ai_lists")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay  # noqa: E402

_layout, _tray = nml_core.objective_layout, nml_core.Tray
G = {"dice": 0, "rows": [], "i": 0, "cmp": 0, "ok": 0, "hand": 0}
# Fixed for the life of the corpus (DESIGN §1.6.5); `movement` is read per file.
# W5a: the corpus predates menu_wide/menu_los/los/hero_last/cast_fold/ambush,
# so `selfplay.LEGACY_FIDELITY_KNOBS` pins the six play_game() now defaults
# elsewhere back to what this recording actually played.
KNOBS = dict(selfplay.LEGACY_FIDELITY_KNOBS, sidecars=False, hero_attach="table",
             dice="table", charge_landing="table", sighting="model", cond_ap=True,
             objectives="rulebook", deployment="arena", engage_fold=True,
             versatile_reach=False)


def replay_knobs(kn: dict) -> dict:
    """PR #636's fix (`tools/game_narrator.py`'s `replay()`), generalised here
    rather than duplicated in both this module and `gen0_replay_shards.py`:
    every `KNOBS`-pinned knob the RECORD itself stamps a value for wins over
    `KNOBS`'s gen0-era pin, so a shipped-default record (every one a
    `pool_value_fn`-armed A/B seat writes) replays with the knobs it was
    actually played with. A key the record is silent on (every Gen-0 file
    here, predating it) keeps `KNOBS`'s legacy value, exactly as before."""
    return {**KNOBS, **{k: kn[k] for k in KNOBS if k in kn}}


class Diverged(Exception):
    """The replay left the recording — the proof failing, loudly and with a place."""


def menu_diff(got: list, want: list) -> str:
    """First field on which two candidate menus differ, "" when identical."""
    if len(got) != len(want):
        return "menu width %d, recorded %d" % (len(got), len(want))
    for i, (g, w) in enumerate(zip(got, want)):
        for k in sorted(set(g) | set(w)):
            if g.get(k) != w.get(k):
                return "cand[%d].%s = %r, recorded %r" % (i, k, g.get(k), w.get(k))
    return ""


def forced_pick(core, state, player, net_player=0, eps=0.0, explore_seed=0, cands=False):
    """`selfplay._pick_for` with the RECORDED act in place of the search's answer.
    The menu is checked BEFORE the act goes in: no game outlives its divergence.

    Gen-1 recorder fix: the forced act is `cands["played"]` — the build index
    that IS the recorded `row["action"]` — falling back to `cands["best"]`
    (the hand argmax) on a record from before `played` existed, where the
    two were always equal. Forcing `best` unconditionally (the old code)
    diverges at the very first `pool_value_fn` re-rank (PR #627): the search
    itself never picked `best` there, so the state after "playing" it stops
    matching the recording's own next state."""
    if not state.pool(player, bool(core.knobs().get("hero_attach", True))):
        return {}
    pick = core.plan_with_rollout(state, player, selfplay.TRAINER_STATICS,
                                  eps=0.0, explore_seed=explore_seed, cands=True)
    if not pick.get("used"):
        return {}
    if G["i"] >= len(G["rows"]):
        raise Diverged("seq %d: recording holds only %d positions" % (G["i"], len(G["rows"])))
    row = G["rows"][G["i"]]
    G["i"], G["cmp"] = G["i"] + 1, G["cmp"] + 1
    bad = menu_diff(pick["trace"]["cands"], row["cands"]["list"])
    if bad:
        raise Diverged("seq %d (round %d, side %d): %s" % (row["seq"], row["round"], row["side"], bad))
    G["ok"] += 1
    G["hand"] += int(pick["trace"]["scored"][0]["idx"] == row["cands"]["best"])
    played_idx = row["cands"].get("played", row["cands"]["best"])
    act = row["cands"]["list"][played_idx]
    pick["action"], pick["unit_key"] = act, act["unit"]
    return pick


@contextlib.contextmanager
def armed(fn):
    """gen0_one.py's shims (layout +500000, tray on the DICE seed) and `fn`
    forced as `_pick_for`, scoped to the `with` block and restored on the way
    out — including on an exception. A bare assignment never restores, so a
    caller that replays IN-PROCESS (not through this tool's own subprocess
    CLI, which exits and takes every shim with it) leaves the next test
    reading this replay's stale globals."""
    prev_layout, prev_tray = nml_core.objective_layout, nml_core.Tray
    nml_core.objective_layout = lambda t, s, m, z: _layout(t, s + 500000, m, z)
    nml_core.Tray = lambda _s: _tray(G["dice"])
    try:
        with selfplay.forced_picks(fn):
            yield
    finally:
        nml_core.objective_layout, nml_core.Tray = prev_layout, prev_tray


def replay(path: str, lists: str, dice_offset: int) -> dict:
    """One game replayed; the returned `divergence` is "" only on a clean run."""
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    kn = rec["prescreen"]["knobs"]
    # The corpus names no core commit (DESIGN §1.6.4): the sha ef9a3e48 is
    # DERIVED from the fleet epoch and corroborated by one signature probe —
    # `record_cands` landed at PR #522. A file saying otherwise was not
    # written by the build this proof is about. `record_aux` (PR #533) is
    # NOT refused: its targets (models-alive/wounds on `rounds_log`, DESIGN_
    # gen0_training §2.6) are additive to the game actually played, so a
    # Gen-1 record stamping it replays exactly like one that does not.
    if not kn.get("record_cands"):
        raise SystemExit("REFUSED %s: record_cands=%s" % (path, kn.get("record_cands")))
    G.update(dice=rec["dice_seed"] + dice_offset, rows=rec["planner_positions"],
             i=0, cmp=0, ok=0, hand=0)
    armies = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
    t0 = time.perf_counter()
    try:
        with armed(forced_pick):
            selfplay.play_game(rec["seed"], armies[0], armies[1], REPO, BANK, None,
                               top_k=1, horizon=1, dice_seed=G["dice"],
                               movement=kn["movement"],
                               # DEFECT_LEDGER #12: the RECORD's own key, absent
                               # (every corpus here) meaning OFF — this proof stays
                               # about the recording, not today's default.
                               dangerous_end_morale=bool(kn.get("dangerous_end_morale", False)),
                               **replay_knobs(kn))
        bad = "" if G["i"] == len(G["rows"]) else (
            "ran dry after %d of %d recorded positions" % (G["i"], len(G["rows"])))
    except Diverged as exc:
        bad = str(exc)
    return {"file": Path(path).name, "compared": G["cmp"], "matched": G["ok"],
            "recorded": len(G["rows"]), "hand_top1": G["hand"],
            "seconds": round(time.perf_counter() - t0, 3), "divergence": bad}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+", help="corpus gen0_s<seed>_d<dice>.json files")
    ap.add_argument("--lists", default=LISTS, help="local mirror of the fleet's ai_lists")
    ap.add_argument("--dice-offset", type=int, default=0, help="RED: must diverge")
    a = ap.parse_args()
    print("[REPLAY] corpus commit ef9a3e48, DERIVED (DESIGN §1.6.4) from the fleet epoch:"
          " record_cands landed at PR #522, and every file below must report cands=true"
          " (record_aux, PR #533, is additive and accepted either way).\n[REPLAY]"
          " module=%s dice_offset=%d"
          % (nml_core.__file__, a.dice_offset))
    out = []
    for g in a.games:
        out.append(replay(g, a.lists, a.dice_offset))
        print("[GAME] %(file)s %(matched)d/%(recorded)d hand=%(hand_top1)d"
              " %(seconds).2fs %(divergence)s" % out[-1])
    good = sum(1 for r in out if not r["divergence"])
    seen = sum(r["compared"] for r in out) or 1
    print("[VERDICT] %s %d/%d games, %d positions compared, %d menus matched exactly,"
          " hand-argmax top-1 %.1f%%, %.2f s/game"
          % ("PASS" if good == len(out) else "FAIL", good, len(out), seen,
             sum(r["matched"] for r in out), 100.0 * sum(r["hand_top1"] for r in out) / seen,
             sum(r["seconds"] for r in out) / len(out)))
    return 0 if good == len(out) else 1


if __name__ == "__main__":
    sys.exit(main())
