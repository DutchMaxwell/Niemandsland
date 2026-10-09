feat(rules): the hotseat round ends by itself (rules 2.6a)

Rules-automation plan step 2.6a ("Automatic round end"), re-cut for Road 2: on a hotseat Automatic
table (two humans, no AI seat) the round ends by itself the moment neither side has an eligible unit
left — the same end-of-round truth as solo, without the solo opener pump.

What
- `hotseat_record_activation`: when TwoHumanTurn leaves `side_on_turn == NONE` (both sides spent) it
  calls `_hotseat_end_round()`; otherwise the 2.T3 hand-over line and the button refresh run as before.
- `_hotseat_end_round`: `_solo_auto_seize()`, `_solo_book_mission_vp(final)` with the summary after
  SOLO_GAME_ROUNDS, then `advance_round()` + refresh + broadcast + "Round N begins". The opener is
  `TwoHumanTurn.next_round_opener()` — the side that did NOT take the round's last activation.
- `_hotseat_start_round`: starts the new round with that opener (a wiped opener yields to the other side).
- `_update_round_button`: on a hotseat Automatic table the Next Round button is disabled while any unit
  still has to act, tooltip "the round ends when every unit has acted" — exactly as solo. Manual tables
  are untouched.

Test amendment (why the patch touches a second file)
- The merged 2.T2a test `test_p2_may_activate_on_its_turn` had a single P2 unit, so 2.6a's auto round end
  fired on that one activation and `advance_round()` cleared `is_activated` — the assertion would read
  false. The patch adds a second P2 unit so the round stays alive; the check's intent (P2 is not refused
  on its turn) is unchanged. Flagged to the lead before building (option A).

Files
- scripts/main.gd: `_hotseat_round_spent`, `_hotseat_end_round`, `_hotseat_start_round`;
  `hotseat_record_activation` now ends the round; `_update_round_button` disables the lever.
- test/e2e/e2e_hotseat_round_end_test.gd: the RED commit (501a12d6) — auto round end + opener, mission VP
  booking, disabled button, Manual untouched.
- test/e2e/e2e_hotseat_turn_guard_test.gd: the minimal 2.T2a amendment.

RED / GREEN
- RED: on origin/main the new suite fails — no round advance, no mission VP line, the button is never
  disabled.
- GREEN: `git apply --check` is clean on both files; `godot --headless --check-only --script scripts/main.gd`
  is parse-clean (only the usual autoload-name compile stop). Full gdUnit shards run on CI.

Not in this step (kept for 2.6b / 2.6c)
- Round-start recovery for both humans and the two-human Ambush prompts: `_solo_round_start` returns early
  without an AI seat, so it is deliberately not called here.

Size: ~50 production lines + 3 test lines.
