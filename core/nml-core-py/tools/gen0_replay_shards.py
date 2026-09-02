#!/usr/bin/env python3
"""DESIGN_gen0_training §8.6 step 4' — production replay, real token export.

Forces recorded acts through PR #564's `forced_pick`; per activation calls
`Core.policy_tokens` (PR #584) and packs the LIVE rows only, per
netlab/SHARD_SCHEMA.md (ptr-based, masks implied, never padded on disk).
Shards land as atomic `.npz`+`.json` pairs, skipped once finished and
redone if truncated. PYTHONPATH must reach a `.forge/site` wheel built from
`core-policy-tokens-s` — never the shared venv.
"""
import argparse, json, math, multiprocessing as mp, numpy as np, os, sys, time  # noqa: E401
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen0_replay_one as gr, selfplay  # noqa: E402

OUT_DEFAULT = os.path.expanduser("~/selfplay_out/gen0_shards")
RAGGED = {"units": 72, "objs": 12, "terr": 12, "cands": 40}  # §8.1 token widths


def terrain_rows(pieces: list, side: int) -> np.ndarray:
    # The terrain BANK's Terrain::sandbox() is empty for every replayed game
    # (found in prep: 200/35,200 bank files checked, 0 pieces each), so the
    # 18 pieces come from the RECORD's own `terrain` key instead — the
    # narrator's drawing list (narrator_render.py:9-14,122-126), format
    # [kind, x_in, z_in, w_in, h_in, rot_deg], already inches, centre origin.
    # Every column tokens.rs's `terrain_token` (PR #584) reads is present in
    # that list — none is zero-filled: kind, centre and half-extent (w/h are
    # FULL extents there, halved below), and rotation (degrees, converted).
    out = []
    for kind, x, z, w, h, rot in pieces:
        cx, cz = (-x, -z) if side == 2 else (x, z)
        yaw = math.radians(rot)
        out.append([cx / 30.0, cz / 30.0, (w / 2) / 12.0, (h / 2) / 12.0, math.cos(yaw), math.sin(yaw),
                    float(kind == 1), float(kind == 2), float(kind == 3), float(kind == 4),
                    float(kind in (1, 2)), float(kind == 2)])
    return np.array(out, dtype=np.float16)


def export(core, state, row: dict, cands: list, opener_seat: bool) -> dict:
    # §8.2/§8.6: the real token export. `opener_seat` is derived from the
    # game record (no other seam carries it into a forced replay).
    # `hero_attach` is a documented no-op in PR #584 (reserved for later).
    t = core.policy_tokens(state, row["side"], cands, row["cands"]["best"],
                           hero_attach=True, opener_seat=opener_seat)
    nu, no_, nc = (sum(t[k]) for k in ("units_mask", "objs_mask", "cands_mask"))
    return {"units": np.array(t["units"][:nu], dtype=np.float16),
            "objs": np.array(t["objs"][:no_], dtype=np.float16),
            "terr": _TERR[row["side"]],
            "glob": np.array(t["glob"], dtype=np.float16),
            "cands": np.array(t["cands"][:nc], dtype=np.float16),
            "actor": np.array(t["actor"][:nc], dtype=np.int16),
            "target": np.array(t["target"][:nc], dtype=np.int16),
            # Gen-0 recorded no cands.scored (§1.6) — NaN until Gen-1 (§2.6).
            "hand_score": np.full(nc, np.nan, dtype=np.float16),
            "label": np.int16(t["label"])}


_ROWS: list = []  # per-process accumulator, reset per game
_OPENER: dict = {}  # {round: side} for the game currently replaying
_TERR: dict = {}  # {side: (18, 12) rows} for the game currently replaying


def _export_picker(core, state, player, net_player=0, eps=0.0, explore_seed=0, cands=False):
    # forced_pick unmodified, plus one export() call per row it consumes.
    before = gr.G["i"]
    pick = gr.forced_pick(core, state, player, net_player, eps, explore_seed, cands)
    if gr.G["i"] > before:
        row = gr.G["rows"][before]
        _ROWS.append(export(core, state, row, row["cands"]["list"], row["side"] == _OPENER[row["round"]]))
    return pick


def replay_game(path: str, lists: str) -> tuple:
    # A divergence discards THIS game's rows (skipped and counted, never
    # written) — it does not fail the shard.
    global _ROWS, _OPENER, _TERR
    _ROWS = []
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    kn = rec["prescreen"]["knobs"]
    if not kn.get("record_cands") or kn.get("record_aux"):
        return [], {"file": Path(path).name, "positions": 0, "divergence": "REFUSED: not a Gen-0 recording"}
    gr.G.update(dice=rec["dice_seed"], rows=rec["planner_positions"], i=0, cmp=0, ok=0, hand=0)
    _OPENER = {}
    for r in rec["planner_positions"]:
        _OPENER.setdefault(r["round"], r["side"])
    _TERR = {1: terrain_rows(rec["terrain"], 1), 2: terrain_rows(rec["terrain"], 2)}
    armies = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
    try:
        with gr.armed(_export_picker):
            selfplay.play_game(rec["seed"], armies[0], armies[1], gr.REPO, gr.BANK, None, top_k=1, horizon=1,
                               dice_seed=gr.G["dice"], movement=kn["movement"], **gr.KNOBS)
        bad = "" if gr.G["i"] == len(gr.G["rows"]) else "ran dry %d/%d" % (gr.G["i"], len(gr.G["rows"]))
    except (gr.Diverged, gr.nml_core.Unsupported) as exc:
        bad = str(exc)
    rows = [] if bad else _ROWS
    return rows, {"file": Path(path).name, "positions": len(rows), "recorded": len(gr.G["rows"]), "divergence": bad}


