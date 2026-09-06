# Position parity: Stage A inventory

Source revision (`origin/main` when implementation began):
`f04a218edcf32f983d786f6eb7be7040730bee4b`.
PR 0 adds an instrument and baseline; it does not port a gameplay formula.

## Boundary resolved from the preflight

The preflight identified three different interfaces:

| Layer | Table | Rust | Stage A scope |
| --- | --- | --- | --- |
| Joint position selection | `AiPosition.solve` | No corresponding exposed solver | Excluded |
| Activation search | `AiPlanner.plan_with_rollout` | `NmlCore.plan_with_rollout` | Excluded |
| Fixed-action movement | `SoloController` -> `MovementPlanner` -> final gates and snap | `mv::step` -> `mv::plan` -> existing core gate | Included |

Stage A fixes the actor, action, goal/displacement, granted band, charge target,
and both armies on one board, then compares the final moving models by identity.
The neural planner supplies the action; this work measures its physical result.
It neither ports nor substitutes `AiPosition.solve`.

The existing MOVE method retains its arity. Its optional `position_action`
envelope forwards a plain state, terrain, action and band to the shared core
movement executor. Ordinary calls still run the original formation solver.
The harness-only adapter advertises implemented stage capabilities; it does not
reimplement geometry or use table output to repair the core's answer.

The reference constructs live model nodes and calls production movement methods.
A subclass observes final-placement and whole-unit-shorten calls, then delegates
to the original methods. For charge snap it applies the same engagement/remainder
checks as `main.gd` before calling production `snap_charge`.

## Fixture provenance and measurements

The converter joins 168 pairs of solo-game recordings by unit, round and all
moving-model start coordinates, then selects one action per game without using
parity outcomes. Generated cases add explicit coverage for large/oval bases,
formation, skirmish chains, terrain caps/exemptions, charges with/without contact,
walls, displacement budgets and placement repair. JSON includes board, terrain,
both physical armies, the fixed action and candidate target IDs.

Source hashes and JSONL line numbers are checked in; private paths and names are
not. Band values are the recorded movement request's effective granted band.
Combat profiles and target-scoring inputs are omitted because they cannot affect
this fixed-band movement experiment. Model yaw is absent from the source capture;
both reconstructed sides use zero yaw. The adapter verifies every base radius.

The three PR 0 matching runs contain 183 positions (168 games plus 15 generated cases),
1,302 moving models including attached heroes. It measured 2 equal positions,
16 all-models-within 0.5 inches, and 167 declined. Accepted models: 6 equal,
50 within 0.5 inches, 0 beyond; 1,252 declined. Equality is included in within.
All 168 ordinary formation calls equal both Rust and their recorded output.
The 14 accepted but non-equal positions have maximum delta 0.000008214 inch;
this residual difference bucket remains visible under the strict equal metric.

Three actual engine runs produced identical full result sets, wall timing
excluded. Their common SHA-256 is:
`f995b247039c22596fe165af19760de7aac69b54ae0c0994462c6f52c3f3eb85`.
The final driver verified all three saved reports before writing the baseline.

```text
parity: n=183 equal=2 within_0.5in=16 declined=167 by_reason={"base_shapes":147,"boxed_escape":16,"caught_panic":0,"charge_final_placement":11,"charge_snap":6,"coherency_hold":0,"parse_error":0,"skirmish_chain":1,"whole_unit_shorten":70}
```

Instrumented call totals in seconds (timing is not an equality metric):

| Run | Table | Rust |
| --- | ---: | ---: |
| 1 | 814.782619 | 9.446966 |
| 2 | 823.238358 | 9.403916 |
| 3 | 817.494136 | 9.331275 |

The wide sweep (PR 7) adds 121 generated positions across base footprints,
game systems, board sizes, terrain densities against each movement exemption,
charge reaches, formation shapes, skirmish spreads, board edges, wall lanes and
attached heroes. On 304 positions and 1,702 moving models the harness measures
`n=304 equal=15 within_0.5in=302 declined=0`; five models remain beyond half an
inch, in `recorded-037` and `generated-board-72x48-charge`.

The fixture README defines reproduction and strict equality (1e-9 inch).
A one-inch mutation of the hold model fails the real baseline gate (exit 1);
the original third-run report passes (exit 0). All 18 instrument tests pass.

## Declines and coverage gaps

`mv::entry::plan_unit_step_call` accepts every successfully parsed formation
call. MOVE boundary failures are parse errors or caught panics. The search's
`sim::Unsupported` variants are outside this Stage A experiment.

