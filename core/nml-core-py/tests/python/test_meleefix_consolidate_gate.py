"""meleefix 2c: the replay gate's consolidation bar (`melee_replay_gate.read_consolidate`, the `consol` verdict).

The recorder writes a `kind:"consolidate"` line inside a charge's melee (epoch 96+). The gate keys it to the last act / auto line
before it (its own interleaved ordinal) and hands the core the recorded planner inputs. These cases pin:

1. the keys `read_consolidate` gives on a hand-written acts.jsonl, and that a line after a non-charge activation (or before the
   first one) is reported as mis-joined;
2. the verdict: a mis-joined line FAILS even when another line compared equal; a run with lines but no wipe PASSES (nothing to
   compare); wiped charges of which none was compared (0/0) FAIL; a consolidation that lands elsewhere FAILS; one that lands on
   the table's spot PASSES.

The core is a stub (as in `test_both_silent_gate.py`) that returns a fixed after-state per act, so the cases pin the gate's
bookkeeping, not the consolidation itself. Every act draws no dice on either side (both silent = equal).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = str(Path(__file__).resolve().parents[4])
IN = mrg.IN2M
SPOT = [[0.0, 0.0, 0.0], [2.0 * IN, 0.0, 0.0]]          # the survivor's two models, centroid (1 in, 0)
ELSEWHERE = [[0.0, 0.0, 1.0 * IN], [2.0 * IN, 0.0, 1.0 * IN]]


class _Next:
    def __init__(self, units):
        self._units = units

    def plain(self):
        return {"units": self._units}


class _Core:
    def __init__(self, after):
        self._after = after

    def set_header(self, header):
        pass

    def state_of(self, plain):
        return plain

    def resolve_with_tray(self, state, action, rng, tray):
        return _Next(self._after.get(action.get("probe"), {})), {"rolls": [], "unported": []}


class _Stub:
    def __init__(self, after):
        self._after = after
        self.offered: list[list] = []

    def load(self, repo):
        return _Core(self._after)

    def set_legacy_no_cond_ap(self, flag):
        pass

    def Tray(self, seed):
        return self

    def Rng(self, seed):
        return self

    def roll(self, n):
        pass

    def offer_consolidation(self, plans):
        self.offered.append(json.loads(plans))


def _write(d: Path, rows: list[dict]) -> None:
    d.mkdir(parents=True)
    head = {"kind": "header", "profiles": {"a": {"name": "A"}, "b": {"name": "B"}}, "terrain": None, "knobs": {}}
    (d / "acts.jsonl").write_text("\n".join(json.dumps(x) for x in [head] + rows) + "\n")
    (d / "dice.jsonl").write_text("")
    (d / "arena_stub.json").write_text(json.dumps({"dice_seed": 1}))


def _charge(probe: str, state: dict | None = None) -> dict:
    return {"kind": "act", "round": 1, "player": 1, "state": state or {},
            "pick": {"action": {"kind": mrg.CHARGE_KIND, "unit": "a", "charge": "b", "probe": probe}}}


def _hold(state: dict | None = None) -> dict:
    """A non-charge act line; its state is the charge before it's recorded next state."""
    return {"kind": "act", "round": 1, "player": 2, "state": state or {}, "pick": {"action": {"kind": 0}}}


def _consolidate(unit: str) -> dict:
    return {"kind": "consolidate", "act": 99, "plans": [{"t": "consolidate", "unit": unit}]}


def _units(a_alive: int, b_alive: int, a_pos=SPOT) -> dict:
    return {"units": {"a": {"alive": a_alive, "positions": a_pos}, "b": {"alive": b_alive, "positions": []}}}


