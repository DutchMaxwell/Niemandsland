"""NML-1010 W2 (missions R1) — the `mission` knob on `play_game`.

`mission="duel"` (the default) must reproduce today's game byte-for-byte:
`assets/solo/missions.json` is loaded but every optional state key it could
add (`vp`/`vp_flavour`/`vp_memo`/`markers_meta`/`destroy_seq`) stays absent,
so `result_digest` does not move and no `mission` key rides `knobs`. A
`round_vp` mission (`domination`, majority booked EVERY round) must NOT: its
round-1 `vp` line differs from duel's, and the id is stamped in both
`result["mission"]["name"]` and `result["knobs"]["mission"]`.

RED (manual, not a standing test): comment out the `if eff_scoring ==
"round_vp":` branch in `selfplay.py`'s round loop (falling through to the
`elif eff_scoring == "end":` arm, i.e. today's unconditional `vp_round_add`)
— `test_domination_differs_from_duel_at_round_one` fails, because
`mission="domination"` would then book VP exactly like duel.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
#: the fast trainer's own knobs (`mass_fast.FIDELITY_DEFAULTS`), so the only
#: free variable across every call below is `mission`.
FAST = {"top_k": 2, "horizon": 1}
SEED = 27


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")


def _play(mission: str, core) -> dict:
    return sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, mission=mission, **FAST)


@needs_lists
def test_duel_default_is_byte_identical_to_no_mission_kwarg():
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    explicit = _play("duel", core)
    assert sp.result_digest(base) == sp.result_digest(explicit)
    assert "mission" not in base["knobs"]
    assert base["scoring"] == "end"


@needs_lists
def test_domination_differs_from_duel_at_round_one_and_stamps_the_id():
    core = nml_core.load(str(REPO))
    duel = _play("duel", core)
    dom = _play("domination", core)
    assert dom["rounds_log"][0]["vp"] != duel["rounds_log"][0]["vp"]
    assert dom["mission"]["name"] == "domination"
    assert dom["knobs"]["mission"] == "domination"
    assert dom["scoring"] == "round_vp"


@needs_lists
def test_unknown_mission_id_raises():
    core = nml_core.load(str(REPO))
    with pytest.raises(ValueError):
        _play("not_a_mission", core)