| Decline reason / residual bucket | Measured positions | Closing PR |
| --- | --- | --- |
| base_shapes | 0 | PR 1: non-charge; PR 3: charge |
| whole_unit_shorten | 0 | PR 2: 56 closed; PR 4: 14 boxed continuations |
| boxed_escape | 0 | PR 4 (#735) |
| accepted non-equal endpoints (difference, not decline) | 178 | localised below |
| charge_final_placement | 0 | PR 3 (#730) |
| charge_snap | 0 | PR 3 (#730) |
| skirmish_chain | 0 | PR 6 (#750) |
| coherency_hold | 9 (wide sweep) | PR 7 |
| parse_error | 0 | no observed failure |
| caught_panic | 0 | no observed failure |

Coverage gaps count as declines even if endpoint coordinates coincide.
Reason counts overlap: a charge can expose a gate skip and a missing snap.
The aggregate declined count counts that position once. Shape coverage is
conservative: a gate with any live non-round obstacle exposes the missing shape
capability, even when the current result does not touch that obstacle.
The inventory counts above reflect PR 4; the measurements above preserve PR 0.

A missing extension, invalid reference rebuild, missing output/model, unexpected
stage, or nonfinite coordinate fails the instrument instead of manufacturing a
parity result. Declined positions retain diagnostic deltas but never contribute
to accepted equality or the accepted half-inch count.

## Accepted non-equal endpoints — localisation

An accepted position whose endpoints are not bit-equal is a difference, not a
decline; after the shape, shorten, charge and boxed-escape ports there are 178
of 182 accepted. `diag=1` traces the
reference table's own gate, overlap-push and shorten calls,
`endpoint_localisation.json` pins the first call of each for the outliers, and
`mv::gate::endpoint_localisation` replays those through the same core functions
on the table's own input, so each difference is attributed to ONE stage.

| Class | Cases | Largest | Measured cause |
| --- | ---: | ---: | --- |
| Coordinate-space residue | 171 | 0.0000082 in | The core gate holds centres as f64 in the planner's INCH frame, the table as float32 world metres: a few float32 units in the last place. |
| Shorten-amplified residue | 4 | 0.0000948 in | The same residue crossing a bisection branch of the whole-unit shorten. |
| `recorded-128` | 1 | 0.0941212 in | Overlap push: 2 of 21 models end 0.048 in apart on identical input, then the shorten amplifies it. Shorten and the other gate passes replay exactly. |
| `recorded-162` | 1 | 0.1223899 in | Pre-gate. The table's gate corrects nothing and the core gate replays it to 0.0000005 in, so the movement solver plans one of eleven models differently at the difficult-terrain cap. |
| `recorded-037` | 1 | 0.7382609 in | Collapse-ladder rung. The table keeps the full 16 in rung (achieved 1.244 in) and rejects the 0.75 rung (1.387 in) on the 0.005 m margin; the core accepts it and reports `budget_in` 12. Its gate replays to 0.0000031 in. |

None is table nondeterminism — three identical runs share one SHA. The residue
needs the gate to carry the table's float32 world-metre frame, a port of its
own; each outlier is an amplifier acting on that residue and is pinned so a
later port can only shrink it.

## Stage A formula audit

| Formula | Existing Rust implementation | Remaining gap / measurement |
| --- | --- | --- |
| Formation coherency | `mv/form.rs`: radius-aware link graph, penalties, projections | Raw seam comparison plus final-stage deltas |
| System chain limit | Both gate arms and the caller's ladder select 6 inches for a skirmish system, 9 otherwise, at the table epoch | Closed |
| Base geometry | `State::base_shape` feeds shared `geom::pair_gap_m` in gates, ladder and snap | All charge and non-charge footprints covered |
| Large bases | Recorded radii and footprints feed final corrections | Bounding-radius terrain rest matches the table |
| Difficult terrain | `mv/cap.rs` trims polylines; `mv/step.rs` replans at cap | Compare per-model trim, unit replan, and Flying/Strider exemptions |
| Gate displacement budget | `mv/step.rs::gate_caps` computes remaining per-model caps | Compare corrections after table gate and retrace |
| Non-charge final placement | `mv/gate.rs` includes epoch-6 shortening and table straggler repair | No observed shortening decline remains |
| Charge rest / overlap / coherency | Epoch-6 uncapped contact-aware terrain rest, shaped overlap, coherency repair and wall clamp | No observed decline remains |
| Charge snap | Shared footprint query, engagement reach, remaining arc budget, contact slack and residual rejection | Epoch-6 execution and diagnostic use the same snap |
| Boxed escape | Epoch-6 room probe, granted-band rotation search, coherent-first choice and round budget | Compared against the acting unit's own chain |
| Coherency hold | Epoch-6 hold: torn at every rung from a coherent start returns zero band and the start positions | Closed; exposed only by the wide sweep |
| Walls | Both planners route around walls; core non-charge gate clamps crossings | Compare final per-model endpoints and separate formation results |
| Charge corridor | Table declaration probe routes, trims, finalizes and probes contact | Stage A covers execution geometry; declaration/target selection is outside the fixed-action input |
| Numeric conversions | Core explicitly models several Vector3 float32 roundings | 178 accepted non-equal positions, attributed per stage below |

Generated cases enter both contact and no-contact charge gates; the 14-inch
charge exposes exhausted snap slack. The difficult-terrain case grants 6 inches,
while the otherwise identical Strider/Flying cases grant 12 on both sides.
The packed case enters whole-unit shortening; the skirmish case also enters
boxed escape. Walls and large/oval bases each have explicit generated inputs.

The source audit excludes the joint solver's sampling, target enumeration, LOS
scoring, location weights, hard filters, difficulty-band selection and override
policy. These are not movement formula declines.

Relevant sources: `scripts/solo/solo_controller.gd` (`_execute_move`,
`_plan_positions`, `_finalize_placement`, `_shorten_world_to_legal`,
`_charge_move`, `snap_charge`); `scripts/main.gd::_run_ai_melee`;
`core/nml-core/src/mv/{entry,form,cap,gate,step}.rs`.
Several module comments predate implemented gate/ladder stages. Executable call
sites, especially the non-charge guard around `mv::step`'s final gate, define
coverage rather than those historical comments.

## Port order and regression gates

Order is determined by the measured decline/difference buckets, descending by
count; one bucket per PR. The initial proposed sequence is shown above; remeasure
after each port because overlapping coverage and residual-difference counts can
change. The small accepted residuals need a root-cause test before any port.
Charge-gate, shorten, shape and snap gaps remain separate ports. Zero is an observation on
this fixture set, not proof that the unexercised coherency-hold path is ported.

Each port starts with a failing Rust test and pins shared fixture values on both
sides. Reuse core geometry; use fields/wrappers instead of widening signatures.
Rule-dependent behavior belongs behind
`rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`. Existing environment defaults and
multiplayer remain untouched.

The gate pins fixture bytes, IDs/order, individual model distance buckets,
accepted model deltas, formation buckets and every decline count. Removing a
coverage gap cannot hide a regression elsewhere. Baseline writes require an
explicit reason and three identical runs. Timing is evidence, not equality.

Only after measured parity reaches the target should the series attempt the
fixed-seed arena gate. Every PR remains unmerged.

## PR 1: shape-aware final placement

`gate::Disc` now carries the recorded footprint alongside its bounding radius.
The moving models (including attached heroes) and live external obstacles read
`State::base_shape`, backed by the same dimensions and per-model radii the table
reconstructs. Overlap relaxation and coherency use `geom::pair_gap_m`; the
collapse ladder reads the same shaped graph. The all-round ladder retains its
original arithmetic. Terrain rest, wall chords and fallback escape scans keep
bounding circles, as their table counterparts do. Geometry is not epoch-gated.

The Rust RED pins `generated-oval-large` from the decline bucket: the circular
gate measured 4.791311318 inches against the table's 6.244360534-inch footprint
gap. Both tests read `cases.json` and `base_shapes.json`. Additional shared
short-axis, long-axis and clear-contact probes exercise moving and obstacle
ovals. No production GDScript or environment defaults change.

PR 1 advertised shape capability only for non-charge actions. Seven charge
fixtures retained their shape decline while the charge gate was skipped;
that remainder belongs to the charge-final-placement port.

PR 1's three complete runs agree: 183 positions, 4 equal, 97 within 0.5in,
82 declined; `base_shapes` falls 147 -> 7 and all other decline counts stay fixed.
Every endpoint matches the original raw report; removing conservative shape
coverage declines exposes four existing above-half-inch residuals (15 models),
without worsening any per-model tier or previously accepted delta. Those cases
are `recorded-005`, `recorded-079`, `recorded-138`, and `recorded-166`.

Three-run SHA-256 (timing excluded):
`ceed09f8894999d98de97000adb8ad702e98153b7075c71f4a980086dddae5ce`.

PR 2 acceptance: [three runs, test evidence and the 14-case remainder](https://github.com/DutchMaxwell/Niemandsland/pull/724).
PR 3 acceptance: [charge buckets closed, three runs and test evidence](https://github.com/DutchMaxwell/Niemandsland/pull/730).
PR 4 acceptance: [boxed escape, shared budget probes and three runs](https://github.com/DutchMaxwell/Niemandsland/pull/735).
