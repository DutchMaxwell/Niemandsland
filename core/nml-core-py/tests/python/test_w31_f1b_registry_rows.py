"""W31-F1 follow-up (release 0.3.15) — the Python mirror of the table's registry-gated reads.

`list_to_profile._rule_active` twins `RulesRegistry.unit_rule_active`: a carrier counts only where its book's
mechanics section fields the rule. Vanguard (the deploy flag's registry arm) and Bounding (the activation advance
bonus) are the two reads the mirror has; Hit & Run Shooter and Quick Throw are read by the core from the registry
directly. Table twin: test/v36/f1b_registry_rows_test.gd; Rust twin:
core/nml-core/src/tests/unit/v36_data_rows/f1b_rows.rs.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import list_to_profile as l2p  # noqa: E402

VANGUARD_BOOKS = ["prime_brothers", "watch_prime_brothers", "wolf_brothers", "wolf_prime_brothers"]


def test_control_a_book_with_its_row_applies_vanguard():
    assert l2p._rule_active(["Vanguard"], "gf", "dark_elf_raiders", "Vanguard")


def test_vanguard_books_without_a_row_apply_it_in_both_engines():
    dropped = [b for b in VANGUARD_BOOKS if not l2p._rule_active(["Vanguard"], "gf", b, "Vanguard")]
    assert not dropped, f"Vanguard silently dropped in: {dropped}"
    for book in VANGUARD_BOOKS:
        flags = l2p._deploy_flags({"special_rules": ["Vanguard"], "item_grants": []}, "gf", book)
        assert flags["vanguard"] and abs(flags["vanguard_place_in_m"] - 9.0 * 0.0254) < 1e-9, book


def test_bounding_adds_its_activation_reach_where_the_book_fields_it():
    reach = l2p._max_activation_advance_bonus_in
    assert reach(["Bounding"], [], "aof", "giant_tribes") == 4.0, "the control book keeps its row"
    assert reach([], [], "aof", "eternal_wardens") == 0.0
    assert reach(["Bounding"], [], "aof", "eternal_wardens") == 4.0, "aof/eternal_wardens: Bounding silently dropped"
