"""Shared sidestep limits survive simulation and plain-state round trips."""
import json
import math
from pathlib import Path

import nml_core
import pytest


@pytest.mark.parametrize('case_id', ['recorded-144', 'recorded-077'])
def test_boxed_budget_and_round_reset_use_the_shared_pins(case_id):
    root = Path(__file__).resolve().parents[4]
    directory = root / 'test/fixtures/position_parity'
    cases = json.loads((directory / 'cases.json').read_text())['cases']
    fixture = next(c for c in cases if c['id'] == case_id)
    pins = json.loads((directory / 'boxed_escape.json').read_text())
    pin = next(p for p in pins['cases'] if p['id'] == case_id)
    budget = json.loads((directory / 'boxed_budget.json').read_text())
    profiles = {u['id']: dict(u, unit_id=u['id'], name=u['id'], quality=4, defense=4,
        model_count=len(u['positions']), special_rules=u['rules'], weapons=[]) for u in fixture['units']}
    action = fixture['action']
    for probe in budget['probes']:
        plain = {'round': fixture['round'] + int(probe['new_round']), 'rounds_total': 4,
            'sidestep_budget': {'round': fixture['round'], 'used': probe['used']},
            'units': {u['id']: dict(u, alive=len(u['positions'])) for u in fixture['units']}}
        plain['units'][action['unit']]['bands'] = {'advance':action['band_in'], 'rush':action['band_in']}
        core = nml_core.load(str(root))
        core.set_header({'profiles': profiles, 'terrain':fixture['terrain'], 'knobs': {
            'movement':True, 'hero_attach':True, 'rules_epoch':6, 'dangerous':False}})
        state = core.state_of(plain)
        move = core.plain_move(state,action['unit'],action['dest'],action['band_in'])
        resolved = core.resolve(state,action).plain()
        keys = state.keys()
        assert move['end'] == [resolved['units'][keys[u]]['positions'][m] for u,m in move['movers']]
        left = budget['limit'] if probe['new_round'] else budget['limit']-probe['used']
        big = case_id == 'recorded-077'
        allowed = big or left > 0
        spent = not big and allowed
        assert move['sidestep_spent'] == spent
        delta = max(math.dist(a,b)/.0254 for a,b in zip(move['end'],pin['expected_world']))
        assert (delta <= pins['tolerance_in']) == allowed
        counter = resolved.get('sidestep_budget',{})
        remaining = budget['limit'] - counter.get('used',0) if counter.get('round') == resolved['round'] else budget['limit']
        assert remaining == left-int(spent)
        assert core.state_of(resolved).plain().get('sidestep_budget') == resolved.get('sidestep_budget')
