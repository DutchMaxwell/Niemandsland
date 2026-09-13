"""Planner week-1 (due 2026-09-20): the determinism probe.

`selfplay.play_game` plays 100 fixed seeds TWICE each; every seed's
`final_state_hash` — `selfplay.final_state_digest`, a SHA-256 over the whole
`State.plain()` the game ends with (positions, wounds, flags, mods, LOS, ...)
— must be identical across the two runs: 100/100.

`final_state_hash` rides the result only under `record_final_state=True`, the
`record_aux` pattern: a default call's `result_digest` must not move, so every
in-flight corpus and pinned constant stays byte-identical.

The seeds are pinned to 1..100 — the terrain bank's `board_<seed>.json` covers
them on the TEST host — and the planner knobs to the training corpus's own
`NML_TOP_K=2 NML_HORIZON=1` (`farm/mass_wave_template.sh:9`), so a re-run of
this file is the same 100 games. The receipt (per-seed hashes, aggregate root,
wall clock, peak RSS, machine fingerprint) is printed; run it with `-s` to
read it on green:

    PYTHONPATH=core/nml-core-py/python python -m pytest \\
        core/nml-core-py/tests/python/test_final_state_determinism.py -s -q
"""

from __future__ import annotations

import hashlib
import inspect
import json
import os
import platform
import resource
import sys
import time
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"

#: The probe's pinned games: seeds 1..100 and the corpus's own planner knobs.
SEED_START = 1
GAMES = 100
FAST = {"top_k": 2, "horizon": 1}


class _FakeState:
    """The one thing `final_state_digest` may touch: `.plain()`."""

    def __init__(self, plain: dict):
        self._plain = plain

    def plain(self) -> dict:
        return self._plain


def _machine_fingerprint() -> str:
    """`uname -a` fields + CPU model + cores + RAM, no subprocess."""
    uname = platform.uname()
    cpu = ""
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text().splitlines():
            if line.lower().startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    if not cpu:
        cpu = platform.processor() or "unknown"
    ram_kb = "unknown"
    meminfo = Path("/proc/meminfo")
    if meminfo.exists():
        for line in meminfo.read_text().splitlines():
            if line.startswith("MemTotal:"):
                ram_kb = line.split()[1]
                break
    return (
        "uname='%s %s %s %s %s' cpu='%s' cores=%s ram_kb=%s"
        % (uname.system, uname.node, uname.release, uname.version, uname.machine,
           cpu, os.cpu_count(), ram_kb)
    )


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def test_the_final_state_digest_is_canonical():
    """The hash is over the STATE, not over dict order: equal plain states
    hash equal, a moved model changes it. No game and no terrain bank needed,
    so this contract is checked on every machine, skip or no skip."""
    a = {"round": 4, "units": {"p1:u": {"wounds": [1, 0], "positions": [[1.0, 0.0]]}}}
    b = {"units": {"p1:u": {"positions": [[1.0, 0.0]], "wounds": [1, 0]}}, "round": 4}
    moved = {"round": 4, "units": {"p1:u": {"wounds": [1, 0], "positions": [[1.5, 0.0]]}}}
    assert sp.final_state_digest(_FakeState(a)) == sp.final_state_digest(_FakeState(b))
    assert sp.final_state_digest(_FakeState(a)) != sp.final_state_digest(_FakeState(moved))


def test_the_final_state_hash_is_opt_in():
    """`record_final_state` defaults to False — the flag must not move any
    existing `result_digest`, the same promise `record_aux` makes."""
    assert inspect.signature(sp.play_game).parameters["record_final_state"].default is False


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_100_fixed_seed_games_have_identical_final_state_hashes():
    """The probe: two fresh-core passes over seeds 1..100, 100/100 equal."""
    seeds = list(range(SEED_START, SEED_START + GAMES))

    def play_all() -> dict[int, str]:
        core = nml_core.load(str(REPO))
        out: dict[int, str] = {}
        for seed in seeds:
            res = sp.play_game(
                seed, ARMY1, ARMY2, REPO, BANK_DIR, core,
                record_final_state=True, **FAST,
            )
            out[seed] = res["final_state_hash"]
        return out

    t0 = time.perf_counter()
    first = play_all()
    second = play_all()
    wall = time.perf_counter() - t0
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss

    mismatched = [s for s in seeds if first[s] != second[s]]
    root = hashlib.sha256(
        json.dumps([[s, first[s]] for s in seeds], sort_keys=True).encode("utf-8")
    ).hexdigest()
    for seed in seeds:
        print("DETERMINISM seed=%d final_state_hash=%s" % (seed, first[seed]))
    print(
        "DETERMINISM matches=%d/%d identical=%s seeds=%d..%d final_state_root=%s"
        % (len(seeds) - len(mismatched), len(seeds), not mismatched,
           SEED_START, seeds[-1], root)
    )
    print("DETERMINISM machine %s" % _machine_fingerprint())
    print("DETERMINISM wall_seconds=%.1f max_rss_kb=%d" % (wall, rss))
    if mismatched:
        for seed in mismatched[:5]:
            print("DETERMINISM mismatch seed=%d first=%s second=%s"
                  % (seed, first[seed], second[seed]))
    assert not mismatched, "final-state hash mismatch on seeds %s" % mismatched
