#!/usr/bin/env python3
"""NML-1158b step 2 — join the policy dump with the game outcome.

Reads policy_dump.jsonl (step 1) plus each game's arena result JSON and
writes policy_rows.jsonl, one row per (act, unit menu): {game, act_no,
unit, side, board, cands, pick_idx, pick_rs, menu_mean_rs, winner, vp,
weight}. WEIGHT ports clone_train.load()'s levers: the winner lever
(netlab/clone_train.py:113-115 — losing-side rows carry --winner-weight,
winner/draw rows stay 1.0) and the margin lever's structure (:116-121,
winning side only, cap 3.0) driven by the design's advantage signal
(POLICY_NET_DESIGN 2026-09-01 §2): pick_rs - menu_mean_rs from trace.rs.
Defaults are pure clone: every weight 1.0. The pick is judged by the ONE
definition of an impossible shot, filter_corpus.classify_action
(filter_corpus.py:112-155, imported per clone_train.py:33-38) — planner
menus carry no victim_row today, so it returns None on every current
pick; a victim-carrying corpus reuses the same referee. A pick index
outside its menu refuses (filter_corpus.classify :107-108 pattern);
--red corrupts one pick index per file to prove the loader refuses.
"""
import argparse
import glob
import json
import sys
from pathlib import Path

try:  # the private corpus referee, exactly one definition (clone_train.py:33-38)
    sys.path.insert(0, str(Path("~/nml-mission/tools").expanduser()))
    from filter_corpus import classify_action, DEFAULT_SLACK_IN  # noqa: E402
except ImportError:  # CI has no private mission dir; the label gate is off there
    classify_action, DEFAULT_SLACK_IN = None, 6.0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dump", default="~/nml-mission/policy_out/policy_dump.jsonl")
    ap.add_argument("--corpus", default="~/selfplay_out/qbg_ref")
    ap.add_argument("--out", default="~/nml-mission/policy_out/policy_rows.jsonl")
    ap.add_argument("--winner-weight", type=float, default=1.0,
                    help="loser-row weight (clone_train.py:113-115); 1.0 = pure clone")
    ap.add_argument("--advantage", action="store_true",
                    help="winning-side rows scale by the capped rollout margin "
                         "pick_rs - menu_mean_rs (clone_train.py:116-121 shape)")
    ap.add_argument("--red", action="store_true",
                    help="corrupt one pick index per file; the loader must refuse")
    a = ap.parse_args(argv)
    lines = [ln for ln in Path(a.dump).expanduser().read_text().splitlines() if ln.strip()]
    header, rows = json.loads(lines[0]), [json.loads(ln) for ln in lines[1:]]
    if header.get("schema") != "policy_dump/1":
        sys.exit(f"refusing dump schema {header.get('schema')!r} (want policy_dump/1)")
    if a.red and rows:
        rows[0]["pick_idx"] = len(rows[0]["cands"])
    corpus = Path(a.corpus).expanduser()
    res = {}
    for g in sorted({r["game"] for r in rows}):
        j = json.load(open(sorted(glob.glob(str(corpus / g / "arena_*.json")))[0]))
        o = j.get("objectives") if isinstance(j.get("objectives"), dict) else {}
        res[g] = (str(j.get("winner", "")), int(o.get("vp1", 0)), int(o.get("vp2", 0)))
    out, dropped = [], 0
    for r in rows:
        p = r["pick_idx"]
        if not -1 <= p < len(r["cands"]) or any(
                len(c["vec"]) != header["act_dim"] for c in r["cands"]):
            sys.exit(f"count mismatch board/vec/pick at {r['game']}:{r['act_no']}/"
                     f"{r['unit']}: pick {p} outside menu of {len(r['cands'])}")
        if p >= 0 and classify_action is not None and classify_action(
                {"kind": int(r["cands"][p]["kind"]),
                 "victim_row": int(r["cands"][p].get("victim_row", -1)), "unit_row": -1},
                r["board"], {}, DEFAULT_SLACK_IN) is not None:
            dropped += 1          # the pick itself is impossible: no legal label
            continue
        rs = [c["rs"] for c in r["cands"] if c.get("rs") is not None]
        mean_rs = sum(rs) / len(rs) if rs else None
        pick_rs = r["cands"][p]["rs"] if p >= 0 else None
        side, win = int(r["side"]), res[r["game"]][0]
        w = 1.0
        if a.winner_weight < 1.0 and win in ("p1", "p2"):       # clone_train.py:113-115
            w = 1.0 if win == "p%d" % side else a.winner_weight
        if a.advantage and win == "p%d" % side and pick_rs is not None:
            w *= min(3.0, 1.0 + max(0.0, pick_rs - mean_rs))    # clone_train.py:116-121 shape
        out.append({"kind": "policy_row", "game": r["game"], "act_no": r["act_no"],
                    "unit": r["unit"], "side": side, "board": r["board"],
                    "cands": [{"i": c["i"], "vec": c["vec"]} for c in r["cands"]],
                    "pick_idx": p, "pick_rs": pick_rs, "menu_mean_rs": mean_rs,
                    "winner": win, "vp": res[r["game"]][1:], "weight": w})
    o = Path(a.out).expanduser()
    o.parent.mkdir(parents=True, exist_ok=True)
    with o.open("w") as fh:
        fh.write(json.dumps({"kind": "header", "schema": "policy_rows/1",
                             "src_schema": header["schema"], "rows": len(out),
                             "dropped": dropped, "winner_weight": a.winner_weight,
                             "advantage": a.advantage}) + "\n")
        for r in out:
            fh.write(json.dumps(r) + "\n")
    lo = sum(1 for r in out if r["weight"] < 1.0)
    hi = sum(1 for r in out if r["weight"] > 1.0)
    print(f"{len(out)} rows from {len(res)} games, {dropped} impossible-pick drops -> {o}")
    for g in sorted(res):
        print(f"  {g}: winner {res[g][0]} vp {res[g][1]}-{res[g][2]} "
              f"rows {sum(1 for r in out if r['game'] == g)}")
    print(f"weights: {lo} loser rows <1.0, {hi} rows >1.0, {len(out) - lo - hi} at 1.0")


if __name__ == "__main__":
    main()
