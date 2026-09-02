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


def test_only_rule_bearer_names_union_the_game_header_and_the_act_state_profile():
    """BLOCK C1 follow-up — a rule granted MID-GAME by a spell is recorded
    only in the per-act state profile (the same state `core.state_of` replays),
    never in the game header: 93 qbg_ref acts carry "Hit & Run Fighter (spell)"
    on the ACTING unit that way and `--only-rule` saw none of them. The
    bearer check must union BOTH reads; the "(spell)" suffix folds off the
    same way `bearer_names` folds any parameter bracket."""
    header_prof = {"special_rules": ["Flying"]}
    act_prof = {"special_rules": ["Hit & Run Fighter (spell)"]}
    assert gate.only_rule_bearer_names(header_prof, act_prof) == {
        "Flying", "Hit & Run Fighter",
    }
    assert gate.only_rule_bearer_names({}, act_prof) == {"Hit & Run Fighter"}, \
        "a unit with no game-header profile at all still reads from the act state"
    assert gate.only_rule_bearer_names(header_prof, {}) == {"Flying"}, \
        "nothing granted mid-game: the state read adds nothing"


def test_only_rule_aura_resolves_to_the_base_die_shape():
    """Aura rung step 2 — `--only-rule "X Aura"` selects by the AURA name but
    must resolve to the BASE rule's own die shape. The import expansion puts
    the bare rule on the unit next to the aura label
    (opr_army_manager.gd:2117 / list_to_profile.py:350), so the BEARER gate
    already matches the full aura name — but `RULE_ROLL_SHAPE` knows the base
    only, so without the strip every aura fell back to Mend's (1, 1) and
    counted the wrong dice: a clean wrong 0."""
    primary = {"roll_kind": "attack", "count": 3, "target": 4}
    extra = {"roll_kind": "attack", "count": 3, "target": 4}
    mend_shaped = {"roll_kind": "attack", "count": 1, "target": 1}
    assert gate.is_rule_roll(extra, "Predator Shooter", primary) is True
    # RED before the strip: the aura read Mend's (1, 1) — matched nothing of
    # its base's shape and claimed any count-1 target-1 die instead.
    assert gate.is_rule_roll(extra, "Predator Shooter Aura", primary) is True, \
        "the aura resolves to its base's EXTRA_ATTACK_DIE shape"
    assert gate.is_rule_roll(mend_shaped, "Predator Shooter Aura", None) is False, \
        "EXTRA_ATTACK_DIE needs a preceding attack roll — Mend's fallback must not match"
    assert gate.shape_key("Predator Shooter Aura") == "Predator Shooter"
    # "Furious" has no RULE_ROLL_SHAPE entry (both names share the Mend
    # fallback today) — the parity must hold whichever way the base evolves.
    for roll in (mend_shaped, extra, {"roll_kind": "attack", "count": 2, "target": 5}):
        assert gate.is_rule_roll(roll, "Furious Aura") \
            == gate.is_rule_roll(roll, "Furious"), \
            "Furious Aura selects the same acts/shape as Furious"


def test_only_rule_aura_is_dice_free_like_its_base():
    """Block B5/B2b family: "Hit & Run Fighter" has NO roll of its own
    (`DICE_FREE_RULES`), so its aura name must never match a roll either.
    Without the strip the aura fell through to Mend's (1, 1) and claimed the
    bearer's ordinary count-1 attack die as the rule's own slot."""
    roll = {"roll_kind": "attack", "count": 1, "target": 1}
    assert gate.is_rule_roll(roll, "Hit & Run Fighter") is False
    assert gate.is_rule_roll(roll, "Hit & Run Fighter Aura") is False, \
        "the aura is dice-free like its base — never matches a roll"


