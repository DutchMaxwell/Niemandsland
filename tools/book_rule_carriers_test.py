"""Contract checks for the names-only army-book carrier generator (tools/book_rule_carriers.py)."""
import importlib.util
import json
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("book_rule_carriers.py")


def load_tool(tmp_path, monkeypatch, index):
    spec = importlib.util.spec_from_file_location("book_rule_carriers", SCRIPT)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    index_path = tmp_path / "index.json"
    index_path.write_text(json.dumps(index), encoding="utf-8")
    monkeypatch.setattr(tool, "INDEX_PATH", str(index_path))
    return tool


def books_dir(tmp_path, gf_books):
    root = tmp_path / "books"
    for system in ("gf", "aof"):
        (root / system).mkdir(parents=True)
        (root / system / "_common.json").write_text(json.dumps({"rules": [{"name": "Fast"}]}), encoding="utf-8")
    for name, book in gf_books.items():
        (root / "gf" / name).write_text(json.dumps(book), encoding="utf-8")
    return str(root)


BOOK = {
    "units": [{
        "name": "Unit One",
        "rules": [{"name": "Fast", "description": "secret rule text"}, {"name": "Foo"}],
        "weapons": [{"specialRules": [{"name": "Bar"}]}],
        "items": [{"content": [{"type": "ArmyBookRule", "name": "Baz"}]}],
        "upgrades": ["p1"],
    }],
    "upgradePackages": [{"uid": "p1", "sections": [{"options": [
        {"gains": [{"type": "ArmyBookRule", "name": "Qux"}]}]}]}],
}


def test_carriers_are_the_non_core_names_of_every_source_and_nothing_else(tmp_path, monkeypatch):
    tool = load_tool(tmp_path, monkeypatch, {"gf": {"ab12": {"faction_folder": "book_a"}}})
    data = tool.build(books_dir(tmp_path, {"book_a__ab12.json": BOOK}), "snap")
    assert data["gf"] == {"book_a": ["Bar", "Baz", "Foo", "Qux"]}, "own, weapon, item and upgrade rules; core Fast out"
    assert data["aof"] == {}
    out = tmp_path / "out.json"
    tool.write(data, str(out))
    text = out.read_text(encoding="utf-8")
    assert "secret rule text" not in text and "Unit One" not in text, "names only: no rule text, no unit names"
    assert json.loads(text)["_meta"]["snapshot"] == "snap"


def test_an_armyid_file_name_without_a_slug_prefix_works_and_an_empty_shell_is_skipped(tmp_path, monkeypatch):
    tool = load_tool(tmp_path, monkeypatch, {"gf": {"ab12": {"faction_folder": "book_a"}}})
    data = tool.build(books_dir(tmp_path, {"ab12.json": BOOK, "zz99.json": {"units": []}}), "")
    assert list(data["gf"]) == ["book_a"], "the shell zz99 has no units and is not in the index: skipped, not fatal"


def test_a_book_with_units_that_the_index_does_not_know_stops_the_run(tmp_path, monkeypatch):
    tool = load_tool(tmp_path, monkeypatch, {"gf": {}})
    with pytest.raises(SystemExit):
        tool.build(books_dir(tmp_path, {"unknown__zz99.json": BOOK}), "")
