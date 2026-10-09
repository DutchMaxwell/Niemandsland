feat(rules): both hotseat sides are asked for their Ambushers (rules 2.6c)

Rules-automation plan step 2.6c ("Round start: Ambush for two humans"), re-cut for Road 2.
STACKS ON PR #1740 (rules 2.6b) — its async round-start chain is the base of this branch.

What
- `_hotseat_start_round` runs the Ambush arrival step from round 2 on, after the Battleborn recovery and
  before the opener takes the turn.
- `_hotseat_ambush_arrivals(round_number, opener)` asks BOTH human sides to place their reserve units,
  ordered by the turn state: the opener first, then the other (GF/AoF v3.5.1 p.13 "starting with the
  player that activates next"). It reuses the tested `_solo_ambush_human_turn` prompt by pointing the
  controller's `human_slot`/`ai_slot` at the side being asked (its owner tray, its beacons, the other
  side as the enemy) and restores them after the loop.
- Solo (`_solo_alternate_ambush_arrivals`, the AI beat) and Manual tables are untouched.

HANDOVER (core edit > 25 lines — NOT applied on this branch)
- RED: test/e2e/e2e_hotseat_ambush_two_humans_test.gd (commit 343b1ee3).
- GREEN: rules_2.6c_green.patch — `git apply` it on top of the RED commit, run the gdUnit shards, then
  commit and open the PR. It compiles against the 2.6b base (checked: `git apply --check` clean).

Assumptions the lead should check (I could not run tests here)
- The per-side prompt BODY still says "You" (the tested `_solo_ambush_human_turn` string). This step adds
  the side line "P2 Ambush (round N): place one reserve unit from the tray" before each prompt, but does
  not reword the prompt body. If the re-cut wants per-side prompt wording, `_solo_ambush_human_turn`
  needs a side parameter (bigger diff).
- Setting a side's Ambush reserves aside at DEPLOYMENT for both humans is upstream of this step and not
  included; the RED test flags the reserve directly on the unit.
- The slot swap restores `human_slot`/`ai_slot` after the loop; an early error path inside
  `_solo_ambush_human_turn` would skip the restore. Keep in mind if the step ever gains an error return.

Size: ~40 production lines in main.gd.
