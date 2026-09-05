"""Public stdlib brain protocol; no native wheel or private model required."""
import json
from pathlib import Path
import sys
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

TOOLS = Path(__file__).resolve().parents[4] / "tools"
sys.path.insert(0, str(TOOLS))
import brain_server


def token():
    return {"units": [[0.0] * 72] * 24, "units_mask": [0] * 24,
            "objs": [[0.0] * 12] * 6, "objs_mask": [0] * 6,
            "terr": [[0.0] * 12] * 18, "terr_mask": [0] * 18,
            "glob": [0.0] * 16, "cands": [[0.0] * 40] * 160,
            "cands_mask": [0] * 160, "actor": [-1] * 160,
            "target": [-1] * 160, "label": -1}


def request():
    return {"schema": 1, "core_commit": "a" * 40, "rules_epoch": 6,
            "side": 2, "leaves": [token(), token()]}


@pytest.fixture
def server():
    instance = brain_server.make_server("127.0.0.1", 0, lambda states, side: [0.0] * len(states),
                                        {"name": "test-zero", "hash": "test-hash"})
    thread = threading.Thread(target=instance.serve_forever, daemon=True)
    thread.start()
    yield instance
    instance.shutdown()
    instance.server_close()
    thread.join()


def post(server, body, headers=None):
    req = Request("http://127.0.0.1:%d/" % server.server_port,
                  json.dumps(body).encode(), {"Content-Type": "application/json", **(headers or {})})
    return urlopen(req, timeout=2)


def test_dummy_batch_and_metadata(server):
    with post(server, request()) as response:
        assert json.load(response) == {"schema": 1, "values": [0.0, 0.0],
                                      "brain": {"name": "test-zero", "hash": "test-hash"}}


@pytest.mark.parametrize("field,value", [("schema", 2), ("schema", True), ("side", 0),
    ("side", True), ("core_commit", "short"), ("rules_epoch", -1), ("leaves", [{}])])
def test_bad_contract_refused(server, field, value):
    body = request()
    body[field] = value
    with pytest.raises(HTTPError) as error:
        post(server, body)
    assert error.value.code == 400


@pytest.mark.parametrize("values", [[0.0], [float("nan"), 0.0], [float("inf"), 0.0], [True, False]])
def test_invalid_scorer_output_refused(values):
    with pytest.raises(ValueError):
        brain_server.evaluate(request(), lambda states, side: values, {"name": "test", "hash": "x"})


def test_nonloopback_binding_refused():
    with pytest.raises(ValueError):
        brain_server.make_server("0.0.0.0", 0, lambda *_: [], {"name": "test", "hash": "x"})


def test_browser_origin_refused(server):
    with pytest.raises(HTTPError) as error:
        post(server, request(), {"Origin": "https://example.com"})
    assert error.value.code == 403


def test_load_dummy_module(monkeypatch):
    monkeypatch.setenv("NML_BRAIN_MODULE", "brain_dummy")
    scorer, identity = brain_server.load_scorer()
    assert scorer([token()], 1) == [0.0]
    assert identity["name"] == "dummy-zero"
    assert len(identity["hash"]) == 64
