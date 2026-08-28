"""GATE M3-9 (NML-1097 / NML-1098) — the loader-parity gate's own instrument check.

The gate compares `list_to_profile`'s unit profiles against an arena act-corpus
header. That corpus lives outside the repo, so these tests build a SYNTHETIC one
instead: a two-unit army list, an `acts.jsonl` whose header profiles are the
trainer's own answer, and a first act that carries the sides.

  * the identical pair must come out GREEN — otherwise the gate would report a
    mismatch that is not there, and every RED number below it would be noise.
  * a header with a DELIBERATELY wrong base radius must come out RED, name the
    `base_radius` column, and exit 1 — the red proof NML-1097 is measured with.
  * the same for a rule the header carries and the loader does not
    (`special_rules`), and for `--report-only`, which must report the mismatch
    and still exit 0.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

import loader_gate  # noqa: E402


def _list_json(prefix: str) -> dict:
    """A two-unit Army-Forge list: a 3-model squad and a hero joined to it."""
    return {
        "gameSystem": "gf",
        "units": [
            {
                "id": "%s_squad" % prefix,
                "selectionId": "%s_squad" % prefix,
                "name": "Squad",
                "size": 3,
                "quality": 4,
                "defense": 4,
                "bases": {"round": "25"},
                "rules": [{"label": "Strider", "name": "Strider"}],
                "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 3}],
                "selectedUpgrades": [],
            },
            {
                "id": "%s_hero" % prefix,
                "selectionId": "%s_hero" % prefix,
                "joinToUnit": "%s_squad" % prefix,
                "combined": False,
                "name": "Hero",
                "size": 1,
                "quality": 3,
                "defense": 4,
                "bases": {"round": "40"},
                "rules": [{"label": "Hero", "name": "Hero"}],
                "weapons": [{"name": "Blade", "range": 0, "attacks": 2, "count": 1}],
                "selectedUpgrades": [],
            },
        ],
    }


def _corpus(tmp_path: Path) -> tuple[Path, Path]:
    """`(ref dir, lists dir)` — one game whose header IS the trainer's answer."""
    lists = tmp_path / "lists"
    lists.mkdir()
    for stem in ("mylist_a", "mylist_b"):
        (lists / ("%s.json" % stem)).write_text(json.dumps(_list_json(stem)))

    profiles: dict = {}
    units: dict = {}
    for side, stem in ((1, "mylist_a"), (2, "mylist_b")):
        for u in loader_gate.trainer_army(lists / ("%s.json" % stem), side, True):
            profiles[u["unit_id"]] = dict(u)
            units[u["unit_id"]] = {
                "player": side,
                "prof": {f: u[f] for f in loader_gate.DYN_FIELDS},
            }

    ref = tmp_path / "ref"
    game = ref / "mylist_a_vs_mylist_b_s1"
    game.mkdir(parents=True)
    with open(game / "acts.jsonl", "w") as f:
        f.write(json.dumps({"kind": "header", "profiles": profiles}) + "\n")
        f.write(json.dumps({"kind": "act", "state": {"units": units}}) + "\n")
    return ref, lists


def _run(ref: Path, lists: Path, *extra: str) -> int:
    return loader_gate.main(["--ref", str(ref), "--lists", str(lists), *extra])


def _corrupt(ref: Path, field: str, value) -> None:
    """Rewrite the header so ONE unit's `field` is wrong."""
    acts = ref / "mylist_a_vs_mylist_b_s1" / "acts.jsonl"
    lines = acts.read_text().splitlines()
    header = json.loads(lines[0])
    first = sorted(header["profiles"])[0]
    header["profiles"][first][field] = value
    lines[0] = json.dumps(header)
    acts.write_text("\n".join(lines) + "\n")


def test_identical_profiles_are_green(tmp_path, capsys):
    ref, lists = _corpus(tmp_path)
    assert _run(ref, lists) == 0
    out = capsys.readouterr().out
    assert "VERDICT        GREEN" in out
    assert "4 distinct roster units" in out


def test_a_wrong_base_radius_is_reported_red(tmp_path, capsys):
    """The NML-1097 red proof: a header radius the loader does not produce. The
    value is deliberately not 0.016 (today's default) nor 0.0125 (the 25 mm base
    NML-1097 will make it produce), so the check stays a check either side of
    that fix."""
    ref, lists = _corpus(tmp_path)
    _corrupt(ref, "base_radius", 0.0999)
    assert _run(ref, lists) == 1
    out = capsys.readouterr().out
    assert "VERDICT        RED" in out
    assert "base_radius" in out
    # exactly one unit, one row, one game — no other column may have moved.
    assert "base_radius                             1        1        1" in out
    assert "special_rules" not in out


def test_a_missing_rule_is_reported_red(tmp_path, capsys):
    """The NML-1098 shape: a rule the table's import grants and the loader drops."""
    ref, lists = _corpus(tmp_path)
    _corrupt(ref, "special_rules", ["Strider", "Furious"])
    assert _run(ref, lists) == 1
    out = capsys.readouterr().out
    assert "VERDICT        RED" in out
    assert "special_rules" in out
    assert "base_radius" not in out


def test_report_only_reports_and_still_exits_zero(tmp_path, capsys):
    ref, lists = _corpus(tmp_path)
    _corrupt(ref, "base_radius", 0.0999)
    assert _run(ref, lists, "--report-only") == 0
    assert "VERDICT        RED" in capsys.readouterr().out


def test_red_base_knob_fails_a_matching_corpus(tmp_path, capsys):
    """`--red-base-mm` corrupts the TRAINER side, so the gate must go red on an
    otherwise-green corpus — the knob that keeps proving the column after the fix."""
    ref, lists = _corpus(tmp_path)
    assert _run(ref, lists, "--red-base-mm", "99") == 1
    out = capsys.readouterr().out
    assert "VERDICT        RED" in out
    assert "base_radius" in out


def test_red_drop_rule_knob_fails_a_matching_corpus(tmp_path, capsys):
    ref, lists = _corpus(tmp_path)
    assert _run(ref, lists, "--red-drop-rule", "Strider") == 1
    out = capsys.readouterr().out
    assert "VERDICT        RED" in out
    assert "special_rules" in out


def test_a_roster_mismatch_is_counted_as_misaligned_not_as_fields(tmp_path, capsys):
    """The instrument check: a header that is not the same roster must be called
    MISALIGNED, never quietly compared field by field."""
    ref, lists = _corpus(tmp_path)
    _corrupt(ref, "model_count", 99)
    assert _run(ref, lists) == 1
    out = capsys.readouterr().out
    assert "1 misaligned sides" in out
    assert "model_count" not in out.split("field ")[-1].split("VERDICT")[0]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
