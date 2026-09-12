"""A loaded policy encoder follows the Core's legacy source-data override."""
import json
from pathlib import Path

import nml_core
import pytest

from test_state_epoch import shooting_line

REPO = Path(__file__).resolve().parents[4]


def quality_sensitive_net():
    # The own-side quality pool is phi[22 + 10]. With quality 2 an
    # ADVANCE scores -0.5 versus HOLD's 0; with legacy quality 4 it scores
    # +0.5. All weights and the loader selftest are synthetic.
    weights = [[0.0, 0.0, 0.0] for _ in range(93 + 20)]
    weights[32] = [1.0, 1.0, 0.0]
    weights[93 + nml_core.ADVANCE] = [2.0, 0.0, 1.0]
    return dict(schema="policy_net/1", state_dim=93, act_dim=20, hidden=3,
                w1=weights, b1=[-3.0, -3.0, 0.0], w2=[1.0, -1.0, -1.5], b2=0.0,
                selftest=dict(phi=[0.0] * 93, vecs=[[0.0] * 20], expected=[0.0]))


@pytest.mark.parametrize("clear", [False, True])
def test_policy_source_override_is_independent_of_load_order(tmp_path, clear):
    profiles, plain = shooting_line()
    profiles["shooter"]["quality"] = 2
    net_path = tmp_path / "policy.json"
    net_path.write_text(json.dumps(quality_sensitive_net()), encoding="utf-8")

    def first_kind(change_after_load):
        core = nml_core.load(str(REPO))
        core.set_header(dict(profiles=profiles,
                             knobs=dict(rules_epoch=9, top_k=1, horizon=1)))
        if clear:
            core.set_encoder_source_qd(4, 4)
        change = core.clear_encoder_source_qd if clear else lambda: core.set_encoder_source_qd(4, 4)
        if not change_after_load:
            change()
        core.load_policy_net(str(net_path))
        if change_after_load:
            change()
        result = core.plan_with_rollout(core.state_of(plain), 1, {},
                                        cands=True, policy_mode="order")
        assert result["used"], result
        return result["trace"]["scored"][0]["kind"]

    expected = nml_core.HOLD if clear else nml_core.ADVANCE
    assert first_kind(False) == expected, "the synthetic policy must distinguish both encodings"
    assert first_kind(True) == expected, "changing the Core must also update an already loaded policy"
