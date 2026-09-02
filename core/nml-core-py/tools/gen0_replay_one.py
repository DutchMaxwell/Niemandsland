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
KNOBS = dict(sidecars=False, charge_gate="off", hero_attach="table", dice="table",
             charge_landing="table", sighting="model", cond_ap=True,
             objectives="rulebook", deployment="arena", engage_fold=True)


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
    The menu is checked BEFORE the act goes in: no game outlives its divergence."""
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
    act = row["cands"]["list"][row["cands"]["best"]]
    pick["action"], pick["unit_key"] = act, act["unit"]
    return pick


def arm() -> None:
    """gen0_one.py's shims (layout +500000, tray on the DICE seed) and the forced
    picker, installed on the first replay so that importing this module is inert."""
    nml_core.objective_layout = lambda t, s, m, z: _layout(t, s + 500000, m, z)
    nml_core.Tray = lambda _s: _tray(G["dice"])
    selfplay._pick_for = forced_pick


def replay(path: str, lists: str, dice_offset: int) -> dict:
    """One game replayed; the returned `divergence` is "" only on a clean run."""
    arm()
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    kn = rec["prescreen"]["knobs"]
    # The corpus names no core commit (DESIGN §1.6.4): the sha ef9a3e48 is
    # DERIVED from the fleet epoch and corroborated by two signature probes —
    # `record_cands` landed at PR #522, `record_aux` at PR #533. A file saying
    # otherwise was not written by the build this proof is about.
    if not kn.get("record_cands") or kn.get("record_aux"):
        raise SystemExit("REFUSED %s: record_cands=%s record_aux=%s"
                         % (path, kn.get("record_cands"), kn.get("record_aux")))
    G.update(dice=rec["dice_seed"] + dice_offset, rows=rec["planner_positions"],
             i=0, cmp=0, ok=0, hand=0)
    armies = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
    t0 = time.perf_counter()
    try:
        selfplay.play_game(rec["seed"], armies[0], armies[1], REPO, BANK, None,
                           top_k=1, horizon=1, dice_seed=G["dice"],
                           movement=kn["movement"], **KNOBS)
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
          " record_cands landed at PR #522, record_aux at PR #533, and every file below must"
          " report cands=true/aux=false.\n[REPLAY] module=%s dice_offset=%d"
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
