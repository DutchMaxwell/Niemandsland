"""Firefight golden G9b ("Firefight at epoch 109"): the G9 lists plus one Precision Charge carrier (alpha, played as
`orc_marauders`) and two units that carry Imprecise themselves (beta, played as `robot_legions` - self-play takes the
faction from the list FILE NAME, and the skirmish Imprecise row is faction-scoped), on the banked 48 x 48 tier board 1,
seed 1, table dice. Two digests are pinned: at epoch 108 and at 109, and they differ - so the 109 change (Precision
Charge and the unit's Imprecise firing in the skirmish books) is witnessed in a full self-play game, and either leg fails
on its own when a rules change moves it.
Epochs 104-108 do not move this game (measured 28.11.: the same digest at 104..108 on five banked boards - self-play never
pushes without an up-front intent, and no multi-hit Blast spread or ledge walk changed an outcome). They stay witnessed by
their step-API proofs: 104 `tests/sim/command_groups.rs` + `tests/deployment/skirmish_a_setup.rs`; 105
`tests/deployment/skirmish_a_setup.rs` + `test/core_terrain_tiers_test.gd`; 106 `tests/activation_skirmish_vertical.rs` +
`test/e2e/e2e_ft_07_jump_test.gd`; 107 `tests/activation_skirmish_vertical.rs`; 108 `tests/activation_blast_choice.rs` +
`tests/dice/skirmish_e9_blast.rs` + `test/e2e/e2e_ft_12_blast_test.gd`.
Hard checks as G9: 4 rounds, no unported branch, `unknown_rules` only on the ticketed allow-list."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIX = Path(__file__).resolve().parent / "fixtures" / "ff_g9b"
#: unknown_rules allowed only with a ticket id: the AI encoder's vocabulary gap (#3971), not a rules gap.
ALLOWED_UNKNOWN = {"Imprecise": "#3971", "Precision Charge": "#3971"}
DIGESTS = {
    108: "9ca2948a86825cea4c70fcea5cd2fd9b1334fa18b3b999911291ad72905c9b12",
    109: "a0d1657c96b7079345e60c6968a776e4f2453bc9f2775146227aff93a227d42a",
}


@pytest.mark.parametrize("epoch", sorted(DIGESTS))
def test_g9b_firefight_at_epoch_109_plays_as_pinned(epoch):
    res = sp.play_game(1, FIX / "orc_marauders_400.json", FIX / "robot_legions_400.json", REPO, FIX,
                       dice="table", rules_epoch=epoch)
    assert res["rounds_played"] == 4
    assert res["dice_tally"].get("unported_acts", 0) == 0, res["dice_tally"]
    assert [n for n in res["unknown_rules"] if n not in ALLOWED_UNKNOWN] == []
    assert sp.result_digest(res) == DIGESTS[epoch]


def test_g9b_the_two_legs_differ():
    """The 109 change must move this game: equal digests would make the 109 leg a blind copy of the 108 one."""
    assert DIGESTS[108] != DIGESTS[109]
