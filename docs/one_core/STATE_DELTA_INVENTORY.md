# State-delta inventory (One core P4.0-3)

The core resolves an activation on a captured `State`, then hands a result back to the table. This
file lists every field of that `State` and asks, field by field, which of the return surfaces can
carry a change of it back to the table that ran the activation.

Source of the field list: `core/nml-core/src/state.rs` (`pub struct State`, line 462). The test
`test/one_core/state_delta_inventory_test.gd` re-parses that struct and reddens when a field is
missing here or listed here but gone from the struct. Add or remove a row in the table below in the
same commit as the struct change.

## Return surfaces

- **Delta** — `UnitDelta` (`core/nml-core/src/activation.rs:293`), filled by `delta_of`
  (`activation.rs:306`) and serialized by `delta_array` (`core/nml-core-godot/src/actcall.rs:73`).
  Fields: `unit`, `removed` (indices into the before-list), `shaken`, `alive`, `moved`, `unknown`.
  Landed by `land_delta` (`scripts/solo/core_activation.gd:383`), which writes only the Shaken marker
  and uses `unknown`/`alive` as a guard.
- **Landings** — per-step per-model `at`, `wounds_left`, `dead` (`land_step`,
  `scripts/solo/core_activation.gd:352`). This, not the delta, is what carries model wounds, deaths
  and positions back.
- **MP rows** — `rows` (`scripts/solo/core_activation.gd:965`): per unit
  `[unit_id, is_activated, is_shaken, [[model_index, wounds_current, is_alive, [x_mm, z_mm]], ...]]`.
  `rows_match` (:1062) compares them, `on_mismatch` (:1101) pushes the differing wounds, moves,
  rotations, Shaken marker and activation flag back.
