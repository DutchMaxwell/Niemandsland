#!/usr/bin/env python3
"""RL rollout recorder (RL rollout plan, PR 1 - 11.10.2026): one full game with BOTH seats on the
current policy, one TOKEN ROW per decision in `teacher_record.Capture`'s packed layout (so the
tokenisation cannot drift) plus the RL columns: the SAMPLED build index `played_idx`, its
`logp = log softmax(logits / temp)[a]`, `temp` and the baseline `v` from an ONNX value net (the
state-only token export through the shipped leaf net). `packed()` adds `teacher_record.pack`'s
per-actor outcome (+1 the winner's rows, -1 the loser's, 0 a draw). Each game writes one atomic
`<row_id>.npz` + `.json` (json last = complete; existing = skipped).

DEFAULT OFF: nothing is patched at import time; `_pick_for` is armed only inside `play` and
restored on every exit, so a game played without the recorder stays byte-identical (proof:
test_rl_rollout.py).

SEAM: `play_game`'s `cand_logits_fn` + `policy_mode="order"` scores the policy on the real menu
and the recorder plays the SAMPLED candidate instead of the hand argmax (pure override,
`token_arena_one.py`'s "pure" pattern); the sampler is its own generator seeded with the game
seed, so the same seed replays and the dice stay untouched. `--policy MODULE:FUNC` is
`fn(core, state, menu, side) -> per-candidate logits`.
"""
import argparse, contextlib, hashlib, importlib, json, os, sys  # noqa: E401
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, "..", "python"), os.path.join(HERE, "..", "..", "..", "tools")]
import lab2_net  # noqa: E402
import selfplay as sp  # noqa: E402
import teacher_record as tr  # noqa: E402

SCHEMA = "rl-rollout/1"


class Rollout:
    """Wraps `_pick_for`, samples the policy's action, rewrites the pick to it and captures the row
    + RL columns. `logits_fn(core, state, menu, side) -> logits`."""

    def __init__(self, logits_fn, core, temp=1.0, seed=0, value_fn=None):
        if not float(temp) > 0.0:
            raise ValueError("temp must be > 0, got %r" % (temp,))
        self.logits_fn, self.core, self.temp = logits_fn, core, float(temp)
        self.value_fn = value_fn
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
        row["v"] = np.float32(self.value(core, state, player))
        self.rows.append(row)
        return pick

    def value(self, core, state, player):
        """The baseline V(s): the state-only token export (`cands=[]`, the same flags
        `Capture.row` uses) through the ONNX value net; NaN with no net wired."""
        if self.value_fn is None:
            return float("nan")
        opener = self.capture.first.setdefault(int(state.round), player) == player
        tok = core.policy_tokens(state, player, [], -1, hero_attach=True, opener_seat=opener)
        for k in ("units_mask", "objs_mask"):
            if isinstance(tok[k], (bytes, bytearray)):
                tok[k] = np.frombuffer(tok[k], dtype=np.uint8)
        return float(self.value_fn([tok])[0])

    @contextlib.contextmanager
    def armed(self):
        self.real = sp._pick_for
        with sp.forced_picks(self.seen):
            yield self


def play(w):
    """One game: both seats on `w["policy"]` via `cand_logits_fn` + `policy_mode="order"`, the
    sampled candidate played; returns `(result, rows)`."""
    rec = Rollout(w["policy"], w["core"], temp=w["temp"], seed=w["seed"], value_fn=w.get("value_fn"))
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
    arrays["v"] = np.asarray([r["v"] for r in rows], np.float32)
    return arrays


def write(w, res, rows):
    """The atomic pair: `<row_id>.npz` (the pack layout + the RL columns) first, `<row_id>.json`
    LAST so its existence alone means complete; returns the game meta."""
    stem = os.path.join(w["out"], w["row_id"])
    with open(stem + ".npz.tmp", "wb") as fh:
        np.savez(fh, **packed(res, rows))
    os.replace(stem + ".npz.tmp", stem + ".npz")
    meta = {"schema": SCHEMA, "row_id": w["row_id"], "seed": w["seed"], "winner": res["winner"],
            "rows": len(rows), "temp": w["temp"], "policy_sha256": w["policy_sha256"],
            "value_net_sha256": w.get("value_sha256", ""),
            "decisions": [{"seq": int(r["seq"]), "side": int(r["side"]), "round": int(r["round"]),
                           "played_idx": int(r["played_idx"]), "logp": float(r["logp"]), "v": float(r["v"])}
                          for r in rows]}
    with open(stem + ".json.tmp", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, sort_keys=True)
    os.replace(stem + ".json.tmp", stem + ".json")
    return meta


def _init(cfg):
    import nml_core as nm
    net = cfg.get("value_net")
    return dict(cfg, nm=nm, core=cfg.get("core") or nm.load(cfg["repo"]),
                value_fn=(net.values if net is not None else None),
                value_sha256=(net.model_sha256 if net is not None else ""),
                policy_sha256=cfg.get("policy_sha256") or _policy_sha(cfg["policy"]))


def _policy_sha(policy):
    path = getattr(getattr(policy, "__code__", None), "co_filename", "")
    if path and os.path.exists(path):
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    return ""


def _work(w):
    """One game row: skip when the json exists (complete), else play + write; returns the summary."""
    os.makedirs(w["out"], exist_ok=True)
    base = os.path.join(w["out"], w["row_id"])
    if os.path.exists(base + ".json"):
        with open(base + ".json", encoding="utf-8") as fh:
            meta = json.load(fh)
        return {"row_id": w["row_id"], "rows": meta["rows"], "winner": meta["winner"], "skipped": True}
    res, rows = play(w)
    if not rows:
        raise SystemExit("no decision captured for %s" % w["row_id"])
    meta = write(w, res, rows)
    return {"row_id": w["row_id"], "rows": meta["rows"], "winner": meta["winner"], "skipped": False}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for k, d, kw in (("--out", None, {}), ("--repo", None, {}), ("--bank", None, {}),
                     ("--army1", None, {}), ("--army2", None, {}), ("--seed", 27, {"type": int}),
                     ("--row-id", "game", {}),
                     ("--policy", None, {"help": "MODULE:FUNC -> fn(core, state, menu, side) logits"}),
                     ("--policy-sha256", "", {}), ("--value-net", "", {}), ("--temp", 1.0, {"type": float}),
                     ("--top-k", 2, {"type": int}), ("--horizon", 1, {"type": int})):
        ap.add_argument(k, default=d, required=d is None, **kw)
    a = ap.parse_args(argv)
    module, _, func = a.policy.partition(":")
    policy = getattr(importlib.import_module(module), func)
    value = (lab2_net.ShippedNet(a.repo, onnx=a.value_net, sha256=lab2_net._sha256(a.value_net))
             if a.value_net else lab2_net.ShippedNet(a.repo))
    cfg = {"out": a.out, "repo": a.repo, "bank": a.bank, "army1": a.army1, "army2": a.army2, "seed": a.seed,
           "row_id": a.row_id, "policy": policy, "policy_sha256": a.policy_sha256, "value_net": value,
           "temp": a.temp, "top_k": a.top_k, "horizon": a.horizon}
    s = _work(_init(cfg))
    print("[rl] row=%s winner=%s rows=%d skipped=%s out=%s"
          % (s["row_id"], s["winner"], s["rows"], s["skipped"], a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
