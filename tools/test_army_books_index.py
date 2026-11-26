"""tools/army_books_index.py: a book as the API serves it (`uid`, the snapshot files) is read like a list export
(`armyId`), and `--known-only` leaves out - and names - a book whose slug its rules map does not know yet."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import army_books_index as abi  # noqa: E402


def test_a_snapshot_book_is_keyed_by_its_uid(tmp_path):
    (tmp_path / "a.json").write_text(json.dumps({"uid": "U1", "name": "Orc Marauders"}), encoding="utf-8")
    (tmp_path / "b.json").write_text(json.dumps({"armyId": "A2", "name": "Halflings"}), encoding="utf-8")
    (tmp_path / "MANIFEST.json").write_text(json.dumps({"books": []}), encoding="utf-8")
    assert sorted(abi.books_in_dir(str(tmp_path))) == ["A2", "U1"]


def test_known_only_drops_and_names_an_unknown_slug(tmp_path, capsys):
    (tmp_path / "assets" / "solo").mkdir(parents=True)
    (tmp_path / "assets" / "solo" / "rules_mechanics_gff.json").write_text(
        json.dumps({"factions": {"orc_marauders": {}}}), encoding="utf-8")
    index = {"gff": {"U1": {"faction_folder": "orc_marauders"}, "U2": {"faction_folder": "daemons_of_change"}}}
    assert abi.drop_unknown(index, str(tmp_path)) == {"gff": {"U1": {"faction_folder": "orc_marauders"}}}
    assert "left out gff/U2 'daemons_of_change'" in capsys.readouterr().err
