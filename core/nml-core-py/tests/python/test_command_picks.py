"""Ruling D16: the AoF: Skirmish command groups pick two friendly units once, at deployment end (selfplay writes them)."""
import nml_core
from selfplay import _write_command_picks


def test_the_binding_picks_the_two_nearest_living_friends():
    others = [("far", 1, True, (5.0, 0.0)), ("near", 1, True, (1.0, 0.0)), ("mid", 1, True, (2.0, 0.0)),
              ("foe", 2, True, (0.5, 0.0)), ("gone", 1, False, (0.2, 0.0))]
    assert nml_core.default_command_picks("aofs", ["Banner"], 1, (0.0, 0.0), others) == ["near", "mid"]
    assert nml_core.default_command_picks("aofs", [], 1, (0.0, 0.0), others) == [], "no command group"
    assert nml_core.default_command_picks("aof", ["Banner"], 1, (0.0, 0.0), others) == [], "aof has no picks"


def test_deployment_end_writes_the_picks_into_the_command_group_profile_only():
    unit = lambda key, rules: {"unit_id": key, "game_system": "aofs", "special_rules": rules}
    units1 = [unit("a", ["Banner"]), unit("b", []), unit("c", []), unit("d", [])]
    units2 = [unit("x", ["Musician"])]
    pos = {"a": [[0.0, 0.0, 0.0], [0.1, 0.0, 0.0]], "b": [[0.3, 0.0, 0.0]], "c": [[0.2, 0.0, 0.0]], "d": [[0.9, 0.0, 0.0]],
           "x": [[0.4, 0.0, 0.0]]}
    _write_command_picks(units1, units2, pos)
    assert units1[0]["command_picks"] == ["c", "b"]
    assert all("command_picks" not in u for u in units1[1:]), "no other profile changes"
    assert "command_picks" not in units2[0], "no friend placed: nothing to write"
