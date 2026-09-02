"""PLAN A1's instrument check: the rule universe census against a synthetic
mini-repo and a 3-rule synthetic book.

  * the matrix: PORTED via the resolver-arm token, the aura pass deriving
    "Furious Aura" from its base - capped at STAMPED by the aura rule (its
    own mechanics entry stays primitive-null BY DESIGN - the import expands
    "X Aura" to X, but an UNMAPPED-registered aura is never PORTED by the
    base's token), and the plain UNMAPPED MISSING row;
  * the summary arithmetic over 3 names;
  * the RED knob: --hide Furious must drop the core-ported covered count by
    exactly the names that ride the primitive - the alias alone (its
    expanded aura was already capped at STAMPED by the aura rule);
  * a #[cfg(test)] literal is not evidence: a rule name that only appears
    behind the test gate leaves no token, so it can never read PORTED.
"""

import json
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

import rule_universe_census as census  # noqa: E402


@pytest.fixture()
def mini(tmp_path):
    root = tmp_path / "repo"
    (root / "assets" / "solo").mkdir(parents=True)
    (root / "data").mkdir(parents=True)
    (root / "core" / "nml-core" / "src").mkdir(parents=True)
    (root / "core" / "nml-core-py" / "python").mkdir(parents=True)
    (root / "assets" / "solo" / "rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Furious": {"primitive": "Furious", "params": {}},
            "Furious Aura": {"primitive": None, "params": {}},
        },
        "factions": {},
    }))
    (root / "data" / "encoder_rule_vocab_v1.json").write_text(json.dumps(
        {"version": 5, "unit": ["Furious"], "weapon": []}))
    (root / "core" / "nml-core-py" / "python" / "list_to_profile.py").write_text(
        'MOVE_PRIMITIVES = ("Fast", "Slow", "Quick")\n')
    (root / "core" / "nml-core" / "src" / "arm.rs").write_text(
        'pub const ARM: &str = "Furious";\n'
        'pub fn arm(x: i64) -> i64 { x }\n')
    (root / "core" / "nml-core" / "src" / "morale.rs").write_text(
        '// "Ghostrule" lives only behind the test gate\n'
        '#[cfg(test)]\n'
        'mod tests {\n'
        '    #[test]\n'
        '    fn t() {\n'
        '        let s = "Ghostrule"; // test literal - not a resolver arm\n'
        '        assert!(!s.is_empty());\n'
        '    }\n'
        '}\n')
    books = tmp_path / "books" / "gf"
    books.mkdir(parents=True)
    (books / "book_a.json").write_text(json.dumps({
        "name": "Test Faction",
        "gameSystem": "gf",
        "specialRules": [
            {"name": "Furious(3)"},
            {"name": "Furious Aura"},
            {"name": "Off Book"},
        ],
    }))
    return root, tmp_path / "books"


def test_census_matrix_red_knob_and_test_gate(mini):
    root, books = mini
    res = census.census(books, root)
    s = res["summary"]
    assert s["total"] == 3
    assert s["registry_primitive"] == 1
    assert s["mechanics_entry"] == 2
    assert s["core_ported"] == 1
    assert s["core_stamped"] == 1
    assert s["core_partial"] == 0
    assert s["core_missing"] == 1
    assert s["encoder_slot"] == 1
    assert s["all_layers"] == 1

    rows = res["rows"]
    furious = rows["Furious"]["per_system"]["gf"]
    assert furious["core"] == "PORTED"
    assert furious["primitive"] == "Furious"
    assert "arm.rs" in furious["core_note"]
    aura = rows["Furious Aura"]["per_system"]["gf"]
    assert aura["core"] == "STAMPED"
    assert "aura of 'Furious'" in aura["core_note"]
    assert "UNMAPPED-registered" in aura["core_note"]
    assert aura["aura_live"] is True, (
        "base PORTED + import expansion = live, reported on its own line"
    )
    assert furious["aura_live"] is False
    assert s["aura_live"] == 1
    off_book = rows["Off Book"]["per_system"]["gf"]
    assert off_book["primitive"] == "UNMAPPED"
    assert off_book["core"] == "MISSING"
    assert off_book["encoder_slot"] is False
    assert off_book["aura_live"] is False

    tokens, _comments = census.scan_rust(root)
    assert "furious" in tokens
    assert "ghostrule" not in tokens, "a test-gated literal must not be evidence"

    lines = census.summary_lines(res)
    assert (
        "RULES-COVERAGE core-ported        : 1/3"
        "  (STAMPED: 1, PARTIAL: 0, MISSING: 1, N/A: 0 excluded from 3)"
    ) in lines
    assert "consumed 1/3 · stamped-only 1 · missing 1" in lines[3]

    red = census.census(books, root, hide="Furious")["red"]
    assert red["before"] == 1
    assert red["after"] == 0
    assert red["drop"] == 1
    assert red["aliased"] == 2
    assert red["ported_aliased"] == 1
    assert red["ok"] is True


