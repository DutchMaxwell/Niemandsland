"""ANALYSIS MODE's `--stats` red-green — the corpus-wide counter has to
reproduce ANALYSIS_first_pass.md's cross-cutting numbers on the same five
games the first pass drew (`random.Random(20260902).sample(sorted_files, 5)`),
or it is measuring something else.

One number needs a note: the first pass's headline "13 of 17 charges never
reached contact" conflates two different questions. `INVESTIGATION_teacher_
defects.md` Q2 separates them on these same five games: 12 of 17 were
DECLARED BEYOND THE RUSH BAND (`s1873` A31 is the one exception — declared
from 6.89" on a 12" band, well inside it, and still fell short because the
RIGID mover left it 0.97" outside `MELEE_ENGAGE_IN`, a mover bug, not a menu
bug); only 4 of 17 produced a melee, so 17-4=13 "never reached contact". This
tool's `charges_beyond_band` field implements the task's own definition
("declared CHARGE whose gap exceeds the actor's rush band") literally, so it
asserts 12, not 13 — `charges_declared - charges_reached_contact` is the field
that reproduces the first pass's "13 of 17" number.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
GAMES = ["gen0_s314913_d317913", "gen0_s320488_d320488", "gen0_s1873_d1873",
         "gen0_s302919_d303919", "gen0_s53_d3053"]

needs_corpus = pytest.mark.skipif(
    not (all((CORPUS / (g + ".json")).exists() for g in GAMES) and BANK.exists() and LISTS.exists()),
    reason="Gen-0 corpus, terrain bank or ai_lists mirror absent",
)


def run_stats(out: Path) -> list[dict]:
    got = subprocess.run(
        [sys.executable, str(TOOLS / "game_narrator.py"), "--stats", str(out),
         *[str(CORPUS / (g + ".json")) for g in GAMES]],
        capture_output=True, text=True)
    assert got.returncode == 0, got.stderr[-4000:]
    return [json.loads(line) for line in out.read_text("utf-8").splitlines()]


def total(rows: list[dict], field: str) -> int:
    return sum(r[field] for r in rows)


@needs_corpus
def test_stats_mode_writes_one_line_per_game(tmp_path):
    rows = run_stats(tmp_path / "stats.jsonl")
    assert len(rows) == len(GAMES)
    assert {r["game"] for r in rows} == set(GAMES)
    assert total(rows, "activations") == 231, "231 activations across the five games (first pass)"
    assert not (tmp_path / GAMES[0]).exists(), "stats mode must skip narration/SVG output"


@needs_corpus
def test_stats_mode_reproduces_the_first_pass_numbers(tmp_path):
    rows = run_stats(tmp_path / "stats.jsonl")
    # "54 of 231 activations (23%) were HOLD with no shot and no movement"
    assert total(rows, "hold_nothing") == 54
    # "Only 34 of 231 activations (15%) drew a single die"
    assert total(rows, "acts_with_dice") == 34
    # Q1: "HOLD+shoot candidate offered ... 145" / "cannot execute (los_pairs) ... 95"
    assert total(rows, "shoot_offers_total") == 145
    assert total(rows, "shoot_offers_unexecutable") == 95
    # Q2: 17 chosen charges, 4 produced a melee -> 17-4=13 never reached contact
    # (the first pass's "13 of 17"); 12 of 17 were declared beyond the rush band.
    assert total(rows, "charges_declared") == 17
    assert total(rows, "charges_reached_contact") == 4
    assert total(rows, "charges_declared") - total(rows, "charges_reached_contact") == 13
    assert total(rows, "charges_beyond_band") == 12
    # Cross-cutting #5: "38 moves crossed a forest at exactly the full band".
    assert total(rows, "full_band_forest") == 38
    # Cross-cutting #6: two plain (non-CHARGE) moves cost models to dangerous terrain.
    assert total(rows, "dangerous_plain") == 2
    # Four hero-snipe activations named across the five games (Q1/Q3 discussion).
    assert total(rows, "hero_snipes") == 4


@needs_corpus
def test_sample_every_strides_like_gen0_stats(tmp_path):
    out = tmp_path / "strided.jsonl"
    got = subprocess.run(
        [sys.executable, str(TOOLS / "game_narrator.py"), "--corpus", str(CORPUS),
         "--sample-every", "50000", "--stats", str(out)], capture_output=True, text=True)
    assert got.returncode == 0, got.stderr[-4000:]
    rows = [json.loads(line) for line in out.read_text("utf-8").splitlines()]
    assert 1 <= len(rows) <= 4, "a 50000 stride over 143548 games should yield a handful"
