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
    off_book = rows["Off Book"]["per_system"]["gf"]
    assert off_book["primitive"] == "UNMAPPED"
    assert off_book["core"] == "MISSING"
    assert off_book["encoder_slot"] is False

    tokens, _comments = census.scan_rust(root)
    assert "furious" in tokens
    assert "ghostrule" not in tokens, "a test-gated literal must not be evidence"

    lines = census.summary_lines(res)
    assert "RULES-COVERAGE core-ported        : 1/3  (STAMPED: 1, PARTIAL: 0, MISSING: 1)" in lines
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
