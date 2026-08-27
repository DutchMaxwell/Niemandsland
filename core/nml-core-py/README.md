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
| `Core.resolve_stochastic_rng(state, action, rng) -> State` | the same against a LIVE `Rng`, advanced in place |
| `Core.capture_reads() -> dict` | the capture-time registry reads per unit (`morale_bonus`, `aircraft`, `charge_no_difficult`, `shroud`) |
| `Core.score(state, player) -> float` | `AiMissionEval.score` with the reply threat |
| `Core.score_cheap(state, player) -> float` | the same without it |
| `Core.reply_threat(state, player) -> list[float]` | expected reply wounds, in CAPTURE order |
| `Core.playout_seize(state, owners) -> (State, owners)` | the 3" ring |
| `Core.vp_round_add / vp_end_bonus / vp_score_round / vp_score_end` | the VP ledger |
| `Core.apply_destroy_step(markers, owners, seq)` | a destructible marker falls |
| `Core.mission_winner(scoring, owners, vp, markers, alive1, alive2) -> str` | the referee |
| `board(terrain) -> Board` | the header's `"terrain"` object as a lookup (`None` = no board) |
| `Board.n()` / `Board.is_valid()` | the grid width in cells; whether a board was carried |
| `Board.type_at([x, y, z]) -> int` | `TerrainOverlay.get_terrain_at_world_position` |
| `Board.los_blocked(a, b) -> bool` | `SchoolTerrain.los_blocked` — the seam `core_selfplay` stamps |
| `Board.los_pairs(units) -> list[str]` | `BattleSim.state_to_plain`'s `"los_pairs"` rows, key-sorted |
| `type_at` / `los_blocked` / `los_pairs` | the same three as one-shot module functions |
| `Rng(seed)` | Godot's `RandomNumberGenerator`, bit-exact: `.state` (get/set), `.seed()`, `.randf()`, `.randf_range()`, `.randi_range()`, `.rand_u32()` |

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

A whole GAME is the other case: one generator, seeded once, drawn from by the
deployment, the opener roll-off and every played activation in order. That is
`Rng` plus `resolve_stochastic_rng`, and the caller holds it.

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
| P9 | the `Board` surface, plus a red proof: an empty board blocks nothing |

`tests/python/test_selfplay.py` adds the M3-5 layer — the `Rng` stream against
`rng_range_godot.json`, the deployment arithmetic, the caster refill, the
capture round trip, and three RED-GREEN pairs for the seam knobs this milestone
added (see below).

## The terrain gate (NML-1073 M3-4)

`Board`'s answers are gated against GDScript oracles that do not fit in the
repo — 200 school boards written by `tools/terrain_bank_dump.gd` and the act
corpus of `tools/core_selfplay.gd`:

```sh
godot --headless --path . -s res://tools/terrain_bank_dump.gd -- \
    out=~/selfplay_out/terrain_bank from=1 to=200
~/venvs/nmlcore/bin/python core/nml-core-py/tools/los_gate.py \
    --bank ~/selfplay_out/terrain_bank --boards 20 \
    --corpus ~/selfplay_out/m3_oracle
```

| | |
| --- | --- |
| TYPE_AT | `Board.type_at` over each board's 3" lattice, versus the `SchoolTerrain.type_at` answers the generator wrote into it |
| LOS_PAIRS | `Board.los_pairs` versus the recorded `"los_pairs"` rows of every act, whole strings |
| LOS_BLOCKED | the same rows one pair at a time — the diff `tools/act_recheck.gd` prints as `LOS_GRID` |

`--red-lattice-shift-in=0.5` is the RED knob for the first (the lattice sits
0.25" short of each cell's far corner, so half an inch lands in the next cell);
the RED knob for the other two is dropping one of RUINS/CONTAINER/FOREST from
`terrain.rs::los_blocked` and rebuilding.

## Godot-free self-play (NML-1073 M3-5)

`python/selfplay.py` plays the whole game `tools/core_selfplay.gd` plays, with
no Godot in the loop: the army loader (M3-3), the zone deployment, the capture,
the alternating round loop, the round-end seize and the VP ledger, all of it
asking `nml_core` every rule question.

```sh
~/venvs/nmlcore/bin/python core/nml-core-py/python/selfplay.py \
    --army1 ~/nml-mission/farm/ai_lists/robot_legions_1000.json \
    --army2 ~/nml-mission/farm/ai_lists/blessed_sisters_1000.json \
    --seed 27 --games 20 --repo . --bank ~/selfplay_out/terrain_bank \
    --out ~/selfplay_out/m3_py
```

The gate compares whole games against the trainer's own output, seed for seed —
winner, objectives, VP, rounds played and the SEQUENCE of picks:

```sh
~/venvs/nmlcore/bin/python core/nml-core-py/tools/selfplay_gate.py \
    --ref ~/selfplay_out/m3_ref_v2 --bank ~/selfplay_out/terrain_bank \
    --army1 ... --army2 ... --seeds 27-46          # add --red for the red proof
```

### What the gate found — three changes in the crate, not in the harness

Each is a place where the port answered for the ARENA, whose corpora it was
built on, and the trainer differs. All three are guarded so no recorded corpus
moves, and each carries a red proof in `tests/python/test_selfplay.py`.

| | |
| --- | --- |
| `knobs.charge_gate` | `tools/core_selfplay.gd` never stamps `state["charge_illegal"]`, and both menu sites read it as `illegal_cb.is_valid() and illegal_cb.call(...)` (ai_planner.gd:1024/1308) — a gateless caller is offered charges the arena's gate refuses. Absent from every recorded header, so the default is `true`. |
| the sight refresh in `resolve` | `BattleSim._los_clear` probes `state["los_blocked"]` with the CURRENT centres, so a unit that just moved (or lost models, or routed) is seen from where it now is. `sim.rs` now rewrites the `los_pairs` row and column of every unit whose positions changed — only on the live board, and only when the parent carried a matrix. |
| `_safe_advance`'s open-fire-line penalty | ai_planner.gd:773-785 probes `los_blocked(enemy_centre, PROBE POINT)`, which no capture records; with the board in hand it is a question the terrain answers. Guarded exactly as the GDScript guards it, so a corpus without the seam keeps the penalty-free menu. |
