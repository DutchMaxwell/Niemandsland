"""`play_game(route_root=True)` hands #1480's root-move routing (`Knobs::route_root`) to every core of the game - both
seats and a deep seat, which copies the base header - and stamps it on the record; the default writes the identical
header and record (stamped only when on). RED: without the kwarg the header never carries the key."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1, ARMY2 = LISTS / "robot_legions_1000.json", LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(
    not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
    reason="needs the terrain bank + 1000pt lists")


class Spy:
    """A core proxy recording every header it is given."""
    seen: list = []

    def __init__(self, core):
        self.core = core

    def __getattr__(self, name):
        return getattr(self.core, name)

    def set_header(self, header):
        Spy.seen.append(dict(header["knobs"]))
        return self.core.set_header(header)


def _play(monkeypatch, **kw):
    Spy.seen = []
    real = nml_core.load
    monkeypatch.setattr(nml_core, "load", lambda repo: Spy(real(repo)))
    res = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, None, top_k=2, horizon=1, dice="table",
                       deep_player=1, deep_top_k=2, deep_horizon=1, **kw)
    return res, list(Spy.seen)


@needs_lists
def test_route_root_reaches_every_core_and_the_record_and_the_default_is_untouched(monkeypatch):
    off, heads_off = _play(monkeypatch)
    on, heads_on = _play(monkeypatch, route_root=True)
    assert heads_off and all("route_root" not in h for h in heads_off) and "route_root" not in off["knobs"]
    assert len(heads_on) >= 2 and all(h.get("route_root") is True for h in heads_on)   # base core + deep core
    assert on["knobs"]["route_root"] is True and on["winner"] in ("p1", "p2", "draw")
    assert off["planner_positions"] != on["planner_positions"]   # the core acts on it: the same game plays differently