def shard_paths(out_dir: Path, idx: int) -> tuple:
    base = out_dir / ("gen0_shard_%05d" % idx)
    return base.with_suffix(".npz"), base.with_suffix(".json")


def pack(rows: list) -> dict:
    # netlab/SHARD_SCHEMA.md: PACKED, ptr-based, masks implied by ptr counts.
    n = len(rows)
    out = {"game_id": np.array([r["game_id"] for r in rows], dtype=np.int32),
           "label": np.array([r["label"] for r in rows], dtype=np.int16),
           "glob": np.stack([r["glob"] for r in rows]) if n else np.zeros((0, 16), np.float16),
           "actor": np.concatenate([r["actor"] for r in rows]) if n else np.zeros(0, np.int16),
           "target": np.concatenate([r["target"] for r in rows]) if n else np.zeros(0, np.int16),
           "hand_score": np.concatenate([r["hand_score"] for r in rows]) if n else np.zeros(0, np.float16)}
    for name, width in RAGGED.items():
        out[name + "_ptr"] = np.concatenate([[0], np.cumsum([len(r[name]) for r in rows])]).astype(np.int64)
        out[name] = np.concatenate([r[name] for r in rows]) if n else np.zeros((0, width), np.float16)
    return out


def run_shard(idx: int, games: list, lists: str, out_dir: str, id_of: dict) -> dict:
    # Whole-or-nothing: partial progress never reaches the final filenames.
    npz_p, json_p = shard_paths(Path(out_dir), idx)
    rows, index = [], []
    for g in games:
        game_rows, meta = replay_game(str(g), lists)
        for r in game_rows:
            r["game_id"] = id_of[Path(g).name]
        index.append(meta)
        rows.extend(game_rows)
    arrays = pack(rows)
    tmp_npz, tmp_json = npz_p.with_name(npz_p.name + ".tmp"), json_p.with_name(json_p.name + ".tmp")
    with open(tmp_npz, "wb") as fh:
        np.savez(fh, **arrays)
    tmp_json.write_text(json.dumps({"shard": idx, "games": index, "positions": len(rows)}, indent=2))
    os.replace(tmp_npz, npz_p)
    os.replace(tmp_json, json_p)
    return {"shard": idx, "games": len(games), "positions": len(rows)}


def _worker(task_q, done_q, lists, out_dir, corpus) -> None:
    # id_of: corpus-GLOBAL game index, stable across --limit/--sample-every.
    id_of = {p.name: i for i, p in enumerate(sorted(Path(corpus).glob("gen0_s*_d*.json")))}
    for idx, games in iter(task_q.get, None):
        done_q.put(run_shard(idx, games, lists, out_dir, id_of))


def discover_shards(corpus, out_dir, shard_size, sample_every, limit):
    games = sorted(Path(corpus).glob("gen0_s*_d*.json"))[::sample_every]
    games = games[:limit] if limit else games
    shards = [games[i:i + shard_size] for i in range(0, len(games), shard_size)]
    todo = [(i, g) for i, g in enumerate(shards) if not all(p.exists() for p in shard_paths(out_dir, i))]
    return games, shards, todo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("corpus", nargs="?", default=os.path.expanduser("~/selfplay_out/gen0_teacher"))
    ap.add_argument("--lists", default=gr.LISTS)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--shard-size", type=int, default=500)
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--sample-every", type=int, default=1)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    games, shards, todo = discover_shards(a.corpus, out_dir, a.shard_size, a.sample_every, a.limit)
    n_workers = min(a.workers, len(todo))
    print("[SHARDS] %d games, %d shards, %d already done, %d to run -> %d workers"
          % (len(games), len(shards), len(shards) - len(todo), len(todo), n_workers))
    if not todo:
        # Nothing to replay (a rerun over a finished corpus): the night
        # chain's sentinel must still land, or a re-launch after completion
        # hangs it forever.
        (out_dir / "STATUS").write_text("DONE games=0/0 rate=0.000/s elapsed=0.0s\n")
        return 0
    ctx = mp.get_context("fork")
    task_q, done_q = ctx.Queue(), ctx.Queue()
    for item in list(todo) + [None] * n_workers:
        task_q.put(item)
    procs = [ctx.Process(target=_worker, args=(task_q, done_q, a.lists, str(out_dir), a.corpus)) for _ in range(n_workers)]
    [p.start() for p in procs]
    (out_dir / "pids.json").write_text(json.dumps({"main": os.getpid(), "workers": [p.pid for p in procs]}))
    total_games = sum(len(g) for _, g in todo)
    t0, done_games, last_status = time.time(), 0, 0.0

    def write_status(done=False):
        rate = done_games / max(time.time() - t0, 1e-9)
        (out_dir / "status.json").write_text(json.dumps({"games_done": done_games, "games_total": total_games,
            "rate_games_per_s": round(rate, 3), "elapsed_s": round(time.time() - t0, 1)}))
        # The night chain's sentinel: a line starting "DONE" in plain STATUS.
        (out_dir / "STATUS").write_text("%s games=%d/%d rate=%.3f/s elapsed=%.1fs\n"
            % ("DONE" if done else "RUNNING", done_games, total_games, rate, time.time() - t0))

    write_status()
    while any(p.is_alive() for p in procs) or not done_q.empty():
        try:
            done_games += done_q.get(timeout=5)["games"]
        except Exception:
            pass
        if time.time() - last_status > 120:
            write_status()
            last_status = time.time()
    [p.join() for p in procs]
    write_status(done=True)
    print("[SHARDS] done: %d games in %.1fs" % (done_games, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
