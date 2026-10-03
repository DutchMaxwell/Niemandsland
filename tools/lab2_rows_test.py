#!/usr/bin/env python3
"""Tests for tools/lab2_rows.py (stage0-row/1) on stub cores: no data, no nml_core. Run: python3 -m pytest -q tools/lab2_rows_test.py"""
import contextlib
import importlib.util
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("lab2_rows", os.path.join(_HERE, "lab2_rows.py"))
rows = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_rows"] = rows
_SPEC.loader.exec_module(rows)

PRINCIPLES_ROW = ("schema prereg_sha256 row_id split part cell source arm opponent seat replicate seeds build model_sha256 "
                  "header_sha256 net decisions y winner valid reason wall_s rss_hwm_mib done").split()
PRINCIPLES_DECISION = "seq side arm allocated_us elapsed_us overshoot_us tree deadline search net_calls".split()
IDENT = dict(prereg_sha256="p", row_id="r", split="D", part="A", cell="1", source="s", arm="T", opponent="I", seat=1,
             replicate=0, seeds={"eval_general": "1"})


class Core:
    def __init__(self, deadline_us, unsupported=None):
        self._k, self.unsupported = {"deadline_us": deadline_us}, unsupported

    def knobs(self):
        return self._k

    def plan_with_rollout(self, state, player, statics, **kw):
        """The repeat call `decline_reason` makes: the core's decline value (or a pick, if none is configured)."""
        return {"used": False, "unsupported": self.unsupported} if self.unsupported else {"used": True}


class Net:
    counts = {1: {"calls": 0, "leaves": 0}, 2: {"calls": 0, "leaves": 0}}


class Sp:
    """Stand-in selfplay: `_pick_for` answers the queued picks and bumps the net counter like a hook would."""
    TRAINER_STATICS = {}

    def __init__(self, picks):
        self.picks = list(picks)

    def _pick_for(self, core, state, player, *a, **k):
        Net.counts[player]["calls"] += 1
        return self.picks.pop(0)

    @contextlib.contextmanager
    def forced_picks(self, fn):
        self._pick_for_live = fn
        yield


class St:
    """A state stub: `pool` lists the side's units still to activate (empty = a dry side)."""
    def __init__(self, pool=()):
        self._pool = list(pool)

    def pool(self, player, attach):
        return self._pool


def run(sp, rec, core, player, state=None, **kw):
    with rec.armed(sp):
        return sp._pick_for_live(core, state or St(), player, **kw)


TREE = {"completed": 6, "deadline_hit": True, "batches": 3, "frontier": 5, "terminal": 1, "elapsed_us": 90, "fallback": None}


def test_schema_keys_match_the_principles_list_exactly_and_a_surplus_key_raises():
    row = rows.make_row(IDENT, {"commit": "c"}, "m", {"1": "h"}, {}, rows.Recorder(lambda s: "T"), 1.0, "p1", True, None, 0.5)
    assert list(row) == PRINCIPLES_ROW and tuple(PRINCIPLES_ROW) == rows.ROW_KEYS and row["rss_hwm_mib"] > 0
    with pytest.raises(KeyError):
        rows.make_row(dict(IDENT, extra=1), {}, "m", {}, {}, None, 1.0, "p1", True, None, 0.5)


