# Parity ruling (D-PAR1)

What "the rules core and the GDScript table agree" means from now on. Decided by the maintainer on
2026-11-22 (decision D-PAR1, "rulebook parity"). Tests, tools, gate reports and PR texts cite this
page by its class names; a lane that needs a different reading asks for a new ruling first.

## The rule in one sentence

The two sides must agree on everything the rulebook fixes - dice, rule-determined state and the
legality of the result - and need not agree on anything the book leaves free; there the core
decides and the table is not copied.

## What must match (five items)

1. **Dice.** Per rule step: whether it rolls, how many dice, and the outcome of each die (hit,
   wound, save, test passed or failed, and the resulting count). A step that rolls on one side
   only, rolls twice, or rolls a different number of dice is unequal even if the end state happens
   to match. A different dice order is acceptable only when every outcome is the same.
2. **Rule-determined state.** Alive / dead per unit, wounds, Shaken, Fatigued, activated, markers
   and objective control, and every ledger entry a rule writes (for example a once-per-game use).
3. **Legal casualties.** The number of casualties must match. Which models are removed may differ
   only where the book leaves the defender a free pick among equal models; removing a model the
   book does not allow yet is unequal on that side.
4. **Legal end positions.** Positions may differ wherever the book leaves direction or distance
   free (an optional move "up to X", consolidation, Hit & Run, pile-in). Each side's end position
   must be legal: no base overlap, no forbidden terrain, coherency kept, distance within the
   allowance, no enemy proximity outside a charge. Equality of positions is not checked.
5. **Log presence.** Every rule that is applied writes at least one battle-log line that names it
   (exact rule-name compare). Wording, line order and roll labels (the printed target number when
   faces and outcomes are identical) are not compared.

## What need not match

Every choice the book leaves free: direction and distance of optional moves, the pick among equal
models, target and weapon order where the book allows either. The core decides these; a
table-vs-core difference in a free choice is not a finding. A pick that belongs to a human player
(for example a mode or an offer the table asks today) is asked of the player through the core,
not decided by it.

## Legality on both sides

One checker - the core's - judges the core's end state before it lands and the table's end state
after a table-resolved activation. An illegal result on either side is a finding; an illegal
optional step of the core is not landed (the unit stays and one log line says why).

## Classes

Every unequal cell, row or record is filed under exactly one class (the most severe that applies,
in this order):

| Class | Meaning |
|---|---|
| `RULE-UNEQUAL` | Item 1 or 2 differs, or item 3 or 4 where the book fixes the result. |
| `ILLEGAL-CHOICE` | A free choice where one side's result breaks the book; the report names the side. |
| `LEGALITY-PENDING` | Interim, until the checker runs in the instrument: positions differ and nobody has checked legality yet. Never counted as equal. |
| `LOG-MISSING` | A rule was applied on the table side and no core line names it. |
| `FREE-CHOICE` | Only book-free choices, wording, line order or roll labels differ. Reported, not gating. |
| `INSTRUMENT` | The difference comes from the recorder, harness or compare, not from either rules side. |
| `UNKNOWN` | The data does not show enough to decide. Never guessed into another class. |

A cell where the table is wrong by a lead rule call (with a book source) keeps its class and gets
the overlay `ruled`; it is not repaired on the table.

## Deny files and epochs

- **Deny files.** A new deny entry only for a dice, state or legality difference. No
  deny -> fix -> lift cycle for text: a wording or label gap is never a refusal reason.
- **Epochs.** No rules-epoch bump per fix. A core outcome change rides a pending-epoch constant;
  pending constants go live together in one batch. An input that only the door sends and that
  reaches no recorded act needs no epoch; such a change proves it with the full cargo test,
  byte-identical goldens (`test/fixtures/one_core/golden_*.json`) and the Python replay-gate tests.
  Recorded corpora and goldens keep replaying byte-exact at their stamp.
- **Freeze.** The table gets no line alignment and no change made only to match the core. A table
  defect that a player can see (wrong dice, wrong state, illegal result) is still fixed, with the
  core's behaviour as the reference, and the fix names the deletion that will remove it. Otherwise
  its production changes are deletions or the fallback wiring of a deletion plan.

## What the last parity gate (G1) reads

On one sha, with the table still present, all read with the classes above:

- the shoot coverage ledger (AI door and human door, situations plain / cover / deadly_kill),
- the 5-seed roster sweep (`test/one_core/roster_sweep.gd`, 1000 and 2000 points),
- a 24-game shadow soak with terrain (`scripts/solo/core_shadow.gd`).

Pass: `RULE-UNEQUAL` 0 that is not `ruled`, `ILLEGAL-CHOICE` 0 on the core side (the table side
is reported, not gating), `LOG-MISSING` 0, `start_twice` 0, and every run with at least one
fired cell (a run with 0 fired cells is broken, not green). Every gate also shows it can fail: a
planted swapped face and a planted rule edit read `RULE-UNEQUAL`, a planted dropped rule line
reads `LOG-MISSING`, a planted rewording reads `FREE-CHOICE`.
