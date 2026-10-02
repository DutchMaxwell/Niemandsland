#!/usr/bin/env python3
"""Row schema and per-decision log of the stage-0 lab driver (tree plan step 22, "stage0-row/1").

`Recorder` wraps the real `_pick_for` (selfplay.forced_picks) and times every planner call with
perf_counter_ns; each landed pick becomes one decision {seq, side, arm, allocated_us, elapsed_us,
overshoot_us, tree, deadline, search, net_calls}. `make_row` assembles the row of the shared schema,
`guarded` turns an Unsupported / timeout into an INVALID row so the run continues (anything else is a
bug and propagates), `vmhwm_mib` is the worker's peak RSS.
"""
import contextlib
import hashlib
import json
import time

SCHEMA = "stage0-row/1"
ROW_KEYS = ("schema", "prereg_sha256", "row_id", "split", "part", "cell", "source", "arm", "opponent", "seat",
            "replicate", "seeds", "build", "model_sha256", "header_sha256", "net", "decisions", "y", "winner", "valid",
            "reason", "wall_s", "rss_hwm_mib", "done")
DECISION_KEYS = ("seq", "side", "arm", "allocated_us", "elapsed_us", "overshoot_us", "tree", "deadline", "search",
                 "net_calls")
TREE_KEYS = ("completed", "deadline_hit", "batches", "frontier", "terminal")


def sha_of(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=True, allow_nan=False).encode()).hexdigest()


def vmhwm_mib():
    """The process's peak resident set (VmHWM) in MiB."""
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith("VmHWM:"):
                return int(line.split()[1]) / 1024
    return 0.0


class Declined(Exception):
    """A planner answered NO pick while its side still had units to activate: the core's `used: false` decline (e.g.
    TreeUnported("deadly")), which `_pick_for` turns into `{}` and the play loop would read as a dry side. Never a
    silent pass (prereg section 2: an unsupported transition is INVALID) - `guarded` ends the row as INVALID."""


class Recorder:
    """Decisions of ONE game/ending. `arm_of(player)` names the arm that seat plays; `net` (or None) gives the
    per-seat call counts the decision cost."""

    def __init__(self, arm_of, net=None):
        self.arm_of, self.net, self.decisions, self._sigs = arm_of, net, [], []

    def calls(self, side):
        return self.net.counts.get(side, {"calls": 0})["calls"] if self.net else 0

    @contextlib.contextmanager
    def armed(self, sp):
        real = sp._pick_for

        def timed(core, state, player, *args, **kwargs):
            before, t0 = self.calls(player), time.perf_counter_ns()
            pick = real(core, state, player, *args, **kwargs)
            if not pick:
                pool = state.pool(player, bool(core.knobs().get("hero_attach", True)))
                if pool:
                    raise Declined("side %d (%s) declined with %d units to activate" % (player, self.arm_of(player), len(pool)))
            if pick:
                self.add(player, core.knobs().get("deadline_us", 0), (time.perf_counter_ns() - t0) // 1000,
                         pick.get("trace") or {}, self.calls(player) - before, kwargs.get("sig"))
            return pick

        with sp.forced_picks(timed):
            yield self

    def add(self, side, allocated, elapsed, trace, net_calls, sig=None):
        tree, dl = trace.get("tree"), trace.get("deadline")
        alloc = allocated if allocated and allocated > 0 else None
        self.decisions.append({
            "seq": len(self.decisions) + 1, "side": side, "arm": self.arm_of(side), "allocated_us": alloc,
            "elapsed_us": elapsed, "overshoot_us": max(0, elapsed - alloc) if alloc else None,
            "tree": dict({k: tree[k] for k in TREE_KEYS}, fallback=tree.get("fallback")) if tree else None,
            "deadline": {"completed": dl["completed"], "cut": dl["cut"], "fallback": dl.get("fallback")} if dl else None,
            "search": None, "net_calls": net_calls})
        self._sigs.append(sig)

    def attach_search(self, draws):
        """`draws` = [{seed, counter, sig}] of the streams: a decision that was handed a sig gets its (seed, counter)."""
        by_sig = {d["sig"]: {"seed": d["seed"], "counter": d["counter"]} for d in draws}
        for dec, sig in zip(self.decisions, self._sigs):
            if sig is not None:
                dec["search"] = by_sig.get(sig)

    def attach_logged_search(self, log):
        """A `play_game` result log: row i carries `search: {seed, counter}` where a stream fed the pick."""
        for dec, row in zip(self.decisions, log):
            dec["search"] = row.get("search")


def make_row(identity, build, model_sha256, header_sha256, net, rec, y, winner, valid, reason, wall_s):
    """The shared schema; `identity` = {prereg_sha256, row_id, split, part, cell, source, arm, opponent, seat,
    replicate, seeds}. Missing or surplus keys raise."""
    row = dict(identity, schema=SCHEMA, build=build, model_sha256=model_sha256, header_sha256=header_sha256,
               net=net, decisions=rec.decisions if rec else [], y=y, winner=winner, valid=valid, reason=reason,
               wall_s=wall_s, rss_hwm_mib=vmhwm_mib(), done=True)
    if set(row) != set(ROW_KEYS):
        raise KeyError("row keys differ from the schema: %s" % sorted(set(row) ^ set(ROW_KEYS)))
    return {k: row[k] for k in ROW_KEYS}


def guarded(nm, fn):
    """(fn(), None), or (None, reason) when the core declined (Unsupported), the call timed out or the core PANICKED
    (pyo3's PanicException is a BaseException: uncaught it kills the worker; caught, it ends this row as INVALID)."""
    try:
        return fn(), None
    except nm.Unsupported as e:
        return None, "unsupported: %s" % e
    except TimeoutError as e:
        return None, "timeout: %s" % e
    except Declined as e:
        return None, "declined: %s" % e
    except BaseException as e:
        if type(e).__name__ != "PanicException":
            raise
        return None, "panic: %s" % e
