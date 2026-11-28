"""Firefight golden G9 (plan step 23): one full core self-play game - two made-up 400 pt gff lists, the empty 48 x 48 board,
seed 1, table dice, played at a FIXED rules epoch - with its result digest pinned. Every rules change that moves a Firefight
game moves this digest; a deliberate change re-pins it with the new digest in the diff.
Hard checks beside the digest (lead 28.11.): 4 rounds, every model deployed on the 48 x 48 table, no unported branch, and
`unknown_rules` (the AI row encoder's vocabulary report) empty or only names on the ticketed allow-list."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIX = Path(__file__).resolve().parent / "fixtures" / "ff_g9"
#: The epoch the digest was pinned at: a record replays at its own epoch, so a later bump does not move this golden.
EPOCH = 103
#: unknown_rules allowed only with a ticket id; these lists carry no unknown name today.
ALLOWED_UNKNOWN: dict[str, str] = {}
DIGEST = "1c2748b2678c8d63641596cfef91d86e6a8d28c1aee3a2daa20a9bca2056936e"


def test_g9_a_400_pt_firefight_game_plays_as_pinned(monkeypatch):
    placed: list[float] = []
    real = sp.deploy_zone

    def spy(*a, **k):
        out = real(*a, **k)
        placed.extend(max(abs(m[0]), abs(m[2])) / sp.IN2M for unit in out for m in unit)
        return out

    monkeypatch.setattr(sp, "deploy_zone", spy)
    res = sp.play_game(1, FIX / "goldtest_alpha_400.json", FIX / "goldtest_beta_400.json", REPO, FIX,
                       dice="table", rules_epoch=EPOCH)
    assert res["rounds_played"] == 4
    assert placed and max(placed) <= 24.0, "a model deployed off the 48 x 48 table"
    assert res["dice_tally"].get("unported_acts", 0) == 0, res["dice_tally"]
    assert [n for n in res["unknown_rules"] if n not in ALLOWED_UNKNOWN] == []
    assert sp.result_digest(res) == DIGEST
