feat(rules): hotseat turn hand-over line (rules 2.T3)

Rules-automation plan step 2.T3, first half ("Hand-over"): after an activation completes on a hotseat
Automatic table the turn pass is announced in the battle log.

What
- `hotseat_record_activation` now logs exactly one line when the turn moves:
  - the other side has an eligible unit -> "P2 to activate";
  - the other side is spent -> TAIL, same side keeps activating: "P2 has no units left — P1 keeps activating";
  - both sides spent -> no line (the round end is step 2.6a).
- The turn chip from 2.T2a already follows the side; this only adds the log line.

Files
- scripts/main.gd: `_hotseat_handover_line(just_acted)`, called from `hotseat_record_activation`.
- test/e2e/e2e_hotseat_turn_handover_test.gd: the RED commit (3987d7b9).

RED / GREEN
- RED: on origin/main the three cases fail — no hand-over line is logged at all.
- GREEN: `godot --headless --check-only --script scripts/main.gd` is parse-clean (only the usual
  autoload-name compile stop). Full gdUnit shards run on CI.

Scope note (why this is 2.T3a, not all of 2.T3)
- The plan's 2.T3 also lists "the human Pass / Delayed Action keeps its rule check for both humans" and
  "embarked cargo and Second Wind generalised from human vs AI to either side". In hotseat Automatic
  there is NO AI seat, so the SoloController alternation pump (`_solo_after_activation`, cargo/Second
  Wind/Pass) never runs there — those generalisations belong with the round-flow work (2.6a-c) and the
  Pass door, and are not part of this hand-over increment. Recommend splitting 2.T3 accordingly.

Size: 16 production lines.
