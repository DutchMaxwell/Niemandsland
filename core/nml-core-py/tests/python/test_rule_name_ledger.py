"""The rule name ledger's instrument check: the ledger must emit WHICH rule
names the census universe contains (one row per system/rule, count equal to
the census's own distinct gf+aof name counts), and diff an audited list
against it - AUDITED / UNAUDITED / UNKNOWN buckets, exit code 1 while anything
is UNAUDITED or UNKNOWN (gate use), 0 when both are empty.

RED first: this file shipped before the tool existed (rules-ledger-wave6).
"""

import json
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

import rule_universe_census as census  # noqa: E402
import rule_name_ledger as ledger  # noqa: E402


@pytest.fixture()
def books(tmp_path):
    """A synthetic private book snapshot: gf carries Furious (aliased twice),
    its aura and one off-book name; aof carries Furious again (so the name
    sits in BOTH systems -> one row per system) plus Tough."""
    gf = tmp_path / "books" / "gf"
    aof = tmp_path / "books" / "aof"
    gf.mkdir(parents=True)
    aof.mkdir(parents=True)
    (gf / "book_a.json").write_text(json.dumps({
        "name": "Test Faction", "gameSystem": "gf",
        "specialRules": [
            {"name": "Furious(3)"}, {"name": "Furious Aura"}, {"name": "Off Book"},
        ],
    }))
    (aof / "book_a.json").write_text(json.dumps({
        "name": "Other Faction", "gameSystem": "aof",
        "specialRules": [{"name": "Furious(2)"}, {"name": "Tough"}],
    }))
    return tmp_path / "books"


def test_ledger_emits_the_census_distinct_names(books, capsys):
    """(a) The emitted row count equals the census's own distinct gf+aof name
    count, the header is `system<TAB>rule`, and rows are deterministic TSV
    (one row per system for a name in both systems)."""
    rc = ledger.main(["--books", str(books)])
    assert rc == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "system\trule"
    rows = [tuple(line.split("\t")) for line in out[1:]]
    universe = census.build_universe(census.load_books(books))
    expected = sum(
        1 for s in census.SYSTEMS for u in universe.values() if s in u["systems"]
    )
    # gf: Furious, Furious Aura, Off Book (3) + aof: Furious, Tough (2)
    assert expected == 5
    assert len(rows) == expected, (
        "the ledger's emitted row count must be the census's own "
        "distinct-name count, or the list is not auditable"
    )
    assert rows == sorted(rows)
    assert ("gf", "Furious") in rows and ("aof", "Furious") in rows
    assert ("gf", "Off Book") in rows
    assert ("aof", "Tough") in rows


def test_audited_diff_buckets_and_exit_code(books, tmp_path, capsys):
    """(b) A hand-written audited file with one deliberate typo produces
    exactly 2 AUDITED, 1 UNKNOWN and the rest of the universe UNAUDITED (3
    rows - the diff is system-scoped, so Furious audited in aof leaves
    gf/Furious unaudited), with every bucket's full names printed; (c) the
    exit code is 1 in that case and 0 when UNAUDITED and UNKNOWN are both
    empty."""
    audited = tmp_path / "audited.tsv"
    audited.write_text(
        "# wave 1 audit - hand-written\n"
        "\n"
        "gf\tFurious\n"
        "aof\tTough\n"
        "gf\tFuroius\n"  # deliberate typo -> UNKNOWN
    )
    rc = ledger.main(["--books", str(books), "--audited", str(audited)])
    assert rc == 1
    out = capsys.readouterr().out.splitlines()
    assert "AUDITED: 2" in out
    assert "UNAUDITED: 3" in out
    assert "UNKNOWN: 1" in out
    assert "gf\tFuroius" in out, "the UNKNOWN name must be listed in full"
    assert "gf\tOff Book" in out, "the UNAUDITED names must be listed in full"
    assert "gf\tFurious Aura" in out
    assert "aof\tFurious" in out, "auditing a name in aof does not audit gf"

    complete = tmp_path / "complete.tsv"
    complete.write_text(
        "gf\tFurious\ngf\tFurious Aura\ngf\tOff Book\naof\tFurious\naof\tTough\n"
    )
    rc2 = ledger.main(["--books", str(books), "--audited", str(complete)])
    assert rc2 == 0, "everything audited, nothing unknown - the gate passes"
    out2 = capsys.readouterr().out.splitlines()
    assert "UNAUDITED: 0" in out2
    assert "UNKNOWN: 0" in out2