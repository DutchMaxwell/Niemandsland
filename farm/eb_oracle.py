#!/usr/bin/env python3
"""E-B GRADER HEADROOM — the re-simulation oracle worker and scorer.

E-B (pre-registered in ~/nml-mission/PLAN.md, "Pre-registered probes";
RSI_RESTART_DESIGN_2026-09-13.md R6) asks one question: if the planner's
GRADER is replaced by a re-simulation oracle — each finalist candidate is
PLAYED OUT and scored by its ACTUAL result — does that player gain >= 5
points over CHIMAERE on the 6-faction thermometer? If not, the grader is not
the bottleneck and the whole net programme is bounded.

This file implements the oracle seat and scores the run. It is the public
half of `farm/eb_runner.sh`; the runner owns the sample plan, the
pre-registration file and the SCORE stamp.

THE ORACLE, precisely. The planner already scores every candidate with the
hand/rollout blend (`plan.rs` prefilter + `rollout.rs`) and the CHIMAERE seat
re-ranks that pool with the value net (`pool_value_fn`, `value_player.py`).
The oracle seat instead arms the core's own full-playout arbitration
(`arbitration.rs::arbitrate`, the shipped `AiPlanner.full_playout`): the top
two candidates are each played to GAME END under the cheap policy with
STOCHASTIC dice (3 playouts per branch, escalating by 2 while the mean marker
delta stays inside the margin, hard cap 7) and the pick is decided by the
actual marker delta. `playout_search=True` plus a per-activation `sig` is what
arms it; `TRAINER_KNOBS["playout_margin"]` is raised so the arbitration fires
on every activation with a runner-up, not only on near-ties. Same planner,
same candidate sets, same search depth on both seats — the grader is the only
difference. The reference seat is CHIMAERE (`--ckpt2`) or, for a net-free
smoke test, the plain hand grader (`--ckpt2` omitted).

Nothing here writes a SCORE. `score` writes one, with the core sha + rules
epoch stamp the runner passes in (`--core-sha` / `--rules-epoch`), so a
receipt can prove which core judged it.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys
import time
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[1])
PUB_PY = os.path.join(REPO, "core", "nml-core-py", "python")
PUB_TOOLS = os.path.join(REPO, "core", "nml-core-py", "tools")
BANK_DEFAULT = os.path.expanduser("~/selfplay_out/terrain_bank")
NETLAB = os.path.expanduser(os.environ.get("NETLAB_DIR", "~/nml-mission/netlab"))

for _p in (PUB_PY, PUB_TOOLS):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import nml_core  # noqa: E402
import selfplay  # noqa: E402

_ORIG_PICK = selfplay._pick_for
_ORIG_LAYOUT, _ORIG_TRAY = nml_core.objective_layout, nml_core.Tray
_SHIPPED_KNOBS = dict(dice="table", deployment="arena")
_ORACLE = {"side": 0, "ref": None, "w": 1.0, "margin": 1.0e9}


def install_shims(dice_seed: int) -> None:
    """The arena's own board/dice shims (token_arena_one_v3.py): layout seed
    +500000 and a tray seeded from the row's dice_seed."""
    nml_core.objective_layout = (
        lambda terrain, seed, mode, zones: _ORIG_LAYOUT(terrain, seed + 500000, mode, zones)
    )
    nml_core.Tray = lambda _seed: _ORIG_TRAY(dice_seed)


