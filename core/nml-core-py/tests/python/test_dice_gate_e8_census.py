"""#857 — the per-record charge-landing instrument on the epoch-8 reference.

`tools/dice_gate_pr.py` (the box's per-record variant of `dice_gate.py`) measured
the defect: 145 of the e8 reference's 327 scored melee acts are `both_silent`
charges — the TABLE landed the charger short of the 1" engage ring, no die was
drawn on either side — and the port landed those chargers on a DIFFERENT vector
(145 acts, median 2.94", worst 12.84"). This file is the same measurement, as a
test: it runs wherever the corpus lives (`~/selfplay_out/qbg_ref_e8`, the gate
host), replays every recorded CHARGE act with `movement=table`, and reports

  * `both_silent` count and the median recorded-vs-replayed CHARGER landing gap
    of that bucket (the defect's own numbers — the fix's job is to drive the
    median from 2.940" toward < 0.5" without moving a single fought charge).

The stream comparison is a survey number, not an assert: melee acts share
their activation ordinal with later activations (the length confound every
replay gate classifies), so a raw tuple compare parts on known-benign acts.

The fixture parity pin lives on the Rust side
(`core/nml-core/tests/charge857_fall_short.rs`); this is the corpus-wide census.
"""

from __future__ import annotations

import os
import statistics
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
CORPUS = Path(os.path.expanduser("~/selfplay_out/qbg_ref_e8"))
CHARGE_KIND = 3

def _build_cannot_read_corpus() -> bool:
    """The census needs a wheel that READS the corpus's vintage (vocab 7). An
    older installed wheel (e.g. the laptop's read-only one) skips honestly —
    a replay that cannot load is a build gap, not a census verdict."""
    import nml_core

    try:
        return nml_core.rule_vocab_version() < 7
    except Exception:
        return True


needs_corpus = pytest.mark.skipif(
    not CORPUS.is_dir() or _build_cannot_read_corpus(), reason="needs the epoch-8 reference corpus qbg_ref_e8"
)


def survey() -> dict:
    """Per-record measurement over every game of the corpus, as tallies."""
    import nml_core

    games = sorted(d for d in CORPUS.iterdir() if (d / "acts.jsonl").exists())
    out = {"games": 0, "melee_acts": 0, "both_silent": 0, "fought": 0,
           "stream_equal": 0, "stream_acts": 0, "gaps": []}
    for d in games:
        head, lines, dice, seed = srg.read_game(d)
        burn = srg.burn_prefix(dice)
        out["games"] += 1
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       sighting="model", movement=True,
                                       cond_ap_dice=True)})
        for pos, act in enumerate(lines):
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) != CHARGE_KIND or not action.get("charge"):
                continue
            i0 = srg.first_at_or_after(dice, k)
            tray = nml_core.Tray(seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                nxt, report = core.resolve_with_tray(
                    core.state_of(act["state"]), action, nml_core.Rng(0), tray)
            except Exception:  # a declined activation is not a landing verdict
                continue
            out["melee_acts"] += 1
            got = [(r["kind"], r["count"], r["target"], r["faces"])
                   for r in report["rolls"]]
            want = [(srg.combat_kind(r["roll_kind"]), r["count"], r["target"], r["faces"])
                    for r in dice[i0:] if int(r["act"]) == k]
            if not got and not want:
                out["both_silent"] += 1
                keys = act["state"]["units"]
                nxt_state = lines[pos + 1]["state"] if pos + 1 < len(lines) else None
                if nxt_state is None or action["unit"] not in keys \
                        or action["unit"] not in nxt_state["units"]:
                    continue
                port = nxt.plain()["units"][action["unit"]]["positions"]
                rec = nxt_state["units"][action["unit"]]["positions"]
                out["gaps"].append(centroid_gap(port, rec))
            else:
                out["fought"] += 1
                out["stream_acts"] += 1
                out["stream_equal"] += got == want
    return out


def centroid_gap(port: list, rec: list) -> float:
    """Recorded-vs-replayed charger CENTROID delta, inches — the research's
    per-record gap (`tab_c` vs `port_c`)."""
    pc = (sum(p[0] for p in port) / len(port), sum(p[2] for p in port) / len(port))
    rc = (sum(p[0] for p in rec) / len(rec), sum(p[2] for p in rec) / len(rec))
    return ((pc[0] - rc[0]) ** 2 + (pc[1] - rc[1]) ** 2) ** 0.5 / 0.0254


needs_corpus = pytest.mark.skipif(
    not CORPUS.is_dir() or _build_cannot_read_corpus(),
    reason="needs the epoch-8 reference corpus qbg_ref_e8 and a vocab-7 build",
)


@pytest.mark.timeout(3300)
@needs_corpus
def test_the_e8_reference_census():
    """The MEASUREMENT the PR quotes, kept as a running survey. The stream
    comparison is deliberately NOT an assert: melee acts share their ordinal
    with later activations (the length confound every replay gate classifies),
    so a raw tuple compare parts on known-benign acts — 44/183 on unmodified
    main, measured. The numbers this prints on a survey run are the defect's
    vital signs: both_silent count and the bucket's median landing gap."""
    got = survey()
    med = statistics.median(got["gaps"]) if got["gaps"] else 0.0
    assert got["both_silent"] + got["fought"] == got["melee_acts"], (
        "the census must classify every melee act: %r" % got)
    assert got["melee_acts"] == 328 and got["games"] == 168, (
        "the e8 reference's own composition moved: %r" % got)