def test_stamped_vs_ported_on_a_shared_primitive(tmp_path):
    """A shared "class" primitive (#489's Utility Buff shape): a resolver
    token for the PRIMITIVE stamps every entry, but only a param in
    CONSUMED_PARAM_KEYS is actually read - the rest is STAMPED, not PORTED."""
    root = tmp_path / "repo"
    for d in ("assets/solo", "data", "core/nml-core/src", "core/nml-core-py/python"):
        (root / d).mkdir(parents=True)
    (root / "assets/solo/rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Buff Stamped": {"primitive": "Utility Buff", "params": {"def_mod": -1}},
            "Buff Consumed": {"primitive": "Utility Buff", "params": {"hit_mod": 1}},
        },
        "factions": {},
    }))
    (root / "data/encoder_rule_vocab_v1.json").write_text(json.dumps({"unit": [], "weapon": []}))
    (root / "core/nml-core-py/python/list_to_profile.py").write_text("MOVE_PRIMITIVES = ()\n")
    (root / "core/nml-core/src/arm.rs").write_text('pub const UB: &str = "Utility Buff";\n')
    books = tmp_path / "books" / "gf"
    books.mkdir(parents=True)
    (books / "book_a.json").write_text(json.dumps({
        "name": "Test Faction", "gameSystem": "gf",
        "specialRules": [{"name": "Buff Stamped"}, {"name": "Buff Consumed"}],
    }))
    res = census.census(tmp_path / "books", root)
    per = res["rows"]
    assert per["Buff Stamped"]["per_system"]["gf"]["core"] == "STAMPED"
    assert per["Buff Consumed"]["per_system"]["gf"]["core"] == "PORTED"
    assert res["summary"]["core_stamped"] == 1
    assert res["summary"]["core_ported"] == 1


