"""GATE D1-B6 (NML-1073 M5) — `tools/dice_gate.py` on the BUNDLED games.

The tool's own home is the 168-game arena corpus outside the repo. This file
runs the identical `run()` over the two games that already ship here — the
`shoot_replay` fixture (a shooting game) and the `melee_replay` one (a charge
game) — so all three checks and all three red knobs are exercised on every
machine, corpus or no corpus.

The fixtures are laid out under `tmp_path` under their ORIGINAL dir names,
because `dice_stream_gate.dice_seed_of` cross-checks the `dice_seed` in the
arena json against the `_s<seed>` suffix of the dir. That cross-check is the
reason the fixture dirs cannot simply be pointed at in place.

WHAT IS PINNED, and it is the B6 claim rather than any single number:

  * the GREEN arm: check A exact on both games, and every class row's buckets
    SUM to that class's activation count — a report that does not add up is a
    gate with somewhere to hide.
  * each RED knob moves ITS OWN check and leaves the other two at the green
    numbers. That is what makes them three reds and not one: a knob that
    reddened everything (`--mode off` in the B4 gate) proves the reporting
    channel, not the check.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import dice_gate as gate  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
#: fixture dir -> the corpus dir name it was copied from (its `_s<seed>` suffix
#: is what `dice_seed_of` cross-checks against the arena json's `dice_seed`).
GAMES = {
    "shoot_replay": "alien_hives_1000_vs_battle_brothers_1000_s33",
    "melee_replay": "alien_hives_1000_vs_change_disciples_1000_s31",
}


@pytest.fixture(scope="module")
def ref(tmp_path_factory) -> Path:
    """The two bundled games under their original names, as a `--ref` dir."""
    out = tmp_path_factory.mktemp("qbe_fixture")
    for src, name in GAMES.items():
        shutil.copytree(FIXTURES / src, out / name)
    return out


def summary(ref: Path, tmp_path: Path, red: str = "") -> tuple[int, dict]:
    """`gate.run` over the fixture ref, as (exit code, summary JSON)."""
    out = tmp_path / ("dice_gate_%s.json" % (red or "green"))
    code = gate.run(ref, str(REPO), 0, str(out), red, report_only=True)
    return code, json.loads(out.read_text())


# --------------------------------------------------------------- the units ---


def test_the_red_formula_is_a_one_pip_off_by_one_and_nothing_else():
    """`successes_red` keeps the natural-6 rule and moves the THRESHOLD: at 4+
    a recorded 4 stops counting, a 5 and a 6 still count. If this ever agreed
    with `successes` the `--red-formula` arm would be a no-op."""
    faces = [1, 3, 4, 5, 6]
    assert gate.successes(faces, 4) == 3
    assert gate.successes_red(faces, 4) == 2
    assert gate.successes_red([6], 7) == 1  # the natural 6 survives the break


def test_tallies_split_attack_from_defense_and_floor_the_unsaved():
    """Check B's number. More blocks than hits cannot mean negative wounds."""
    rolls = [("attack", 3, 4, [4, 5, 2], "AI (A)"), ("defense", 2, 5, [5, 6], "AI (B)")]
    assert gate.tallies(rolls) == (2, 2, 0)
    assert gate.tallies(rolls[:1]) == (2, 0, 2)


def test_classify_names_every_way_two_roll_lists_can_part():
    a = ("attack", 2, 4, [4, 5], "AI (A)")
    assert gate.classify([], []) == "both_silent"
    assert gate.classify([a], []) == "table_silent"
    assert gate.classify([], [a]) == "port_silent"
    assert gate.classify([a], [a]) == "full_equal"
    assert gate.classify([a], [("attack", 3, 4, [4, 5, 6], "AI (A)")]) == "shape"
    assert gate.classify([a], [("attack", 2, 4, [4, 5], "AI (B)")]) == "shape"
    assert gate.classify([a], [("attack", 2, 4, [1, 5], "AI (A)")]) == "faces"
    assert gate.classify([a], [a, a]) == "length"


# ---------------------------------------------------------------- the gate ---


def test_green_the_stream_is_exact_and_every_class_row_adds_up(ref, tmp_path):
    """The green arm, and the one structural claim the report makes about
    itself: check A exact on both fixtures, both activation classes present,
    and every class row's buckets adding up to that class's activation count.
    The B and C numbers are NOT pinned here — they are the D1 ladder's open
    measurement, held down by charge landing (D5) and per-model sighting (D6a),
    and a test that froze today's figures would break on the next rung."""
    code, s = summary(ref, tmp_path)
    assert code == 0                      # --report-only
    assert s["games"] == 2
    assert s["checks"]["stream_ok"] == 2, s["first"]["stream"]
    assert s["checks"]["rolls"] > 0
    assert s["classes"]["shooting"]["acts"] > 0
    assert s["classes"]["melee"]["acts"] > 0
    for name, row in s["classes"].items():
        assert sum(row[b] for b in gate.BUCKETS) == row["acts"], name
    assert s["totals"]["full_equal"] > 0, "the fixtures were chosen to contain equal acts"


def test_red_extra_draw_reddens_the_STREAM_and_only_the_stream(ref, tmp_path):
    """One burned draw shifts every recorded face by one, so check A must fall
    to 0/2. Checks B and C seed their own tray per activation and never see it."""
    green = summary(ref, tmp_path)[1]["checks"]
    code, s = summary(ref, tmp_path, "extra-draw")
    assert code == 0, "the tool's own red bar"
    assert s["checks"]["stream_ok"] == 0
    assert s["checks"]["tally_equal"] == green["tally_equal"]
    assert s["checks"]["next_equal"] == green["next_equal"]


def test_red_formula_reddens_the_TALLY_and_only_the_tally(ref, tmp_path):
    """Scoring the table's faces one pip off must cost check B activations and
    leave A and C exactly where the green arm left them."""
    green = summary(ref, tmp_path)[1]["checks"]
    code, s = summary(ref, tmp_path, "formula")
    assert code == 0
    assert s["checks"]["tally_red"] < s["checks"]["tally_equal"] == green["tally_equal"]
    assert s["checks"]["stream_ok"] == green["stream_ok"] == 2
    assert s["checks"]["next_equal"] == green["next_equal"]


def test_red_one_wound_reddens_the_NEXT_STATE_and_only_it(ref, tmp_path):
    """One wound is the smallest difference check C must never miss. No
    activation can pass both arms — port == table and port + 1 == table cannot
    both hold — so the count must drop, and on these fixtures to zero."""
    green = summary(ref, tmp_path)[1]["checks"]
    code, s = summary(ref, tmp_path, "one-wound")
    assert code == 0
    assert green["next_equal"] > 0, "the fixtures must contain acts C can agree on"
    assert s["checks"]["next_red"] < green["next_equal"]
    assert s["checks"]["next_equal"] == green["next_equal"]
    assert s["checks"]["stream_ok"] == green["stream_ok"] == 2
    assert s["checks"]["tally_equal"] == green["tally_equal"]
