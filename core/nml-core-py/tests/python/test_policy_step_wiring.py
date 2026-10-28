"""#1698 wiring guard — the path seam must reach the Python binding's `policy_step`.

THE HOLE. `Core.policy_step` builds its OWN `Policy` (the one-step greedy reply
the fork/continuation tools read) with `Policy::new` and never set `Policy.reach`
or the `route_root` seam split — the same omission commit e958f7ae (#1471) fixed
for `Core.plan_with_rollout` and #1785 fixed for `Core.full_playout`. So a header
with `seam_path: true` was accepted, stamped and silently ignored by THIS entry:
`policy_step` on state S answered exactly like the same call on a seam-off core,
and the Python reply parted from the in-search reply of the same brain (the
policy_step the crate's own rollout plays):

    "core-py: policy_step (Python) disagrees with the in-search scripted reply"
    — https://github.com/DutchMaxwell/Niemandsland/issues/1698

MUTATION GUARD. Same shape as `test_seam_path_wiring.py`: play one smoke game
with the seam off under `TRAINER_KNOBS`, capture the activation states, then ask
`policy_step` on every captured state with the seam OFF and ON (one header, only
`seam_path` flipped) and require at least one answer to differ. With `Policy.reach`
unwired the seam is inert and every answer is identical, so the test fails.

SKIP: needs the terrain bank and the private AI-list corpus outside the repo, the
same escape hatch `test_seam_path_wiring.py` and `test_knob_wiring.py` use.
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
LISTS = Path(os.path.expanduser(os.environ.get("NML_AI_LISTS_DIR", "")))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
SEEDS = range(27, 34)
MAX_STATES = 500


class _HeaderSpy:
    """A transparent proxy that records every header `play_game` sets, so the
    test can flip one knob and replay the SAME states through `policy_step`."""

    def __init__(self, real):
        self._real = real
        self.headers: list[dict] = []

    def set_header(self, header):
        self.headers.append(header)
        return self._real.set_header(header)

    def __getattr__(self, name):
        return getattr(self._real, name)


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_the_path_seam_changes_policy_step(monkeypatch):
    real = nml_core.load(str(REPO))
    core = _HeaderSpy(real)

    captured: list[tuple[dict, int]] = []
    real_pick = sp._pick_for

    def seen(c, state, player, *a, **kw):
        pick = real_pick(c, state, player, *a, **kw)
        if pick.get("used") and len(captured) < MAX_STATES:
            captured.append((state.plain(), int(player)))
        return pick

    monkeypatch.setattr(sp, "_pick_for", seen)
    monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_path", False)
    for seed in SEEDS:
        sp.play_game(seed, ARMY1, ARMY2, REPO, BANK_DIR, core, sidecars=False)

    assert captured, "the smoke game recorded no activation — the gate proves nothing"
    assert core.headers, "play_game never set a header"

    header = core.headers[-1]
    assert real.knobs().get("seam_path") is False, "the seam should start off"

    off = [real.policy_step(real.state_of(plain), player, True) for plain, player in captured]

    on_header = {**header, "knobs": dict(header["knobs"], seam_path=True)}
    real.set_header(on_header)
    assert real.knobs().get("seam_path") is True, "the flipped knob did not read back"

    on = [real.policy_step(real.state_of(plain), player, True) for plain, player in captured]

    assert off != on, (
        "seam_path on/off gave identical policy_step answers on all %d captured "
        "activations (seeds %d-%d): the path seam never reaches the binding's "
        "policy_step (Policy.reach unset)" % (len(captured), SEEDS[0], SEEDS[-1] - 1)
    )
