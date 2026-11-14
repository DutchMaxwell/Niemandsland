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
| `fatigued` | battle_sim.gd:2124 | no | no | **YES** |
| `in_cover` | battle_sim.gd:2112 | no | no | no (capture input) |
| `aircraft` | battle_sim.gd:2106 | no | no | no (structural input) |
| `dormant` | battle_sim.gd:2130 | no | no | no (round-start state) |
| `dormant_models` | battle_sim.gd:2131 | no | no | no (arrival input) |
| `dormant_wounds` | battle_sim.gd:2132 | no | no | no (arrival input) |
| `casts` | battle_sim.gd:2126 | no | no | **YES** |
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
| `buffs` | main.gd:447 | no | no | **YES** |
| `vs_mark_round` | main.gd:24332 | no | no | **YES** |
| `hit_and_run_round` | solo_controller.gd:12793 | no | no | **YES** |
| `moved_round` | main.gd:1761 | `moved` bool (guard only) | X/Z only | **YES** (round value lost) |
| `delayed_action_round` | solo_controller.gd:9994 | no | no | **YES** |
| `coordinate_via_round` | game_unit.gd:333 | no | no | **YES** |
| `reckless_rolled_round` | main.gd:24471 | no | no | **YES** |
| `reckless_ap_round` | main.gd:24502 | no | no | **YES** |
| `reckless_backfire_round` | main.gd:24507 | no | no | **YES** |
| `versatile_pick_round` | main.gd:15462 | no | no | **YES** |
| `versatile_pick_mode` | main.gd:15471 | no | no | **YES** |
| `retreating_strike_round` | main.gd:8888 | no | no | **YES** |
| `mind_control_moved_round` | main.gd:24569 | no | no | **YES** |
| `growth_markers` | main.gd:24962 | no | no | **YES** |
| `growth_round` | main.gd:24968 | no | no | **YES** |
| `growth_strike_round` | main.gd:9335 | no | no | **YES** |
| `vengeance_markers` | main.gd:8827 | no | no | **YES** |
| `second_wind_used` | solo_controller.gd:13886 | no | no | **YES** |
| `surprise_attack_used` | main.gd:25248 | no | no | **YES** |
| `reinforcement_used` | main.gd:16256 | no | no | **YES** |
| `second_wind_round` | solo_controller.gd:13833 | no | no | **YES** |
| `second_wind_uses` | solo_controller.gd:13833 | no | no | **YES** |
| `limited_used` | solo_controller.gd:9772 | no | no | **YES** |
| `piercing_tag_used` | main.gd:24614 | no | no | **YES** |
| `piercing_tag_markers` | main.gd:24674 | no | no | **YES** |
| `piercing_tag_persistent` | main.gd:24677 | no | no | **YES** |
| `piercing_spot_round` | main.gd:24612 | no | no | **YES** |
| `storm_used` | main.gd:25124 | no | no | **YES** |
| `feats_used` | solo_controller.gd:2002 | no | no | **YES** |
| `teleport_used` | main.gd:25312 | no | no | **YES** |
| `spot_markers` | main.gd:15256 | no | no | **YES** |
| `tag_markers` | main.gd:15714 | no | no | **YES** |
| `spot_round` | main.gd:15222 | no | no | **YES** |
| `precision_used` | main.gd:24773 | no | no | **YES** |

## Summary

- 79 `State` fields; **36 gap rows**.
- No gap among the board facts an activation moves: model wounds, deaths and positions ride the
  per-step landings, `shaken` rides `delta_of`, `activated` and `shaken` ride the MP rows.
- Every gap is a per-activation ledger or latch the dice path reads again later: fatigue, casts, the
  live buff ledger, the once-per-round/per-game stamps, and both marker pools (`spot_markers`,
  `tag_markers`, `piercing_tag_markers`). The delta stops at `shaken`, and the MP rows compare only
  activation, Shaken and per-model wounds/life/XZ — so a table and the core can disagree on any of
  these without a local or MP signal.
