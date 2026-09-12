"""Standalone Python state imports enforce the corpus Spawn template contract."""
from copy import deepcopy
from pathlib import Path

import nml_core
import pytest

REPO = Path(__file__).resolve().parents[4]

CARRIER = {'unit_id': 'p1_0_a',
 'name': 'A',
 'quality': 4,
 'defense': 3,
 'tough': 2,
 'wounds_max': [2, 2, 2],
 'model_count': 3,
 'caster_value': 0,
 'base_radius': 0.02,
 'game_system': 'gf',
 'faction_folder': 'ratmen_clans',
 'special_rules': ['Spawn(Rat Swarm [2])'],
 'item_grants': [],
 'attached_hero_rules': [],
 'move_bands': {'advance': 6.0, 'rush': 12.0},
 'weapons': []}

ENEMY = {'unit_id': 'p2_0_b',
 'name': 'B',
 'quality': 4,
 'defense': 3,
 'tough': 1,
 'wounds_max': [1],
 'model_count': 1,
 'caster_value': 0,
 'base_radius': 0.02,
 'game_system': 'gf',
 'faction_folder': 'ratmen_clans',
 'special_rules': [],
 'item_grants': [],
 'attached_hero_rules': [],
 'move_bands': {'advance': 6.0, 'rush': 12.0},
 'weapons': []}

TEMPLATE = {'unit_id': 'spawn:p1_0_a:Spawn(Rat Swarm [2])',
 'name': 'Rat Swarm',
 'quality': 4,
 'defense': 3,
 'tough': 1,
 'wounds_max': [4, 4],
 'model_count': 2,
 'caster_value': 0,
 'base_radius': 0.03,
 'game_system': 'gf',
 'faction_folder': 'ratmen_clans',
 'special_rules': [],
 'item_grants': [],
 'attached_hero_rules': [],
 'move_bands': {'advance': 6.0, 'rush': 12.0},
 'weapons': []}

PLAIN_STATE = {'round': 1,
 'rounds_total': 4,
 'scoring': 'end',
 'units': {'p1_0_a': {'player': 1,
                      'alive': 3,
                      'wounds': [2, 2, 2],
                      'radii': [0.02, 0.02, 0.02],
                      'positions': [[0.0, 0.0, 0.0], [0.05, 0.0, 0.0], [-0.05, 0.0, 0.0]],
                      'in_cover': False,
                      'shaken': False,
                      'fatigued': False,
                      'activated': False,
                      'casts': 0,
                      'morale_bonus': 0,
                      'aircraft': False,
                      'dormant': False,
                      'ambush_arrived_round': -1,
                      'earliest_arrival_round': -1,
                      'wound_frac': 0.0,
                      'mods': {},
                      'mods_base': {},
                      'bands': {'advance': 6.0, 'rush': 12.0}},
           'p2_0_b': {'player': 2,
                      'alive': 1,
                      'wounds': [1],
                      'radii': [0.02],
                      'positions': [[1.0, 0.0, 0.0]],
                      'in_cover': False,
                      'shaken': False,
                      'fatigued': False,
                      'activated': False,
                      'casts': 0,
                      'morale_bonus': 0,
                      'aircraft': False,
                      'dormant': False,
                      'ambush_arrived_round': -1,
                      'earliest_arrival_round': -1,
                      'wound_frac': 0.0,
                      'mods': {},
                      'mods_base': {},
                      'bands': {'advance': 6.0, 'rush': 12.0}}}}

def load_state(epoch, *, template=False, dormant=False, dead=False):
    core = nml_core.load(str(REPO))
    header = {"profiles": {"p1_0_a": CARRIER, "p2_0_b": ENEMY},
              "knobs": {"rules_epoch": epoch}}
    if template:
        header["spawn_profiles"] = {TEMPLATE["unit_id"]: TEMPLATE}
    core.set_header(header)
    plain = deepcopy(PLAIN_STATE)
    carrier = plain["units"]["p1_0_a"]
    carrier["dormant"] = dormant
    if dead:
        carrier["alive"] = 0
        for field in ("positions", "wounds", "radii"):
            carrier[field] = []
    return core.state_of(plain)


@pytest.mark.parametrize("epoch", [8, 9])
def test_standing_spawn_carrier_requires_its_template(epoch):
    with pytest.raises(nml_core.Unsupported, match="no spawn_profiles template for unit key p1_0_a"):
        load_state(epoch)


@pytest.mark.parametrize("epoch", [8, 9])
@pytest.mark.parametrize("options", [{"template": True}, {"dead": True}, {"dormant": True}])
def test_spawn_template_or_exempt_carrier_loads(epoch, options):
    state = load_state(epoch, **options)
    assert state.keys() == ["p1_0_a", "p2_0_b"]


@pytest.mark.parametrize("epoch", [0, 7])
def test_legacy_spawn_carrier_needs_no_template(epoch):
    assert load_state(epoch).keys() == ["p1_0_a", "p2_0_b"]
