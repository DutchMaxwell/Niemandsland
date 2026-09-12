"""Network selftests and state encoders must have compatible input shapes."""
import json
from pathlib import Path

import nml_core
import pytest

from test_fitted import tiny_net
from test_policy_configuration import quality_sensitive_net

REPO = Path(__file__).resolve().parents[4]


@pytest.mark.parametrize("width", [92, 94])
def test_policy_requires_the_state_width_its_encoder_produces(tmp_path, width):
    net = quality_sensitive_net()
    net["state_dim"] = width
    net["w1"] = [[0.0, 0.0, 0.0] for _ in range(width + net["act_dim"])]
    net["selftest"]["phi"] = [0.0] * width
    path = tmp_path / "policy-width.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    with pytest.raises(nml_core.Unsupported, match="state.*width|state_dim"):
        nml_core.load(str(REPO)).load_policy_net(str(path))


@pytest.mark.parametrize("fault", ["features_short", "features_long", "unit_short",
                                   "objective_short", "pair_missing", "slot_outside"])
def test_fitted_selftest_shapes_are_checked_before_forward(tmp_path, fault):
    net = tiny_net()
    test = net["selftest"]
    if fault == "features_short":
        test["features"] = []
    elif fault == "features_long":
        test["features"].append(0.0)
    elif fault == "unit_short":
        test["board"][0] = [1.0]
    elif fault == "objective_short":
        test["board"][1] = [3.0, 0.0, 0.0]
    elif fault == "pair_missing":
        test["board"][0][20] = 1.0
    elif fault == "slot_outside":
        net["slots"] = {"1": 1}
        net["unit_w1"].extend([[0.0], [0.0]])
        test["board"][0][20] = 1.0
        test["board"][0].extend([1.0, 1.0])
    path = tmp_path / "selftest.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    with pytest.raises(nml_core.Unsupported, match="selftest|slot"):
        nml_core.load(str(REPO)).load_net(str(path))


def test_fitted_selftest_accepts_a_compact_objective_row(tmp_path):
    net = tiny_net()
    net["selftest"]["board"][1] = [3.0, 0.0, 0.0, 0.0]
    path = tmp_path / "compact-objective.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    core = nml_core.load(str(REPO))
    core.load_net(str(path))
    assert core.has_net()