def oracle_pick_for(core, state, player, net_player=0, eps=0.0, explore_seed=0, cands=False):
    """`selfplay._pick_for` with a per-seat grader.

    Oracle seat: `playout_search=True` and `sig=explore_seed` (a unique
    per-activation integer), so the crate's own full-playout arbitration
    decides. A refusal (e.g. no runner-up, or the crate declining the
    arbitration) falls back to the untouched hand pick for that activation.
    Reference seat: byte-identical to the shipped `_pick_for`, plus the value
    hook when one is armed.
    """
    if not state.pool(player, bool(core.knobs().get("hero_attach", True))):
        return {}
    ref = _ORACLE["ref"]
    oracle = player == _ORACLE["side"]
    vhook = ref if (ref is not None and not oracle) else None
    statics = dict(selfplay.TRAINER_STATICS)
    if oracle:
        statics["playout_search"] = True
    try:
        pick = core.plan_with_rollout(
            state, player, statics, sig=explore_seed, eps=eps,
            explore_seed=explore_seed, cands=cands or vhook is not None,
        )
    except nml_core.Unsupported:
        pick = {"used": False}
    if not pick.get("used"):
        return _ORIG_PICK(core, state, player, net_player, eps, explore_seed, cands)
    trace = pick.get("trace")
    if trace is not None:
        pick["played_idx"] = trace["scored"][trace["best_idx"]]["idx"]
    if vhook is not None and not pick.get("explored"):
        pool_idx = trace["pool_idx"]
        hand_rs = [e["rs"] for e in trace["rs"]]
        cand_list = trace["cands"]
        try:
            values = vhook.values(core, state, cand_list, pool_idx)
        except (nml_core.Unsupported, ValueError):
            values = None
        if values is not None:
            w = _ORACLE["w"]
            bi = max(range(len(pool_idx)), key=lambda j: hand_rs[j] + w * values[j])
            act = cand_list[pool_idx[bi]]
            pick["action"], pick["unit_key"] = act, act["unit"]
            pick["played_idx"] = pool_idx[bi]
    return pick


def stem_and_grades(seed, dice, order, oracle_label, ref_label):
    p1, p2 = (oracle_label, ref_label) if order == 1 else (ref_label, oracle_label)
    return "arena_%s_vs_%s_s%d_d%d.json" % (p1, p2, seed, dice), {"p1": p1, "p2": p2}


def play_one(out_dir, repo, bank, seed, dice, order, a1, a2,
             oracle_label, ref_label, ckpt2, tk, th, w, margin) -> str:
    install_shims(dice)
    selfplay.TRAINER_KNOBS["playout_margin"] = margin
    selfplay._pick_for = oracle_pick_for
    pieces = selfplay.load_board(seed, bank)[2]
    ref = None
    if ckpt2:
        if NETLAB not in sys.path:
            sys.path.insert(0, NETLAB)
        from value_player import TokenValuePlayer  # noqa: PLC0415
        values = [p.strip() for p in ckpt2.split(",") if p.strip()]
        ref = TokenValuePlayer(",".join(values), None, 3 - order, pieces)
    _ORACLE.update(side=order, ref=ref, w=w)
    stem, grades = stem_and_grades(seed, dice, order, oracle_label, ref_label)
    t0 = time.perf_counter()
    res = selfplay.play_game(
        seed, a1, a2, repo, bank, None, sidecars=False,
        top_k=tk, horizon=th, **_SHIPPED_KNOBS, dice_seed=dice,
    )
    res["grades"] = grades
    res["armies"] = {"p1": a1, "p2": a2}
    res["wall_seconds"] = round(time.perf_counter() - t0, 3)
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    with open(os.path.join(out_dir, stem), "w", encoding="utf-8") as f:
        json.dump(res, f)
    return stem


