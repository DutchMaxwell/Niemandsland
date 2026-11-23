# 0002. Rules epochs: recorded games replay byte-identically

- Status: Accepted
- Date: 2026-11-23

## Context

The rules core replays recorded games: activation corpora written by the table's recorder
(`scripts/solo/act_recorder.gd`), the core's own self-play records, and the goldens under
`test/fixtures/one_core/`. Training data, replay gates and parity reports all assume that a
record replays to exactly the same result it was recorded with.

A rules fix changes outcomes. Ported without care, it silently changes the replay of every record
made before it. The first attempt at an opt-out was one boolean knob per rule
(`cond_ap_dice`, `versatile_reach` in the record header, `core/nml-core/src/acts.rs`); that does
not scale, and a later pattern - gating on the live `CURRENT_RULES_EPOCH` symbol - broke replay
twice, because the next bump silently re-pointed every such gate at the new number.

## Decision

Every record carries the rules epoch it was played at (`rules_epoch` in the header; absent means
0, the rule set of the oldest corpus; `record_rules_epoch` in `acts.rs` resolves it). A change to
a recorded rules outcome is gated by epoch, as the doc comments on `rules_epoch` and `rule_on` in
`core/nml-core/src/acts.rs` prescribe:

1. Bump `CURRENT_RULES_EPOCH` to a new number `n`.
2. Define a **new frozen constant** `EPOCH_<n>_<NAME>: u32 = n` (for example
   `EPOCH_95_PARITY_BATCH`).
3. Gate the new behaviour on `rule_on(rules_epoch, EPOCH_<n>_<NAME>)`, which is simply
   `rules_epoch >= since_epoch`. **Never gate on `CURRENT_RULES_EPOCH` itself.**
4. Mirror the new number in the table's recorder in the same change
   (`static var rules_epoch: int = n` in `scripts/solo/act_recorder.gd`), so table recordings
   stamp the epoch they actually play.
5. Test both legs: one test pins the old epoch (old behaviour), one the new.

Several outcome changes may wait behind `PENDING_EPOCH_*` placeholder constants and go live
together as one batch epoch, instead of one bump per fix. An input that only the door sends and
that reaches no recorded act needs no epoch; such a change proves itself with the full cargo test,
byte-identical goldens and the Python replay-gate tests.

## Consequences

- Records stamped below an epoch replay byte-exact, forever; the old behaviour stays reachable
  in code for as long as such records are kept.
- The gate is enforced in CI: `tools/epoch_gate_check.py` reads the PR diff (the
  "Clippy and epoch gate" job in `.github/workflows/rust.yml`) and refuses a bump without a new
  frozen constant, a new gate on `CURRENT_RULES_EPOCH`, a missing old-leg or new-leg test pinned by
  constant or test name, a constant without a bump, an epoch that moves down, or a missing
  recorder mirror (unless the diff states a `MIRROR HOLD:` reason).
- Epoch numbers are never reused or renumbered silently; a rebase that collides with another
  epoch takes the next free number and moves its pins with it.
- The cost is accumulated branches in the rules code (`if rule_on(...)`). Removing an old leg is
  a deliberate change that drops replay support for the records below it.
