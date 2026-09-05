"""GATE for the `deployment` knob (NML-1152 step 8) — test_knob_wiring style.

THE HOLE this guards: `play_game(deployment="arena")` rewires the PRE-GAME —
the roll-off moves BEFORE deployment and onto the tie-re-roll law, deployment
leaves the game stream entirely (per-side `seed + slot` generators inside the
Rust pipeline), and the winner deploys first. A cut wire (the mode string
accepted and stamped, never actually read) would leave every existing gate
green, because none of them runs a WHOLE game under the knob.

So, in the H6 mutation-guard shape:

- arena vs zone must play a DIFFERENT game (digest without the knobs block —
  the arena stamp lives there, so hashing it raw would pass a cut wire);
- the stamp must read back — result `knobs.deployment` AND the header stamp
  `play_game` feeds `Core.set_header` (observed through a forwarding proxy;
  the crate's knob struct ignores the key, the corpus is what reads it);
- the DEFAULT path must stay byte-identical to the pre-change code: seed 25
  at HEAD 9774621 (knob absent) digested `95f3afea…`; any default-path drift
  — a moved draw, a reordered header — trips it;
- arena must be DETERMINISTIC: same seed twice, same digest.

SKIP: needs the terrain bank and the private AI-list corpus outside the repo,
the same escape hatch `test_selfplay.py`'s corpus gate uses.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))

ARMY1 = LISTS / "alien_hives_1000.json"
ARMY2 = LISTS / "battle_brothers_1000.json"
SEED = 27

#: `sp.result_digest` over the seed-25 default game with its `knobs` block
#: stripped — the byte-identity reference for the "zone" path (wall time and
#: `dice_tally` are excluded by the digest's own law, stamps by the stripping:
#: at HEAD 9774621, the commit this knob landed on, the RAW digest was
#: `95f3afea…`; NML-1158a (#480) then stamped `knobs.fit_blend` onto every
#: result — popping that one key restores `95f3afea…` exactly, so the game
#: stream is unchanged and only stamp metadata moved. The stripped pin
#: survives future stamp additions; only an in-game or header drift trips it.
#: Re-pinned 2026-09-05 (armies-basename fix, DIGEST_DIVERGENCE_2026-09-05.md):
#: `armies` moved from the caller's absolute path to the list basename plus
#: `armies_sha256`; the game did not move.
DEFAULT_SEED_25_DIGEST = "ce46e9247e20ef58f50b659f5338ea44a8dca8f8917258b61d11a64e79633ec6"


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_knobs(result: dict) -> str:
    """`sp.result_digest` over the result with its `knobs` field removed first:
    under "arena" the block gains `knobs.deployment`, so the raw digest would
    move even if the knob changed nothing about the game itself."""
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


class _HeaderSpy:
    """Forwards everything to the real `Core`, keeps every `set_header` dict.
    The harness has no other way to read back a header it just set."""

    def __init__(self, inner):
        self._inner = inner
        self.headers: list[dict] = []

    def set_header(self, header):
        self.headers.append(header)
        return self._inner.set_header(header)

    def __getattr__(self, name):
        return getattr(self._inner, name)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_deployment_arena_vs_zone_plays_a_different_game():
    """Step 8 / 1: `play_game(deployment="arena")` must re-deploy and re-dice
    the pre-game — the same-seed game differs from the zone game with the
    knobs block stripped, and both stamps say which mode wrote them."""
    core = nml_core.load(str(REPO))
    zone = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core)
    arena = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="arena")
    assert "deployment" not in zone["knobs"], "the zone path grew a stamp — not byte-identical"
    assert arena["knobs"]["deployment"] == "arena"
    assert _digest_without_knobs(zone) != _digest_without_knobs(arena)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_the_arena_mode_is_stamped_into_the_result_and_header():
    """Step 8 / 2: the stamp must reach BOTH places the design names — the
    result's `knobs` block and the header knobs `Core.set_header` receives.
    The zone arm carries neither: a default game is the same object it was
    before this knob existed (the `objectives_layout` doctrine)."""
    core = nml_core.load(str(REPO))
    spy = _HeaderSpy(core)
    arena = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, spy, deployment="arena")
    assert arena["knobs"]["deployment"] == "arena"
    assert len(spy.headers) == 1
    assert spy.headers[0]["knobs"]["deployment"] == "arena"
    zone = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, spy)
    assert "deployment" not in zone["knobs"]
    assert len(spy.headers) == 2
    assert "deployment" not in spy.headers[1]["knobs"]


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_the_default_path_is_byte_identical_to_the_pre_change_code():
    """Step 8 / 3: a game with the knob absent must digest exactly what the
    pre-change code digested — the vintage-pin proof on a corpus seed. This is
    the test that fails if the arena branch leaked a draw into the game stream,
    reordered the header, or stamped the zone path. The knobs block is stripped
    before hashing (`_digest_without_knobs`): stamp metadata (`deployment`,
    `fit_blend`, …) may grow without the game moving — the raw digest at the
    9774621 vintage is recoverable from the stripped one by re-adding exactly
    the vintage's stamp set (proven when #480 landed: pop `fit_blend`,
    `95f3afea…` returns)."""
    # W5a: pinned to the legacy fidelity knobs — this test is about the
    # deployment knob, not the shipped-defaults flip, so it keeps the
    # ORIGINAL vintage pin instead of moving it for an unrelated reason.
    core = nml_core.load(str(REPO))
    r = sp.play_game(25, ARMY1, ARMY2, REPO, BANK_DIR, core, **sp.LEGACY_FIDELITY_KNOBS)
    assert _digest_without_knobs(r) == DEFAULT_SEED_25_DIGEST


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_the_arena_mode_is_deterministic():
    """Step 8 / 4: same seed twice under "arena" — identical games. The
    per-side streams are seeded `seed + slot`, the roll-off off the game
    stream, nothing wall-clock reaches the pre-game."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="arena")
    b = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="arena")
    assert sp.result_digest(a) == sp.result_digest(b)