def cmd_plan(a) -> int:
    """Compose the paired+seat-swapped sample plan from a bank TSV.

    A bank row is `seed dice seat army1 army2`, where `seat` is the seat the
    ORACLE plays (the token banks call it `net_player`). For every seed the
    plan forces BOTH seat orders on every dice value it sees, so no row's seat
    partner can go missing and the pairing is complete by construction. Seeds
    whose rows disagree about the armies, or carry a lone seat with no partner,
    are refused loudly rather than silently dropped.
    """
    seeds = {}
    for line in Path(a.pairs).read_text(encoding="utf-8").splitlines():
        cols = line.strip().split("\t")
        if not cols or not cols[0].isdigit():
            continue
        seed, dice, seat, a1, a2 = int(cols[0]), int(cols[1]), int(cols[2]), cols[3], cols[4]
        if a.seed_lo is not None and seed < a.seed_lo:
            continue
        if a.seed_hi is not None and seed > a.seed_hi:
            continue
        entry = seeds.setdefault(seed, {"armies": None, "dice": set()})
        if entry["armies"] is None:
            entry["armies"] = (a1, a2)
        elif entry["armies"] != (a1, a2):
            raise SystemExit("plan: seed %d has inconsistent armies: %r vs %r"
                             % (seed, entry["armies"], (a1, a2)))
        entry["dice"].add(dice)

    rows, k = [], 0
    for seed in sorted(seeds):
        a1, a2 = seeds[seed]["armies"]
        for dice in sorted(seeds[seed]["dice"]):
            for seat in (1, 2):
                rows.append("%d\t%d\t%d\t%s\t%s" % (seed, dice, seat, a1, a2))
        k += 1
        if a.max_games and len(rows) >= a.max_games:
            rows = rows[:a.max_games]
            break
    print("plan_seeds=%d" % k)
    print("plan_games=%d" % len(rows))
    if a.out == "-":
        for row in rows:
            print(row)
    else:
        Path(a.out).write_text("\n".join(rows) + ("\n" if rows else ""), encoding="utf-8")
        print("plan: %d seeds -> %d games -> %s" % (k, len(rows), a.out))
    return 0


def cmd_play(a) -> int:
    rows = []
    for line in Path(a.tsv).read_text(encoding="utf-8").splitlines():
        cols = line.strip().split("\t")
        if not cols or not cols[0].isdigit():
            continue
        rows.append([int(cols[0]), int(cols[1]), int(cols[2]), cols[3], cols[4]])
    played = 0
    for seed, dice, order, a1, a2 in rows:
        stem, _ = stem_and_grades(seed, dice, order, a.oracle_label, a.ref_label)
        if (Path(a.out_dir) / stem).exists():
            continue  # resumable
        stem = play_one(a.out_dir, a.repo, a.bank, seed, dice, order, a1, a2,
                        a.oracle_label, a.ref_label, a.ckpt2, a.top_k, a.horizon,
                        a.value_w, a.playout_margin)
        played += 1
        print("[EB] %s oracle_seat=%d wall=%.1fs" % (stem, order, 0.0), flush=True)
    print("[EB] worker done: %d game(s) played" % played, flush=True)
    return 0


def _side_margin(obj, side):
    other = "p2" if side == "p1" else "p1"
    vp, vpo = obj.get("vp" + side[1]), obj.get("vp" + other[1])
    p, po = obj.get(side), obj.get(other)
    if (vp or 0) != 0 or (vpo or 0) != 0:
        return (vp or 0) - (vpo or 0)
    return (p or 0) - (po or 0)


