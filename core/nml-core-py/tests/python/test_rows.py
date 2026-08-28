"""GATE R (NML-1073 M3-6a) — the encoder BOARD ROWS and the eval's FEATURE
VECTOR, rebuilt in Rust and checked against the Godot trainer's own record.

The trainer writes two things per activation that no other gate covers: the v5
encoder row block (``BattleSim.board_rows``) and the raw feature vector
(``AiMissionEval.features``, logged with ``rich`` ON). Both live in
``core_s<seed>.json`` under ``planner_positions``; the act line next to it
carries the plain state the same activation was decided on. So the question is
exact: rebuild the state from the plain form, ask the Rust port, compare.

ALIGNMENT. ``acts.jsonl`` carries the header on line 1 and then ONE act line per
activation in play order; ``planner_positions`` carries ONE row per activation
in the same play order (``tools/core_selfplay.gd:288`` appends the row for the
same pick the recorder writes the act for). The two are matched BY ORDER, and
the ``(round, side)`` pair of every matched couple is asserted equal — the test
fails if that pairing ever slips.

THE TWO STUB COLUMNS. ``tools/core_selfplay.gd:474`` hands every trainer unit a
fresh ``OPRApiClient.OPRUnit.new()`` and never copies quality/defense onto it,
so ``board_rows``'s ``q = od.quality`` / ``d = od.defense``
(battle_sim.gd:199-200) stamp the CLASS DEFAULTS 4/4 into every recorded row —
7411 of them, every single one a 4, which this test asserts rather than assumes.
The plain state carries ``u.get_quality()``, the list's real stat and what
``od.quality`` is in a game that is not the trainer's stub, so the port answers
the real stat and these two columns are counted apart. NML-1073 M3-6a finding.

Run it with the venv that carries the module, over the recorded games:

    NML_ORACLE_DIR=~/selfplay_out/m3_oracle_v2 \\
      ~/venvs/nmlcore/bin/pytest core/nml-core-py/tests/python/test_rows.py -s
"""

from __future__ import annotations

import glob
import json
import os
from pathlib import Path

import pytest

import nml_core

REPO_ROOT = str(Path(__file__).resolve().parents[4])
ORACLE = Path(
    os.environ.get("NML_ORACLE_DIR", str(Path.home() / "selfplay_out" / "m3_oracle_v2"))
)
#: `q` and `d` — the two columns the trainer's stub `OPRUnit` never fills.
STUB_COLS = (10, 11)

pytestmark = pytest.mark.skipif(
    not ORACLE.is_dir(),
    reason=f"no recorded games at {ORACLE} (set NML_ORACLE_DIR)",
)


def games():
    for d in sorted(glob.glob(str(ORACLE / "*") + os.sep)):
        core = glob.glob(os.path.join(d, "core_s*.json"))
        acts = os.path.join(d, "acts.jsonl")
        if core and os.path.exists(acts):
            yield os.path.basename(d.rstrip(os.sep)), core[0], acts


def cells_differ(got, want) -> bool:
    """One row cell, on the corpus's own terms: an int is exact, a float is 1e-9.

    The int/float split is not cosmetic — `JSON.stringify` writes a GDScript int
    without a decimal point, so a port that answered 4.0 where the row says 4
    would have changed the encoder's input format.
    """
    gi, wi = isinstance(got, int), isinstance(want, int)
    if gi != wi:
        return True
    return got != want if gi else abs(got - want) > 1e-9


#: NML-1112 replay switch, NOT a game knob — the sibling of
#: `list_to_profile.LEGACY_CORE_SELFPLAY` for the rule READING. `core_selfplay.gd`
#: runs no aura expansion, so a "Furious Aura" carrier in this corpus answered the
#: "Furious" query only through the pre-NML-1112 prefix match; two of the eight
#: games carry such a unit and recorded it into column 18 (the flag) and column 13
#: (melee EV). Neither reading is game-true — a real aura grants unit-wide, the
#: prefix gave it to the carrier alone. This gate pins the SEARCH LOOP, not the
#: rule; the loader gap is NML-1105.
LEGACY_PREFIX_RULES = True


@pytest.fixture(autouse=True)
def _legacy_prefix_rules():
    nml_core.set_legacy_prefix_rules(LEGACY_PREFIX_RULES)
    yield
    nml_core.set_legacy_prefix_rules(False)


