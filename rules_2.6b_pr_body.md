feat(rules): the hotseat round start rolls recovery for both sides (rules 2.6b)

Rules-automation plan step 2.6b ("Round start: recovery for both sides"), re-cut for Road 2: at the
start of a hotseat Automatic round every Shaken Battleborn/Steadfast unit rolls its recovery die on its
OWN owner's tray — the human side now rolls too, instead of only being reminded.

What
- `_solo_battleborn_recovery`: the non-AI (human) branch now rolls through `_owner_roll`, applies the
  result (`card_toggle_shaken` + `_solo_mirror_shaken`) and logs the same one result line as the AI
  ("recovers from Shaken (4+)" / "stays Shaken"). The old human reminder line ("roll for X to recover
  from Shaken") is gone. The AI branch is byte-identical.
- `_hotseat_start_round` (2.6a) now awaits `_solo_battleborn_recovery()` before the opener takes the
  turn — `_solo_round_start` is not reached on a table with no AI seat.
- The round-end chain is now awaited end to end: `hotseat_record_activation` -> `_hotseat_end_round` ->
  `_hotseat_start_round`, and the radial activation door awaits `hotseat_record_activation` (the same
  `await ... .call(...)` seam `begin_activation` already uses) so the recovery roll completes before the
  activation is closed out.

On purpose: this changes the human side of solo
- In solo (human vs NACHTMAHR) the human's Shaken Battleborn/Steadfast units now roll and may clear
  Shaken automatically, where the automation used to leave a reminder and never touch the player's
  markers. This is the step's intent (recovery "for both sides").

Files
- scripts/main.gd: `_solo_battleborn_recovery` human branch, `_hotseat_start_round`, `_hotseat_end_round`,
  `hotseat_record_activation`.
- scripts/radial_menu_controller.gd: the activation door awaits the record call.
- test/e2e/e2e_hotseat_round_start_recovery_test.gd: the RED commit (b8bcb450) — a Shaken Battleborn unit
  at a hotseat round start rolls exactly one result line, no reminder; a Shaken unit without the rule
  does not.

RED / GREEN
- RED: on origin/main the human side logs the reminder ("roll for ...") and no result line.
- GREEN: `godot --headless --check-only --script scripts/main.gd` and `...radial_menu_controller.gd` are
  parse-clean (only the usual autoload-name stop). Full gdUnit shards run on CI.

Size: 23 production lines in main.gd + 3 in radial_menu_controller.gd.