def test_inject_split_aim_reuses_split_aim_and_leaves_covered_or_aligned_acts_alone():
    """The corpus's own aiming oracle (`shoot_replay_gate.split_aim`), folded
    onto one act: a shots.jsonl line naming a DIFFERENT unit than the recorded
    `shoot` key becomes the action's `split`. An act that already carries one,
    one `split_aim` cannot cover (no shots.jsonl line here), and one where
    every shot already agrees with the recorded target (nothing to inject)
    each come back UNCHANGED — the same three `split_aim` outcomes B4 already
    reads as "stay pooled"."""
    head = {"profiles": {"u1": {"name": "Squad A"}, "u2": {"name": "Squad B"}}}
    units = {"u1": {"alive": 3}, "u2": {"alive": 3}}
    shots = [{"member": "m1", "weapon": "w1", "target": "Squad B"}]
    action = {"shoot": "u1"}

    aimed_action, aimed = gate.inject_split_aim(head, shots, action, units)
    assert aimed is True
    assert aimed_action["split"] == [{"member": "m1", "weapon": "w1", "target": "u2"}]
    assert action == {"shoot": "u1"}, "the input action is never mutated in place"

    pre_split = {"shoot": "u1", "split": [{"target": "u2"}]}
    same, aimed2 = gate.inject_split_aim(head, shots, pre_split, units)
    assert (same, aimed2) == (pre_split, False)

    uncovered, aimed3 = gate.inject_split_aim(head, [], action, units)
    assert (uncovered, aimed3) == (action, False)

    aligned_shots = [{"member": "m1", "weapon": "w1", "target": "Squad A"}]
    aligned, aimed4 = gate.inject_split_aim(head, aligned_shots, action, units)
    assert (aligned, aimed4) == (action, False)


def test_split_unrecorded_flags_a_multi_attack_shooting_act_with_no_split_field():
    """NML-1150 GAP: two raw "attack"-shaped rolls under one shooting ordinal,
    no recorded `action.split` — the table split the volley, the recorder
    predates the field. One attack roll, a defense roll, a `split` field, or a
    non-shooting class must each leave it False."""
    two_attacks = [{"roll_kind": "attack"}, {"roll_kind": "attack"}]
    assert gate.split_unrecorded("shooting", two_attacks, {}) is True
    assert gate.split_unrecorded("shooting", two_attacks, {"split": [{"target": "b"}]}) is False
    one_attack = [{"roll_kind": "attack"}, {"roll_kind": "defense"}]
    assert gate.split_unrecorded("shooting", one_attack, {}) is False
    assert gate.split_unrecorded("melee", two_attacks, {}) is False


def test_pos_verdict_buckets_equal_moved_and_unknown():
    """Check C POS's own vocabulary — NML-1152 step 10, the position add-on
    check C never had: within tolerance is `pos_equal`, past it is bucketed
    by inches, and a combatant with no recorded position at all is
    `pos_unknown` — never counted a failure, on either side."""
    def state(a, b):
        return {"units": {"a": {"positions": a}, "b": {"positions": b}}}

    here = [[0.0, 0.0, 0.0]]
    assert gate.pos_verdict(state(here, here), state(here, here), ("a", "b"), 0.5) \
        == ("pos_equal", 0.0)

    moved = [[2 * gate.INCH_M, 0.0, 0.0]]
    bucket, gap = gate.pos_verdict(state(moved, here), state(here, here), ("a", "b"), 0.5)
    assert bucket == "pos_moved_3in"
    assert gap == pytest.approx(2.0)

    missing = state([], here)
    assert gate.pos_verdict(missing, state(here, here), ("a", "b"), 0.5) == ("pos_unknown", None)


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


def test_movement_table_sets_the_header_knob_and_rigid_clears_it(ref, tmp_path, monkeypatch):
    """NML-1152 S0: `--movement` must reach the twin as `knobs.movement` on
    EVERY game's header, not just be accepted by argparse. `table` sets it
    True; the default `rigid` sets it explicitly False, so a corpus's own
    stale knob can never leak through unclobbered."""
    real_load = gate.nml_core.load
    headers: list[dict] = []

    class HeaderSpy:
        def __init__(self, core):
            self._core = core

        def set_header(self, header):
            headers.append(header)
            return self._core.set_header(header)

        def __getattr__(self, name):
            return getattr(self._core, name)

    monkeypatch.setattr(gate.nml_core, "load", lambda repo: HeaderSpy(real_load(repo)))

    summary(ref, tmp_path)  # default: rigid
    assert headers and all(h["knobs"]["movement"] is False for h in headers)

    headers.clear()
    code = gate.run(ref, str(REPO), 0, str(tmp_path / "table.json"), "",
                     report_only=True, movement="table")
    assert code == 0
    assert headers and all(h["knobs"]["movement"] is True for h in headers)


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
