"""A1 (play test 29.10.2026): the army-book Lacerate never ignores Regeneration.

Lacerate only makes the target re-roll unmodified Defense 6s. The five committed mechanics maps
filed every "Lacerate" entry with `bypass_regen: true`, and tools/rules_mechanics_export.py wrote
it that way. The table (#1911) and the core skip that param for the Lacerate name, so the data must
say what the rule does. The primitive's other names (Ignores Regeneration, the Unstoppable scopes)
keep their bypass.

Run:  python3 -m pytest tools/test_rules_map_lacerate_regen.py
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SYSTEMS = ("gf", "gff", "aof", "aofr", "aofs")


def _entries(system: str, name: str) -> list[dict]:
    data = json.loads((REPO / "assets" / "solo" / f"rules_mechanics_{system}.json").read_text())
    books = [data.get("common", {})] + list(data.get("factions", {}).values())
    return [book[name] for book in books if name in book]


def test_committed_maps_lacerate_keeps_regeneration():
    seen = 0
    for system in SYSTEMS:
        for e in _entries(system, "Lacerate"):
            seen += 1
            assert e["primitive"] == "Lacerate", system
            assert e["params"]["bypass_regen"] is False, f"{system}: Lacerate must not bypass Regeneration"
    assert seen == 33
    # CONTROL: the name that IS the bypass keeps it.
    for system in SYSTEMS:
        for e in _entries(system, "Ignores Regeneration"):
            assert e["params"]["bypass_regen"] is True, system


def test_exporter_writes_lacerate_without_the_bypass():
    spec = importlib.util.spec_from_file_location("rme", REPO / "tools" / "rules_mechanics_export.py")
    rme = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rme)
    for system in SYSTEMS:
        assert rme.params_for(system, "Lacerate", "Lacerate") == {"bypass_regen": False}
        assert rme.params_for(system, "Lacerate", "Lacerate", {"bypass_regen": True}) == {"bypass_regen": False}
        assert rme.params_for(system, "Ignores Regeneration", "Lacerate") == {"bypass_regen": True}
