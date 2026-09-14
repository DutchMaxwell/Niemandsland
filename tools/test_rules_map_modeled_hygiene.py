"""Registry-name hygiene: editing markers must not ship as modeled rule names.

The five spell-mechanics maps (assets/solo/rules_mechanics_<system>.json)
once listed "Sniper REMOVE" in their `modeled` arrays - a leftover editing
marker, not a rule (wave-4 accounting 2026-09-06, DROP ruling). A modeled
name is what `RulesRegistry.modeled_tokens()` serves, so the marker read as
"automated" to the game. The fix drops it from the arrays and parks the name
in the rule universe census's NA_NAMES beside "Unique".

Reads the committed maps directly (no private books needed) and the census's
own NA_NAMES table - exactly the two artefacts the fix edits.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CENSUS_TOOLS = REPO / "core" / "nml-core-py" / "tools"
sys.path.insert(0, str(CENSUS_TOOLS))

import rule_universe_census  # noqa: E402

SYSTEMS = ("gf", "gff", "aof", "aofr", "aofs")


def _modeled_names(system: str) -> list[str]:
    path = REPO / "assets" / "solo" / f"rules_mechanics_{system}.json"
    data = json.loads(path.read_text())
    return list(data["modeled"])


def test_no_modeled_name_is_an_editing_marker():
    offenders = sorted(
        f"{system}/{name}"
        for system in SYSTEMS
        for name in _modeled_names(system)
        if "REMOVE" in name
    )
    assert not offenders, (
        "an editing marker ships as a modeled rule name - drop it from the"
        f" modeled arrays and park it in NA_NAMES: {offenders}"
    )


def test_sniper_remove_is_parked_in_na_names():
    assert "Sniper REMOVE" in rule_universe_census.NA_NAMES, (
        "'Sniper REMOVE' is an editing marker, not a rule (wave-4 accounting"
        " 06.09.) - it belongs in NA_NAMES beside 'Unique'"
    )
