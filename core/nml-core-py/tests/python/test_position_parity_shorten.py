"""The movement diagnostic and simulator must consume the header's replay epoch."""
import json
from pathlib import Path

import nml_core
import pytest


@pytest.mark.parametrize(('case_id', 'covered'), [('recorded-003', True), ('recorded-144', True)])
def test_whole_unit_shorten_uses_the_header_epoch(case_id, covered):
    root = Path(__file__).resolve().parents[4]
    fixtures = json.loads((root / 'test/fixtures/position_parity/cases.json').read_text())
    case = next(c for c in fixtures['cases'] if c['id'] == case_id)
    profiles = {
        u['id']: dict(u, unit_id=u['id'], name=u['id'], quality=4, defense=4,
                      model_count=len(u['positions']), special_rules=u['rules'], weapons=[])
        for u in case['units']
    }
    plain = {'round': case['round'], 'rounds_total': 4, 'units': {
        u['id']: dict(u, alive=len(u['positions'])) for u in case['units']}}
    act = case['action']
    plain['units'][act['unit']]['bands'] = {'advance': act['band_in'], 'rush': act['band_in']}
    ends = []
    for epoch in (0, 5, 6, 7):
        core = nml_core.load(str(root))
        core.set_header({'profiles': profiles, 'terrain': case['terrain'], 'knobs': {
            'movement': True, 'hero_attach': True, 'rules_epoch': epoch, 'dangerous': False}})
        state = core.state_of(plain)
        move = core.plain_move(state, act['unit'], act['dest'], act['band_in'])
        resolved = core.resolve(state, act).plain()
        assert move['end'] == resolved['units'][act['unit']]['positions']
        assert move['shorten_covered'] == (epoch >= 6 and covered)
        ends.append(move['end'])
    assert ends[0] == ends[1]
    assert ends[2] == ends[3]
    assert (ends[1] != ends[2]) == covered
