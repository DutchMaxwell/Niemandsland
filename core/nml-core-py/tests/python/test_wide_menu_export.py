"""NML-1073 — Gen-1 `menu_wide="table"` wide-menu shard-export RED/GREEN.

FINDING (netlab prep agent, corroborated here on a 300-record uniform
sample of the Gen-1 value-player corpus, seed 7, and on a full scan of all
six `~/selfplay_out/gen1_records/box*` directories, ~47.7k records /
2.52M recorded positions): 142/300 sampled games (47.3%) are refused whole
by `gen0_replay_shards.replay_game()` with `Unsupported::TooManyCandidates`
— ALL 142, no other divergence cause. The corpus-wide scan puts a position
above `tokens.rs`'s old `N_CAND = 80` cap in 86,893/2,516,427 positions
(3.45%), but those positions cluster: 24,884/47,731 games (52.1%) carry at
least one, so the exporter's whole-game refusal throws away roughly half
the Gen-1 corpus. Width distribution over the full scan: p50 34, p90 67,
p95 76, p99 93, p99.9 109, max 136.

Gen-0 (hand teacher, `menu_wide` off) never saw this: its narrower menus
never approached 80. `menu_wide="table"` is now a SHIPPED default, so
Gen-1 (and every corpus after it) will keep hitting this.

DECISION (a) — raise the cap, no truncation: `netlab/token_data.py`'s
`ShardSet.pad_batch` (READ-ONLY, private; verified by inspection, not
edited here) buckets a batch EXACTLY on `(units, cands)` counts read off
each position's own `cands_ptr` segment width and pads to THAT batch's own
width — never to a fixed global constant. `token_policy.py`'s
`TokenPolicyModel.forward` reads `C = cands.shape[1]` at call time (a
cross-attention over a dynamic sequence length), so no weight matrix is
shaped by `N_CAND` either. `netlab/token_data.py` DOES carry its own
module-level `N_CAND = 80`, but grep across every `netlab/*.py` file shows
it is never referenced outside that one assignment — vestigial
documentation, not a real constraint. Nothing downstream depends on the
Rust-side cap's exact value, so raising it is free: `tokens::build` still
pads a single position's own export to `N_CAND` internally, but
`gen0_replay_shards.export()` immediately re-slices back down to the
position's true live count (`t["cands"][:nc]`) before it ever reaches the
packed, ptr-based, ragged shard — the padding never leaves `tokens.rs`.
Option (b) (truncate to 32, keeping `cands.played` + the hand best) was
rejected: it would throw away real search alternatives from a third of
Gen-1's already-scarce wide-menu positions for no measured benefit, since
the consumer places no upper bound on menu width at all.

New cap: `N_CAND = 160` — comfortably above the measured full-corpus max
(136) and its own p99.9 (109), room enough that a next corpus (also
`menu_wide="table"`, bigger point-cost lists) needs no immediate re-bump.

RED/GREEN below is a REAL played game, not hand-edited JSON: hand-editing
`row["cands"]["list"]` would make `gen0_replay_one.forced_pick`'s own
`menu_diff` check (the replay-fidelity tripwire, PR #564) diverge on a
menu-width MISMATCH before ever reaching `policy_tokens` — a different,
unrelated failure. `selfplay.play_game(seed=1, blood_brothers_2000 vs
change_disciples_2000, menu_wide="table", top_k=1, horizon=1)` is fully
deterministic and needs only the checked-in terrain bank + 2000pt list
fixtures (`needs_fixtures` below) — no dependency on the private,
uncommitted `~/selfplay_out/gen1_records` corpus. Round 3/seq 39/side 1 of
that game genuinely computes a 109-candidate menu (measured; `best` ==
`played` == 95, no `pool_value_fn` re-rank in play here).

RED measured by hand against this file's parent commit (`N_CAND = 80`,
before the fix in this PR): `gen0_shard_00000.json` shows
`{"file": "gen0_s1_d1.json", "positions": 0, "recorded": 73,
"divergence": "TooManyCandidates(95)"}` — `replay_game()` aborts the WHOLE
game at the first over-cap position it reaches (round/seq earlier than the
109-wide one; `Unsupported` unwinds straight out of the `with gr.armed(...)`
block), so none of the 73 rows are written, not just the 109-wide one.
GREEN (after `N_CAND = 160`): divergence `""`, all 73 rows exported, and
the shard's own `cands_ptr` segment width at the 109-wide position equals
109 with `label == 95` — the play carried through untouched, not
truncated.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import gen0_replay_one as gr  # noqa: E402
import selfplay  # noqa: E402

SHARDS_TOOL = str(Path(__file__).resolve().parents[2] / "tools" / "gen0_replay_shards.py")
BANK = Path(gr.BANK)
LISTS = Path(gr.LISTS)
P1 = LISTS / "blood_brothers_2000.json"
P2 = LISTS / "change_disciples_2000.json"

needs_fixtures = pytest.mark.skipif(
    not (BANK.is_dir() and P1.exists() and P2.exists()),
    reason="terrain bank or the 2000pt ai_lists mirror absent",
)

WIDE_SEED = 1
WIDE_ROUND, WIDE_SIDE, WIDE_SEQ = 3, 1, 39  # measured coordinates of the 109-wide position
WIDE_WIDTH = 109


def _build_wide_menu_record(out_dir: Path) -> tuple[Path, dict]:
    """One fixed-seed, real `menu_wide="table"` game — see module docstring
    for why this must be a genuinely played game, not edited JSON."""
    out = selfplay.play_game(
        WIDE_SEED, str(P1), str(P2), gr.REPO, str(BANK), None,
        top_k=1, horizon=1, dice_seed=WIDE_SEED, dice="table", deployment="arena",
        menu_wide="table", record_cands=True, record_aux=False,
    )
    rows = out["planner_positions"]
    widths = [len(r["cands"]["list"]) for r in rows]
    assert max(widths) == WIDE_WIDTH, (
        "fixture regression: seed %d no longer produces a %d-wide menu (got max %d) "
        "-- core RNG/menu logic moved, re-pin WIDE_* above" % (WIDE_SEED, WIDE_WIDTH, max(widths))
    )
    wide_idx = widths.index(WIDE_WIDTH)
    wide_row = rows[wide_idx]
    assert (wide_row["round"], wide_row["side"], wide_row["seq"]) == (WIDE_ROUND, WIDE_SIDE, WIDE_SEQ)
    out["prescreen"] = {"knobs": dict(out["knobs"], record_cands=True, record_aux=False)}
    path = out_dir / ("gen0_s%d_d%d.json" % (WIDE_SEED, WIDE_SEED))
    path.write_text(json.dumps(out), encoding="utf-8")
    return path, wide_row


@needs_fixtures
def test_a_109_wide_menu_position_exports_instead_of_refusing_the_whole_game(tmp_path):
    """GREEN (N_CAND raised): the game is not refused, every recorded
    position lands in the shard, and the 109-wide position's own segment
    and label survive untouched."""
    corpus_dir = tmp_path / "corpus"
    corpus_dir.mkdir()
    rec_path, wide_row = _build_wide_menu_record(corpus_dir)
    rec = json.loads(rec_path.read_text(encoding="utf-8"))
    rows = rec["planner_positions"]
    out_dir = tmp_path / "shards"
    p = subprocess.run(
        [sys.executable, SHARDS_TOOL, str(corpus_dir), "--lists", str(LISTS),
         "--limit", "1", "--shard-size", "1", "--workers", "1", "--out", str(out_dir)],
        capture_output=True, text=True,
    )
    assert p.returncode == 0, p.stdout + p.stderr
    index = json.loads((out_dir / "gen0_shard_00000.json").read_text())
    game_meta = index["games"][0]
    assert game_meta["divergence"] == "", game_meta  # RED on main: "TooManyCandidates(95)"
    assert index["positions"] == len(rows) == game_meta["recorded"]  # RED on main: positions == 0
    arrays = np.load(out_dir / "gen0_shard_00000.npz")
    ptr = arrays["cands_ptr"]
    widths = (ptr[1:] - ptr[:-1]).tolist()
    want_widths = [len(r["cands"]["list"]) for r in rows]
    assert widths == want_widths
    wide_idx = want_widths.index(WIDE_WIDTH)
    assert widths[wide_idx] == WIDE_WIDTH
    assert arrays["label"].tolist()[wide_idx] == wide_row["cands"]["played"] == wide_row["cands"]["best"]