- **Capture side (IN)** — what the core is told before the activation: the recorder's `ledger` (`AiActRecorder._ledger_of`,
  a recorded corpus format and the AI search's input, so unchanged) and, from the one-core door's capture only (C-10),
  `step_ledger` per unit (the Versatile pick, the reckless / retreating-strike / mind-control / regenerative-strength /
  piercing-spot round stamps) and the top-level `second_wind` (the army's grants of the round). Not on the wire yet:
  `piercing_tag_used` (the Piercing Tag latches are another lane's), `second_wind_used`'s per-unit flag rides the `ledger`.
- **Gap** — `YES` when the table reads/uses the field, an activation can change it, and none of the
  surfaces above carries the change back. Those are the fields where a core/table split stays
  invisible locally and, for most of them, also across the MP check.

## Inventory

| Field | Table reads it | Delta carries | MP rows carry | Gap? |
|---|---|---|---|---|
| `sidestep_budget` | solo_controller.gd:6367 | no | no | no (table-owned move budget) |
| `roster` | battle_sim.gd:2053 | no | no | no (structural input) |
| `profiles` | battle_sim.gd:2386 | no | no | no (structural input) |
| `round` | core_activation.gd:57 | no | no | no (table round) |
| `rounds_total` | core_activation.gd:59 | no | no | no (scenario input) |
| `scoring` | battle_sim.gd:2183 | no | no | no (scenario input) |
| `objectives` | battle_sim.gd:2169 | no | no | no (capture input) |
| `markers_meta` | battle_sim.gd:2195 | no | no | no (round-end state) |
| `destroy_seq` | battle_sim.gd:2196 | no | no | no (round-end state) |
| `attacker` | battle_sim.gd:2198 | no | no | no (mission input) |
| `vp` | battle_sim.gd:2186 | no | no | no (mission ledger) |
| `vp_flavour` | battle_sim.gd:2187 | no | no | no (mission input) |
| `vp_memo` | battle_sim.gd:2188 | no | no | no (mission ledger) |
| `cast_events` | battle_sim.gd:2286 | no | no | no (cast log input) |
| `player` | battle_sim.gd:2108 | no | no | no (structural input) |
| `alive` | battle_sim.gd:2110 | guard (`removed`/`alive`) | per model `is_alive` | no |
| `activated` | battle_sim.gd:2125 | no | yes | no (the table sets it) |
| `shaken` | battle_sim.gd:2123 | yes (`land_delta`) | yes | no |
| `fatigued` | battle_sim.gd:2124 | yes (`land_delta`, P4.0-4d) | no | no (delta) |
| `in_cover` | battle_sim.gd:2112 | no | no | no (capture input) |
| `aircraft` | battle_sim.gd:2106 | no | no | no (structural input) |
| `dormant` | battle_sim.gd:2130 | no | no | no (round-start state) |
| `dormant_models` | battle_sim.gd:2131 | no | no | no (arrival input) |
| `dormant_wounds` | battle_sim.gd:2132 | no | no | no (arrival input) |
| `casts` | battle_sim.gd:2126 | yes (`land_delta`, P4.0-4d) | no | no (delta) |
| `morale_bonus` | battle_sim.gd:2115 | no | no | no (capture input) |
| `ambush_arrived_round` | battle_sim.gd:2107 | no | no | no (round state) |
| `earliest_arrival_round` | battle_sim.gd:2133 | no | no | no (capture input) |
| `wound_frac` | battle_sim.gd:1844 | no | no | no (playout-only accumulator) |
| `positions` | battle_sim.gd:2109 | landings only | X/Z mm per living model | no |
| `wounds` | battle_sim.gd:2111 | landings only | per model | no |
| `radii` | battle_sim.gd:2098 | no | no | no (capture input) |
| `kits` | battle_sim.gd:2099 | no | no | no (capture input) |
| `kit_names` | battle_sim.gd:2040 | no | no | no (capture input) |
| `mods` | battle_sim.gd:2119 | no | no | no (capture input) |
| `mods_base` | battle_sim.gd:2122 | no | no | no (capture input) |
| `attached` | battle_sim.gd:2100 | no | no | no (structural input) |
| `attached_to` | battle_sim.gd:2101 | no | no | no (structural input) |
| `los` | battle_sim.gd:2166 | no | no | no (capture input) |
| `sees_tab` | — (core-derived from `los`) | no | no | no (core-derived) |
| `los_pairs` | battle_sim.gd:2319 | no | no | no (trainer seam input) |
| `bands` | battle_sim.gd:2251 | no | no | no (capture input) |
| `shroud` | main.gd:5118 | no | no | no (capture input) |
| `charge_no_difficult` | act_recorder.gd:846 | no | no | no (capture input) |
| `charge_probe_r` | act_recorder.gd:845 | no | no | no (capture input) |
| `buffs` | main.gd:447 | spent once buffs (`land_delta`, C-15); a buff the core ADDS is not carried | no | no (delta) |
| `vs_mark_round` | main.gd:24332 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `hit_and_run_round` | solo_controller.gd:12793 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `moved_round` | main.gd:1761 | yes (`land_delta`, P4.0-4e) | X/Z only | no (delta) |
| `delayed_action_round` | solo_controller.gd:9994 | no | no | **YES** |
| `coordinate_via_round` | game_unit.gd:333 | no | no | **YES** |
| `reckless_rolled_round` | main.gd:24471 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `reckless_ap_round` | main.gd:24502 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `reckless_backfire_round` | main.gd:24507 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `versatile_pick_round` | main.gd:15462 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `versatile_pick_mode` | main.gd:15471 | yes (`land_delta`, P4.0-4g) | no | no (delta) |
| `retreating_strike_round` | main.gd:8888 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `mind_control_moved_round` | main.gd:24569 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `growth_markers` | main.gd:24962 | yes (`land_delta`, C-13) | no | no (delta) |
| `growth_round` | main.gd:24968 | no | no | **YES** |
| `growth_strike_round` | main.gd:9335 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `vengeance_markers` | main.gd:8827 | yes (`land_delta`, P4.0-4f) | no | no (delta) |
| `second_wind_used` | solo_controller.gd:13886 | no | no | **YES** |
| `surprise_attack_used` | main.gd:25248 | no | no | **YES** |
| `reinforcement_used` | main.gd:16256 | no | no | **YES** |
| `second_wind_round` | solo_controller.gd:13833 | no | no | **YES** |
| `second_wind_uses` | solo_controller.gd:13833 | no | no | **YES** |
| `limited_used` | solo_controller.gd:9772 | yes (`land_delta`, C-11) | no | no (delta) |
| `piercing_tag_used` | main.gd:24614 | yes (`land_delta`, C-12) | no | no (delta) |
| `piercing_tag_markers` | main.gd:24674 | yes (`land_delta`, P4.0-4f) | no | no (delta) |
| `piercing_tag_persistent` | main.gd:24677 | yes (`land_delta`, C-12) | no | no (delta) |
| `piercing_spot_round` | main.gd:24612 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `storm_used` | main.gd:25124 | yes (`land_delta`, C-11) | no | no (delta) |
| `feats_used` | solo_controller.gd:2002 | Protection Feat family only (`land_delta`, P4.D-38a) | Protection Feat family only (door capture, P4.D-38a) | **YES** (every other feat family: reported, `land_delta` push_error) |
| `teleport_used` | main.gd:25312 | no | no | **YES** |
| `spot_markers` | main.gd:15256 | yes (`land_delta`, P4.0-4f) | no | no (delta) |
| `tag_markers` | main.gd:15714 | yes (`land_delta`, P4.0-4f) | no | no (delta) |
| `spot_round` | main.gd:15222 | yes (`land_delta`, P4.0-4e) | no | no (delta) |
| `precision_used` | main.gd:24773 | yes (`land_delta`, C-11) | no | no (delta) |

## Summary

- 79 `State` fields; **10 gap rows** (P4.0-4d landed `fatigued` and `casts`; P4.0-4e the twelve round
  stamps; P4.0-4f the four marker pools; P4.0-4g `versatile_pick_mode`; C-11 the three once-per-game name lists
  `limited_used`, `storm_used`, `precision_used`; C-13 `growth_markers`; C-15 the once-buff spend (`buffs`);
  C-12 the two Piercing-Tag latches `piercing_tag_used` / `piercing_tag_persistent`, -26).
- No gap among the board facts an activation moves: model wounds, deaths and positions ride the
  per-step landings, `shaken` rides `delta_of`, `activated` and `shaken` ride the MP rows.
- Every remaining gap is a once-per-game latch the dice path reads again later: the once-per-game flags
  (`second_wind_used`, the feat name list, `surprise_attack_used`, `reinforcement_used`, `teleport_used`),
  plus `growth_round` (derived). The delta stops
  at `shaken`, the ledger, the round stamps, the pools, the Versatile pick, the spent name lists, the growth count,
  the once-buff spend and the Piercing-Tag latches, and the MP rows compare
  only activation, Shaken and per-model wounds/life/XZ — so a table and the core can disagree on any of
  these without a local or MP signal.

## Classification (One core P4.0-4a)

Every gap row above is assigned one class by following the core's write and the table's own writer.
A live activation on the core path is *plain*: `is_plain` (`scripts/solo/core_activation.gd`) demands
no `special_rules`, no weapon `special_rules` and no attached hero, so the rule/feat/marker branches
below are unreachable — the core only *reads* those fields. The core's own plain writes are
`moved_round` (`sim.rs:9770`, the P3 supplied-placement move), `activated`, model `wounds`/`positions`
and the `buffs` spend (`sim.rs:10594`).

- **(a) Table-owned on the core path.** The core's plain activation does not write the field and the
  table's own writer still runs, so the value cannot go stale. The cited core writer sits in a
  rule/feat/marker branch a plain unit never enters.
- **(b) Lost on the core path.** The plain activation changes the field (or the table's spend for it
  never runs) and neither the delta, the landings nor the MP rows carry it back, so the value goes
  stale until the table resets it. The cases for the (b) fields live in
  `test/one_core/state_delta_lost_test.gd`; they were red on purpose until the fixes below.
- **(c) Core-internal only.** The only core writer is the AI rollout/search (`rollout.rs`), not the
  live `sim::resolve`; the table's own value is never touched by a core activation.

| Class | Field | Evidence (core writer; table reader) |
|---|---|---|
| (a) | `fatigued` | `sim.rs:2108,3292` (Second Wind branch); `battle_sim.gd:2124`; the table's own fatigue toggle is the writer |
| (a) | `casts` | `sim.rs:1925-1928` (Vengeance branch); `battle_sim.gd:2126`; table cast path writes it |
| (b), fixed (#2803/#2804, then C-15) | `buffs` | core spends at `sim.rs:10594` (`spend_exchange_wounded`) in its own copy of the ledger (the capture DOES send it: `_stamp_gate_reads` writes `ledger`, `fold_ledger` reads it), no delta key carries the spend back, and the table's `_solo_spend_once_mods` (`main.gd:6161`) never ran on the core path; read `main.gd:447`. Fixed by #2803 (the volley's once buffs; the table's own spend after a `done` activation); the once morale buff fixed by #2804 (spent right after the morale die) |
| (a) | `vs_mark_round` | `sim.rs:1911,1964` (Vengeance branch); `main.gd:24332`; table writer runs |
| (a) | `hit_and_run_round` | `sim.rs:3171,3197` (Hit-and-Run branch); `solo_controller.gd:12793`; table writer runs |
| (a) | `moved_round` | `sim.rs:9770` writes it on the P3 placed move, but `_on_units_dropped` (`main.gd:22883`) and `_solo_animate_move` (`main.gd:12255`) set the table's copy on the same move; the delta's `moved` is a guard, P4.0-4e lands the round stamp; read `main.gd:1761` |
| (c) | `delayed_action_round` | only `rollout.rs:404` (AI search); table reads `solo_controller.gd:9994` and writes it itself |
| (c) | `coordinate_via_round` | only `rollout.rs:319` (AI search); table reads `game_unit.gd:333` and writes it at `:351` |
| (a) | `reckless_rolled_round` | `sim.rs:2341` (Reckless branch); `main.gd:24471`; table writer runs |
| (a) | `reckless_ap_round` | `sim.rs:2353` (Reckless branch); `main.gd:24502`; table writer runs |
| (a) | `reckless_backfire_round` | `sim.rs:2354` (Reckless branch); `main.gd:24507`; table writer runs |
| (a) | `versatile_pick_round` | `sim.rs:8220` (Versatile branch); `main.gd:15462`; table writer runs |
| (a) | `versatile_pick_mode` | `sim.rs:8221` (Versatile branch); `main.gd:15471`; table writer runs; P4.0-4g lands the int mode onto the table's `versatile_pick` Dictionary |
| (a) | `retreating_strike_round` | `sim.rs:3081` (Retreating Strike branch); `main.gd:8888`; table writer runs |
| (a) | `mind_control_moved_round` | `sim.rs:2175` (Mind Control branch, `EPOCH_73_V36`); `main.gd:24569`; table writer runs |
| (a) | `growth_markers` | `sim.rs:4253,4268` (Growth branch); `main.gd:24962`; table writer runs |
| (a) | `growth_round` | `sim.rs:4251` (Growth branch), plus the fold at `io.rs:1308` (no ledger key on the wire); `main.gd:24968`; table writer runs |
| (a) | `growth_strike_round` | `sim.rs:5901` (Growth strike); `main.gd:9335`; table writer runs |
| (a) | `vengeance_markers` | `io.rs:1278` folds the ledger, read at `sim.rs:3822`; `main.gd:8827`; table writer runs |
| (a) | `second_wind_used` | `sim.rs:3290` (Second Wind branch); `solo_controller.gd:13886`; table writer runs |
| (a) | `surprise_attack_used` | `sim.rs:1121` (Surprise Attack branch); `main.gd:25248`; table writer runs |
| (a) | `reinforcement_used` | `deployment.rs:3631` (reinforcement step), fold `io.rs:1264`; `main.gd:16256`; never an activation |
| (a) | `second_wind_round` | `sim.rs:3286` (Second Wind branch); `solo_controller.gd:13833`; table writer runs |
| (a) | `second_wind_uses` | `sim.rs:3289` (Second Wind branch); `solo_controller.gd:13833`; table writer runs |
| (a) | `limited_used` | `sim.rs:1405,6060` (`mark_spent_limited`, limited-weapon branch); `solo_controller.gd:9772`; table writer runs |
| (a) | `piercing_tag_used` | `sim.rs:2449` (Piercing tag branch); `main.gd:24614`; table writer runs; C-12 lands the core's latch (the capture sends it too) |
| (a) | `piercing_tag_markers` | `sim.rs:2455,2464,2514` (Piercing tag branch); `main.gd:24674`; table writer runs |
| (a) | `piercing_tag_persistent` | `sim.rs:2456,2475`, fold `io.rs:1288`; `main.gd:24677`; table writer runs; C-12 lands the core's standing flag onto `piercing_tag_source` |
| (a) | `piercing_spot_round` | `sim.rs:2436` (Piercing Spot branch); `main.gd:24612`; table writer runs |
| (a) | `storm_used` | `sim.rs:1449` (Storm branch); `main.gd:25124`; table writer runs |
| (a) | `feats_used` | `sim.rs:1840,5852,5936,9468` (feat branches); `solo_controller.gd:2002`; table writer runs |
| (a) | `teleport_used` | `sim.rs:2221` (Teleport branch); `main.gd:25312`; table writer runs |
| (a) | `spot_markers` | `sim.rs:2638,2742` (Spotter branch); `main.gd:15256`; table writer runs |
| (a) | `tag_markers` | `sim.rs:2675,2753` (Tagger branch); `main.gd:15714`; table writer runs |
| (a) | `spot_round` | `sim.rs:2619` (Spotter branch); `main.gd:15222`; table writer runs |
| (a) | `precision_used` | `sim.rs:2653` (Precision branch); `main.gd:24773`; table writer runs |

Counts: **33 (a), 1 (b), 2 (c)**; the (b) is fixed by #2803 (volley) and #2804 (morale). The single (b) was the live buff ledger: the core's `spend_once`
is the one plain-path write whose result no surface carries (the capture sends the ledger, the core
spends in its copy, no delta key brings the spend back) and the table's own spend is skipped on the core path.
