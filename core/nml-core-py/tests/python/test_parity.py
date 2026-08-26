"""GATE P (NML-1073 M3-1) — the ACT corpus replayed through the PYTHON module.

The Rust gates G4 (`core/nml-core/tests/plan.rs`) and G5 (`tests/arbitration.rs`)
already pin the search against the recording. This file asks the one question
they cannot: does the same search, driven from Python across the pyo3 seam,
still answer with the same activation?

A seam can break parity in ways the Rust side never sees — a dict read in the
wrong order (``units`` carries CAPTURE order in its key order), a float rounded
on the way in, a candidate key dropped on the way out. So the bar is the Rust
bar, field for field:

  * ``trace.scored``  — the ranked prefilter: same length, same ORDER, same
    (idx, unit, kind) per row and the 1-ply score to 1e-9;
  * ``trace.pool_idx`` — which candidates the four guarantees admitted, EXACTLY;
  * ``trace.rs``      — one rollout value per pool candidate, to 1e-9;
  * ``trace.best_idx`` / ``trace.runner_idx`` — exactly;
  * ``pick``          — unit_key, the action dict, expectation before/after to
    1e-9, ``waits``, ``runner_up`` and ``rolled_units`` as a set;
  * ``trace.arbitration`` — n, sum_b, sum_r, swapped, on the arbitrated corpus.

Plus the seam's own property, which no Rust gate covers: ``state_of(plain)
.plain() == plain`` on every act. That is what says the harness can hand a state
back to Godot, or to a checkpoint, without having quietly moved it.

Run it with the venv that carries the module:

    ~/venvs/nmlcore/bin/pytest core/nml-core-py/tests/python -s
"""

from __future__ import annotations

import json
import os
import statistics
import time
from pathlib import Path

import pytest

import nml_core

# The checkout the mechanics assets (`assets/solo/*.json`) are read from, and
# the fixtures the Rust gates use — one corpus, one bar, two callers.
REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"

#: Both sides are f64 written by ``JSON.stringify(.., full_precision = true)``,
#: so an exact hit is achievable and anything above this is a difference in the
#: arithmetic, not in the print.
EPS = 1e-9

#: The field list, in report order. Every name is one comparison the gate makes.
FIELDS = (
    "unit_key",
    "action",
    "expectation.before",
    "expectation.after",
    "runner_up",
    "waits",
    "rolled_units",
    "trace.scored",
    "trace.pool_idx",
    "trace.rs",
    "trace.best_idx",
    "trace.runner_idx",
    "trace.arbitration",
)


def load(name):
    """The header line plus every act of one corpus."""
    lines = (FIXTURES / name).read_text().splitlines()
    header = json.loads(lines[0])
    acts = [json.loads(x) for x in lines[1:] if x.strip()]
    return header, acts


def core_for(header):
    core = nml_core.load(str(REPO))
    core.set_header(header)
    return core


def close(a, b):
    return abs(float(a) - float(b)) <= EPS


