"""GATE M3-3 (NML-1073) — Army-Forge list -> unit profile, in Python.

Two layers:

  * synthetic unit tests below — a tiny hand-built Army-Forge list JSON per
    case (combined-unit folding, a joined hero that stays SEPARATE, an
    upgrade-label item grant) — always run, no external data.

  * the CORPUS gate — profiles_from_list(list_p1) | profiles_from_list(list_p2)
    against every game's header in ~/selfplay_out/m3_oracle/ (the M3-0
    oracle), field by field. That corpus lives outside the repo (Godot
    self-play output, not a committed fixture) and the AI lists it was built
    from live in the private mission tracker (~/nml-mission/farm/ai_lists),
    so this half SKIPS wholesale when either directory is absent instead of
    failing a machine that never ran M3-0.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

from list_to_profile import (  # noqa: E402
    _rule_to_string,
    _rules_in_upgrade_label,
    profiles_from_army_forge_json,
    profiles_from_list,
)

# NML-1073 M3-3b: m3_oracle_v2 replaces m3_oracle as the gate corpus — the
# v1 games were recorded with core_selfplay's bare-"AP" bug (see
# _rule_to_string's docstring), so their header "profiles" no longer match
# this port's (correct) weapon-rule strings. m3_oracle stays on disk
# untouched for another builder's unrelated gate.
ORACLE_DIR = Path.home() / "selfplay_out" / "m3_oracle_v2"
AI_LISTS_DIR = Path.home() / "nml-mission" / "farm" / "ai_lists"


# === synthetic unit tests =====================================================


def _selection(
    sel_id: str,
    name: str,
    *,
    quality: int = 4,
    defense: int = 4,
    size: int = 1,
    rules: list[dict] | None = None,
    weapons: list[dict] | None = None,
    upgrades: list[dict] | None = None,
    join_to_unit: str | None = None,
    combined: bool = False,
) -> dict:
    sel: dict = {
        "id": sel_id,
        "selectionId": sel_id,
        "name": name,
        "quality": quality,
        "defense": defense,
        "size": size,
        "rules": rules or [],
        "weapons": weapons or [],
        "selectedUpgrades": upgrades or [],
    }
    if join_to_unit is not None:
        sel["joinToUnit"] = join_to_unit
        sel["combined"] = combined
    return sel


def test_combined_unit_folds_into_one_profile():
    """A combined:true partner (a champion bought INTO a squad) merges into
    ONE profile keyed by the host — pooled models/wounds, weapons and rules
    from BOTH selections, matching core_selfplay.gd:_units_from_list's
    two-pass fold."""
    data = {
        "gameSystem": "gf",
        "units": [
            _selection(
                "host",
                "Trooper Squad",
                size=4,
                rules=[{"name": "Fast"}],
                weapons=[{"name": "Rifle", "range": 24, "attacks": 1, "count": 4}],
            ),
            _selection(
                "partner",
                "Trooper Champion",
                size=1,
                rules=[{"name": "Tough(2)"}],  # base rule — NOT folded (see below)
                weapons=[{"name": "Power Sword", "range": 0, "attacks": 2, "count": 1}],
                upgrades=[{"option": {"label": "Veteran (Furious)"}}],
                join_to_unit="host",
                combined=True,
            ),
        ],
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=1)
    assert list(profiles.keys()) == ["p1_0_host"]
    prof = profiles["p1_0_host"]
    # pooled models: 4 host (tough 1, no Tough rule on the host) + 1 partner (tough 2)
    assert prof["model_count"] == 5
    assert prof["wounds_max"] == [1, 1, 1, 1, 2]
    # weapons from BOTH selections, host first
    assert [w["name"] for w in prof["weapons"]] == ["Rifle", "Power Sword"]
    # Fast (host's own base rule) + Furious (partner's UPGRADE-label grant) fold in;
    # the partner's own base rule (Tough(2)) does NOT — core_selfplay.gd only ever
    # copies a selection's base "rules" into special_rules at HOST creation time,
    # never for a combined partner (only used locally there for per-model tough).
    assert prof["special_rules"] == ["Fast", "Furious"]
    assert prof["tough"] == 1  # no "Tough(" in special_rules -> default floor
    assert prof["move_bands"] == {"advance": 8.0, "rush": 16.0}  # Fast: +2"/+4"


def test_joined_hero_stays_a_separate_unit():
    """A joinToUnit selection with combined:false (an attached HERO, not a
    combined-in champion) is its OWN profile — core_selfplay's loader never
    links it to its host (NML-1081: live attachment is import-path/MP-only),
    so attached_hero_rules on the host stays empty and the hero gets its own
    unit_id/profile entry."""
    data = {
        "gameSystem": "gf",
        "units": [
            _selection("host", "Trooper Squad", size=4),
            _selection(
                "hero",
                "Captain",
                rules=[{"name": "Hero"}],
                weapons=[{"name": "Energy Blade", "range": 0, "attacks": 3, "count": 1}],
                join_to_unit="host",
                combined=False,  # attached hero, not folded in
            ),
        ],
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=2)
    assert set(profiles.keys()) == {"p2_0_host", "p2_1_hero"}
    assert profiles["p2_0_host"]["model_count"] == 4
    assert profiles["p2_0_host"]["attached_hero_rules"] == []
    hero = profiles["p2_1_hero"]
    assert hero["model_count"] == 1
    assert hero["special_rules"] == ["Hero"]
    assert hero["weapons"][0]["name"] == "Energy Blade"


def test_upgrade_label_grants_an_item_rule():
    """An upgrade OPTION's parenthesized label tail grants a rule the raw
    "rules" array never carries (NML-1066) — "Archivist (Caster(2))" must
    show up in special_rules AND drive caster_value, exactly like
    core_selfplay.gd:_rules_in_upgrade_label + _append_selection."""
    assert _rules_in_upgrade_label("Archivist (Caster(2))") == ["Caster(2)"]
    data = {
        "gameSystem": "gf",
        "units": [
            _selection(
                "caster",
                "Adept",
                upgrades=[{"option": {"label": "Archivist (Caster(2))"}}],
            ),
        ],
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=1)
    prof = profiles["p1_0_caster"]
    assert prof["special_rules"] == ["Caster(2)"]
    assert prof["caster_value"] == 2


def test_weapon_swap_label_grants_nothing():
    """A weapon-swap upgrade's label ALSO carries a parenthesized tail (its
    profile, e.g. "A2, AP(1)") — that must NOT leak into special_rules
    (NML-1066 guard: any split token that looks like a weapon-profile field
    voids the whole label as a rule grant)."""
    assert _rules_in_upgrade_label('Energy Sword (A2, AP(1), Rending)') == []
    data = {
        "gameSystem": "gf",
        "units": [
            _selection(
                "swap",
                "Trooper",
                upgrades=[{"option": {"label": "Energy Sword (A2, AP(1), Rending)"}}],
            ),
        ],
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=1)
    assert profiles["p1_0_swap"]["special_rules"] == []


def test_weapon_rule_keeps_its_rating():
    """NML-1073 M3-3b: a weapon-level specialRules entry (e.g.
    {"name": "AP", "rating": 1}) carries no "label" — only "rating". The old
    label/name fallback silently dropped it to a bare "AP" (ap ends up 0);
    this must produce "AP(1)", with the weapon's derived "ap" field
    mirroring the rating."""
    assert _rule_to_string({"name": "AP", "rating": 1}) == "AP(1)"
    data = {
        "gameSystem": "gf",
        "units": [
            _selection(
                "u",
                "Unit",
                weapons=[
                    {
                        "name": "Reaper Rifle",
                        "range": 24,
                        "attacks": 1,
                        "count": 1,
                        "specialRules": [
                            {"name": "AP", "rating": 1},
                            {"name": "Blast", "rating": 3},
                        ],
                    }
                ],
            ),
        ],
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=1)
    weapon = profiles["p1_0_u"]["weapons"][0]
    assert weapon["rules"] == ["AP(1)", "Blast(3)"]
    assert weapon["ap"] == 1


def test_base_radius_is_the_32mm_trainer_default():
    """core_selfplay's loader never copies a list's "bases" field onto the
    unit, so every model falls back to the SAME 32 mm default regardless of
    what "bases" says — this port matches that (see module docstring)."""
    data = {
        "gameSystem": "gf",
        "units": [_selection("u", "Unit", size=1)],
        "bases": {"round": "60mm"},  # present in the JSON, ignored by the loader
    }
    profiles = profiles_from_army_forge_json(data, "test_faction", player=1)
    assert profiles["p1_0_u"]["base_radius"] == pytest.approx(0.016, abs=1e-9)


# === corpus gate ===============================================================


def _oracle_games() -> list[Path]:
    if not ORACLE_DIR.is_dir() or not AI_LISTS_DIR.is_dir():
        return []
    return sorted(p for p in ORACLE_DIR.iterdir() if (p / "acts.jsonl").is_file())


def _deep_eq(a, b) -> str | None:
    if isinstance(a, float) or isinstance(b, float):
        try:
            if math.isclose(float(a), float(b), rel_tol=0, abs_tol=1e-9):
                return None
        except (TypeError, ValueError):
            pass
        return None if a == b else f"{a!r} != {b!r}"
    if isinstance(a, dict) and isinstance(b, dict):
        for k in a:
            if k not in b:
                return f".{k}: missing"
            r = _deep_eq(a[k], b[k])
            if r:
                return f".{k}{r}"
        return None
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return f": length {len(a)} != {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            r = _deep_eq(x, y)
            if r:
                return f"[{i}]{r}"
        return None
    return None if a == b else f": {a!r} != {b!r}"


@pytest.mark.skipif(
    not ORACLE_DIR.is_dir() or not AI_LISTS_DIR.is_dir(),
    reason="M3-0 oracle corpus / private mission ai_lists not present on this machine",
)
@pytest.mark.parametrize("game_dir", _oracle_games(), ids=lambda p: p.name)
def test_matches_oracle_header(game_dir: Path):
    with open(game_dir / "acts.jsonl") as f:
        header = json.loads(f.readline())
    want = header["profiles"]
    left, right = game_dir.name.split("_vs_")
    right = right.rsplit("_s", 1)[0]  # strip the trailing "_s<seed>"
    got = profiles_from_list(AI_LISTS_DIR / f"{left}.json", 1)
    got.update(profiles_from_list(AI_LISTS_DIR / f"{right}.json", 2))
    assert set(want.keys()) <= set(got.keys())
    mismatches = []
    for uid, wprof in want.items():
        for k, wv in wprof.items():
            r = _deep_eq(wv, got[uid].get(k))
            if r:
                mismatches.append(f"{uid}.{k}{r}")
    assert not mismatches, "\n".join(mismatches)
