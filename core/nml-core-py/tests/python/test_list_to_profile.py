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

import list_to_profile  # noqa: E402
from list_to_profile import (  # noqa: E402
    _rule_to_string,
    _rules_in_upgrade_label,
    base_shape_of,
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

#: NML-1097 — base_radius. `tools/core_selfplay.gd:_units_from_list` never
#: copies a list's "bases" onto `unit_properties`, so every unit in an M3
#: corpus header was recorded at the 32 mm fallback; the ARENA, importing the
#: SAME list through the table's own path, records the real radius.
#: NML-1098 — special_rules, item_grants, move_bands, tough, caster_value.
#: `tools/core_selfplay.gd` parses rule names out of upgrade LABEL text and
#: never reads a list's items, item grants or auras, so every M3 corpus
#: header was recorded without them; the ARENA, importing the SAME lists
#: through the table's own path, records all of them.
#: Both are fields this loader deliberately no longer reproduces field for
#: field: the trainer now follows the table, so this corpus can no longer
#: gate these columns — `tools/loader_gate.py` (against the arena's act
#: headers) does, and it is the stronger oracle. Everything else below still
#: has to match core_selfplay exactly.
DIVERGED_FROM_CORE_SELFPLAY = (
    "base_radius",
    "special_rules",
    "item_grants",
    "move_bands",
    "tough",
    "caster_value",
)


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
    two-pass fold and, since NML-1098, `_merge_combined_units`' rule fold."""
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
                rules=[{"name": "Tough(2)"}],  # base rule — folded (see below)
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
    # NML-1098: the partner's own rule line folds into the anchor, deduped —
    # `_merge_combined_units` (opr_api_client.gd:1402-1404). "Furious" does NOT:
    # an upgrade LABEL is not a rule source on the table, only `option.gains` is,
    # and every one of the 6741 selectedUpgrades in both AI list pools has none.
    assert prof["special_rules"] == ["Fast", "Tough(2)"]
    # FLAGGED, the table's own reading: a merged Tough(2) champion makes the
    # WHOLE squad read Tough(2) at unit level while per-model wounds stay 1 — the
    # per-model Tough guard exists for ITEMS (:809-811) and not for this merge.
    # Ported as the table has it; no unit in qbf_ref exercises the difference.
    assert prof["tough"] == 2
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


def _item(name: str, granted: list[str], count: int = 1, weapon: str | None = None) -> dict:
    """One resolved non-weapon `loadout` entry, in Army Forge's own shape."""
    content: list[dict] = [{"type": "ArmyBookRule", "name": g} for g in granted]
    if weapon:
        content.append({"type": "ArmyBookWeapon", "name": weapon, "attacks": 2})
    return {"name": name, "type": "ArmyBookItem", "count": count, "content": content}


def test_an_items_name_and_its_rules_reach_the_rule_line():
    """NML-1098, `_parse_tts_unit` :790-813: a unit-wide loadout item puts its
    OWN name on the rule line and then every rule it grants, in that order, and
    the grants are also indexed by item for the registry."""
    sel = _selection("u", "Trooper", rules=[{"label": "Strider"}])
    sel["loadout"] = [_item("Combat Bio-Engineer", ["Furious Aura"])]
    prof = profiles_from_army_forge_json(
        {"gameSystem": "gf", "units": [sel]}, "test_faction", player=1
    )["p1_0_u"]
    assert prof["special_rules"] == [
        "Strider",
        "Combat Bio-Engineer",
        "Furious Aura",
        "Furious",  # the aura pass, below
    ]
    assert prof["item_grants"] == ["Furious Aura"]


def test_a_per_model_item_stays_off_the_rule_line_and_keeps_its_tough():
    """An item only a SUBSET of the models carry is per-model equipment: its
    name never joins the unit rule line, and a Tough(X) it grants must not buff
    the whole squad (:803-813). Its other rules still apply unit-wide."""
    sel = _selection("u", "Squad", size=5)
    sel["loadout"] = [_item("Weapon Team", ["Tough(3)", "Shielded"], count=1)]
    prof = profiles_from_army_forge_json(
        {"gameSystem": "gf", "units": [sel]}, "test_faction", player=1
    )["p1_0_u"]
    assert prof["special_rules"] == ["Shielded"]
    assert prof["tough"] == 1
    assert prof["item_grants"] == ["Tough(3)", "Shielded"]


def test_an_item_that_grants_a_weapon_loses_that_name_from_the_rule_line():
    """`_granted_weapons_of_item` (:775-781): a Weapon Team's autocannon is a
    weapon, not a profile-less rule, so the table erases its name again."""
    sel = _selection("u", "Trooper", rules=[{"label": "HE Autocannon"}])
    sel["loadout"] = [_item("Weapon Team", [], weapon="HE Autocannon")]
    prof = profiles_from_army_forge_json(
        {"gameSystem": "gf", "units": [sel]}, "test_faction", player=1
    )["p1_0_u"]
    assert prof["special_rules"] == ["Weapon Team"]


def test_an_aura_grants_its_base_rule_to_the_unit_and_to_its_hero():
    """`_expand_auras` (opr_army_manager.gd:2112-2147): "X Aura" on a joined
    hero grants X to the host AND back to the hero, so the "all models"
    quantifier sees it. The base keeps any qualifier."""
    host = _selection("host", "Squad", size=3)
    hero = _selection("hero", "Champion", join_to_unit="host")
    hero["loadout"] = [_item("Blessed Icon", ["Bane in Melee Aura"])]
    profiles = profiles_from_army_forge_json(
        {"gameSystem": "gf", "units": [host, hero]}, "test_faction", player=1
    )
    assert profiles["p1_0_host"]["special_rules"] == ["Bane in Melee"]
    assert profiles["p1_1_hero"]["special_rules"] == [
        "Blessed Icon",
        "Bane in Melee Aura",
        "Bane in Melee",
    ]


def test_the_legacy_reading_still_parses_the_upgrade_label(monkeypatch):
    """`LEGACY_CORE_SELFPLAY` reproduces `tools/core_selfplay.gd` again — rule
    names out of the upgrade LABEL text, no loadout pass, no item grants, no
    auras. The M3-5 seed-for-seed gates replay corpora recorded under it."""
    monkeypatch.setattr(list_to_profile, "LEGACY_CORE_SELFPLAY", True)
    assert _rules_in_upgrade_label("Archivist (Caster(2))") == ["Caster(2)"]
    assert _rules_in_upgrade_label("Energy Sword (A2, AP(1), Rending)") == []
    sel = _selection(
        "caster", "Adept", upgrades=[{"option": {"label": "Archivist (Caster(2))"}}]
    )
    sel["loadout"] = [_item("Combat Bio-Engineer", ["Furious Aura"])]
    prof = profiles_from_army_forge_json(
        {"gameSystem": "gf", "units": [sel]}, "test_faction", player=1
    )["p1_0_caster"]
    assert prof["special_rules"] == ["Caster(2)"]
    assert prof["caster_value"] == 2
    assert prof["item_grants"] == []


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


def _radius_of(sel: dict, system: str = "gf") -> float:
    data = {"gameSystem": system, "units": [sel]}
    return profiles_from_army_forge_json(data, "test_faction", player=1)["p1_0_u"][
        "base_radius"
    ]


def test_base_radius_reads_the_lists_round_base():
    """NML-1097: a 25 mm base is 12.5 mm of radius, not the 32 mm default."""
    sel = _selection("u", "Unit", size=1)
    sel["bases"] = {"round": "25", "square": "25"}
    assert _radius_of(sel) == pytest.approx(0.0125, abs=1e-12)


def test_a_tough_model_scales_its_base_up():
    """`OPRArmyManager.model_base_long_mm`: Tough(3) justifies a 40 mm long
    edge, so a 25 mm base is scaled by 40/25 — the arena's own 0.02 for every
    Tough(3) hero on a 25 mm base. A 40 mm base is already there and unchanged."""
    small = _selection("u", "Unit", size=1, rules=[{"label": "Tough(3)"}])
    small["bases"] = {"round": "25"}
    assert _radius_of(small) == pytest.approx(0.0125 * (40.0 / 25.0), abs=1e-12)
    big = _selection("u", "Unit", size=1, rules=[{"label": "Tough(3)"}])
    big["bases"] = {"round": "40"}
    assert _radius_of(big) == pytest.approx(0.02, abs=1e-12)


def test_an_oval_base_answers_its_circumscribed_radius():
    """`BaseShape.bounding_radius` of the oval `shape_for_model` builds — the
    105x70 mm walker the arena records as 0.0630971..., not a 32 mm round."""
    sel = _selection("u", "Unit", size=1, rules=[{"label": "Tough(6)"}])
    sel["bases"] = {"round": "105x70", "square": "100x60"}
    want = math.sqrt(0.0525**2 + 0.035**2)
    assert _radius_of(sel) == pytest.approx(want, abs=1e-12)


def test_an_unusable_base_runs_the_keyword_tough_ladder():
    """Army Forge answers `round:"none"` for a model it has no recommendation
    for (common for vehicles). NML-1097b: the table then classifies the model
    by keyword + Tough (`_classify_big_model`) and sizes an OVAL vehicle base
    off Tough alone — this loader now matches, reproducing qbf_ref's own
    "Battle Tank" (Tough(12) -> 92x120) and "Organ Tank" (Tough(9) -> 70x105)."""
    battle_tank = _selection("u", "Battle Tank", size=1, rules=[{"label": "Tough(12)"}])
    battle_tank["bases"] = {"round": "none", "square": "none"}
    want_battle_tank = math.sqrt(0.046**2 + 0.060**2)
    assert _radius_of(battle_tank) == pytest.approx(want_battle_tank, abs=1e-12)

    organ_tank = _selection("u", "Organ Tank", size=1, rules=[{"label": "Tough(9)"}])
    organ_tank["bases"] = {"round": "none", "square": "none"}
    want_organ_tank = math.sqrt(0.035**2 + 0.0525**2)
    assert _radius_of(organ_tank) == pytest.approx(want_organ_tank, abs=1e-12)


def test_an_unusable_base_keeps_the_32mm_default_below_tough_3():
    """Below Tough(3) `_apply_tough_base_fallback` is a no-op (opr_api_client.gd:
    617-618) — a normal infantry model with no base recommendation keeps
    OPRUnit's 32 mm default, unchanged by the NML-1097b keyword ladder."""
    plain = _selection("u", "Unit", size=1)
    plain["bases"] = {}
    assert _radius_of(plain) == pytest.approx(0.016, abs=1e-12)


def test_a_regiments_list_reads_the_square_base():
    """`aofr` takes the SQUARE recommendation first (opr_api_client.gd:643)."""
    sel = _selection("u", "Unit", size=1)
    sel["bases"] = {"round": "25", "square": "40x40"}
    assert _radius_of(sel, system="aofr") == pytest.approx(0.02, abs=1e-12)


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
            if k in DIVERGED_FROM_CORE_SELFPLAY:
                continue
            r = _deep_eq(wv, got[uid].get(k))
            if r:
                mismatches.append(f"{uid}.{k}{r}")
    assert not mismatches, "\n".join(mismatches)


def test_base_shape_of_reads_a_d5_4b_header_and_survives_an_older_one():
    """NML-1073 M5 D5-4b — the base-SHAPE reader, both eras of act header.

    D5-4b made `BattleSim._unit_profile` write `base_shape` / `base_w_mm` /
    `base_d_mm`; every corpus recorded before it (`qbf_ref`, `qag_ref`, the
    oracle games this file gates on) carries none of the three. A reader that
    only worked on the new era would take the whole gate down on the old one,
    and one that quietly answered 32 mm for a missing oval would invent the
    very number the rung exists to record — hence `None`, not a default.
    """
    oval = {"base_radius": 0.0756, "base_shape": "oval",
            "base_w_mm": 92, "base_d_mm": 120}
    assert base_shape_of(oval) == ("oval", 92, 120)
    assert base_shape_of({"base_shape": "round", "base_w_mm": 32,
                          "base_d_mm": 32}) == ("round", 32, 32)
    # "rect" is read even though the recorder never writes it — shape_for_model
    # has no RECT branch, so a square-based unit is recorded as round.
    assert base_shape_of({"base_shape": "rect", "base_w_mm": 25,
                          "base_d_mm": 50}) == ("rect", 25, 50)

    # A pre-D5-4b header: round, and the axes are UNKNOWN rather than assumed.
    assert base_shape_of({"base_radius": 0.016}) == ("round", None, None)
    assert base_shape_of({}) == ("round", None, None)

    # RED: a shape this port cannot draw is named, not silently rounded off.
    with pytest.raises(ValueError, match="unknown base_shape"):
        base_shape_of({"base_shape": "hexagon"})
