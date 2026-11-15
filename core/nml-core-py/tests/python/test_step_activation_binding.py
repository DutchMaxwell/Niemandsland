"""One-core P4.0-11 — the Python binding of the step API, `Core.step_activation`.

The same entry the Godot binding exposes as `NmlCore.step_activation`: one unit's
activation as the table's ordered inputs, answered `need_roll` / `open` / `refused`
/ `done` / `cancelled`. This test drives one plain volley (a HOLD shot) with
supplied faces to `done` and compares every answer to the recorded fixture.

THE RECORD. `fixtures/step_activation/sho_par_f3_volley.json` was recorded from
`nml_core::activation::step_activation` on the Godot binding's step seams
(`moved_shoot`, `sighting`, `shelf_sight` — `actcall.rs::seams_for_step`) and in
`actcall::run`'s answer shape. The header and state come verbatim from the
recorded activation `fixtures/sho_par_f3/act15.json` (the "Pathfinders" HOLD
shot at "Hive Swarms"). The binding's `"handle"` is the state object under
`"state"` here; every other key is the binding's.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SOURCE = FIXTURES / "sho_par_f3" / "act15.json"
RECORD = FIXTURES / "step_activation" / "sho_par_f3_volley.json"


def test_the_python_step_activation_matches_the_recorded_binding_answer():
    import nml_core

    source = json.loads(SOURCE.read_text())
    record = json.loads(RECORD.read_text())
    core = nml_core.load(str(REPO))
    core.set_header(source["header"])
    state = core.state_of(source["state"])

    calls = record["calls"]
    assert [call["answer"]["step"] for call in calls] == ["need_roll", "need_roll", "done"]
    assert calls[-1]["answer"]["delta"][0]["removed"] == [0]

    for i, call in enumerate(calls):
        answer = core.step_activation(state, record["unit"], call["transcript"], record["enforce"])
        plain = {k: v for k, v in answer.items() if k != "state"}
        assert plain == call["answer"], f"call {i} ({call['answer']['step']}) differs from the record"

    # The `done` answer's new state is the volley's: "Hive Swarms" lost model slot 0.
    assert answer["state"].plain()["units"][record["target"]]["alive"] == 2

    # One malformed entry is the binding's refusal with the entry's index, never a silent drop.
    refused = core.step_activation(state, record["unit"], [{"t": "begin"}, {"t": "wat"}], record["enforce"])
    assert refused == {"step": "refused", "index": 1, "reason": "input 1 is not understood"}
