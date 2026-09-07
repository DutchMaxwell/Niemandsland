# PARITY-FRAME PR 3 — the overlap push in the table's float32 world frame (design note, 2026-09-07)
PR 2 (coherency predicates in the world frame) is FOLDED into this PR: on the 304-case corpus no predicate
verdict flips between the inch and the world read (90,336 model pairs x 3 thresholds, 0 flips; the straggler
pull's nearest-neighbour choice in 235 torn configs, 0 flips), so a predicate-only PR has no RED. Reference
branch, local only: `parity-frame-2-coherency-world` (542aa42f RED, 11633db3 measured WIP).
## 1. The third scale — where the rounding happens
The table moves centres as float32 world metres (separation_resolver.gd:113 float32 `Vector2` resultant in
loop order, :122-123 step `resultant * 0.0254f` + translate; read separation_checker.gd:295, float32
`distance_to` minus f64 radii). The core moves them in f64 INCHES (gate.rs:243 step, :256 escape, :446 cap)
and reads `edge` in f64 (:317 at :222). `WorldDisc::from_disc` (gate.rs:97-98) narrows such a centre to
float32 INCH first (`d.c as f32`), then applies the table order — a THIRD grid: ULP 3.8e-6 in for 32-64 in,
7.6e-6 above 64 in (the report said 7.6e-6 at 32-64: wrong), 1.6-3x coarser than the world grid (2.35e-6 in).
## 2. Measured (`cargo test -p nml-core --release`, endpoint_localisation and pins)
- recorded-037 overlap push on the table's own input: 2.246e-6 in on main; 2.0981e-5 in with the world-frame
  `edge` read through `from_disc` (WIP), 10x worse — the third scale compounding over 4 Gauss-Seidel passes and
  5 moved models. Whole gate 3.206e-6 in (bound 3.1e-6); the f32-inch OUTPUT quantisation of `finalize_placement`
  alone is 1.877e-6 in per axis on this case (max coord 52.77 in) — the API's own floor.
- recorded-003: 9.48e-5 in in the harness (shorten-amplified class with -105 9.04e-5, -026 7.50e-5, -106 3.51e-5);
  its PINNED table input replays the shorten at 0.000000000 in on main AND on the WIP: the residue enters through
  the core's OWN shorten input (the push above), not through the shorten's reads.
- A blend output read back through the table order misses on 7,446 of 28,548 fixture coordinates; the inverse of
  its own f64 write, `((c - board/2) * IN2M) as f32`, misses 0 (pinned on the reference branch).
## 3. Candidate fixes
A. Single-rounding read: `world()` converts a non-f32-exact centre with one rounding (the inverse write above),
   table order only for planner-fresh centres. ~10 production lines. Expected: back to main's ~2e-6 in on 037,
   not below — the push still accumulates in f64 inches; A only removes the self-inflicted loss.
B. The push in the table's loop: `resolve_overlaps`, `travel_to_clear`, `overlap_pass`, cap truncation on
   `WorldDisc` — float32 resultant in loop order, step `resultant * 0.0254f`, cap circle around the f32 planned
   world point (`_cap_gate_disp` solo_controller.gd:6438), `edge` on the f32 centre, radii from the metre truth
   (new `GateFlags.radii_m`, default `r_in * IN2M`; the inch radius is one f64 ULP short, PR 1). ~80-100 lines;
   split B1 (inner solver) / B2 (pass order + cap) above 120. Expected on 037: <= 1 world ULP (2.4e-6 in) or 0
   on identical input; 128's 0.048 in is localised, not explained — B instruments `resolve_overlaps`. Pick B.
## 4. RED for PR 3
`endpoint_localisation` (gate.rs:939-940): 037's overlap bound `0.0000023 -> 1e-9` fails on main at 0.000002246 in
(captured in 542aa42f); 128's `0.0482231 -> 1e-9` at 0.048223054 in. GREEN = new measured maxima, 037 <= 1e-6,
128 <= 1e-4; whole-gate bounds only shrink.
## 5. Carried from the reference branch
Needed: `edge` on `WorldDisc` (`pair_gap_m / IN2M`), `world()` at the seam, the RED above. Dropped to PR 4 (pull
and shorten chain): `overspread`/`largest_component`/`config_coherent` on `WorldDisc`, `GateFlags.board_in`,
`blended_world` and its read-back pin.
