"""GATE D0 (NML-1073 M5) — `tools/outcome_gate.py`'s COMPARISON LOGIC.

The tool's own home is the 168-game arena corpus outside the repo, and a whole
game there costs ~50 seconds — far too much for a test suite. What is pinned
here is therefore the half that decides the verdict and carries no dice at all:
the pick vocabulary, the per-game comparison, the dice-tape walk, and the ONE
synthetic red.

THE SYNTHETIC RED is `--red-swap-seats` on a hand-built pair: a game the twin
got exactly right, whose result is then read from the other seat, MUST stop
comparing equal. If it did not, the comparison would not be reading the seats
at all and every "identical result" in the tool's report would be worthless.
The draw case is pinned right next to it, because a draw with a symmetric
marker count IS seat-symmetric and survives the swap honestly — that is why
the tool reports the surviving draws instead of pretending the red is total.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import outcome_gate as gate  # noqa: E402


def _res(winner="p1", p1=2, p2=1, neutral=0, rounds=4, picks=None):
    return {"winner": winner, "rounds_played": rounds,
            "objectives": {"p1": p1, "p2": p2, "neutral": neutral},
            "picks": picks if picks is not None else [(1, "a", 0, ""), (2, "b", 3, "c")]}


# ------------------------------------------------------------- pick vocab ---


def test_pick_key_reads_seat_unit_kind_and_either_target():
    assert gate.pick_key(1, {"unit": "u", "kind": 3, "charge": "v"}) == (1, "u", 3, "v")
    assert gate.pick_key(2, {"unit": "u", "kind": 0, "shoot": "w"}) == (2, "u", 0, "w")


def test_pick_key_ignores_the_destination():
    """A charge that aims a millimetre differently is the same PICK — where it
    lands is D5-2's own gate's question, not this one's."""
    a = {"unit": "u", "kind": 2, "dest": [0.0, 0.0, 0.0]}
    b = {"unit": "u", "kind": 2, "dest": [9.0, 0.0, 9.0], "wave": "rush"}
    assert gate.pick_key(1, a) == gate.pick_key(1, b)


def test_pick_key_survives_an_act_without_an_action():
    """9 of the 717 recorded picks in `qbg_ref` carry no `action` at all."""
    assert gate.pick_key(1, None) == (1, "", -1, "")


def test_pick_class_names_the_first_field_to_part():
    base = (1, "u", 2, "t")
    assert gate.pick_class(base, (2, "u", 2, "t")) == "seat"
    assert gate.pick_class(base, (1, "v", 2, "t")) == "unit"
    assert gate.pick_class(base, (1, "u", 3, "t")) == "kind"
    assert gate.pick_class(base, (1, "u", 2, "s")) == "target"
    assert gate.pick_class(base, base) == "none"


# ----------------------------------------------------------------- verdict ---


def test_compare_identical_game_is_result_and_sequence():
    v = gate.compare(_res(), _res())
    assert (v["result"], v["sequence"], v["div_at"], v["margin_diff"]) == (True, True, None, 0)


def test_compare_same_result_different_picks_is_not_a_sequence():
    """The whole point of the SEQUENCE column: a Face-Off marker count is a
    coarse number, and two different games land on it often enough."""
    v = gate.compare(_res(), _res(picks=[(1, "a", 0, ""), (2, "z", 3, "c")]))
    assert v["result"] is True
    assert (v["sequence"], v["div_at"], v["div_class"]) == (False, 2, "unit")


def test_compare_parts_on_the_winner_and_on_the_markers_and_on_the_rounds():
    assert gate.compare(_res(), _res(winner="p2"))["result"] is False
    assert gate.compare(_res(), _res(p1=1, p2=2))["result"] is False
    assert gate.compare(_res(), _res(rounds=3))["result"] is False


def test_compare_reports_a_length_divergence_at_the_shorter_end():
    v = gate.compare(_res(), _res(picks=[(1, "a", 0, "")]))
    assert (v["div_at"], v["div_class"], v["sequence"]) == (2, "length", False)


def test_compare_measures_the_objective_margin_difference():
    assert gate.compare(_res(p1=3, p2=0), _res(p1=0, p2=3))["margin_diff"] == 6


# ------------------------------------------------------- the synthetic red ---


def test_red_swap_seats_breaks_a_game_the_twin_got_right():
    """THE RED. The twin's played game does not move — only the labels do — so
    a result the comparison scored right must score wrong from the other seat."""
    twin = _res()
    assert gate.compare(_res(), twin)["result"] is True
    assert gate.compare(_res(), gate.swap_seats(twin))["result"] is False


def test_red_swap_seats_leaves_a_symmetric_draw_standing():
    """And the honest exception the tool reports rather than hides: a draw on a
    symmetric marker count IS seat-symmetric."""
    drawn = _res(winner="draw", p1=1, p2=1, neutral=1)
    assert gate.compare(drawn, gate.swap_seats(drawn))["result"] is True


# --------------------------------------------------------------- dice tape ---


def _roll(kind="attack", count=2, target=4, faces=(3, 5), roll_kind=None):
    r = {"kind": kind, "count": count, "target": target, "faces": list(faces)}
    if roll_kind is not None:
        r = {"roll_kind": roll_kind, "count": count, "target": target, "faces": list(faces)}
    return r


def test_dice_divergence_none_when_the_streams_agree():
    rec = [_roll(roll_kind="attack"), _roll(roll_kind="defense", count=1, faces=(6,))]
    twin = [[_roll()], [_roll(kind="defense", count=1, faces=(6,))]]
    assert gate.dice_divergence(twin, rec) is None


def test_dice_divergence_folds_the_recorded_rule_kinds():
    """NML-1104: the corpus names the RULE behind a die ("morale", "dangerous",
    ...); the port stamps every combat die "attack"/"defense"."""
    assert gate.dice_divergence([[_roll(count=1, faces=(5,))]],
                                [_roll(roll_kind="morale", count=1, faces=(5,))]) is None


def test_dice_divergence_reports_the_twin_act_ordinal_of_the_first_mismatch():
    rec = [_roll(roll_kind="attack"), _roll(roll_kind="attack", count=3, faces=(1, 2, 3))]
    twin = [[_roll()], [_roll(count=2, faces=(1, 2))]]
    assert gate.dice_divergence(twin, rec) == 2


def test_dice_divergence_catches_a_tape_that_runs_out_and_one_left_over():
    assert gate.dice_divergence([[_roll()], [_roll()]], [_roll(roll_kind="attack")]) == 2
    assert gate.dice_divergence([[_roll()]],
                                [_roll(roll_kind="attack"), _roll(roll_kind="attack")]) == 2


# ------------------------------------------------------------- report bits ---


def test_bucket_is_fine_at_the_start_and_coarse_in_the_tail():
    assert [gate.bucket(n) for n in (1, 2, 3, 4, 6, 7, 12, 13, 99)] == \
        ["1", "2", "3", "4-6", "4-6", "7-12", "7-12", "13+", "13+"]
    assert gate.bucket(None) == "never"


def test_hist_keeps_the_given_order_and_drops_zeros():
    assert gate.hist(["b", "a", "b"], ("a", "b", "c")) == "a=1  b=2"