def test_unmapped_registered_aura_never_ported_by_token_sharing(tmp_path):
    """The aura rule: an UNMAPPED-registered "Foo Aura" (registry lists it,
    primitive null) must not inherit PORTED from its ported base "Foo" -
    PORTED means CONSUMED and the aura has no primitive, hence no params
    anyone reads. The base's token alone caps it at STAMPED; only the
    aura's OWN full-name token (e.g. bar_aura) in non-test core code
    reads PORTED."""
    root = tmp_path / "repo"
    for d in ("assets/solo", "data", "core/nml-core/src", "core/nml-core-py/python"):
        (root / d).mkdir(parents=True)
    (root / "assets/solo/rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Foo": {"primitive": "Foo", "params": {}},
            "Foo Aura": {"primitive": None, "params": {}},
            "Bar Aura": {"primitive": None, "params": {}},
        },
        "factions": {},
    }))
    (root / "data/encoder_rule_vocab_v1.json").write_text(json.dumps({"unit": [], "weapon": []}))
    (root / "core/nml-core-py/python/list_to_profile.py").write_text("MOVE_PRIMITIVES = ()\n")
    (root / "core/nml-core/src/arm.rs").write_text(
        'pub const FOO: &str = "Foo";\n'
        'pub const BAR_AURA: &str = "Bar Aura";\n'
    )
    books = tmp_path / "books" / "gf"
    books.mkdir(parents=True)
    (books / "book_a.json").write_text(json.dumps({
        "name": "Test Faction", "gameSystem": "gf",
        "specialRules": [
            {"name": "Foo"},
            {"name": "Foo Aura"},
            {"name": "Bar"},
            {"name": "Bar Aura"},
        ],
    }))
    res = census.census(tmp_path / "books", root)
    per = res["rows"]
    assert per["Foo"]["per_system"]["gf"]["core"] == "PORTED"
    aura = per["Foo Aura"]["per_system"]["gf"]
    assert aura["primitive"] == "UNMAPPED-registered"
    assert aura["core"] == "STAMPED", (
        f"UNMAPPED-registered aura must cap at STAMPED, got {aura['core']}"
        f" ({aura['core_note']})"
    )
    own = per["Bar Aura"]["per_system"]["gf"]
    assert own["core"] == "PORTED"
    assert "bar_aura" in own["core_note"]
    assert res["summary"]["core_ported"] == 2
    assert res["summary"]["core_stamped"] == 1
    assert "capped at STAMPED" in census.markdown_report(res)


def test_na_names_excluded_from_ported_denominator(tmp_path):
    """SPEC_block_C_next_2026-09-02.md's census-hygiene bullet: Unique
    (list-building only) and Swift (already folded into the loader's
    move-band pass) must land in the N/A class, never MISSING, and the
    core-ported ratio's own denominator must exclude them - a stale
    denominator would silently count them as still-unported. "Swift Aura"
    rides the same N/A verdict through the existing aura-inherits-base pass,
    with no NA_NAMES entry of its own."""
    root = tmp_path / "repo"
    for d in ("assets/solo", "data", "core/nml-core/src", "core/nml-core-py/python"):
        (root / d).mkdir(parents=True)
    (root / "assets/solo/rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Unique": {"primitive": None, "params": {}},
            "Swift": {"primitive": "Swift", "params": {"negates": "Slow"}},
            "Swift Aura": {"primitive": None, "params": {}},
            "Furious": {"primitive": "Furious", "params": {}},
        },
        "factions": {},
    }))
    (root / "data/encoder_rule_vocab_v1.json").write_text(json.dumps({"unit": [], "weapon": []}))
    (root / "core/nml-core-py/python/list_to_profile.py").write_text("MOVE_PRIMITIVES = ()\n")
    (root / "core/nml-core/src/arm.rs").write_text('pub const ARM: &str = "Furious";\n')
    books = tmp_path / "books" / "gf"
    books.mkdir(parents=True)
    (books / "book_a.json").write_text(json.dumps({
        "name": "Test Faction", "gameSystem": "gf",
        "specialRules": [
            {"name": "Unique"}, {"name": "Swift"}, {"name": "Swift Aura"},
            {"name": "Furious"},
        ],
    }))
    res = census.census(tmp_path / "books", root)
    rows = res["rows"]
    assert rows["Unique"]["per_system"]["gf"]["core"] == "N/A"
    assert rows["Swift"]["per_system"]["gf"]["core"] == "N/A"
    assert rows["Swift Aura"]["per_system"]["gf"]["core"] == "N/A", (
        "an aura inherits its base's N/A verdict without its own NA_NAMES entry"
    )
    assert rows["Swift Aura"]["per_system"]["gf"]["aura_live"] is False, (
        "N/A outranks the aura pass - an N/A base is never live"
    )
    assert rows["Furious"]["per_system"]["gf"]["core"] == "PORTED"

    s = res["summary"]
    assert s["total"] == 4
    # Unique, Swift and the inherited Swift Aura all land in N/A - the
    # inheritance adds its own row to the count, it just needs no NA_NAMES
    # entry of its own to get there.
    assert s["core_na"] == 3
    assert s["core_ported_denominator"] == 1
    assert s["core_ported"] == 1
    assert s["core_missing"] == 0, "no N/A name may count as MISSING"

    lines = census.summary_lines(res)
    ported_line = next(l for l in lines if "core-ported" in l)
    assert "1/1" in ported_line
    assert "N/A: 3 excluded from 1" in ported_line

    offenders = res["offenders"]
    assert offenders[0]["occ_unported"] == 0, (
        "Unique/Swift/Swift Aura must never count as unported offenders"
    )


