"""GATE for the Transport(X) loader wiring (wave 4 follow-up, 07.09.2026) —
synthetic, no external corpus.

THE HOLE this guards: the deployment seam was dead by construction —
`deploy_unit_specs` hard-coded `"transport_capacity": 0`, so the core's
transport fill (deployment.rs::transport_fill, fed at :1052-1054) drew
nothing for ANY list ("exact for the transport-free corpus lists",
deployment.rs:222). The port wires the table's own parse into the loader:
`TransportState.capacity_of_rules` (transport_state.gd:64-77, reached via
opr_army_manager.gd:2870-2874 `transport_capacity`) reads the unit's OWN
"Transport(X)" rule string, registry params ignored.

The wave-4 frozen-constant law gates the new read: a record stamped below
`EPOCH_7_TABLE_RULES` replays the transport-free seam. The read lives
py-side (the loader builds the UnitSpec), so the gate lives py-side too —
`rule_on`'s loader leg — with the constant taken off `nml_core`, never the
literal 7, so a later epoch bump cannot silently re-arm old records.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import list_to_profile  # noqa: E402
import selfplay as sp  # noqa: E402


def _selection(
    sel_id: str,
    name: str,
    *,
    size: int = 1,
    rules: list[dict] | None = None,
    loadout: list[dict] | None = None,
    join_to_unit: str | None = None,
) -> dict:
    sel: dict = {
        "id": sel_id,
        "selectionId": sel_id,
        "name": name,
        "quality": 4,
        "defense": 4,
        "size": size,
        "rules": rules or [],
        "weapons": [],
        "selectedUpgrades": [],
    }
    if loadout is not None:
        sel["loadout"] = loadout
    if join_to_unit is not None:
        sel["joinToUnit"] = join_to_unit
        sel["combined"] = False
    return sel


def _spec_caps(data: dict) -> dict:
    specs, _fold = list_to_profile.deploy_unit_specs(data, "test_faction", 1)
    return {s["key"]: s["transport_capacity"] for s in specs}


def test_a_transport_rule_fills_the_dead_seam():
    """The unit's OWN rule string is the parse source — the table's
    capacity_of_rules law (registry params ignored), first match wins."""
    data = {
        "gameSystem": "gf",
        "units": [
            _selection("t", "Heavy Tank", rules=[{"name": "Transport", "label": "Transport(21)"}]),
            _selection("g", "Grunts", size=10),
        ],
    }
    caps = _spec_caps(data)
    assert caps["p1_0_t"] == 21
    assert caps["p1_1_g"] == 0


def test_an_item_granted_transport_fills_the_seam():
    """A loadout item's granted rule rides the rule line already
    (_selection_rules -> "Transport(6)" via _rule_to_string) — the same set
    the table's get_special_rules carries, so the parse sees it."""
    data = {
        "gameSystem": "gf",
        "units": [
            _selection(
                "t",
                "Cargo Truck",
                loadout=[{"name": "Cargo Hold", "count": 1, "specialRules": [{"name": "Transport", "rating": 6}]}],
            ),
        ],
    }
    assert _spec_caps(data)["p1_0_t"] == 6


def test_a_joined_hero_never_grants_the_host_capacity():
    """The spec is the HOST's — capacity_of_rules reads the host unit's own
    rules (opr_army_manager.gd:2870-2874), never a folded hero's."""
    data = {
        "gameSystem": "gf",
        "units": [
            _selection("host", "Grunts", size=10),
            _selection(
                "h", "Vradhez", join_to_unit="host", rules=[{"name": "Transport", "label": "Transport(9)"}]
            ),
        ],
    }
    assert _spec_caps(data)["p1_0_host"] == 0


def test_the_gate_keeps_a_pre_epoch7_record_transport_free():
    """The frozen-constant gate: below EPOCH_7_TABLE_RULES the seam stays
    dead — a corpus recorded before the port replays transport-free."""
    roster = [{"key": "t", "transport_capacity": 21}, {"key": "g", "transport_capacity": 0}]
    sp._gate_transport_fill(roster, nml_core.EPOCH_7_TABLE_RULES - 1)
    assert roster[0]["transport_capacity"] == 0
    assert roster[1]["transport_capacity"] == 0


def test_the_gate_leaves_an_epoch7_record_alive():
    """At the frozen epoch the parsed X survives the gate — fresh records
    stamp `CURRENT_RULES_EPOCH`, so the live fill is the shipped default."""
    roster = [{"key": "t", "transport_capacity": 21}]
    sp._gate_transport_fill(roster, nml_core.EPOCH_7_TABLE_RULES)
    assert roster[0]["transport_capacity"] == 21
    sp._gate_transport_fill(roster, nml_core.CURRENT_RULES_EPOCH)
    assert roster[0]["transport_capacity"] == 21
