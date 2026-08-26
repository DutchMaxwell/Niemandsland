# nml_core — the Python seam (NML-1073 M3-1)

The Rust rules core (`core/nml-core`) as a CPython extension module, so a
harness can play self-play games with the Rust search on both sides and no
Godot in the loop. Nothing here re-implements a rule: the crate next door owns
the port, this one owns the marshalling.

## Build and install

```sh
# 1. a venv of its own (uv; `python3 -m venv` does the same job)
uv venv --python 3 ~/venvs/nmlcore
uv pip install --python ~/venvs/nmlcore/bin/python maturin pytest

# 2. build the module into it
cd core/nml-core-py
VIRTUAL_ENV=~/venvs/nmlcore \
CARGO_TARGET_DIR=~/.cache/nml-m3-1-target \
  ~/venvs/nmlcore/bin/maturin develop --release

# 3. the gate (23 + 16 recorded activations replayed through Python)
~/venvs/nmlcore/bin/pytest core/nml-core-py/tests/python -s
```

`maturin build --release` writes a wheel instead; install it with
`uv pip install --python ~/venvs/nmlcore/bin/python target/wheels/nml_core-*.whl`.

## API

```python
import nml_core

core = nml_core.load("/path/to/openTTS")   # where assets/solo/*.json live
core.set_header(header)                    # the act-corpus header line
state = core.state_of(plain)               # one plain state -> an opaque State
```

| call | what it answers |
| --- | --- |
| `load(repo_root) -> Core` | the per-game closure; feed it a header next |
| `Core.set_header(header)` | profiles + terrain + knobs, through `acts::read_act_header` |
| `Core.knobs()` / `Core.has_terrain()` | what the header resolved to |
| `Core.state_of(plain) -> State` | `BattleSim.state_to_plain` read back in |
| `State.plain() -> dict` | the same state written back out (exact) |
| `State.copy()`, `.keys()`, `.pool(player)`, `.alive_models()`, `.round`, `.rounds_total`, `.scoring`, `.units` | the harness's book-keeping |
| `Core.plan_with_rollout(state, player, statics, sig=None) -> dict` | `AiPlanner.plan_with_rollout` — pick + `trace` + `leaf_state` |
| `Core.candidates(state, unit_key) -> list[dict]` | the full menu of one unit |
| `Core.resolve(state, action) -> State` | `BattleSim.resolve` — in expectation |
| `Core.resolve_stochastic(state, action, seed) -> State` | `BattleSim.resolve_stochastic` |
| `Core.score(state, player) -> float` | `AiMissionEval.score` with the reply threat |
| `Core.score_cheap(state, player) -> float` | the same without it |
| `Core.reply_threat(state, player) -> list[float]` | expected reply wounds, in CAPTURE order |
| `Core.playout_seize(state, owners) -> (State, owners)` | the 3" ring |
| `Core.vp_round_add / vp_end_bonus / vp_score_round / vp_score_end` | the VP ledger |
| `Core.apply_destroy_step(markers, owners, seq)` | a destructible marker falls |
| `Core.mission_winner(scoring, owners, vp, markers, alive1, alive2) -> str` | the referee |

Plain dicts and lists in, plain dicts and lists out; a `State` is opaque because
handing the struct-of-arrays out per call would spend more time marshalling than
searching. Anything the port cannot answer raises `nml_core.Unsupported` with
the reason's own name (`ActionKind(4)`, `UnknownUnit`, `NetPlayout`, …). The one
exception is `plan_with_rollout`, where a decline is a VALUE —
`{"used": False, "unsupported": "PlayoutArbitration"}` — because the GDScript
answers `{"used": false}` too and a harness has to route on it.

## Two things the caller owns

**The seed.** `resolve_stochastic(state, action, seed)` seeds one `GodotRng` and
advances it for that call. The formula stays with the caller:
`tools/core_selfplay.gd:262-268` builds the log-local seed as
`game_seed * 100000 + row_index`, and `+ 50000` for the runner-up branch. This
module never invents one — a guessed dice stream is a silent lie.

**Nothing else.** The per-activation profile reading is NOT the caller's job:
`state_of` feeds each act's `prof` block through a `ProfileCache`/`StaticsCache`
pair exactly the way `acts.rs` does, so a state whose hero fell is searched on
the table that says so. `State.plain()` hands the `prof` blocks back verbatim —
two of their seven fields are deliberately unmodelled (`ProfileDyn`), so the
reader keeps what it read instead of inventing them. A state this port DERIVED
(`resolve`, a rollout leaf) carries none: it has no recorded read.

**The signature.** `sig` is `AiPlanner._playout_sig` at record time and is an
INPUT. Without it a close top-2 declines with `PlayoutArbitration` instead of
inventing a dice stream (gate P3 proves it does).

## Gate

`tests/python/test_parity.py` replays both recorded act corpora through the
module and holds the answer to the Rust gates' own bar (G4 `plan.rs`, G5
`arbitration.rs`), field for field:

| | |
| --- | --- |
| P1 `acts_25.jsonl` | 23/23 picks on all 13 fields |
| P2 `acts_arb.jsonl` | 16/16 picks, all 16 arbitrated, with the recorded `sig` |
| P3 red proof | 16/16 arbitrated acts decline without a `sig` |
| P4 round trip | 41/41 states identical after `state_of(...).plain()` |
| P5 | an unsupported call raises rather than answering wrongly |
| P6 | the harness surface (resolve, dice, mission scorers, eval) answers |
| P7 | bench, printed not asserted |
| P8 `acts_hero_dead.jsonl` | 2/2 across a hero's death, plus a red proof: the same act with its `prof` blocks stripped answers differently |
