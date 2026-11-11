# DAT-13a (rules 3.6): the spell exporter reads the 3.6 army-book wording.
#
# Gaps on origin/main (1f181c70), each pinned with a made-up sentence in our own words (never
# army-book text) that walks the same grammar path: a capitalised Defense / Morale Test modifier
# is not seen; an "on its/their weapons" qualifier is swallowed into the granted rule's name or
# breaks the range clause; the "in line of sight" clause is not recorded per spell (ruling
# D-SPELL-LOS: a spell needs line of sight only when its own text says so; absent key = no);
# the hygiene key set refuses needs_los; and there is no --armyforge DIR input (the local
# registry checkout is gone). Rows marked "control" pass on main too and must stay green.
#
# Run:  python3 -m pytest tools/test_spells_mechanics_export_v36.py -q
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parent / "spells_mechanics_export.py"
_spec = importlib.util.spec_from_file_location("sme_v36", TOOL)
sme = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sme)

LOS_DAMAGE = 'Pick one enemy unit within 18" in line of sight, which takes 3 hits with AP(1). The fixture ends.'
DEF_MOD = 'Pick one friendly unit within 9", which gets +2 to Defense rolls once, while the fixture hums.'
BUFF = {"kind": "buff", "duration": "once"}
DEBUFF = {"kind": "debuff", "duration": "once"}

# (made-up sentence, status, effect, needs_los) - RED on main unless marked control.
CASES = [
    (DEF_MOD, "modeled", {**BUFF, "modifier": {"def_mod": 2}}, False),
    ('Pick one enemy unit within 15", which gets -1 to Morale Test rolls once, as a test of nerve.',
     "castable", {**DEBUFF, "modifier": {"morale_mod": -1}, "beneficiary": "target"}, False),
    ('Pick one friendly unit within 6", which gets Shred on its weapons when shooting once, a sharp idea.',
     "modeled", {**BUFF, "grants_rule": "Shred", "scope": "shooting"}, False),
    ('Pick up to two enemy units within 12", which friendly units get Rending on their weapons in melee '
     'against once, for the drill.',
     "modeled", {**DEBUFF, "grants_rule": "Rending", "scope": "melee", "beneficiary": "attackers"}, False),
    ('Pick one friendly unit within 6", which gets +6" range on its weapons when shooting once, far.',
     "castable", {**BUFF, "modifier": {"range_in": 6}, "scope": "shooting"}, False),
    (LOS_DAMAGE, "modeled", {"kind": "damage", "hits": 3, "weapon_rules": ["AP(1)"]}, True),
    # control: the lowercase hit modifier, and a text without the clause gets no key (byte-identical).
    ('Pick one friendly unit within 9", which gets +1 to hit rolls in melee once, for the control.',
     "modeled", {**BUFF, "modifier": {"hit_mod": 1}, "scope": "melee"}, False),
    ('Pick one enemy unit within 18", which takes 2 hits. The fixture ends.',
     "modeled", {"kind": "damage", "hits": 2, "weapon_rules": []}, False),
    # control (lead amendment 30.10.): "Enhanced <X>" is an upgrade grant, never priced.
    ('Pick one friendly unit within 12", which gets Enhanced Surge once, a made-up upgrade.',
     "castable", {**BUFF, "grants_rule": "Enhanced Surge"}, False),
]


CASE_IDS = ["defense-caps", "morale-test-caps", "grant-its-weapons", "grant-their-weapons", "range-its-weapons",
            "los-clause", "control-hit-lowercase", "control-no-los", "control-enhanced"]


@pytest.mark.parametrize("text,status,effect,needs_los", CASES, ids=CASE_IDS)
def test_spell_entry_reads_the_3_6_wording(text, status, effect, needs_los):
    e = sme.spell_entry({"name": "Test Spell", "threshold": 1, "effect": text})
    assert (e["status"], e["effect"]) == (status, effect)
    assert e.get("needs_los") is (True if needs_los else None)


def test_enhanced_grant_is_never_an_ev_grant():
    # control: no EV base name starts with "Enhanced", so main already says False; this guards it.
    assert [sme.ev_grant(n) for n in ("Enhanced Surge", "Enhanced Bane when Shooting", "Surge")] == [False, False, True]


def test_hygiene_accepts_needs_los():
    entry = sme.spell_entry({"name": "Test Spell", "threshold": 1, "effect": LOS_DAMAGE})
    sme.hygiene_check({"factions": {"test_faction": {"spells": [{**entry, "needs_los": True}]}}})


def _write_armyforge(root: Path) -> None:
    # Per system: one book with spells in non-alphabetical order, one book without spells, and a
    # shared "_" file that must be skipped (the CLI walks every system).
    book = {"uid": "abc123", "versionString": "9.9.9", "spells": [
        {"name": "Zeta Bolt", "threshold": 2, "effect": LOS_DAMAGE},
        {"name": "Alpha Ward", "threshold": 1, "effect": DEF_MOD}]}
    files = {"test_faction__abc123": book, "no_spells__def456": {"uid": "def456", "spells": []},
             "_common": {"uid": "shared", "spells": book["spells"]}}
    for system in sme.SYSTEMS:
        (root / system).mkdir(parents=True)
        for name, data in files.items():
            (root / system / f"{name}.json").write_text(json.dumps(data), encoding="utf-8")


def test_armyforge_dir_builds_book_ordered_map(tmp_path):
    _write_armyforge(tmp_path)
    system_map, stats = sme.build_system_map("", "", "gf", armyforge=str(tmp_path))
    assert list(system_map["factions"]) == ["test_faction"]
    book = system_map["factions"]["test_faction"]
    assert (book["book_uid"], book["book_version"]) == ("abc123", "9.9.9")
    assert [(s["name"], s.get("needs_los")) for s in book["spells"]] == [("Zeta Bolt", True), ("Alpha Ward", None)]
    assert (stats["factions"], stats["spells"], stats["missing_books"]) == (1, 2, 0)


def test_armyforge_cli_writes_then_checks(tmp_path):
    _write_armyforge(tmp_path / "af")
    run = [sys.executable, str(TOOL), "--armyforge", str(tmp_path / "af"), "--out", str(tmp_path / "out")]
    assert subprocess.run(run, capture_output=True).returncode == 0
    gf = json.loads((tmp_path / "out" / "spells_mechanics_gf.json").read_text(encoding="utf-8"))
    assert list(gf["factions"]) == ["test_faction"]
    assert subprocess.run(run + ["--check"], capture_output=True).returncode == 0
    (tmp_path / "out" / "spells_mechanics_aof.json").write_text("{}\n", encoding="utf-8")
    assert subprocess.run(run + ["--check"], capture_output=True).returncode == 1
