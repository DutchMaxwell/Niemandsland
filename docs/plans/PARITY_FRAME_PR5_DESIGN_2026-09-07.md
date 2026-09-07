# PARITY-FRAME PR 5 — the collapse ladder's own arithmetic (design note, 2026-09-07)

Series state: PR 1 (#767, the world frame) and PR 3 (#771, B1 inner solver) merged; PR 4 (#776, B2
cap circle + the f64 inch mirror) DRAFT pending its harness column; PR 2 folded (0 predicate flips);
the recorded-026 regression under B1 is pinned RED with its root cause in #799 (the closing push's
escape scan flips on ULPs of the straggler pull's pile input — the pull's own world-frame port is
the fix, its own PR). This note prepares PR 5: `recorded-037`, the largest accepted residue of the
corpus (0.7383 in on m0, all 21 models 0.12-0.74 in off), `models.beyond_0.5in` 5 -> 2 when closed.

## 1. What the harness measured (main = #771, three identical runs)

`recorded-037`: a 21-model RUSH at 16 in (20 x 25 mm round + a 40 mm hero, Strider), `gate_calls`
4, `shorten_calls` 4 on the table — the full plan is gate-shortened and the ladder re-plans at 12,
8 and 4 in. `table_budget_in` 16, `rust_budget_in` 12. The endpoint ledger (PR 3) replays the
table's FIRST gate call to 0.000003036 in and its whole-unit shorten to 0.0 in on the table's own
input, so the gate is not the stage: the RUNG CHOICE is. The table keeps the full rung (achieved
1.2440 in) and rejects the 12 in rung (1.3873 in); the core keeps the 12 in rung.

## 2. The table's ladder (solo_controller.gd:4947-4983) against the core's (step.rs:687-744)

    table: a3 = _achieved_m(positions, p3)                 # METRES, |anchor_of(after)-anchor_of(before)|
           keep if (c3 and not best_coherent) or (c3 == best_coherent and a3 > best_ach + 0.005)
           break if a3 >= b3 * 0.75 and c3
    core:  a3 = achieved_in(&starts, &p3)                  # INCHES, distance_to(centroid, centroid)
           keep if (c3ok && !best_coherent) || (c3ok == best_coherent && a3 > best_ach + 0.005 / IN2M)
           break if a3 >= r3 * 0.75 && c3ok

`anchor_of` (move_intent.gd:18) sums float32 `Vector3` WORLD positions in model order and divides
by `float(n)`; `_achieved_m` is the float32 `length()` of the anchor difference. The core's
`centroid` (flow.rs:58) sums float32 `V2` INCH positions in the same order, divides by `n as f32`,
and `distance_to` is the float32 inch length. Same operation order, different grid: the inch grid
is 1.6-3x coarser than the world grid on this board (PR 3 design note, section 1), and the margin
`0.005 / IN2M` = 0.19685039 in is compared in that frame. The 037 rung pair sits 0.1433 in apart —
0.05 in INSIDE the margin — so the margin arithmetic alone cannot flip it. Two candidates remain,
to be separated by the trace before any port:

  (a) the core's own rung PLANS differ from the table's (the planner at 12/8/4 in, the p.11 cap,
      the trim, `gate_caps` per rung) so its `a3`/`best_ach` are not 1.3873/1.2440 — the harness's
      `formation` block only proves the FULL-band planner equal (168/168);
  (b) the coherency verdicts differ: `coherent_placement` on the all-round fast path
      (`components_r`/`max_edge_spread_r`, float32 inch) vs `_config_coherent_world` on float32
      world shapes — `(c3ok && !best_coherent)` keeps a rung regardless of the margin. 037's
      `whole_unit_shorten` stage ran on the table (the full rung was NOT coherent-and-legal before
      the shorten), so a torn/coherent flip on a rung is live here.

## 3. RED (this branch, cargo level)

`test/fixtures/position_parity/collapse_ladder.json` pins the table's endpoints, `budget_in` 16
and the four rung values; `tests/position_parity_ladder.rs` replays the case through `plain_move`
at epoch 6 and asserts the kept band first, then the endpoints at 1e-4 in. On main it fails at
the band: `the ladder kept the 12 in rung, the table kept 16`.

## 4. Steps for PR 5 (<= 120 production lines, base main, never stacked)

1. Trace, test builds only: per rung `(reach, a3, c3ok, best_ach, best_coherent, kept)` from
   `Move::execute`, written past libtest's capture (the NML_GATE_TRACE_FILE pattern of #799), and
   the same numbers from the table via `position_parity.gd --diag=1` (extend `gate_trace` with the
   ladder rows: `_achieved_m`, `_config_coherent_world` per `_finalize_placement` call). Decide
   (a) or (b) on numbers.
2. If (a): the rung plan — pin the table's per-rung `_plan_move` output (the PR 6 instrument,
   brought forward) and close the planner/trim difference on that rung.
   If (b): `coherent_placement`'s all-round fast path reads `edge` on float32 WORLD shapes
   (`edge_w` on `WorldDisc::from_disc`) — a pure frame change, no epoch gate; the 168/168
   formation equalities must stay (the fast path is shared with the formation planner's
   predicates, see the PR 3 risk list) — measure them before and after.
3. Either way: `achieved_in` gets a world-frame twin `achieved_m` (float32 `Vector3` sums of the
   WORLD positions, `length()` in metres) and the ladder compares `a3 > best_ach + 0.005` in
   metres, as the table does. `Landing` gains a `ladder: Vec<(f64, f64, bool)>` field (add a field,
   never widen a signature) so the pin can assert every rung, not just the kept one.
4. GREEN: `budget_in` 16, endpoints <= 1e-4 in; `recorded-037` leaves the beyond-0.5 bucket
   (`models.beyond_0.5in` 5 -> 2); three identical harness runs in the PR body.
