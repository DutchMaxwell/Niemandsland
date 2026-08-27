"""GATE Q C4 (NML-1073) — `selfplay.result_digest`. Unit tests only, no
corpus or bank: `throughput.py`'s determinism checks and `box_digest.py` both
lean on two properties of this function — timing fields never move the
digest, and everything else does — and this file pins both without playing a
game.
"""

from __future__ import annotations

import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402


def _sample_result() -> dict:
    """A result-shaped dict deep enough to touch every field KIND
    `result_digest` must reach: a `planner_positions` row's `board` / `ids` /
    `features` / `value` / `pair` / `fork`, plus `terrain` and `magic` — the
    exact fields the old `throughput.digest_of` (winner/vp/objectives/picks
    only) could not see. `wall_seconds` is the field `selfplay.main()` stamps
    on after `play_game` returns."""
    return {
        "schema": 1,
        "seed": 27,
        "winner": "p1",
        "vp": {"p1": 4, "p2": 3},
        "objectives": {"p1": 2, "p2": 1, "neutral": 0},
        "terrain": [[1, 0.0, 0.0, 6.0, 6.0, 0]],
        "magic": {"casts": {"p1": 1, "p2": 0}, "tokens_spent": {"p1": 2, "p2": 0}},
        "planner_positions": [
            {
                "side": 1,
                "round": 1,
                "seq": 0,
                "value": 0.6123456789,
                "unit": "p1_u0",
                "kind": 2,
                "action": {"kind": 2, "unit": "p1_u0"},
                "board": [[0.0, 1.5, 4.0]],
                "ids": [0],
                "features": [0.1, 0.2, 0.3],
                "pair": {"chosen": [[0.0]], "runner": [[1.0]]},
                "fork": {
                    "chosen_runs": [{"p1": 1, "p2": 0}],
                    "runner_runs": [{"p1": 0, "p2": 1}],
                },
            }
        ],
        "wall_seconds": 1.234,
    }


def test_digest_is_stable_for_an_equal_dict():
    a = _sample_result()
    b = copy.deepcopy(a)
    assert sp.result_digest(a) == sp.result_digest(b)


def test_digest_ignores_top_level_key_order():
    a = _sample_result()
    b = {k: a[k] for k in reversed(list(a))}
    assert sp.result_digest(a) == sp.result_digest(b)


def test_one_field_change_flips_the_digest():
    base = sp.result_digest(_sample_result())
    changed = _sample_result()
    changed["planner_positions"][0]["features"][2] = 0.30000001
    assert sp.result_digest(changed) != base


def test_nested_sidecar_change_flips_the_digest():
    """The field the old narrow digest could never see."""
    base = sp.result_digest(_sample_result())
    changed = _sample_result()
    changed["planner_positions"][0]["fork"]["chosen_runs"][0]["p1"] = 2
    assert sp.result_digest(changed) != base


def test_terrain_change_flips_the_digest():
    base = sp.result_digest(_sample_result())
    changed = _sample_result()
    changed["terrain"][0][1] = 3.0
    assert sp.result_digest(changed) != base


def test_timing_field_does_not_flip_the_digest():
    a = _sample_result()
    b = copy.deepcopy(a)
    b["wall_seconds"] = 999.0
    assert sp.result_digest(a) == sp.result_digest(b)


def test_missing_timing_field_still_matches():
    """`play_game`'s own return value never carries `wall_seconds` — only
    `main()` stamps it on afterward — so a digest taken before and after that
    stamp must agree."""
    a = _sample_result()
    b = copy.deepcopy(a)
    del b["wall_seconds"]
    assert sp.result_digest(a) == sp.result_digest(b)


def test_excluded_fields_list_is_exactly_wall_seconds():
    """Pins the exclusion list itself — a second timing field must be added
    here deliberately, not slip in unnoticed."""
    assert sp.DIGEST_EXCLUDED_FIELDS == ("wall_seconds",)
