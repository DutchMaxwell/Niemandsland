"""aifix harness: `eval_ab_one.py --base-preset / --base-knobs` puts a knob bundle on BOTH seats, the candidate
overlaying its own `--preset`, and the record stamps what each seat played. Without the flags the kwargs and the
stamp are exactly what every earlier run used. `play_game` is stubbed: the question is the plumbing."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import eval_ab_one  # noqa: E402
import selfplay  # noqa: E402


def _run(monkeypatch, tmp_path, *extra):
    seen = {}

    def fake_play_game(seed, army1, army2, repo, bank, core, **kw):
        seen.update(kw)
        return {"winner": "draw"}

    monkeypatch.setattr(selfplay, "play_game", fake_play_game)
    monkeypatch.setattr(sys, "argv", [
        "eval_ab_one.py", str(tmp_path), "--seed", "27", "--dice-seed", "27",
        "--army1", "a.json", "--army2", "b.json", "--cand-player", "1", *extra])
    assert eval_ab_one.main() == 0
    (rec,) = list(Path(tmp_path).glob("arena_*.json"))
    return seen, json.loads(rec.read_text())["prescreen"]


def test_without_the_flags_the_reference_seat_has_no_bundle(monkeypatch, tmp_path):
    kw, pre = _run(monkeypatch, tmp_path, "--preset", "afpoints_p1")
    assert kw["knob_overrides"] == selfplay.KNOB_PRESETS["afpoints_p1"]
    assert "knob_overrides_other" not in kw
    assert pre["knobs_by_seat"] == {"p1": selfplay.KNOB_PRESETS["afpoints_p1"]}


def test_a_base_preset_reaches_both_seats_and_the_stamp(monkeypatch, tmp_path):
    base, cand = selfplay.KNOB_PRESETS["aifix_all"], selfplay.KNOB_PRESETS["afpoints_p1"]
    kw, pre = _run(monkeypatch, tmp_path, "--base-preset", "aifix_all", "--preset", "afpoints_p1")
    assert kw["knob_override_player"] == 1
    assert kw["knob_overrides"] == {**base, **cand}
    assert kw["knob_overrides_other"] == base
    assert pre["knobs_by_seat"] == {"p1": {**base, **cand}, "p2": base}


def test_base_knobs_json_overlays_the_base_preset_for_both_seats(monkeypatch, tmp_path):
    base = selfplay.KNOB_PRESETS["aifix_all"]
    kw, pre = _run(monkeypatch, tmp_path, "--base-preset", "aifix_all", "--base-knobs", '{"menu_all_targets": 2}')
    assert kw["knob_overrides_other"] == {**base, "menu_all_targets": 2}
    assert pre["knobs_by_seat"]["p2"] == {**base, "menu_all_targets": 2}
    assert pre["knobs_by_seat"]["p1"] == {**base, "menu_all_targets": 2}
