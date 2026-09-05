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

The fixture README defines reproduction and strict equality (1e-9 inch).
A one-inch mutation of the hold model fails the real baseline gate (exit 1);
the original third-run report passes (exit 0). All 18 instrument tests pass.

## Declines and coverage gaps

`mv::entry::plan_unit_step_call` accepts every successfully parsed formation
call. MOVE boundary failures are parse errors or caught panics. The search's
`sim::Unsupported` variants are outside this Stage A experiment.

| Decline reason / residual bucket | Measured positions | Closing PR |
| --- | --- | --- |
| base_shapes | 7 | PR 1: non-charge closed; charge-gate remainder |
| whole_unit_shorten | 70 | PR 2 (proposed) |
| boxed_escape | 16 | PR 3 (proposed) |
| accepted non-equal endpoints (difference, not decline) | 97 | PR 4 (investigate first) |
| charge_final_placement | 11 | PR 5 (proposed) |
| charge_snap | 6 | PR 6 (proposed) |
| skirmish_chain | 1 | PR 7 (proposed) |
| coherency_hold | 0 | no observed case |
| parse_error | 0 | no observed failure |
| caught_panic | 0 | no observed failure |

Coverage gaps count as declines even if endpoint coordinates coincide.
Reason counts overlap: a charge can expose a gate skip and a missing snap.
The aggregate declined count counts that position once. Shape coverage is
conservative: a gate with any live non-round obstacle exposes the missing shape
capability, even when the current result does not touch that obstacle.
The inventory counts above reflect PR 1; the measurements above preserve PR 0.

A missing extension, invalid reference rebuild, missing output/model, unexpected
stage, or nonfinite coordinate fails the instrument instead of manufacturing a
parity result. Declined positions retain diagnostic deltas but never contribute
to accepted equality or the accepted half-inch count.

## Stage A formula audit

| Formula | Existing Rust implementation | Remaining gap / measurement |
| --- | --- | --- |
| Formation coherency | `mv/form.rs`: radius-aware link graph, penalties, projections | Raw seam comparison plus final-stage deltas |
| System chain limit | `mv/gate.rs` and `mv/step.rs` use `MAX_CHAIN_IN` | Table selects 6 inches for skirmish, 9 otherwise |
| Base geometry | `State::base_shape` feeds shared `geom::pair_gap_m` in the gate and ladder | Charge final-placement remains skipped |
| Large bases | Recorded radii and footprints feed final corrections | Bounding-radius terrain rest matches the table |
| Difficult terrain | `mv/cap.rs` trims polylines; `mv/step.rs` replans at cap | Compare per-model trim, unit replan, and Flying/Strider exemptions |
| Gate displacement budget | `mv/step.rs::gate_caps` computes remaining per-model caps | Compare corrections after table gate and retrace |
| Non-charge final placement | `mv/gate.rs` has bounds, overlap, terrain projection, coherency repair, wall clamp | Whole-unit shorten remains absent |
| Charge rest / overlap / coherency | Formation and shaped near-face aim exist | `mv/step.rs` skips the entire final-placement call when contact is allowed |
| Charge snap | `Landing::remaining_in` records budget minus longest model arc | MOVE endpoints precede table snap; reserve slack/contact checks remain a gap |
| Boxed escape | Core stops after the forward gate-collapse ladder | Table can rotate goals when its lateral-room probe succeeds |
| Coherency hold | Core prefers coherent ladder rungs | Table holds if every rung tears an initially coherent unit |
| Walls | Both planners route around walls; core non-charge gate clamps crossings | Compare final per-model endpoints and separate formation results |
| Charge corridor | Table declaration probe routes, trims, finalizes and probes contact | Stage A covers execution geometry; declaration/target selection is outside the fixed-action input |
| Numeric conversions | Core explicitly models several Vector3 float32 roundings | 97 accepted non-equal positions; investigate residuals before attributing cause |

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
Charge-gate,
shorten, shape and snap gaps remain separate ports. Zero is an observation on
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

Shape capability is advertised only for non-charge actions. Seven charge
fixtures still encounter the skipped charge gate and retain their shape decline;
that remainder belongs to the charge-final-placement port.

PR 1's first two complete runs agree: 183 positions, 4 equal, 97 within 0.5in,
82 declined; `base_shapes` falls 147 -> 7 and all other decline counts stay fixed.
Every endpoint matches the original raw report; removing conservative shape
coverage declines exposes four existing above-half-inch residuals (15 models),
without worsening any per-model tier or previously accepted delta. Those cases
are `recorded-005`, `recorded-079`, `recorded-138`, and `recorded-166`.
