"""The committed encoder vocabulary owns an `alias` block (rules 3.6 renames).

Plain json + pathlib only, so this runs without a built nml_core.
"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
VOCAB_PATH = REPO / "data" / "encoder_rule_vocab_v1.json"

EXPECTED_UNIT = sorted([
    "Anti-Cover Aura",
    "Anti-Cover when Shooting",
    "Anti-Cover when Shooting Aura",
    "Bravery",
    "Bravery Aura",
    "Bravery Buff",
    "Counter in Melee Aura",
    "Enhanced Angelic Blessing Buff",
    "Enhanced Bestial",
    "Enhanced Bestial Aura",
    "Enhanced Buccaneer",
    "Enhanced Buccaneer Aura",
    "Enhanced Changebound",
    "Enhanced Changebound Aura",
    "Enhanced Clan Warrior",
    "Enhanced Clan Warrior Aura",
    "Enhanced Cursed Undead Buff",
    "Enhanced Destroyer",
    "Enhanced Destroyer Aura",
    "Enhanced Devout",
    "Enhanced Devout Aura",
    "Enhanced Empyrean Spirit",
    "Enhanced Empyrean Spirit Aura",
    "Enhanced Ferocious",
    "Enhanced Ferocious Aura",
    "Enhanced Guardian",
    "Enhanced Guardian Aura",
    "Enhanced Guerrilla",
    "Enhanced Guerrilla Aura",
    "Enhanced Harassing",
    "Enhanced Harassing Aura",
    "Enhanced Havocbound",
    "Enhanced Havocbound Aura",
    "Enhanced Highborn",
    "Enhanced Highborn Aura",
    "Enhanced Hive Bond",
    "Enhanced Hive Bond Aura",
    "Enhanced Hold the Line",
    "Enhanced Hold the Line Aura",
    "Enhanced Hold the Line Buff",
    "Enhanced Infected",
    "Enhanced Infected Aura",
    "Enhanced Lucky",
    "Enhanced Lucky Aura",
    "Enhanced Lustbound",
    "Enhanced Lustbound Aura",
    "Enhanced Machine-Fog",
    "Enhanced Machine-Fog Aura",
    "Enhanced Mischievous",
    "Enhanced Mischievous Aura",
    "Enhanced Ossified",
    "Enhanced Ossified Aura",
    "Enhanced Plaguebound",
    "Enhanced Plaguebound Aura",
    "Enhanced Primal Buff",
    "Enhanced Rapid Blink",
    "Enhanced Rapid Blink Aura",
    "Enhanced Royal Legion",
    "Enhanced Royal Legion Aura",
    "Enhanced Royal Warrior",
    "Enhanced Royal Warrior Aura",
    "Enhanced Scrapper",
    "Enhanced Scrapper Aura",
    "Enhanced Scurry",
    "Enhanced Scurry Aura",
    "Enhanced Self-Repair Buff",
    "Enhanced Shadowborn",
    "Enhanced Shadowborn Aura",
    "Enhanced Sturdy",
    "Enhanced Sturdy Aura",
    "Enhanced Targeting Visor",
    "Enhanced Targeting Visor Aura",
    "Enhanced Vale Oath",
    "Enhanced Vale Oath Aura",
    "Enhanced Vinci Tech",
    "Enhanced Vinci Tech Aura",
    "Enhanced Warbound",
    "Enhanced Warbound Aura",
    "Enhanced Warden",
    "Enhanced Warden Aura",
    "Enhanced Wave-Step",
    "Enhanced Wave-Step Aura",
    "Enhanced Wild Veil",
    "Enhanced Wild Veil Aura",
    "Grounded Defense",
    "Grounded Defense Aura",
    "Grounded Evasion",
    "Piercing Charge",
    "Piercing Charge Aura",
    "Piercing Charge Buff",
    "Piercing Marksman",
    "Piercing Marksman Aura",
    "Quick Throw",
    "Spell Resistance",
    "Spell Resistance Aura",
    "Unique Hero",
    "Versatile Warrior",
    "Versatile Warrior Buff",
])

EXPECTED_WEAPON = sorted([
    "Anti-Cover",
    "Anti-Regen",
    "Crossing Strike",
    "Fracture",
    "Puncture",
])

EXPECTED_SPELL = sorted([
    "Adrenal Booster",
    "Enhanced Serum",
])


def _vocab():
    with open(VOCAB_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def _slot(vocab, band, name):
    if band == "unit":
        return vocab["unit"].index(name)
    if band == "weapon":
        return 200 + vocab["weapon"].index(name)
    if band == "spell":
        return 300 + vocab["spell"].index(name)
    if band == "unit2":
        return 300 + len(vocab["spell"]) + vocab["unit2"].index(name)
    raise AssertionError(f"unknown band {band}")


def test_vocab_version_is_nine():
    assert _vocab()["version"] == 9


def test_alias_block_has_exactly_the_three_bands():
    alias = _vocab().get("alias", {})
    assert set(alias.keys()) == {"unit", "weapon", "spell"}


def test_alias_keys_match_the_renamed_rules():
    alias = _vocab().get("alias", {})
    assert sorted(alias.get("unit", {}).keys()) == EXPECTED_UNIT
    assert sorted(alias.get("weapon", {}).keys()) == EXPECTED_WEAPON
    assert sorted(alias.get("spell", {}).keys()) == EXPECTED_SPELL


def test_no_alias_key_owns_a_slot_of_its_own():
    vocab = _vocab()
    lists = [vocab["unit"], vocab["weapon"], vocab["spell"], vocab["unit2"]]
    for band, entries in vocab.get("alias", {}).items():
        for name in entries:
            for names in lists:
                assert name not in names, f"{band} alias {name!r} still owns a slot"


def test_every_alias_target_has_a_slot_below_1017():
    vocab = _vocab()
    for band, entries in vocab.get("alias", {}).items():
        for name, targets in entries.items():
            for target in targets:
                if band == "unit":
                    bands = ["unit", "unit2"]
                elif band == "weapon":
                    bands = ["weapon"]
                else:
                    bands = ["spell"]
                slots = [
                    _slot(vocab, b, target)
                    for b in bands
                    if target in vocab[b]
                ]
                assert slots, f"{band} alias {name!r} target {target!r} has no slot"
                assert min(slots) < 1017, f"{name!r} target {target!r} sits at {min(slots)}"
