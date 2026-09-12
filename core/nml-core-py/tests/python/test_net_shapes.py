"""Malformed network dimensions fail at load time with a public error."""
import json
from pathlib import Path

import nml_core
import pytest

from test_fitted import tiny_net
from test_policy_configuration import quality_sensitive_net

REPO = Path(__file__).resolve().parents[4]


@pytest.mark.parametrize("kind,matrix", [
    ("policy", "w1"), ("fitted", "unit_w1"),
    ("fitted", "unit_w2"), ("fitted", "head_w1"),
])
@pytest.mark.parametrize("extra", [False, True])
def test_every_weight_row_must_match_its_output_layer(tmp_path, kind, matrix, extra):
    net = quality_sensitive_net() if kind == "policy" else tiny_net()
    # A later row evades a first-row-only width check. Singleton unit_w2
    # still exercises the second layer independently from unit_w1.
    row = net[matrix][-1]
    if extra:
        row.append(0.0)
    else:
        row.pop()
    path = tmp_path / "ragged.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    core = nml_core.load(str(REPO))
    loader = core.load_policy_net if kind == "policy" else core.load_net
    with pytest.raises(nml_core.Unsupported, match="layer"):
        loader(str(path))


@pytest.mark.parametrize("extra", [False, True])
def test_fitted_output_weights_match_the_head_width(tmp_path, extra):
    net = tiny_net()
    if extra:
        net["head_w2"].append(0.0)
    else:
        net["head_w2"].pop()
    path = tmp_path / "head.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    with pytest.raises(nml_core.Unsupported, match="layer"):
        nml_core.load(str(REPO)).load_net(str(path))


@pytest.mark.parametrize("kind", ["policy", "fitted"])
def test_correctly_shaped_synthetic_networks_load(tmp_path, kind):
    net = quality_sensitive_net() if kind == "policy" else tiny_net()
    path = tmp_path / "valid.json"
    path.write_text(json.dumps(net), encoding="utf-8")
    core = nml_core.load(str(REPO))
    if kind == "policy":
        core.load_policy_net(str(path))
        assert core.has_policy_net()
    else:
        core.load_net(str(path))
        assert core.has_net()
