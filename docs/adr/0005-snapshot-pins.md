# 0005. Compare-cleanup literals are snapshot pins

- Status: Accepted
- Date: 2026-11-23

## Context

The one-core suites used to check the rules core against the GDScript table: both sides resolved
the same scenario and the test compared dice, state and log lines. As the table's rules code is
deleted step by step behind `CoreActivation`, those compares lost their second arm. The cases that
carry a rule outcome worth keeping now read that outcome off the door arm alone and compare it
with a literal value (`const WANT_*`, or a literal in the assertion of a single case).

Those literals were read on `main` from the rule outcome the table produced while the compare was
still green. They are a snapshot of the core at that commit. They are not derived from the
rulebook, and the rulebook does not name them: the same rules reading can legitimately produce a
different value after a core change, and a later rulebook-derived oracle test may disagree with
them without either side being wrong about the book.

A reader who cannot tell a snapshot from a rulebook-derived expected value cannot tell a harmless
core change from a defect.

## Decision

A literal that pins a rule outcome in a one-core suite is a **snapshot pin**. It records what the
core produced on `main` at the time the table arm was removed, and it is labelled as such directly
above the pin:

`# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).`

The rule applies to every pinned case the compare cleanup left behind:

- `test/one_core/casualty_slots_door_test.gd`
- `test/one_core/casualty_tie_order_door_test.gd`
- `test/one_core/core_beat_names_door_test.gd`
- `test/one_core/core_beats_guard_test.gd`
- `test/one_core/core_dangerous_test.gd`
- `test/one_core/core_feat_latch_test.gd`
- `test/one_core/core_human_strafe_test.gd`
- `test/one_core/core_ledger_lift_door_test.gd`
- `test/one_core/core_lone_hero_door_test.gd`
- `test/one_core/core_move_through_test.gd`
- `test/one_core/core_once_landing_door_test.gd`
- `test/one_core/core_once_lift_door_test.gd`
- `test/one_core/core_piercing_tag_test.gd`
- `test/one_core/core_slayer_mark_door_test.gd`
- `test/one_core/indirect_door_test.gd`
- `test/one_core/non_opr_unit_test.gd`
- `test/one_core/shred_contact_door_test.gd`
- `test/one_core/stealth_target_door_test.gd`
- `test/one_core/valiant_height_door_test.gd`

Changing a pinned value is a rules-outcome change, not a test cleanup. It needs either a rules
epoch (see [ADR 0002](0002-rules-epochs.md)) when a recorded game would replay differently, or a
written reason in the pull request when only the test's expectation was stale and no recorded
outcome moves. A pull request that touches a pin without one of the two is incomplete.

A pin is not a rulebook source. Code that encodes a rule value still cites the book
(`docs/CODING_STANDARDS.md`, section 4); a pin only holds a core result steady until that test is
replaced.

## Consequences

- A core change that moves a pinned value fails a suite with a message that says "want", and the
  reader can tell from the label that the literal is a snapshot, not the book.
- The pins are deliberately temporary. Once the GDScript table resolver is deleted, the compares
  they replaced are gone for good, and the pins are replaced by rulebook-derived oracle tests that
  state the expected dice, state and legality from the book instead of from a prior core run.
- Until then the pins add a maintenance step: any core change that touches a pinned case must
  update the literal and carry the epoch or the reason that justifies it.
- Refusal and legality counts (`core_runs`, `core_refusals`) are door behaviour, not snapshots of a
  table result; they are not labelled, because they do not move with a rules reading.
