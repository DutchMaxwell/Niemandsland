feat(rules): off-turn drag snap-back (rules 2.T2b, Q7)

Rules-automation plan step 2.T2b. Q7 (maintainer): in an Automatic game a unit dragged out of turn
SNAPS BACK; the escape hatch for corrections is switching to Manual (A1, immediate).

What
- On a hotseat Automatic table (two humans, no AI seat, local) during the PLAYING phase, releasing a
  drag of a unit whose side is not on turn restores every dragged model to its pre-drag position,
  with one battle-log line and a toast: "Bravo Squad is not on turn — moved back".
- No trail, no undo entry, no wound/marker/activation change: the release emits nothing, so every
  `selection_dropped` consumer (battle log, game record, ledger) never sees the move.
- On-turn drags are unchanged; a Manual table is unchanged; the deployment phase stays free (the guard
  requires `game_phase == PLAYING`).
- The restore reuses the same pre-drag snapshot the drop refusal / move take-back use
  (`_drag_start_positions` / `_drag_start_rotations`). Online is out of scope here (the check runs on
  the dragging player's own machine as part of 3.3a).

Files
- scripts/main.gd: `hotseat_off_turn_drag(unit)` — turn check + the one log line/toast.
- scripts/object_manager.gd: `_snapback_off_turn_drag` (restore + notify) wired at the top of the
  real `_stop_dragging` release path; the end-of-drag bookkeeping is factored into `_reset_drag_state`
  (called by the ordinary drop and by the snap-back). `_drag_unit_of` resolves the dragged unit.
- test/e2e/e2e_hotseat_turn_snapback_test.gd: the RED commit (ce04dfff).

RED / GREEN
- RED: on origin/main the new suite's off-turn case fails — the drag commits (the model stays at the
  drop position and no "moved back" line is logged). On-turn, Manual and deployment cases already pass.
- GREEN: pending CI. `godot --headless --check-only --script` is clean on both edited scripts (only the
  usual autoload-name compile stop). Full gdUnit shards run on CI; the changed functions' neighbours
  (`_stop_dragging`, drop refusal, move trails/undo) are covered by the existing shards.

Size: 36 production lines across the two scripts.