def test_read_consolidate_keys_each_line_to_the_charge_it_was_written_in(tmp_path):
    _write(tmp_path / "g", [
        _charge("x"), {"kind": "played", "act": 1}, _consolidate("first"),
        {"kind": "auto", "act": 2, "action": mrg.CHARGE_KIND, "unit": "c"}, _consolidate("second"),
        {"kind": "auto", "act": 3, "action": 1, "unit": "d"},
        _hold(), _charge("y"), _consolidate("fifth"),
    ])
    consols, bad = mrg.read_consolidate(tmp_path / "g")
    assert consols == {1: [{"t": "consolidate", "unit": "first"}], 2: [{"t": "consolidate", "unit": "second"}],
                       5: [{"t": "consolidate", "unit": "fifth"}]}
    assert bad == []


def test_read_consolidate_reports_lines_after_a_non_charge_or_before_any_activation(tmp_path):
    _write(tmp_path / "g", [
        _consolidate("orphan"), _charge("x"), {"kind": "auto", "act": 2, "action": 1, "unit": "d"}, _consolidate("after auto"),
        _hold(), _consolidate("after hold"),
    ])
    consols, bad = mrg.read_consolidate(tmp_path / "g")
    assert consols == {}
    assert bad == [0, 2, 3]


def _run(tmp_path, monkeypatch, rows, after, report_only=False) -> tuple[int, _Stub]:
    _write(tmp_path / "g", rows)
    stub = _Stub(after)
    monkeypatch.setattr(mrg, "nml_core", stub)
    return mrg.run(tmp_path, REPO, "table", 0, report_only), stub


def test_a_partly_mis_joined_run_fails_though_one_line_compared_equal(tmp_path, monkeypatch, capsys):
    rc, stub = _run(tmp_path, monkeypatch,
                    [_charge("wipe"), _consolidate("a"), _hold(_units(2, 0)), _consolidate("stray")],
                    {"wipe": _units(2, 0)["units"]})
    out = capsys.readouterr().out
    assert rc == 1, out
    assert "consol: 1 equal, 0 differ of 1 wiped, 1 mis-joined" in out, out
    assert "FAIL — consol: 1 mis-joined line(s)" in out, out
    assert stub.offered == [[{"t": "consolidate", "unit": "a"}]]


def test_a_run_with_consolidate_lines_and_no_wipe_passes(tmp_path, monkeypatch, capsys):
    rc, _ = _run(tmp_path, monkeypatch, [_charge("both"), _consolidate("a"), _hold(_units(2, 3))],
                 {"both": _units(2, 3)["units"]})
    out = capsys.readouterr().out
    assert rc == 0, out
    assert "consol: 0 equal, 0 differ of 0 wiped, 0 mis-joined" in out, out


def test_wiped_charges_of_which_none_was_compared_fail(tmp_path, monkeypatch, capsys):
    """The table's record shows the wipe, the replay's after-state carries neither unit: the bar compared nothing (0/0)."""
    rc, _ = _run(tmp_path, monkeypatch, [_charge("lost"), _consolidate("a"), _hold(_units(2, 0))], {"lost": {}},
                 report_only=True)
    out = capsys.readouterr().out
    assert rc == 1, out
    assert "FAIL — consol: 0 mis-joined line(s); 1 wiped charge(s), 0 compared" in out, out


def test_a_consolidation_that_lands_elsewhere_fails(tmp_path, monkeypatch, capsys):
    rc, _ = _run(tmp_path, monkeypatch, [_charge("wipe"), _consolidate("a"), _hold(_units(2, 0))],
                 {"wipe": _units(2, 0, ELSEWHERE)["units"]})
    out = capsys.readouterr().out
    assert rc == 1, out
    assert "consol: 0 equal, 1 differ of 1 wiped" in out, out
    assert "FAIL — 0 of 1 charge acts are not FULL-equal, 1 consolidation(s) differ" in out, out


def test_a_consolidation_on_the_tables_spot_passes(tmp_path, monkeypatch, capsys):
    rc, _ = _run(tmp_path, monkeypatch, [_charge("wipe"), _consolidate("a"), _hold(_units(2, 0))],
                 {"wipe": _units(2, 0)["units"]})
    out = capsys.readouterr().out
    assert rc == 0, out
    assert "consol: 1 equal, 0 differ of 1 wiped, 0 mis-joined" in out, out