def test_board_rows_and_features_match_every_recorded_activation():
    names = [n for n, _, _ in games()]
    assert names, f"no games under {ORACLE}"

    acts_n = rows_n = cells_n = keys_n = 0
    rows_bad = feat_bad = 0
    stub_seen = 0
    first = None

    for name, core_path, acts_path in games():
        pos = json.load(open(core_path))["planner_positions"]
        lines = [json.loads(l) for l in open(acts_path)]
        acts = [o for o in lines if o.get("kind") == "act"]
        assert len(acts) == len(pos), f"{name}: {len(acts)} acts vs {len(pos)} rows"

        core = nml_core.load(REPO_ROOT)
        core.set_header(lines[0])
        for k, (act, rec) in enumerate(zip(acts, pos)):
            assert (act["round"], act["player"]) == (rec["round"], rec["side"]), (
                f"{name} act {k}: the act and the logged row are not the same activation"
            )
            state = core.state_of(act["state"])
            acts_n += 1

            got, want = core.board_rows(state), rec["board"]
            assert core.board_row_indices(state) == rec["ids"], f"{name} act {k}: row indices"
            assert len(got) == len(want), f"{name} act {k}: {len(got)} rows vs {len(want)}"
            for ri, (gr, wr) in enumerate(zip(got, want)):
                rows_n += 1
                cells_n += len(gr)
                assert len(gr) == len(wr), f"{name} act {k} row {ri}: row length"
                bad = [
                    (ci, gc, wc)
                    for ci, (gc, wc) in enumerate(zip(gr, wr))
                    if cells_differ(gc, wc)
                ]
                for ci, _, wc in bad:
                    if ci in STUB_COLS and wr[0] not in (3, 4):
                        assert wc == 4, (
                            f"{name} act {k} row {ri} col {ci}: recorded {wc}, but the "
                            f"trainer's stub OPRUnit can only write its default 4"
                        )
                        stub_seen += 1
                real = [b for b in bad if b[0] not in STUB_COLS]
                if real:
                    rows_bad += 1
                    first = first or (name, k, ri, real, gr, wr)

            gf = core.features(state, rec["side"], rich=True)
            wf = rec["features"]
            assert set(gf) >= set(wf), f"{name} act {k}: missing feature keys"
            bad_f = []
            for key in sorted(set(gf) | set(wf)):
                keys_n += 1
                if abs(float(gf.get(key, 0.0)) - float(wf.get(key, 0.0))) > 1e-9:
                    bad_f.append((key, gf.get(key), wf.get(key)))
            if bad_f:
                feat_bad += 1
                first = first or (name, k, "features", bad_f)

    print(
        f"\nGATE R: {len(names)} games, {acts_n} activations, {rows_n} rows, "
        f"{cells_n} cells, {keys_n} feature comparisons; "
        f"{stub_seen} stub quality/defense cells (all 4)"
    )
    assert rows_bad == 0 and feat_bad == 0, f"first mismatch: {first}"


def test_the_committed_rule_vocabulary_covers_the_whole_corpus():
    """A name outside the vocabulary is collected loudly, never silently slotted.

    `BattleSim._rule_pairs` push_warnings and stamps such a name into
    `unknown_rules`; the port keeps the same collector, and on the recorded games
    it must stay empty — a non-empty set means the committed vocabulary
    (`data/encoder_rule_vocab_v1.json`) has fallen behind the army books.
    """
    unknown = set()
    for _, _, acts_path in games():
        lines = [json.loads(l) for l in open(acts_path)]
        core = nml_core.load(REPO_ROOT)
        core.set_header(lines[0])
        for act in lines:
            if act.get("kind") == "act":
                core.board_rows(core.state_of(act["state"]))
        unknown |= set(core.unknown_rules())
    assert not unknown, f"rules outside the committed vocabulary: {sorted(unknown)}"


def test_red_the_legacy_prefix_reading_is_what_this_corpus_recorded():
    """The shim, pinned both ways on the unit that made it necessary.

    `alien_hives_1000_vs_battle_brothers_1000_s101` slot `p1_0_lezKVcK` carries
    "Furious Aura" and no plain "Furious". Under the legacy prefix reading the
    Furious flag (board column 18) is 1, as recorded; under the shipped exact
    reading it is 0 — which is what makes this a fixture and not a bug.
    """
    name = "alien_hives_1000_vs_battle_brothers_1000_s101"
    hit = [g for g in games() if g[0] == name]
    if not hit:
        pytest.skip(f"{name} not in {ORACLE}")
    _, _, acts_path = hit[0]
    lines = [json.loads(l) for l in open(acts_path)]
    act = next(o for o in lines if o.get("kind") == "act")
    rules = act["state"]["units"]["p1_0_lezKVcK"]["prof"]["special_rules"]
    assert "Furious Aura" in rules and "Furious" not in rules, rules

    #: `BattleSim.FLAG_RULES` slot for Furious — rows.rs:51, row column 18.
    FURIOUS_COL = 18
    flags = {}
    for legacy in (True, False):
        nml_core.set_legacy_prefix_rules(legacy)
        core = nml_core.load(REPO_ROOT)
        core.set_header(lines[0])
        state = core.state_of(act["state"])
        ids = core.board_row_indices(state)
        ri = ids.index(0)
        flags[legacy] = core.board_rows(state)[ri][FURIOUS_COL]
    nml_core.set_legacy_prefix_rules(LEGACY_PREFIX_RULES)

    assert flags[True] == 1, "the prefix reading is what the corpus recorded"
    assert flags[False] == 0, (
        "the shipped exact reading must NOT see 'Furious' in 'Furious Aura' — "
        "if this is 1 the NML-1112 fix has been undone"
    )
