"""AI-G4 row F-H1b (rules epoch 73) - the replay gates CUT the table's cast and spell legs.

The table's activation is [movement] -> dangerous-terrain test -> spell cast (the cast die, then the spell's
own saves and morale) -> volley. The core prices a cast as an expectation by design (sim.rs `cast_phase`, no
cast die), so no setting of the gate can make it produce the table's cast roll: the gate has to cut that leg
(lead ruling O3). Since AI-G4 H1a every roll of `dice.jsonl` carries a `leg` (cast / spell / dangerous / main)
and `acts.jsonl` a `kind:"pre"` line per cast leg with the units it changed ({uid: {alive, shaken}}).

The gate then (1) drops the cast/spell rolls from the table's list, (2) burns their dice off the tray, and
(3) starts the core from the state the cast leg left. `dangerous` stays the core's: it rolls its own test.

THE BUNDLED GAME. `fixtures/pre_leg_cut/aof_1000_net_000` is the recorded Beastmen vs Change Disciples game
(AoF 1000 pt, NET arm, seed 36101) re-recorded with the H1a stamps and trimmed: the header, the two act lines
this suite replays (3 and 19: both HOLD-and-shoot, state + pick only), `auto` placeholders for every other
ordinal up to 19 (the ordinal is the position in the act|auto stream, so the dice of the acts before stay
aligned), the `pre` lines up to 19, every roll of acts 1-19 verbatim (the tray burn needs all of them) and the
sidecar shots of the two acts.

  * act 3  - the cast FAILS: one cast die, no spell leg, `pre` is empty. Only the cut + burn is needed.
  * act 19 - Power Bolt succeeds: cast die, the spell's saves, two models fall before the volley. The cut + burn
             AND the patched state are needed.

THE TWO MUTANTS, both through the gate's own `--red-pre` switch (the live gate path, not a re-implementation):

  * `noburn`  - cut the rolls but leave their dice on the tray: the volley draws the cast die's face first, so
                the shapes hold and every act parts AT THE FACES.
  * `nopatch` - cut and burn but keep the pre-spell state: every roll of act 19 still matches, but the target the
                spell thinned out is two models too strong, so the table's morale test after the volley never
                happens in the core - act 19 parts AT THE LENGTH; act 3 (nothing changed) stays equal. (The brief
                expected "at the count"; measured it is the length.)
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "pre_leg_cut"


def gate(capsys, ref: Path = FIXTURE, **kw) -> tuple[int, int, str]:
    """The gate's own run over `ref`: (FULL-equal acts, shooting acts, the whole report)."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", **kw)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def test_pre_leg_cut_acts_3_and_19_are_full_equal(capsys):
    equal, acts, out = gate(capsys)
    assert acts == 2, out
    assert equal == 2, out


def test_cut_without_burn_parts_at_the_faces(capsys):
    equal, acts, out = gate(capsys, red_pre="noburn")
    assert (equal, acts) == (0, 2), out
    assert "faces=2" in out, out


def test_no_patch_parts_act_19_at_the_length(capsys):
    equal, acts, out = gate(capsys, red_pre="nopatch")
    assert (equal, acts) == (1, 2), out
    assert "first field to part: length=1" in out, out


def test_an_old_recording_without_the_stamps_keeps_its_old_numbers(capsys, tmp_path):
    """A recording from before H1a has no `leg` and no `pre` line: every roll reads as `main`, nothing is cut."""
    old = tmp_path / "aof_1000_net_000"
    shutil.copytree(FIXTURE / "aof_1000_net_000", old)
    dice = [json.loads(x) for x in (old / "dice.jsonl").read_text().splitlines() if x.strip()]
    (old / "dice.jsonl").write_text("".join(json.dumps({k: v for k, v in r.items() if k != "leg"}) + "\n"
                                           for r in dice))
    acts = [x for x in (old / "acts.jsonl").read_text().splitlines() if x.strip() and '"kind": "pre"' not in x]
    (old / "acts.jsonl").write_text("\n".join(acts) + "\n")
    equal, acts_n, out = gate(capsys, ref=tmp_path)
    assert (equal, acts_n) == (0, 2), out
    assert "first field to part: count=2" in out, out


def _five_models() -> dict:
    """A five-model unit as the act line carries it: per-model lists over the LIVING models, one x per model."""
    return {"units": {"foe": {"alive": 5, "wounds": [1] * 5, "radii": [0.016] * 5, "kits": list(range(5)),
                              "positions": [[float(i), 0.0, 0.0] for i in range(5)]}}}


def _xs(plain: dict) -> list[float]:
    return [p[0] for p in plain["units"]["foe"]["positions"]]


def test_the_survivors_the_pre_block_names_are_the_models_kept():
    """G4R3 F-PRE-SURV: the spell killed models 0, 2 and 3 (aof_1000_net_033 act 9 killed other models than the first
    k): the replay must start from models 1 and 4, with their own radii, wounds and kits, not from models 0 and 1."""
    out = srg.patch_pre(_five_models(), {"foe": {"alive": 2, "shaken": False, "of": 5, "keep": [1, 4]}})
    foe = out["units"]["foe"]
    assert _xs(out) == [1.0, 4.0] and foe["kits"] == [1, 4] and foe["alive"] == 2


def test_a_pre_record_without_keep_still_keeps_the_first_models():
    """An H1a recording (no `keep`) replays as before: the first k models of the list."""
    out = srg.patch_pre(_five_models(), {"foe": {"alive": 2, "shaken": False}})
    assert _xs(out) == [0.0, 1.0]


def test_a_keep_list_of_another_roster_size_is_not_trusted():
    """`of` is the length of the list `keep` indexes. A unit that lost models BEFORE the cast leg (a dangerous test in
    front of it) has a shorter act-start list: the positions would not line up, so the gate keeps the first k."""
    out = srg.patch_pre(_five_models(), {"foe": {"alive": 2, "shaken": False, "of": 6, "keep": [1, 5]}})
    assert _xs(out) == [0.0, 1.0]


def test_a_dangerous_test_in_front_of_the_cast_leg_leaves_the_act_uncut():
    """The core's own dangerous test would draw BETWEEN two stretches of one resolve and a tray cannot be burned
    mid-resolve: the act stays as recorded, and the gate says so instead of guessing."""
    rolls = [{"leg": "dangerous", "count": 5}, {"leg": "cast", "count": 1}, {"leg": "main", "count": 4}]
    kept, draws, plain = srg.cut_pre_legs(rolls, {"units": {}}, {}, True, True)
    assert kept == rolls and draws == 0
