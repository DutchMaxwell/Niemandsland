# Stage A position parity

The gate compares **the same action on the same board**, including its granted
movement band and fixed charge target. `AiPosition.solve`, target choice,
activation search, damage, and defender pile-in are outside this measurement.

`cases.json` contains one matched action from each of 168 paired solo game
recordings, plus generated cases. Each record includes both armies' physical
state, terrain/walls, board dimensions, the acting unit, and candidate target
IDs. The converter joins action and movement recordings by round, unit name,
and every moving model's starting position (maximum 0.0001 inch error). It
selects match `game_index % matched_actions`, without consulting solver output.
Hashes of both source JSONL files and their line numbers identify provenance;
private paths and names are omitted. Regenerate with:

```sh
python3 tools/position_parity_fixtures.py --corpus "$CORPUS_ROOT"
```

The action's band comes from the matched recorded movement request. Speed
bonuses have therefore already been applied; the harness does not derive a new
band from a roster. Only movement-relevant rule names are retained. This is a
physical-state replay, not an attempt to replay the game's combat or AI choices.
The original captures do not carry model yaw; fixtures use zero yaw on both
sides. Base dimensions and radii are retained, and the table adapter rejects a
rebuild whose base radius differs by more than 0.01 mm.

`tools/position_parity.gd` reconstructs real GameUnit/ModelInstance objects and
calls production `SoloController._move_toward` / `_charge_move`, including all
placement gates. Charges inside the production engagement limit then call
`snap_charge` with `last_move_remaining_in`, as the table does. A harness-only
subclass observes final-gate and whole-unit-shorten calls; it does not replace
their geometry. No gameplay script is modified.

The Rust side uses the existing `NmlCore.plan_unit_step` method with an optional
`position_action` field. That envelope carries a plain state, terrain, fixed
action and band; its marshalling adapter invokes the training core's existing
`mv::step::{plain_move,charge_move}`. Ordinary MOVE dictionaries follow the same
formation path as before. No signature or environment default changes.
For every recorded case a separate formation comparison also calls the ordinary
seam and `MovementPlanner.plan_unit_step` with the original captured input.

## Coverage and equality

The extension advertises implemented Stage A capabilities. The harness compares
those with the table stages actually entered. Unimplemented stages count as
unit and model declines even when the coordinates coincide. `by_reason` is
multi-label: one position can expose both a charge gate and a snap gap. Reason
counts therefore need not sum to the declined unit count. Shape coverage is
conservative: a final-gate call with a live non-round base in its obstacle
universe exposes the missing shape capability, even if that base is distant.

Per-model equality uses world-coordinate distance / 0.0254 <= 1e-9 inch.
`within_0.5in` includes equality. A unit is equal/within only if **every** model
qualifies and no stage declined. Raw per-model deltas remain in the report for
declined positions; they do not inflate accepted parity. Model IDs and ordering
must match exactly. Wall time is reported separately and excluded from both the
baseline and determinism fingerprint.

Missing extension, missing output, script errors (English or German), unknown
stages, missing models and nonfinite coordinates fail the harness. No fallback
answer counts as a Rust result. The regression gate pins fixture bytes, case
IDs, model IDs, per-model distance buckets, existing accepted deltas, formation
buckets and individual decline reason counts. Aggregate improvements cannot
hide an existing case getting worse.

## Run

Build once, install the optional manifest, and import before launching tests:

```sh
cargo build --manifest-path core/Cargo.toml -p nml-core-godot --release -j2
bash core/install_gdextension.sh
godot --headless --editor --path . --import --quit
python3 tools/position_parity.py --out /tmp/position-parity --runs 3
python3 -m pytest test/position_parity_driver_test.py -q
```

On a shared machine wait for >=3500 MB available RAM and no other Cargo/Godot
job of the corresponding kind before build/import. The Python driver applies
that RAM check and serializes its Godot runs, also checking other Godot PIDs.
Use a dedicated CI runner to avoid unrelated launch races.

The initial baseline is generated only after three identical runs with
`--record-baseline 'Initial Stage A measurement'`. Subsequent updates must name
the concrete port or justified fixture change. CI never supplies that option.
`--check-report` runs the regression gate on saved raw results, allowing a
one-model mutation to prove that the checked-in baseline rejects regressions.
Repeat `--check-report` with distinct saved report paths to verify determinism
without relaunching completed runs. Baseline creation still requires three
matching reports and an explicit reason; normal CI launches three fresh runs.
