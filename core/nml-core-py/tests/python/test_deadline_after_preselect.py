"""Stage-0 amendment A3, the lab knob `deadline_after_preselect`: `deadline_us` counts from the end of the root
preselection instead of the planner call. On the binding: the preselection time rides `trace.tree` /
`trace.deadline` ONLY on a pick where the knob ran the clock (the NML-1147a stamp law), `Core.knobs()` carries the
knob, and `play_game`'s `deep_deadline_after_preselect` joins the deep seat's header like every other tree knob.
The clock itself is proven in nml-core `tests/deadline.rs`."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from test_tree_knob import _play, needs_lists  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"


def _pick(knobs):
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header, act = json.loads(lines[0]), json.loads(lines[1])
    core = nml_core.load(str(REPO))
    core.set_header({**header, "knobs": {**header.get("knobs", {}), **knobs}})
    return core, core.plan_with_rollout(core.state_of(act["state"]), act["player"], act["statics"])


def test_the_preselection_time_rides_only_a_pick_where_the_knob_ran_the_clock():
    for extra, key in (({"search_mode": "tree", "tree_budget": 16}, "tree"), ({}, "deadline")):
        core, off = _pick({**extra, "deadline_us": 10**9})
        assert core.knobs()["deadline_after_preselect"] is False
        assert off["used"] and "preselect_us" not in off["trace"][key]
        core, on = _pick({**extra, "deadline_us": 10**9, "deadline_after_preselect": True})
        assert core.knobs()["deadline_after_preselect"] is True
        stamp = on["trace"][key]
        assert isinstance(stamp["preselect_us"], int) and 0 <= stamp["preselect_us"] <= stamp["elapsed_us"], stamp
        assert on["trace"]["pool_idx"] == off["trace"]["pool_idx"]  # an allowance that never binds moves nothing
        _core, plain = _pick({**extra, "deadline_after_preselect": True})  # no deadline: no clock to restart
        assert "preselect_us" not in (plain["trace"].get(key) or {})


@needs_lists
def test_the_deep_seat_knob_stamps_its_seat_only_when_it_parts():
    assert "knobs_by_seat" not in _play(deep_player=1, deep_deadline_after_preselect=False)
    r = _play(deep_player=1, deep_search_mode="tree", deep_deadline_us=900, deep_deadline_after_preselect=True)
    assert r["knobs_by_seat"]["p1"] == {
        "top_k": 2, "horizon": 1, "search_mode": "tree", "deadline_us": 900, "deadline_after_preselect": True}
