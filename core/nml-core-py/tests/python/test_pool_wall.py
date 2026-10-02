"""`trace.pool_completed` (tree plan step 9): stamped ONLY on a pick where `pool_wall_ms` is on."""
import json
import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
ACTS = REPO / "core" / "nml-core" / "tests" / "fixtures" / "acts_wide_25.jsonl"


def _pick(wall_ms):
    with open(ACTS, encoding="utf-8") as f:
        header = json.loads(f.readline())
        acts = [json.loads(line) for line in f]
    core = nml_core.load(str(REPO))
    knobs = dict(header["knobs"])
    if wall_ms is not None:
        knobs["pool_wall_ms"] = wall_ms
    core.set_header({"profiles": header["profiles"], "terrain": header["terrain"], "knobs": knobs})
    for act in acts:
        try:
            pick = core.plan_with_rollout(core.state_of(act["state"]), act["player"], sp.TRAINER_STATICS)
        except Exception:
            continue
        if pick.get("used"):
            return pick["trace"]
    raise AssertionError("no answerable act")


def test_the_stamp_rides_only_a_pick_where_the_knob_is_on():
    assert "pool_completed" not in _pick(None)
    assert "pool_completed" not in _pick(0)
    huge = _pick(3_600_000)["pool_completed"]
    assert huge["deadline_hit"] is False
    cut = _pick(1)
    assert cut["pool_completed"]["completed"] == len(cut["pool_idx"]) == len(cut["rs"]) >= 1