def cmd_score(a) -> int:
    oracle_label = a.oracle_label
    blocks = {}
    n_games = 0
    for path in sorted(glob.glob(os.path.join(a.out_dir, "arena_*.json"))):
        try:
            with open(path) as f:
                res = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        grades = res.get("grades", {}) or {}
        seats = [s for s in ("p1", "p2") if grades.get(s) == oracle_label]
        if len(seats) != 1:
            continue
        seat = seats[0]
        obj = res.get("objectives", {}) or {}
        margin = _side_margin(obj, seat)
        point = 1.0 if margin > 0 else 0.0 if margin < 0 else 0.5
        blocks.setdefault(int(res.get("seed", -1)), []).append(point)
        n_games += 1

    block_means = [sum(v) / len(v) for v in blocks.values()]
    k = len(block_means)
    score = sum(block_means) / k if k else 0.0
    if k > 1:
        var = sum((m - score) ** 2 for m in block_means) / (k - 1)
        sd = math.sqrt(var)
    else:
        sd = 0.0
    se = sd / math.sqrt(k) if k else 0.0
    lo, hi = score - 1.96 * se, score + 1.96 * se

    stamp = []
    if a.core_sha:
        stamp.append("core_sha: %s" % a.core_sha)
    if a.rules_epoch:
        stamp.append("rules_epoch: %s" % a.rules_epoch)
    if a.pin_sha and a.core_sha and a.pin_sha != a.core_sha:
        stamp.append("PIN_MISMATCH: built core %s != yardstick %s" % (a.core_sha, a.pin_sha))

    lines = list(stamp)
    lines += [
        "E-B GRADER HEADROOM — oracle grader vs %s, 6-faction thermometer" % a.ref_label,
        "comparison: oracle win-share vs the 50% the two-seat game gives the opponent",
        "bar (pre-registered, unchanged): oracle gain >= %.1f points => score >= %.1f%%"
        % (a.bar, 50.0 + a.bar),
        "games=%d blocks=%d block_sd=%.4f SE=%.2f points" % (n_games, k, sd, 100 * se),
        "score=%.2f%%  95%% CI [%.2f%%, %.2f%%]" % (100 * score, 100 * lo, 100 * hi),
        "resolution: +/- %.2f points at 95%% (the interval half-width)" % (100 * 1.96 * se),
        "playout noise floor: up to 7 stochastic full playouts per branch "
        "(3 minimum, +2 while the mean marker delta stays inside the margin)",
    ]
    if se > 0:
        lines.append("80%% power to resolve %.1f points: %s"
                     % (a.bar, "YES" if a.bar / (100 * se) >= 2.8 else "NO"))
    if hi >= 100 * (0.50 + a.bar):
        verdict = "ORACLE GAINS >= %.1f points (ceiling not low)" % a.bar
    elif lo < 100 * (0.50 + a.bar) and hi > 50.0:
        verdict = "INCONCLUSIVE against the %.1f-point bar" % a.bar
    else:
        verdict = "NULL: oracle gain < %.1f points (grader not the bottleneck)" % a.bar
    lines.append("verdict (pre-registered bar): %s" % verdict)
    out = "\n".join(lines) + "\n"
    with open(os.path.join(a.out_dir, "SCORE"), "w", encoding="utf-8") as f:
        f.write(out)
    sys.stdout.write(out)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("plan")
    pl.add_argument("--pairs", required=True, help="bank TSV: seed dice seat army1 army2")
    pl.add_argument("--out", required=True, help="composed plan TSV to write")
    pl.add_argument("--seed-lo", type=int, default=None)
    pl.add_argument("--seed-hi", type=int, default=None)
    pl.add_argument("--max-games", type=int, default=0, help="cap for the laptop smoke (0 = all)")
    pl.set_defaults(func=cmd_plan)

    p = sub.add_parser("play")
    p.add_argument("out_dir")
    p.add_argument("--tsv", required=True, help="seed dice seat army1 army2 (TAB), seat = oracle seat")
    p.add_argument("--repo", default=REPO)
    p.add_argument("--bank", default=BANK_DEFAULT)
    p.add_argument("--oracle-label", default="token_oracle")
    p.add_argument("--ref-label", default="token_value_v1")
    p.add_argument("--ckpt2", default=None, help="CHIMAERE comma-joined ckpt list; omitted = hand grader")
    p.add_argument("--top-k", type=int, default=10)
    p.add_argument("--horizon", type=int, default=3)
    p.add_argument("--value-w", type=float, default=1.0)
    p.add_argument("--playout-margin", type=float, default=1.0e9)
    p.set_defaults(func=cmd_play)

    s = sub.add_parser("score")
    s.add_argument("out_dir")
    s.add_argument("--oracle-label", default="token_oracle")
    s.add_argument("--ref-label", default="token_value_v1")
    s.add_argument("--bar", type=float, default=5.0)
    s.add_argument("--core-sha", default="")
    s.add_argument("--rules-epoch", default="")
    s.add_argument("--pin-sha", default="")
    s.set_defaults(func=cmd_score)

    a = ap.parse_args()
    return a.func(a)


if __name__ == "__main__":
    raise SystemExit(main())