def test_an_unknown_deployment_mode_raises_instead_of_falling_back():
    """`resolve_deployment` follows `resolve_sighting`'s rule: a corpus whose
    header claims a rung it did not play is worse than no corpus."""
    with pytest.raises(ValueError, match="deployment must be one of"):
        sp.resolve_deployment("table")


# --- the RULEBOOK's turn order (GF v3.5.1 p.6), `deployment="interleaved"` ----
#
# THE HOLE this guards: the alternation is invisible in the positions. Each
# side scores against its OWN `occupied` (solo_controller.gd:9044), so the
# interleaved game deploys to the SAME spots as the whole-side one — a cut
# wire would leave every position, digest and gate green. `placement_sequence`
# is the only observable, so it is what these tests read.


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_interleaved_alternates_and_starts_with_the_roll_off_winner():
    """The knob ON: the recorded sequence alternates the two slots end to end.
    Whole-side deployment would read 1,1,1,1,2,2,2,2 — that is the RED."""
    core = nml_core.load(str(REPO))
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="interleaved")
    seq = r["placement_sequence"]
    assert seq, "the interleaved branch must record the cross-side order"
    slots = [e[0] for e in seq]
    assert all(a != b for a, b in zip(slots, slots[1:])), (
        "one unit each, in turn (GF v3.5.1 p.6), got %r" % (slots,)
    )
    assert all(isinstance(e[1], str) and e[1] for e in seq), "each entry names its unit: %r" % (seq,)
    assert len(seq) == len(set(e[1] for e in seq)), "every unit is placed once: %r" % (seq,)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_interleaved_reorders_the_deployment_and_changes_nothing_else():
    """The second claim, and the tripwire: strip `placement_sequence` and the
    interleaved game IS the arena game — same positions, same dice, same
    result. If this ever parts, the deploy ladder has grown an enemy-aware
    term and every recorded arena fixture needs re-recording."""
    core = nml_core.load(str(REPO))
    arena = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="arena")
    inter = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="interleaved")
    assert "placement_sequence" not in arena, "the field rides the interleaved branch only"
    bare = {k: v for k, v in inter.items() if k not in ("knobs", "placement_sequence")}
    assert sp.result_digest(bare) == _digest_without_knobs(arena)


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_the_interleaved_mode_is_stamped_and_deterministic():
    """A corpus must say which pre-game it played, and say it reproducibly."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="interleaved")
    b = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deployment="interleaved")
    assert a["knobs"]["deployment"] == "interleaved"
    assert sp.result_digest(a) == sp.result_digest(b)


def test_interleaved_is_a_known_mode():
    assert sp.resolve_deployment("interleaved") == "interleaved"
