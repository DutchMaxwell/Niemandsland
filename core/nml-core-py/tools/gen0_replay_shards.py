#!/usr/bin/env python3
"""DESIGN_gen0_training §5 step 4 — production replay, SCAFFOLD.

Forces recorded acts through PR #564's `forced_pick`; per activation calls
a pluggable `export()` stub (§8.2 fills the real one in). Shards land as
atomic `.npz`+`.json` pairs, skipped once finished and redone if truncated.
PYTHONPATH must reach a `.forge/site` wheel — never the shared venv.
"""
import argparse, json, multiprocessing as mp, numpy as np, os, sys, time  # noqa: E401
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen0_replay_one as gr, selfplay  # noqa: E402

OUT_DEFAULT = os.path.expanduser("~/selfplay_out/gen0_shards")
ARRAY_KEYS = ("label", "kind", "seq", "menu_len", "feat")
# placeholder; real shape is §8.1's token dict (units/objs/terr/glob/cands)
FEATURE_DIM = 8


def export(state, position_row: dict, cands: list) -> dict:
    # STUB seam for §8.2 Core.policy_tokens (`state` = the PyState the forced
    # replay stands on). Only `feat`'s shape changes once the real one lands.
    p = position_row
    return {"label": np.int16(p["cands"]["best"]), "kind": np.int8(p["kind"]), "seq": np.int32(p["seq"]),
            "menu_len": np.int16(len(cands)), "feat": np.zeros(FEATURE_DIM, dtype=np.float32)}


_ROWS: list = []  # per-process accumulator, reset per game


def _export_picker(core, state, player, net_player=0, eps=0.0, explore_seed=0, cands=False):
    # forced_pick unmodified, plus one export() call per row it consumes.
    before = gr.G["i"]
    pick = gr.forced_pick(core, state, player, net_player, eps, explore_seed, cands)
    if gr.G["i"] > before:
        row = gr.G["rows"][before]
        _ROWS.append(export(state, row, row["cands"]["list"]))
    return pick


def replay_game(path: str, lists: str) -> tuple:
    # A divergence discards THIS game's rows (skipped and counted, never
    # written) — it does not fail the shard.
    global _ROWS
    _ROWS = []
    gr.arm()
    selfplay._pick_for = _export_picker
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    kn = rec["prescreen"]["knobs"]
    if not kn.get("record_cands") or kn.get("record_aux"):
        return [], {"file": Path(path).name, "positions": 0, "divergence": "REFUSED: not a Gen-0 recording"}
    gr.G.update(dice=rec["dice_seed"], rows=rec["planner_positions"], i=0, cmp=0, ok=0, hand=0)
    armies = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
    try:
        selfplay.play_game(rec["seed"], armies[0], armies[1], gr.REPO, gr.BANK, None, top_k=1, horizon=1,
                           dice_seed=gr.G["dice"], movement=kn["movement"], **gr.KNOBS)
        bad = "" if gr.G["i"] == len(gr.G["rows"]) else "ran dry %d/%d" % (gr.G["i"], len(gr.G["rows"]))
    except gr.Diverged as exc:
        bad = str(exc)
    rows = [] if bad else _ROWS
    return rows, {"file": Path(path).name, "positions": len(rows), "recorded": len(gr.G["rows"]), "divergence": bad}


def shard_paths(out_dir: Path, idx: int) -> tuple:
    base = out_dir / ("gen0_shard_%05d" % idx)
    return base.with_suffix(".npz"), base.with_suffix(".json")


def run_shard(idx: int, games: list, lists: str, out_dir: str) -> dict:
    # Whole-or-nothing: partial progress never reaches the final filenames.
    npz_p, json_p = shard_paths(Path(out_dir), idx)
    rows, index = [], []
    for g in games:
        game_rows, meta = replay_game(str(g), lists)
        index.append(meta)
        rows.extend(game_rows)
    arrays = {k: (np.stack([r[k] for r in rows]) if rows else np.zeros((0,), dtype=np.float32)) for k in ARRAY_KEYS}
    tmp_npz, tmp_json = npz_p.with_name(npz_p.name + ".tmp"), json_p.with_name(json_p.name + ".tmp")
    with open(tmp_npz, "wb") as fh:
        np.savez(fh, **arrays)
    tmp_json.write_text(json.dumps({"shard": idx, "games": index, "positions": len(rows)}, indent=2))
    os.replace(tmp_npz, npz_p)
    os.replace(tmp_json, json_p)
    return {"shard": idx, "games": len(games), "positions": len(rows)}
