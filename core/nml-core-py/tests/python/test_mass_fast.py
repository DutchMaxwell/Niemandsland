"""GATE Q (NML-1073) -- `tools/mass_fast.py`'s pairing/size formula, pinned.

The private fleet script `farm/mass_wave_template.sh` (formula copied into
`mass_fast.py`'s docstring) is the OLD training corpus's generator:
`fa=F[s%6]`, `fb=F[(s/6)%6]`, `sz=S[(s/36)%3]` for
`F=(alien_hives battle_brothers blessed_sisters blood_brothers
change_disciples robot_legions)` and `S=(1000 1500 2000)`. This test pins
`derive_pairing`'s answer for the first 40 seeds of the real run
(300000..300039) against a table computed independently of the module under
test, so a refactor that silently changes the arithmetic (off-by-one modulus,
swapped fa/fb, wrong divisor) fails here rather than surfacing as a corpus
that quietly drifted from the one `NML-1069`/`NML-1073` planner-lane
experiments were trained on.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import mass_fast as mf  # noqa: E402

# seed, fa, fb, sz -- independently hand-computed from the bash formula above,
# not derived by calling mass_fast.py.
PINNED_300000_300039 = [
    (300000, "alien_hives", "blessed_sisters", 2000),
    (300001, "battle_brothers", "blessed_sisters", 2000),
    (300002, "blessed_sisters", "blessed_sisters", 2000),
    (300003, "blood_brothers", "blessed_sisters", 2000),
    (300004, "change_disciples", "blessed_sisters", 2000),
    (300005, "robot_legions", "blessed_sisters", 2000),
    (300006, "alien_hives", "blood_brothers", 2000),
    (300007, "battle_brothers", "blood_brothers", 2000),
    (300008, "blessed_sisters", "blood_brothers", 2000),
    (300009, "blood_brothers", "blood_brothers", 2000),
    (300010, "change_disciples", "blood_brothers", 2000),
    (300011, "robot_legions", "blood_brothers", 2000),
    (300012, "alien_hives", "change_disciples", 2000),
    (300013, "battle_brothers", "change_disciples", 2000),
    (300014, "blessed_sisters", "change_disciples", 2000),
    (300015, "blood_brothers", "change_disciples", 2000),
    (300016, "change_disciples", "change_disciples", 2000),
    (300017, "robot_legions", "change_disciples", 2000),
    (300018, "alien_hives", "robot_legions", 2000),
    (300019, "battle_brothers", "robot_legions", 2000),
    (300020, "blessed_sisters", "robot_legions", 2000),
    (300021, "blood_brothers", "robot_legions", 2000),
    (300022, "change_disciples", "robot_legions", 2000),
    (300023, "robot_legions", "robot_legions", 2000),
    (300024, "alien_hives", "alien_hives", 1000),
    (300025, "battle_brothers", "alien_hives", 1000),
    (300026, "blessed_sisters", "alien_hives", 1000),
    (300027, "blood_brothers", "alien_hives", 1000),
    (300028, "change_disciples", "alien_hives", 1000),
    (300029, "robot_legions", "alien_hives", 1000),
    (300030, "alien_hives", "battle_brothers", 1000),
    (300031, "battle_brothers", "battle_brothers", 1000),
    (300032, "blessed_sisters", "battle_brothers", 1000),
    (300033, "blood_brothers", "battle_brothers", 1000),
    (300034, "change_disciples", "battle_brothers", 1000),
    (300035, "robot_legions", "battle_brothers", 1000),
    (300036, "alien_hives", "blessed_sisters", 1000),
    (300037, "battle_brothers", "blessed_sisters", 1000),
    (300038, "blessed_sisters", "blessed_sisters", 1000),
    (300039, "blood_brothers", "blessed_sisters", 1000),
]


def test_derive_pairing_pinned_first_40_seeds():
    for seed, fa, fb, sz in PINNED_300000_300039:
        assert mf.derive_pairing(seed) == (fa, fb, sz), "seed %d" % seed


def test_derive_pairing_full_cycle_is_108_and_covers_every_pairing():
    """`len(FACTIONS) ** 2 * len(sizes)` = 6*6*3 = 108 -- the period `--games
    216 --workers 8` (GATE Q proof (a)) relies on: two full cycles, each of
    the 108 (fa, fb, sz) triples appearing exactly twice."""
    base = 300000
    period = len(mf.FACTIONS) ** 2 * len(mf.DEFAULT_SIZES)
    assert period == 108
    first_cycle = [mf.derive_pairing(base + i) for i in range(period)]
    second_cycle = [mf.derive_pairing(base + period + i) for i in range(period)]
    assert first_cycle == second_cycle
    assert len(set(first_cycle)) == period, "every (fa, fb, sz) triple must be distinct within one cycle"


def test_derive_pairing_red_copy_paste_fb_disagrees_with_the_pin():
    """RED PROOF: a plausible copy-paste bug -- `fb` computed with `fa`'s own
    `s % 6` instead of `(s // 6) % 6` -- must disagree with the pinned table
    at some seed in the first 40 -- otherwise the pin above would hold just
    as well for the wrong arithmetic, and the test would prove nothing."""
    disagreements = 0
    for seed, _fa, fb, _sz in PINNED_300000_300039:
        wrong_fb = mf.FACTIONS[seed % len(mf.FACTIONS)]  # fa's formula, not fb's
        if wrong_fb != fb:
            disagreements += 1
    assert disagreements > 0


# ------------------------------------------------- the fidelity knobs (M5) ---
#
# THE HOLE this closes. `_worker` called
# `sp.play_game(seed, ..., top_k=top_k, horizon=horizon)` and nothing else, so
# the corpus generator could only ever write PRE-M5 games -- `dice="expected"`,
# `movement="rigid"`, `hero_attach="off"`, `charge_landing="off"` -- no matter
# what the caller wanted. No gate caught it: the header the generator writes is
# a TRUTHFUL description of the low-fidelity game it played.


def test_fidelity_defaults_match_play_games_own_defaults():
    """`FIDELITY_DEFAULTS` is the CLI's promise that "pass nothing" keeps the
    old behaviour exactly. It is a second copy of `play_game`'s defaults, so it
    is pinned against the signature itself -- a default that moves in
    `selfplay.py` and not here would silently change every corpus this tool
    writes."""
    import inspect

    import selfplay as sp

    sig = inspect.signature(sp.play_game).parameters
    for name, want in mf.FIDELITY_DEFAULTS.items():
        assert sig[name].default == want, (
            "mass_fast.FIDELITY_DEFAULTS[%r]=%r but play_game's default is %r"
            % (name, want, sig[name].default)
        )


def test_the_worker_passes_the_fidelity_knobs_into_the_game(tmp_path):
    """MUTATION GUARD: `_worker` plays the SAME seed twice, once at the
    defaults and once with `dice="table"`, and the two written result files
    must differ. Drop the `**fidelity` from the `play_game` call and both arms
    write the identical expected-value game, which is exactly the failure that
    went unnoticed.

    `dice` is the knob under test because it is the cheapest one that has a
    consumer (`movement="table"` costs ~190x the wall clock of a default game
    and would make this a minutes-long unit test)."""
    import json
    import os

    import pytest

    lists = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
    bank = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
    repo = Path(__file__).resolve().parents[4]
    seed = 300000
    l1, l2, _fa, _fb, _sz = mf.list_paths(seed, lists, mf.DEFAULT_SIZES)
    if not (bank.is_dir() and l1.exists() and l2.exists()):
        pytest.skip("needs the terrain bank + the private 6-faction AI-list corpus")

    def play(fidelity, sub):
        out = tmp_path / sub
        out.mkdir()
        mf._worker([seed], str(lists), str(repo), str(bank), str(out),
                   mf.DEFAULT_SIZES, 2, 1, fidelity)
        return json.load(open(out / ("core_s%d.json" % seed)))

    base = play(dict(mf.FIDELITY_DEFAULTS), "base")
    tray = play(dict(mf.FIDELITY_DEFAULTS, dice="table"), "tray")
    assert base["knobs"]["dice"] == "expected"
    assert tray["knobs"]["dice"] == "table"
    import selfplay as sp

    strip = lambda r: sp.result_digest({k: v for k, v in r.items() if k != "knobs"})
    assert strip(base) != strip(tray), (
        "dice=table wrote the same game as dice=expected -- the fidelity knobs "
        "are not reaching play_game"
    )