def test_every_tree_decision_has_tree_no_pool_or_incumbent_decision_does_and_overshoot_is_computed():
    sp, rec = Sp([{"trace": {"tree": TREE}}, {"trace": {}}, {"trace": {"deadline": {"completed": 2, "cut": True, "elapsed_us": 9}}}]), \
        rows.Recorder(lambda side: "T" if side == 1 else "I", Net)
    run(sp, rec, Core(1), 1, sig=7)       # a tree decision under a 1 us allowance: overshoot = elapsed - 1
    run(sp, rec, Core(0), 2)              # the incumbent: no allowance, no tree
    run(sp, rec, Core(5000), 1)           # a pool decision
    tree, inc, pool = rec.decisions
    assert [list(d) for d in rec.decisions] == [PRINCIPLES_DECISION] * 3 and [d["seq"] for d in rec.decisions] == [1, 2, 3]
    assert tree["tree"] == {"completed": 6, "deadline_hit": True, "batches": 3, "frontier": 5, "terminal": 1, "fallback": None}
    assert tree["allocated_us"] == 1 and tree["overshoot_us"] == max(0, tree["elapsed_us"] - 1) and tree["net_calls"] == 1
    assert inc["tree"] is None and inc["allocated_us"] is None and inc["overshoot_us"] is None and inc["arm"] == "I"
    assert pool["tree"] is None and pool["deadline"] == {"completed": 2, "cut": True, "fallback": None}
    rec.attach_search([{"seed": 5, "counter": 0, "sig": 7}])
    assert tree["search"] == {"seed": 5, "counter": 0} and inc["search"] is None


def test_a_dry_pick_logs_nothing_and_guarded_turns_declines_into_reasons_but_not_bugs():
    sp, rec = Sp([{}]), rows.Recorder(lambda s: "I", Net)
    run(sp, rec, Core(0), 1)
    assert rec.decisions == []

    class Nm:
        class Unsupported(Exception):
            pass

    def boom(exc):
        def f():
            raise exc
        return f
    assert rows.guarded(Nm, lambda: 3) == (3, None)
    assert rows.guarded(Nm, boom(Nm.Unsupported("unported x"))) == (None, "unsupported: unported x")
    assert rows.guarded(Nm, boom(TimeoutError("30 s"))) == (None, "timeout: 30 s")
    with pytest.raises(ZeroDivisionError):
        rows.guarded(Nm, boom(ZeroDivisionError()))


TRAY = 'TreeUnported("takedown")'


class Nm:
    class Unsupported(Exception):
        pass


def test_an_empty_pick_with_units_left_is_a_declined_invalid_row_and_a_dry_side_is_not():
    rec = rows.Recorder(lambda s: "L", Net)
    assert run(Sp([{}]), rec, Core(0, TRAY), 1, state=St()) == {}           # dry side: no units, a legal pass
    with pytest.raises(rows.Declined, match="side 1 .L. declined with 4 units"):
        run(Sp([{}]), rec, Core(0, TRAY), 1, state=St(["u1", "u2", "u3", "u4"]))   # a PRIMARY arm: always INVALID

    def play():
        return run(Sp([{}]), rows.Recorder(lambda s: "L_tray", Net), Core(0, "Unsupported(x)"), 1, state=St(["u1"]))
    out, why = rows.guarded(Nm, play)   # a control arm declining for any reason but TreeUnported stays INVALID
    assert out is None and why.startswith("declined: side 1 (L_tray) declined with 1 units") and why.endswith("Unsupported(x)")
    assert rec.decisions == []


def test_a_control_arm_on_an_unported_tray_transition_is_blocked_stratum_not_invalid():
    def play(arm):
        return lambda: run(Sp([{}]), rows.Recorder(lambda s: arm, Net), Core(0, TRAY), 1, state=St(["u1", "u2"]))
    assert rows.guarded(Nm, play("T_tray")) == (None, 'blocked_stratum: side 1 (T_tray): ' + TRAY)
    assert rows.guarded(Nm, play("L_tray"))[1].startswith("blocked_stratum: ")
    assert rows.guarded(Nm, play("T"))[1].startswith("declined: ")   # the primary T: never blocked


def test_a_core_panic_ends_the_row_as_invalid_but_other_base_exceptions_still_raise():
    class Nm:
        class Unsupported(Exception):
            pass

    PanicException = type("PanicException", (BaseException,), {})   # pyo3_runtime's: NOT an Exception

    def boom(exc):
        def f():
            raise exc
        return f
    msg = "removal index (is 0) should be < len (is 0)"
    assert rows.guarded(Nm, boom(PanicException(msg))) == (None, "panic: " + msg)
    with pytest.raises(KeyboardInterrupt):
        rows.guarded(Nm, boom(KeyboardInterrupt()))