def test_aura_live_control_and_core_counter_net(tmp_path):
    """The aura-live marker (NML aura-family rung, 2026-09-02): an aura whose
    BASE is PORTED is live through the import expansion and reads
    aura_live=True - while core stays STAMPED (PORTED means CONSUMED). Two
    nets: (a) a control aura whose base is NOT ported stays aura_live=False
    (the flag must not be unconditional); (b) the four core counters equal
    the pre-change values - folding aura_live into core_ported fails here."""
    root = tmp_path / "repo"
    for d in ("assets/solo", "data", "core/nml-core/src", "core/nml-core-py/python"):
        (root / d).mkdir(parents=True)
    (root / "assets/solo/rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Rage": {"primitive": "Rage", "params": {}},
            "Rage Aura": {"primitive": None, "params": {}},
            "Dull Aura": {"primitive": None, "params": {}},
        },
        "factions": {},
    }))
    (root / "data/encoder_rule_vocab_v1.json").write_text(json.dumps({"unit": [], "weapon": []}))
    (root / "core/nml-core-py/python/list_to_profile.py").write_text("MOVE_PRIMITIVES = ()\n")
    (root / "core/nml-core/src/arm.rs").write_text('pub const RAGE: &str = "Rage";\n')
    books = tmp_path / "books" / "gf"
    books.mkdir(parents=True)
    (books / "book_a.json").write_text(json.dumps({
        "name": "Test Faction", "gameSystem": "gf",
        "specialRules": [
            {"name": "Rage"},
            {"name": "Rage Aura"},
            {"name": "Dull"},
            {"name": "Dull Aura"},
        ],
    }))
    res = census.census(tmp_path / "books", root)
    per = res["rows"]
    live = per["Rage Aura"]["per_system"]["gf"]
    assert live["core"] == "STAMPED"
    assert live["aura_live"] is True
    control = per["Dull Aura"]["per_system"]["gf"]
    assert control["core"] == "MISSING"
    assert control["aura_live"] is False, "base not ported - nothing is live"
    assert per["Rage"]["per_system"]["gf"]["aura_live"] is False
    assert per["Dull"]["per_system"]["gf"]["aura_live"] is False
    s = res["summary"]
    assert s["aura_live"] == 1
    # byte-identity net: the four core counters are the PRE-CHANGE values
    assert s["core_ported"] == 1
    assert s["core_stamped"] == 1
    assert s["core_partial"] == 0
    assert s["core_missing"] == 2
    lines = census.summary_lines(res)
    assert (
        "RULES-COVERAGE aura-granted       : 1/4  (base PORTED, live through the"
        " import expansion; NOT counted as core-ported)"
    ) in lines
    assert "LIVE via the import expansion" in live["core_note"]


def test_cli_prints_summary_and_writes_json(mini, tmp_path, capsys):
    root, books = mini
    out_json = tmp_path / "out" / "census.json"
    rc = census.main([
        "--books", str(books),
        "--repo", str(root),
        "--out-json", str(out_json),
    ])
    assert rc == 0
    assert "RULES-COVERAGE core-ported" in capsys.readouterr().out
    data = json.loads(out_json.read_text())
    assert data["summary"]["total"] == 3
    assert set(data["rows"]) == {"Furious", "Furious Aura", "Off Book"}