def diff(act, got):
    """Every field on which the produced pick differs from the recorded one."""
    want = act["pick"]
    trace = act["trace"]
    bad = []

    if got["unit_key"] != want["unit_key"]:
        bad.append(("unit_key", f"{got['unit_key']} != {want['unit_key']}"))
    if got["action"] != want["action"]:
        bad.append(("action", f"{got['action']} != {want['action']}"))
    for half in ("before", "after"):
        if not close(got["expectation"][half], want["expectation"][half]):
            bad.append(
                (
                    f"expectation.{half}",
                    f"{got['expectation'][half]!r} != {want['expectation'][half]!r}",
                )
            )

    gru, wru = got["runner_up"], want["runner_up"]
    if bool(gru) != bool(wru.get("action")):
        bad.append(("runner_up", f"present {bool(gru)} vs recorded {bool(wru.get('action'))}"))
    elif gru:
        if gru["unit_key"] != wru["unit_key"]:
            bad.append(("runner_up", f"unit {gru['unit_key']} != {wru['unit_key']}"))
        elif gru["action"] != wru["action"]:
            bad.append(("runner_up", f"action {gru['action']} != {wru['action']}"))
        elif not close(gru["score"], wru["score"]):
            bad.append(("runner_up", f"score {gru['score']!r} != {wru['score']!r}"))

    if got["waits"] != want["waits"]:
        bad.append(("waits", f"{got['waits']} != {want['waits']}"))
    if set(got["rolled_units"]) != set(want["rolled_units"]):
        bad.append(
            ("rolled_units", f"{len(got['rolled_units'])} keys vs {len(want['rolled_units'])}")
        )

    gs, ws = got["trace"]["scored"], trace["scored"]
    why = None
    if len(gs) != len(ws):
        why = f"{len(gs)} rows vs recorded {len(ws)}"
    else:
        for rank, (g, w) in enumerate(zip(gs, ws)):
            if g["idx"] != w["idx"]:
                why = f"rank {rank}: idx {g['idx']} != {w['idx']}"
            elif g["unit"] != w["unit"]:
                why = f"rank {rank}: unit {g['unit']} != {w['unit']}"
            elif g["kind"] != w["kind"]:
                why = f"rank {rank}: kind {g['kind']} != {w['kind']}"
            elif not close(g["score"], w["score"]):
                why = f"rank {rank}: score {g['score']!r} != {w['score']!r}"
            if why:
                break
    if why:
        bad.append(("trace.scored", why))

    if got["trace"]["pool_idx"] != trace["pool_idx"]:
        bad.append(
            (
                "trace.pool_idx",
                f"{got['trace']['pool_idx']} vs recorded {trace['pool_idx']}",
            )
        )

    grs, wrs = got["trace"]["rs"], trace["rs"]
    why = None
    if len(grs) != len(wrs):
        why = f"{len(grs)} values vs recorded {len(wrs)}"
    else:
        for slot, (g, w) in enumerate(zip(grs, wrs)):
            if g["idx"] != w["idx"]:
                why = f"slot {slot}: idx {g['idx']} != {w['idx']}"
            elif not close(g["rs"], w["rs"]):
                why = f"slot {slot} idx {g['idx']}: {g['rs']!r} != {w['rs']!r}"
            if why:
                break
    if why:
        bad.append(("trace.rs", why))

    for field in ("best_idx", "runner_idx"):
        if got["trace"][field] != trace[field]:
            bad.append((f"trace.{field}", f"{got['trace'][field]} != {trace[field]}"))

    ga, wa = got["trace"]["arbitration"], trace.get("arbitration")
    if (ga is None) != (wa is None):
        bad.append(("trace.arbitration", f"present {ga is not None} vs {wa is not None}"))
    elif ga is not None:
        if ga["n"] != wa["n"]:
            bad.append(("trace.arbitration", f"n {ga['n']} != {wa['n']}"))
        elif not close(ga["sum_b"], wa["sum_b"]):
            bad.append(("trace.arbitration", f"sum_b {ga['sum_b']!r} != {wa['sum_b']!r}"))
        elif not close(ga["sum_r"], wa["sum_r"]):
            bad.append(("trace.arbitration", f"sum_r {ga['sum_r']!r} != {wa['sum_r']!r}"))
        elif ga["swapped"] != wa["swapped"]:
            bad.append(("trace.arbitration", f"swapped {ga['swapped']} != {wa['swapped']}"))

    return bad


def sweep(name):
    """One full replay of a corpus. Returns (clean, total, mismatch counts, first)."""
    header, acts = load(name)
    core = core_for(header)
    clean = 0
    counts = {}
    first = None
    declined = {}
    for i, act in enumerate(acts):
        state = core.state_of(act["state"])
        rec = act["trace"].get("arbitration")
        sig = rec["sig"] if rec else None
        got = core.plan_with_rollout(state, act["player"], act["statics"], sig)
        if not got["used"]:
            key = got.get("unsupported", "no candidate")
            declined[key] = declined.get(key, 0) + 1
            continue
        bad = diff(act, got)
        if not bad:
            clean += 1
        for field, why in bad:
            counts[field] = counts.get(field, 0) + 1
            if first is None:
                first = f"act {i} R{act['round']} p{act['player']}: {field}: {why}"
    return clean, len(acts), counts, first, declined


