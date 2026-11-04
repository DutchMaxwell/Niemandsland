"""W31-F1 (release 0.3.15) — the Python mirror of the table's Vanguard gate resolves in every book that fields it.

`list_to_profile._rule_active` is the twin of `RulesRegistry.unit_rule_active`: the carrier counts only where the
book's mechanics section fields the rule. A book with no Vanguard row was dropped by the table's placement while the
core's name arm still pushed the unit, so the two engines disagreed. Table twin:
test/v36/w31_f1_vanguard_books_test.gd; Rust twin: core/nml-core/src/tests/unit/v36_data_rows/w31_f1.rs.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import list_to_profile as l2p  # noqa: E402

BOOKS = [
    ("gf", "battle_brothers"), ("gf", "blood_brothers"), ("gf", "blood_prime_brothers"),
    ("gf", "dark_prime_brothers"), ("gf", "infected_colonies"), ("gf", "knight_prime_brothers"),
    ("gf", "rebel_guerrillas"), ("gf", "saurian_starhosts"),
    ("aof", "dwarves"), ("aof", "saurians"),
]


def test_control_a_book_with_its_row_applies_vanguard():
    assert l2p._rule_active(["Vanguard"], "gf", "dark_elf_raiders", "Vanguard")


def test_books_that_field_vanguard_apply_it_in_both_engines():
    dropped = [f"{s}/{b}" for s, b in BOOKS if not l2p._rule_active(["Vanguard"], s, b, "Vanguard")]
    assert not dropped, f"Vanguard silently dropped in: {dropped}"
    for system, book in BOOKS:
        flags = l2p._deploy_flags({"special_rules": ["Vanguard"], "item_grants": []}, system, book)
        assert flags["vanguard"] and abs(flags["vanguard_place_in_m"] - 9.0 * 0.0254) < 1e-9, (system, book)
