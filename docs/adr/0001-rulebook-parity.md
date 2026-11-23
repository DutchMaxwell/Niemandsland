# 0001. Rulebook parity between the table and the rules core

- Status: Accepted
- Date: 2026-11-23

## Context

Two implementations of the OnePageRules rules live in this repository: the GDScript table
(`scripts/solo/battle_sim.gd`, `scripts/solo/turn_manager.gd` and the code around them) and the
Rust rules core (`core/nml-core/`). For a long time they were compared line by line, which made
every difference look like a defect - including differences the rulebook does not care about,
such as which of two equal models is removed or how far an optional move goes. That reading
pushed both sides toward copying each other instead of toward the book, and it gave no answer
when the two sides were both legal but different.

Engine play (an AI seat, an agreed Automatic online room, and behind its switch a local hotseat
Automatic table) now resolves through the core. The table reaches it through one door,
`scripts/solo/core_activation.gd` (`CoreActivation`): every path that may resolve through the
core asks `applies` / `enabled` first, `engine_offered` offers Solo and Automatic only while the
`NmlCore` extension is loaded, and `NML_ONE_CORE_ACTIVATION=0` (or `off`) is the kill switch back
to the table path. Manual rooms never enter the door.

## Decision

The rules core is the rules authority for engine play, and "the table and the core agree" means
**rulebook parity**, as written in [`docs/one_core/PARITY_RULING.md`](../one_core/PARITY_RULING.md):

1. **What the book fixes must match**: the dice of every rule step (whether it rolls, how many
   dice, each outcome), rule-determined state (alive / dead, wounds, Shaken, Fatigued, activated,
   markers, objective control, every ledger entry a rule writes), the number of casualties, and
   the legality of end positions.
2. **What the book leaves free is the core's**: direction and distance of optional moves, the
   pick among equal models, target and weapon order where either is allowed. A difference there is
   not a finding. A pick that belongs to a human player is asked of the player through the core,
   not decided by it (the per-choice switches `CoreActivation.choice_enabled`).
3. **One legality checker**, the core's, judges the core's end state before it lands and the
   table's end state after a table-resolved activation. An illegal optional step of the core is
   not landed; the unit stays and one log line says why.
4. **Every applied rule logs**: at least one battle-log line that names the rule, compared by
   exact rule name. Wording, line order and roll labels are not compared.
5. Every difference is filed under exactly one class of the ruling (`RULE-UNEQUAL`,
   `ILLEGAL-CHOICE`, `LEGALITY-PENDING`, `LOG-MISSING`, `FREE-CHOICE`, `INSTRUMENT`, `UNKNOWN`).

The table is frozen: it gets no change made only to match the core. A table defect a player can
see (wrong dice, wrong state, an illegal result) is still fixed, with the core's behaviour as the
reference.

## Consequences

- A rules change is judged against the rulebook, not against the other implementation. Code that
  encodes a rule value cites its book source (`docs/CODING_STANDARDS.md`, section 4).
- Parity suites (`test/one_core/`, the roster sweep `test/one_core/roster_sweep.gd`, the shadow
  soak `scripts/solo/core_shadow.gd`) read their results with the classes above, and each gate
  shows it can fail: a planted swapped face or rule edit must read `RULE-UNEQUAL`, a planted
  dropped rule line `LOG-MISSING`.
- A deny entry (a case the core refuses and hands back to the table) is only allowed for a dice,
  state or legality difference, never for wording.
- Core outcome changes ride the rules-epoch mechanism of [ADR 0002](0002-rules-epochs.md), so
  recorded games keep replaying.
- The table's rules code shrinks over time by deletion behind the door; it is not grown to mirror
  the core.
