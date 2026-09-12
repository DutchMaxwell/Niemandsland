"""A captured charge-only bonus must not disappear or extend Rush moves."""
from pathlib import Path

import nml_core
import pytest


REPO = Path(__file__).resolve().parents[4]
IN2M = 0.0254


def line(charge, source="dynamic", epoch=10):
    # The fixture epoch is pinned to the NEW stamp: the charge-band READS sit
    # behind `acts::EPOCH_10_CHARGE_BAND` (rule_on(rules_epoch, 10)), so the
    # gate/movement/resolve tests need a fresh fixture at the bumped epoch.
    # Serialization itself is epoch-agnostic — the round-trip test below pins
    # 0/6/9 explicitly and must still preserve the charge key.
    profiles, units = {}, {}
    for key, player, x in (("a", 1, 0.0), ("b", 2, 14 * IN2M)):
        bands = {"advance": 6.0, "rush": 12.0}
        if charge is not None and key == "a":
            bands["charge"] = charge
        profiles[key] = dict(
            unit_id=key, name=key, quality=4, defense=4, tough=99,
            wounds_max=[99], model_count=1, base_radius=0.016,
            game_system="gf", faction_folder="robot_legions", special_rules=[],
            weapons=[dict(name="Sword", range=0, attacks=1, count=1, rules=[])],
            move_bands=bands if source == "profile" else {"advance": 6., "rush": 12.})
        units[key] = dict(player=player, alive=1, wounds=[99], radii=[0.016],
                          positions=[[x, 0., 0.]])
        if source == "dynamic":
            units[key]["bands"] = bands
    core = nml_core.load(str(REPO))
    core.set_header(dict(profiles=profiles, terrain=dict(cell_params=dict(
        grid_rotation_degrees=0., grid_size_inches=3., inches_to_meters=IN2M,
        table_size_feet=[6., 4.]), cells=[], walls=[], sandbox=[]),
        knobs=dict(rules_epoch=epoch, movement=True, charge_gate=True,
                   dangerous=False)))
    return core, core.state_of(dict(round=1, rounds_total=4, units=units))


@pytest.mark.parametrize("source", ["dynamic", "profile"])
@pytest.mark.parametrize("epoch", [0, 6, 9])
def test_charge_band_survives_import_and_round_trip(source, epoch):
    core, state = line(16., source, epoch)
    expected = {"advance": 6., "rush": 12., "charge": 16.}
    assert state.plain()["units"]["a"]["bands"] == expected
    assert core.state_of(state.plain()).plain()["units"]["a"]["bands"] == expected


@pytest.mark.parametrize("source", ["dynamic", "profile"])
@pytest.mark.parametrize("consumer", ["gate", "diagnostic", "resolve", "rush"])
def test_charge_only_reach_is_used_by_gate_and_movement(source, consumer):
    core, state = line(16., source)
    if consumer == "gate":
        assert core.charge_illegal_matrix(state)["a|b"] is False
    elif consumer == "diagnostic":
        move = core.charge_move(state, "a", "b")
        assert move["end"][0][0] / IN2M > 12.5
    elif consumer == "resolve":
        charged = core.resolve(state, dict(unit="a", kind=nml_core.CHARGE,
                                         charge="b", dest=[14 * IN2M, 0., 0.]))
        assert charged.plain()["units"]["a"]["positions"][0][0] / IN2M > 12.5
    else:
        rushed = core.resolve(state, dict(unit="a", kind=nml_core.RUSH,
                                        dest=[0., 0., 20 * IN2M]))
        assert rushed.plain()["units"]["a"]["positions"][0][2] / IN2M == pytest.approx(12., abs=0.001)


@pytest.mark.parametrize("source", ["dynamic", "profile"])
def test_missing_charge_keeps_legacy_rush_fallback(source):
    core, state = line(None, source)
    assert core.charge_illegal_matrix(state)["a|b"] is True
    assert state.plain()["units"]["a"]["bands"] == {"advance": 6., "rush": 12.}


def test_explicit_zero_charge_does_not_fall_back_to_rush():
    core, state = line(0.)
    plain = state.plain()
    plain["units"]["b"]["positions"] = [[4 * IN2M, 0., 0.]]
    state = core.state_of(plain)
    assert core.charge_illegal_matrix(state)["a|b"] is True


def test_charge_exposure_uses_charge_reach():
    core, state = line(16.)
    assert core.features(state, 2, incoming=[])["my_charge_exposed"] == 1.
    plain = state.plain()
    plain["units"]["a"]["bands"].pop("charge", None)
    assert core.features(core.state_of(plain), 2, incoming=[])["my_charge_exposed"] == 0.