# --------------------------------------------------------------- instrument --


def test_the_module_is_the_one_this_checkout_built():
    """Before any measurement: the module has to be here, and it has to be able
    to read this checkout's mechanics assets — a `Core` with no profiles would
    decline every act and the gate would report green on nothing."""
    assert (REPO / "assets" / "solo").is_dir(), f"{REPO} is not the game checkout"
    header, acts = load("acts_25.jsonl")
    core = core_for(header)
    assert core.has_terrain(), "the 23-act corpus was recorded on a real board"
    assert core.knobs()["top_k"] == 6, "the recorded rollout budget is part of the contract"
    # A call before the header must fail loudly rather than answer for nothing.
    with pytest.raises(nml_core.Unsupported):
        nml_core.load(str(REPO)).state_of(acts[0]["state"])


# ------------------------------------------------------------------- gate P --


def test_p1_the_python_search_reproduces_every_recorded_pick():
    """acts_25.jsonl — 23 activations, the G4 field list, from Python."""
    clean, total, counts, first, declined = sweep("acts_25.jsonl")
    print(
        f"\nGATE P1 pick parity: {clean}/{total} activations reproduced on all "
        f"{len(FIELDS)} fields"
    )
    if counts:
        print("P1 mismatch counts:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    assert not declined, f"the port declined {declined}"
    assert clean == total == 23, f"{counts}\nfirst: {first}"


def test_p2_the_python_search_reproduces_every_arbitrated_verdict():
    """acts_arb.jsonl — 16 activations replayed WITH the recorded playout
    signature, so the stochastic arbitration replays instead of declining."""
    clean, total, counts, first, declined = sweep("acts_arb.jsonl")
    header, acts = load("acts_arb.jsonl")
    arbitrated = sum(1 for a in acts if a["trace"].get("arbitration"))
    print(
        f"\nGATE P2 arbitration parity: {clean}/{total} activations reproduced "
        f"({arbitrated} of them decided by the stochastic arbitration)"
    )
    if counts:
        print("P2 mismatch counts:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    assert arbitrated >= 5, f"only {arbitrated} arbitrated acts — the gate would measure nothing"
    assert not declined, f"the port declined {declined}"
    assert clean == total == 16, f"{counts}\nfirst: {first}"


def test_p3_a_close_top_two_without_a_signature_declines():
    """RED PROOF for P2: `sig` is an INPUT. An arbitrated act replayed WITHOUT
    it must decline, not guess a dice stream — otherwise P2's green would say
    nothing about the arbitration at all."""
    header, acts = load("acts_arb.jsonl")
    core = core_for(header)
    arbitrated = declined = 0
    for act in acts:
        if not act["trace"].get("arbitration"):
            continue
        arbitrated += 1
        got = core.plan_with_rollout(core.state_of(act["state"]), act["player"], act["statics"])
        if not got["used"] and got["unsupported"] == "PlayoutArbitration":
            declined += 1
    print(f"\nGATE P3 without sig: {declined}/{arbitrated} arbitrated acts declined")
    assert declined == arbitrated > 0, "a missing signature must never be guessed around"


@pytest.mark.parametrize(
    "name", ["acts_25.jsonl", "acts_arb.jsonl", "acts_hero_dead.jsonl"]
)
def test_p4_every_state_survives_the_round_trip(name):
    """`state_of(plain).plain() == plain` — the seam's own property. Exact, not
    to a tolerance: a plain state is what the recorder wrote, and a coordinate
    that moves by one ULP here would move silently everywhere."""
    header, acts = load(name)
    core = core_for(header)
    ok = 0
    first = None
    for i, act in enumerate(acts):
        back = core.state_of(act["state"]).plain()
        if back == act["state"]:
            ok += 1
        elif first is None:
            first = f"act {i}: keys {sorted(set(back) ^ set(act['state']))}"
    print(f"\nGATE P4 round trip {name}: {ok}/{len(acts)} states identical")
    assert ok == len(acts), first


def test_p5_an_unsupported_call_raises_rather_than_lying():
    """Errors are exceptions, never a wrong answer. KITE (4) has no `resolve`
    branch in the GDScript either, and an unknown unit key is not a HOLD."""
    header, acts = load("acts_25.jsonl")
    core = core_for(header)
    state = core.state_of(acts[0]["state"])
    key = state.keys()[0]
    with pytest.raises(nml_core.Unsupported, match="ActionKind"):
        core.resolve(state, {"unit": key, "kind": 4})
    with pytest.raises(nml_core.Unsupported, match="UnknownUnit"):
        core.resolve(state, {"unit": "no such unit", "kind": 0})
    with pytest.raises(nml_core.Unsupported):
        core.candidates(state, "no such unit")


def test_p6_the_harness_surface_answers():
    """The calls the milestone-3 harness needs beyond the search: resolve in
    expectation and under dice, the mission scorers and the eval."""
    header, acts = load("acts_25.jsonl")
    core = core_for(header)
    act = acts[0]
    state = core.state_of(act["state"])
    player = act["player"]
    action = act["pick"]["action"]

    after = core.resolve(state, action)
    assert after.round == state.round
    assert after.plain()["units"][action["unit"]]["activated"] is True
    assert state.plain()["units"][action["unit"]]["activated"] is False, "the input is untouched"

    # The CALLER owns the seed — tools/core_selfplay.gd:262-268 builds the
    # log-local one as game_seed * 100000 + row_index.
    a = core.resolve_stochastic(state, action, 7 * 100000 + 0)
    b = core.resolve_stochastic(state, action, 7 * 100000 + 0)
    assert a.plain() == b.plain(), "one seed, one outcome"

    assert isinstance(core.score(state, player), float)
    assert core.score_cheap(state, player) != 0.0
    threat = core.reply_threat(state, player)
    assert len(threat) == state.units

    menu = core.candidates(state, state.pool(player)[0])
    assert menu and all(c["kind"] in (0, 1, 2, 3) for c in menu)

    owners = [0] * len(act["state"]["objectives"])
    seized, owners = core.playout_seize(state, owners)
    assert len(owners) == len(act["state"]["objectives"])
    assert [o["owner"] for o in seized.plain()["objectives"]] == owners
    vp = core.vp_round_add(owners, [0, 0])
    assert sum(vp) == sum(1 for o in owners if o in (1, 2))
    assert core.vp_end_bonus([1, 1, 2], [0, 0]) == [1, 0]
    vp, memo = core.vp_score_round(owners, [0, 0], {}, {}, [])
    assert core.vp_score_end([1, 1, 2], [0, 0], {}) == [1, 0]
    markers, owners2, seq = core.apply_destroy_step(
        [{"owned_by": 1, "destructible": True, "destroyed": False, "destroyed_seq": 0}], [2], []
    )
    assert markers[0]["destroyed"] is True and seq == [1] and owners2 == [0]
    assert core.mission_winner("round_vp", owners, [3, 1], [], 10, 10) == "p1"
    counted = [0, 0]
    for unit in act["state"]["units"].values():
        counted[unit["player"] - 1] += max(unit["alive"], 0)
    assert state.alive_models() == counted


# ------------------------------------------------------------------- bench --


def test_p7_bench_reports_the_python_overhead():
    """What one activation costs from Python. The Rust reference is
    `cargo run --release --bin planbench`, which times the SAME 23 acts with the
    same knobs; the difference is what the seam charges per call.

    Not an assertion — a measurement. The number is printed (`pytest -s`) so a
    regression is visible, but a busy machine must not turn a bench into a red
    gate.
    """
    repeats = int(os.environ.get("NML_BENCH_REPEATS", "5"))
    header, acts = load("acts_25.jsonl")
    core = core_for(header)
    states = [(core.state_of(a["state"]), a["player"], a["statics"]) for a in acts]

    plans = []
    for _ in range(repeats):
        for state, player, statics in states:
            t = time.perf_counter()
            core.plan_with_rollout(state, player, statics)
            plans.append((time.perf_counter() - t) * 1e6)

    # The two marshalling halves on their own, so the overhead can be attributed
    # instead of guessed: reading a plain state in, and writing one back out.
    reads, writes = [], []
    for act in acts:
        t = time.perf_counter()
        state = core.state_of(act["state"])
        reads.append((time.perf_counter() - t) * 1e6)
        t = time.perf_counter()
        state.plain()
        writes.append((time.perf_counter() - t) * 1e6)

    print(
        f"\nGATE P7 bench ({len(plans)} calls over {len(acts)} acts x {repeats}):\n"
        f"  plan_with_rollout  mean {statistics.mean(plans):8.1f} us  "
        f"median {statistics.median(plans):8.1f} us  max {max(plans):8.1f} us\n"
        f"  state_of(plain)    mean {statistics.mean(reads):8.1f} us  "
        f"median {statistics.median(reads):8.1f} us\n"
        f"  State.plain()      mean {statistics.mean(writes):8.1f} us  "
        f"median {statistics.median(writes):8.1f} us"
    )
    assert plans


# ------------------------------------------------- the per-act profiles --


def test_p8_a_fallen_hero_stops_lending_its_rules_to_its_host():
    """GATE P8 (NML-1073 M2-5b, from Python) — the act line carries the profile
    fields a live game rewrites under the unit key ``prof``, and the search has
    to read the table THAT says, not the header's deployment reading.

    `acts_25.jsonl` cannot show this: its 299 ``prof`` blocks all still read the
    way the header does, so a module that ignored them would pass P1 anyway.
    `acts_hero_dead.jsonl` is the recording where one hero falls between two
    activations — his host stops inheriting his rules and GAINS every unit-wide
    rule he happened to lack, and the pick changes with it.
    """
    header, acts = load("acts_hero_dead.jsonl")
    assert len(acts) == 2, "the fixture is one activation before and one after the death"
    core = core_for(header)

    clean = 0
    picks = []
    for i, act in enumerate(acts):
        got = core.plan_with_rollout(
            core.state_of(act["state"]), act["player"], act["statics"]
        )
        assert got["used"], f"act {i + 1} declined: {got.get('unsupported')}"
        picks.append(got["unit_key"])
        bad = diff(act, got)
        if not bad:
            clean += 1
        else:
            print(f"P8 act {i + 1}:", bad)
    print(f"\nGATE P8 hero death: {clean}/2 activations reproduced; picked {picks}")
    assert clean == 2

    # The death has to change the ANSWER, or the fixture proves nothing.
    assert acts[0]["pick"]["unit_key"] != acts[1]["pick"]["unit_key"]

    # RED PROOF: act 2 with its `prof` blocks STRIPPED is the pre-M2-5b port —
    # the header's deployment reading, i.e. a hero who is still voting. It has
    # to answer differently, or P8's green would say nothing.
    stale_state = json.loads(json.dumps(acts[1]["state"]))
    for unit in stale_state["units"].values():
        unit.pop("prof", None)
    stale = core.plan_with_rollout(
        core.state_of(stale_state), acts[1]["player"], acts[1]["statics"]
    )
    assert stale["used"]
    bad = [field for field, _ in diff(acts[1], stale)]
    print(f"GATE P8 RED proof: act 2 without `prof` is off on {len(bad)} field(s): {bad}")
    assert bad, "a stale profile table has to be VISIBLE here, or this gate cannot fail"
