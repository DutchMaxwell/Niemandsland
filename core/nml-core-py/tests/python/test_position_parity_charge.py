"""Shared charge pins cross the diagnostic and simulator at the table epoch."""
import json
import math
from pathlib import Path

import nml_core
import pytest


@pytest.mark.parametrize('case_id', ['generated-charge-14', 'recorded-136'])
def test_charge_placement_and_snap_use_the_header_epoch(case_id):
    root = Path(__file__).resolve().parents[4]
    fixture_dir = root / 'test/fixtures/position_parity'
    case = next(c for c in json.loads((fixture_dir / 'cases.json').read_text())['cases'] if c['id'] == case_id)
    pins = json.loads((fixture_dir / 'charge_gates.json').read_text())
    pin = next(p for p in pins['cases'] if p['id'] == case_id)
    profiles = {u['id']: dict(u, unit_id=u['id'], name=u['id'], quality=4, defense=4,
        model_count=len(u['positions']), special_rules=u['rules'], weapons=[]) for u in case['units']}
    plain = {'round':case['round'], 'rounds_total':4, 'units':{
        u['id']:dict(u, alive=len(u['positions'])) for u in case['units']}}
    action = dict(case['action'], charge=case['action']['target'])
    plain['units'][action['unit']]['bands'] = {'advance':action['band_in'], 'rush':action['band_in']}
    endings = []
    for epoch in (0, 5, 6, 7):
        core = nml_core.load(str(root))
        core.set_header({'profiles':profiles, 'terrain':case['terrain'], 'knobs':{
            'movement':True, 'hero_attach':True, 'rules_epoch':epoch, 'dangerous':False}})
        state = core.state_of(plain)
        move = core.charge_move(state, action['unit'], action['target'])
        resolved = core.resolve(state, action).plain()
        assert move['end'] == resolved['units'][action['unit']]['positions']
        if epoch >= 6:
            assert max(math.dist(a,b) / .0254 for a,b in zip(move['end'],pin['expected_world'])) <= pins['tolerance_in']
            if pin['snap_in'] is None:
                assert move['snap_in'] is None
            else:
                assert abs(move['snap_in']-pin['snap_in']) <= pins['tolerance_in']
        endings.append(move['end'])
    assert endings[0] == endings[1]
    assert endings[2] == endings[3]
    assert endings[1] != endings[2]
