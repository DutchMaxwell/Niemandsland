"""SELFPLAY-BOARD: self-play plays a game on its list's rules-book table (`nml_core.book_board_in`), not on a fixed 72 x 48.
A Firefight game deploys inside the 48 x 48 table; a gf game keeps the 72 x 48 front line it always had."""
import json
import sys
from pathlib import Path

import nml_core
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIX = Path(__file__).resolve().parent / "fixtures" / "ff_g9"
ALPHA, BETA = FIX / "goldtest_alpha_400.json", FIX / "goldtest_beta_400.json"


def test_the_book_tables():
    assert list(nml_core.book_board_in("gff")) == [48.0, 48.0]
    assert list(nml_core.book_board_in("aofs")) == [48.0, 48.0]
    assert list(nml_core.book_board_in("gf")) == [72.0, 48.0]


def _deployed(monkeypatch, path_a, path_b) -> list[list[float]]:
    """The models `deploy_zone` placed in a real `play_game`, in inches [x, z]."""
    placed: list[list[float]] = []
    real = sp.deploy_zone

    def spy(*a, **k):
        out = real(*a, **k)
        placed.extend([m[0] / sp.IN2M, m[2] / sp.IN2M] for unit in out for m in unit)
        return out

    monkeypatch.setattr(sp, "deploy_zone", spy)
    sp.play_game(1, path_a, path_b, REPO, FIX)
    return placed


def test_a_firefight_game_deploys_inside_the_48_in_table(monkeypatch):
    placed = _deployed(monkeypatch, ALPHA, BETA)
    assert placed, "the game deployed nothing - the spy saw no deploy_zone"
    assert max(abs(x) for x, _ in placed) <= 24.0, "a model deployed off the 48 x 48 table"
    assert max(abs(z) for _, z in placed) <= 24.0
    assert (sp.TABLE_W_IN, sp.TABLE_D_IN) == (72.0, 48.0), "the module table is restored after the game"


def test_a_gf_game_keeps_the_72_in_front_line(monkeypatch, tmp_path):
    lists = []
    for src in (ALPHA, BETA):
        data = json.loads(src.read_text(encoding="utf-8"))
        data["gameSystem"] = "gf"
        dst = tmp_path / src.name.replace("goldtest", "goldtestgf")
        dst.write_text(json.dumps(data), encoding="utf-8")
        lists.append(dst)
    board = json.loads((FIX / "board_1.json").read_text(encoding="utf-8"))
    board["terrain"]["cell_params"]["table_size_feet"] = [6.0, 4.0]
    (tmp_path / "board_1.json").write_text(json.dumps(board), encoding="utf-8")
    placed: list[list[float]] = []
    real = sp.deploy_zone

    def spy(*a, **k):
        out = real(*a, **k)
        placed.extend([m[0] / sp.IN2M, m[2] / sp.IN2M] for unit in out for m in unit)
        return out

    monkeypatch.setattr(sp, "deploy_zone", spy)
    sp.play_game(1, lists[0], lists[1], REPO, tmp_path)
    assert max(abs(x) for x, _ in placed) > 24.0, "a gf front line still spans the 72 in table"


def test_a_banked_board_of_another_size_with_terrain_is_refused(tmp_path):
    board = json.loads((FIX / "board_1.json").read_text(encoding="utf-8"))
    board["terrain"]["cell_params"]["table_size_feet"] = [6.0, 4.0]
    board["terrain"]["cells"] = [[1, 1, 2]]
    (tmp_path / "board_1.json").write_text(json.dumps(board), encoding="utf-8")
    with pytest.raises(ValueError, match="no terrain bank for that table"):
        sp.play_game(1, ALPHA, BETA, REPO, tmp_path)
