feat(rules): off-turn verbs are refused, the turn chip follows (rules 2.T2a)

Rules-automation plan step 2.T2a "refuse off-turn verbs, show the turn chip".

What
- On a hotseat Automatic table (two humans, no AI seat, local) the pure `TwoHumanTurn`
  state now enforces one side per activation: P1 activates, then only P2 may.
- The radial Activate door (`radial_menu_controller._toggle_activation`) and the combat
  verbs (Shoot/Fight via `solo_begin_targeting`, Charge/Advance/Rush via `solo_begin_auto`,
  Cast via `solo_begin_cast`, Pass via `solo_begin_pass`) refuse an off-turn unit with one
  battle-log line naming the side on turn ("It is P2's turn").
- A turn chip beside the rules chip reads "Turn: P1" / "Turn: P2"; it is gated like the
  rules chip (`RulesAutomation.ui_enabled()`, still false until step 2.10) AND only shows
  on a hotseat Automatic table.
- Manual tables and solo-vs-AI tables are untouched: the guard runs only when
  `_solo_hotseat_automatic()` is true, so an AI seat keeps the SoloController alternation
  (2.4) and Manual keeps free activation. Q7: off-turn DRAGS stay allowed here; the
  snap-back is 2.T2b.

Files
- scripts/main.gd: `_hotseat_side_on_turn` / `_hotseat_eligible_counts` / `hotseat_turn_refusal`
  / `hotseat_record_activation` / `hotseat_log_refusal` / `_hotseat_verb_refused`, the turn-chip
  block in `_update_rules_chip`, and the verb guards.
- scripts/radial_menu_controller.gd: the Activate-door guard + activation recording.
- test/e2e/e2e_hotseat_turn_guard_test.gd: committed as the RED commit b9fb292e.

RED / GREEN
- RED: on origin/main (2.4 base) 3 of 5 cases fail — no guard (P1's second unit activates,
  an off-turn Shoot opens targeting) and no turn chip (lane RED commit message).
- GREEN: the lead applied `rules_2.T2a_green.patch` clean on the RED commit b9fb292e and
  pushed ed3d5987 ("68 production lines added vs origin/main"). Gate: CI build.yml gdUnit
  shards + export/launch smoke. (Local Godot is blocked for the DeepSeek lead by the guard.)

Review note
- The `solo_begin_targeting` guard is placed AFTER `_ensure_solo_controller()` so the 2.4
  suite (`test_p2_may_enter_targeting_and_no_ai_turn_follows`) still gets the geometry
  controller and keeps its assertions green.
- Size: 68 production lines (non-blank, non-comment) across the two scripts.
