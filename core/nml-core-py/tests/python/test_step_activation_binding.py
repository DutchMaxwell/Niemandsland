"""One-core P4.0-11 — the Python binding of the step API, `Core.step_activation`.

The same entry the Godot binding exposes as `NmlCore.step_activation`: one unit's
activation as the table's ordered inputs, answered `need_roll` / `open` / `need_choice` / `refused`
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
        # A `done` answer also carries the door-only `illegal` list (nobody moved here: empty).
        assert answer.get("illegal", []) == [], answer.get("illegal")
        plain = {k: v for k, v in answer.items() if k not in ("state", "illegal")}
        assert plain == call["answer"], f"call {i} ({call['answer']['step']}) differs from the record"

    # The `done` answer's new state is the volley's: "Hive Swarms" lost model slot 0.
    assert answer["state"].plain()["units"][record["target"]]["alive"] == 2

    # One malformed entry is the binding's refusal with the entry's index, never a silent drop.
    refused = core.step_activation(state, record["unit"], [{"t": "begin"}, {"t": "wat"}], record["enforce"])
    assert refused == {"step": "refused", "index": 1, "reason": "input 1 is not understood"}


def test_a_takedown_choice_is_asked_answered_and_refused_through_the_python_binding():
    """P4.0-5 on the Python seam: `{"t": "choice"}` goes in, `need_choice` comes out (the Godot seam's shape).

    The recorded shooter's rifle gets the Takedown rule (the header's profile is the only change); the
    target keeps its three living models, so the choice is open. An empty `option` asks the core."""
    import nml_core

    source = json.loads(SOURCE.read_text())
    record = json.loads(RECORD.read_text())
    unit, target = record["unit"], record["target"]
    for weapon in source["header"]["profiles"][unit]["weapons"]:
        if weapon["name"] == "Heavy Rifle":
            weapon["rules"].append("Takedown")
    core = nml_core.load(str(REPO))
    core.set_header(source["header"])
    state = core.state_of(source["state"])
    choice_id = f"takedown_model:{unit}:{target}"
    start = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": target}]

    asked = core.step_activation(state, unit, start + [{"t": "choice", "id": choice_id}], False)
    assert asked == {"step": "need_choice", "id": choice_id, "options": ["slot:0", "slot:1", "slot:2"], "owner": unit, "lines": [], "landings": []}

    # A valid answer reaches the dice: the core now asks for the volley's first roll.
    answered = core.step_activation(state, unit, start + [{"t": "choice", "id": choice_id, "option": "slot:1"}], False)
    assert answered["step"] == "need_roll"

    # A wrong option is the core's refusal at the choice's index, never a silent acceptance.
    wrong = core.step_activation(state, unit, start + [{"t": "choice", "id": choice_id, "option": "slot:9"}], False)
    assert (wrong["step"], wrong["index"]) == ("refused", 2) and "slot:9" in wrong["reason"]

    # A choice entry without an `id` is still the binding's own "not understood" refusal.
    bad = core.step_activation(state, unit, start + [{"t": "choice"}], False)
    assert bad == {"step": "refused", "index": 2, "reason": "input 2 is not understood"}


def test_a_cast_input_is_understood_and_refused_by_the_core_until_it_resolves_casts():
    """CC-4: `{"t": "cast", ..}` goes through the Python seam as an `Input::Cast`. The core resolves no cast yet (CC-3), so the
    answer is ITS refusal at the cast's index; "input 2 is not understood" would mean the binding dropped the input. A
    malformed field is the binding's refusal, never a default in disguise (the field-by-field read is pinned by
    `stepcall::tests::a_cast_input_keeps_every_field`)."""
    import nml_core

    source = json.loads(SOURCE.read_text())
    record = json.loads(RECORD.read_text())
    unit, target = record["unit"], record["target"]
    core = nml_core.load(str(REPO))
    core.set_header(source["header"])
    state = core.state_of(source["state"])
    start = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": target}]
    cast = {"t": "cast", "seq": 0, "caster": unit, "spell": "Bolt", "targets": [target], "base": 4, "threshold": 1,
            "boost": 1, "boost_sources": [[unit, 1]], "interference": 1, "interference_sources": [[target, 1]],
            "conduit": "", "conduit_shaken": [], "pools": [[1, [[target, 2]]]], "once": False, "open": False}

    # The fixture caster holds no spell "Bolt", so the core's own cast check (CC-5a) answers first; either way it is the core's cast
    # sentence ("cast 0: ..."), never "input 2 is not understood".
    refused = core.step_activation(state, unit, start + [cast], False)
    assert refused["step"] == "refused" and refused["index"] == 2 and refused["reason"].startswith("cast 0: "), refused

    # Only the required fields: understood too. A cast before the declared action: the core's order rule reads first.
    minimal = {k: cast[k] for k in ("t", "seq", "caster", "spell", "targets", "base", "threshold")}
    assert core.step_activation(state, unit, start + [minimal], False)["reason"].startswith("cast 0: ")
    early = core.step_activation(state, unit, [{"t": "begin"}, cast], False)
    assert early == {"step": "refused", "index": 1, "reason": "a cast before the action was declared"}

    for bad in ({"targets": target}, {"boost_sources": [[unit]]}, {"pools": [[1]]}, {"conduit": 3}, {"seq": "0"}):
        answer = core.step_activation(state, unit, start + [{**cast, **bad}], False)
        assert answer == {"step": "refused", "index": 2, "reason": "input 2 is not understood"}, bad
    assert core.step_activation(state, unit, start + [{k: v for k, v in cast.items() if k != "spell"}], False)["reason"] == "input 2 is not understood"


def test_check_rest_reads_the_recorded_board_clean_and_a_planted_overlap_illegal():
    """`Core.check_rest` - the legality checker over named unit keys, the Godot binding's shape.

    The recorded volley's shooter and target stand legally; the shooter's first model put onto the target's first
    model reads `overlap` naming that base. An unknown key is an error, never an empty (legal-looking) answer."""
    import nml_core
    import pytest

    source = json.loads(SOURCE.read_text())
    record = json.loads(RECORD.read_text())
    unit, target = record["unit"], record["target"]
    core = nml_core.load(str(REPO))
    core.set_header(source["header"])
    done = core.step_activation(core.state_of(source["state"]), unit, record["calls"][-1]["transcript"], record["enforce"])
    assert done["step"] == "done" and done["illegal"] == []
    assert core.check_rest(core.state_of(source["state"]), [unit, target]) == {"ok": True, "illegal": []}

    units = source["state"]["units"]
    units[unit]["positions"][0] = list(units[target]["positions"][0])
    planted = core.check_rest(core.state_of(source["state"]), [unit])
    assert planted["ok"] is False
    overlap = [i for i in planted["illegal"] if i["kind"] == "overlap"]
    assert overlap and overlap[0]["unit"] == unit and overlap[0]["model"] == 0 and overlap[0]["other"] == target, planted
    with pytest.raises(Exception, match="unknown unit"):
        core.check_rest(core.state_of(source["state"]), ["no such unit"])
