#!/usr/bin/env python3
"""RL rollout recorder (RL rollout plan, PR 1 part 1 - 11.10.2026): one full game with BOTH seats
on the current policy, one in-memory TOKEN ROW per decision in `teacher_record.Capture`'s packed
layout (so the tokenisation cannot drift) plus the RL columns: the SAMPLED build index
`played_idx`, its `logp = log softmax(logits / temp)[a]` and `temp`; `packed()` adds
`teacher_record.pack`'s per-actor outcome (+1 the winner's rows, -1 the loser's, 0 a draw).

DEFAULT OFF: nothing is patched at import time; `_pick_for` is armed only inside `play` and
restored on every exit, so a game played without the recorder stays byte-identical (proof:
test_rl_rollout.py).

SEAM: `play_game`'s `cand_logits_fn` + `policy_mode="order"` scores the policy on the real menu
and the recorder plays the SAMPLED candidate instead of the hand argmax (pure override,
`token_arena_one.py`'s "pure" pattern); the sampler is its own generator seeded with the game
seed, so the same seed replays and the dice stay untouched. `--policy MODULE:FUNC` is
`fn(core, state, menu, side) -> per-candidate logits`.
"""
import argparse, contextlib, hashlib, importlib, os, sys  # noqa: E401
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, "..", "python"), os.path.join(HERE, "..", "..", "..", "tools")]
import selfplay as sp  # noqa: E402
import teacher_record as tr  # noqa: E402


class Rollout:
    """Wraps `_pick_for`, samples the policy's action, rewrites the pick to it and captures the row
    + RL columns. `logits_fn(core, state, menu, side) -> logits`."""

    def __init__(self, logits_fn, core, temp=1.0, seed=0):
        if not float(temp) > 0.0:
            raise ValueError("temp must be > 0, got %r" % (temp,))
        self.logits_fn, self.core, self.temp = logits_fn, core, float(temp)
        self.rng = np.random.default_rng(int(seed))
        self.rows, self.capture, self.pending, self.real = [], tr.Capture(), None, None

    def hook(self, state, menu, side):
        """`cand_logits_fn`'s `(state, menu, side)`: score the policy on the real menu, sample the
        action from `softmax(logits / temp)` and keep `(logits, a, logp)` for `seen`."""
        logits = np.asarray(self.logits_fn(self.core, state, menu, side), np.float64).reshape(-1)
        if len(logits) != len(menu):
            raise ValueError("policy logits %d != menu %d" % (len(logits), len(menu)))
        z = logits / self.temp
        if not np.isfinite(z.max()):
            raise ValueError("policy gave no finite logit for a %d-row menu" % len(menu))
        p = np.exp(z - z.max())
        p = p / p.sum()
        a = int(self.rng.choice(len(p), p=p))
        self.pending = (logits, a, float(np.log(p[a])))
        return logits.astype(np.float32)

    def seen(self, core, state, player, *args, **kwargs):
        """The armed `_pick_for`: run the real planner (its `cand_logits_fn` call sampled above),
        then play the sampled build index and capture the row."""
        self.pending = None
        pick = self.real(core, state, player, *args, **kwargs)
        if not pick or "cands" not in (pick.get("trace") or {}):
            return pick
        if self.pending is None:
            raise RuntimeError("no policy call before the pick - is cand_logits_fn armed?")
        logits, a, logp = self.pending
        menu = pick["trace"]["cands"]
        if len(menu) != len(logits):
            raise ValueError("menu moved between the policy call and the real one (%d != %d)" % (len(menu), len(logits)))
        act = menu[a]
        pick["action"], pick["unit_key"], pick["played_idx"] = act, act["unit"], a
        row = self.capture.row(core, state, player, pick)
        row["played_idx"], row["logp"], row["temp"] = np.int32(a), np.float32(logp), np.float32(self.temp)
        self.rows.append(row)
        return pick

    @contextlib.contextmanager
    def armed(self):
        self.real = sp._pick_for
        with sp.forced_picks(self.seen):
            yield self


def play(w):
    """One game: both seats on `w["policy"]` via `cand_logits_fn` + `policy_mode="order"`, the
    sampled candidate played; returns `(result, rows)`."""
    rec = Rollout(w["policy"], w["core"], temp=w["temp"], seed=w["seed"])
    with rec.armed():
        res = sp.play_game(w["seed"], w["army1"], w["army2"], w["repo"], w["bank"], w["core"],
                           sidecars=False, record_cands=True,
                           cand_logits_fn={1: rec.hook, 2: rec.hook}, policy_mode="order",
                           top_k=w["top_k"], horizon=w["horizon"])
    return res, rec.rows


def packed(res, rows):
    """The `teacher_record.pack` layout + the RL columns (in memory); `outcome` is the pack's own
    per-actor mapping (+1 the winner's rows, -1 the loser's, 0 a draw)."""
    arrays = tr.pack(rows, res["winner"])
    arrays["played_idx"] = np.asarray([r["played_idx"] for r in rows], np.int32)
    arrays["logp"] = np.asarray([r["logp"] for r in rows], np.float32)
    arrays["temp"] = np.asarray([r["temp"] for r in rows], np.float32)
    return arrays


def _init(cfg):
    import nml_core as nm
    return dict(cfg, nm=nm, core=cfg.get("core") or nm.load(cfg["repo"]),
                policy_sha256=cfg.get("policy_sha256") or _policy_sha(cfg["policy"]))


def _policy_sha(policy):
    path = getattr(getattr(policy, "__code__", None), "co_filename", "")
    if path and os.path.exists(path):
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    return ""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for k, d, kw in (("--repo", None, {}), ("--bank", None, {}), ("--army1", None, {}), ("--army2", None, {}),
                     ("--seed", 27, {"type": int}), ("--row-id", "game", {}),
                     ("--policy", None, {"help": "MODULE:FUNC -> fn(core, state, menu, side) logits"}),
                     ("--policy-sha256", "", {}), ("--temp", 1.0, {"type": float}),
                     ("--top-k", 2, {"type": int}), ("--horizon", 1, {"type": int})):
        ap.add_argument(k, default=d, required=d is None, **kw)
    a = ap.parse_args(argv)
    module, _, func = a.policy.partition(":")
    policy = getattr(importlib.import_module(module), func)
    cfg = {"repo": a.repo, "bank": a.bank, "army1": a.army1, "army2": a.army2, "seed": a.seed,
           "row_id": a.row_id, "policy": policy, "policy_sha256": a.policy_sha256,
           "temp": a.temp, "top_k": a.top_k, "horizon": a.horizon}
    w = _init(cfg)
    res, rows = play(w)
    if not rows:
        raise SystemExit("no decision captured for %s" % a.row_id)
    arr = packed(res, rows)
    print("[rl] row=%s winner=%s rows=%d played_idx=[%d..%d] logp=[%.3f..%.3f] policy_sha256=%s"
          % (a.row_id, res["winner"], len(rows), int(arr["played_idx"].min()), int(arr["played_idx"].max()),
             float(arr["logp"].min()), float(arr["logp"].max()), w["policy_sha256"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
