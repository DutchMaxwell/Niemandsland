# Rules Wave 4 — accounting: claimed vs delivered

Closes wave 4 the way wave 3 closed: per-family ledger, table gaps, and the 21 UNCLEAR verdicts.
Companion corrections landed in `docs/plans/RULES_WAVE4_2026-09-06.md` §2 and §5 (struck-through,
dated, not deleted).

## 0. Measurement note — the census in this table is reported, not re-run

This job's brief asked for an independent re-run of
`core/nml-core-py/tools/rule_universe_census.py` at `origin/main`, using this job's own numbers
rather than the orchestrator's. That re-run **did not happen**, and the reason is itself worth
recording rather than smoothing over:

- The census requires `--books <dir>`, a private army-book snapshot (89 books, `gf/`/`aof/`) that
  the tool loads at runtime and that is deliberately **never committed to this repo** (see the
  tool's own `PRIVATE-SAFE` comment).
- This job runs inside a worktree sandbox scoped to `/home/andreaskesberg/.cache/nml-w4-6/wt`. Any
  attempt to locate or read outside that root is refused by the tool layer itself — confirmed by a
  blocked `find /` and a blocked `printenv` — independent of anything this brief says about staying
  inside `ROOT`.
- Net result: the private book snapshot is unreachable from this job, with or without permission.
  The checkpoint table below is the orchestrator's numbers, carried over **as reported, not
  independently verified**. A future accounting job needs either the books snapshot mounted inside
  its worktree, or a pre-computed census JSON checked in as an artefact, to close this gap.

That is the finding this section exists to state: not "the numbers match" or "the numbers differ,"
but **"this job could not check."** Treat the table below accordingly.

## 1. Census checkpoints (reported by the orchestrator)

| checkpoint | core_ported | all_layers |
|---|---|---|
| wave-4 start | 378 | 165 |
| after W4-2 #756 (F1) | 384 | 167 |
| after W4-3 #757 (F2) | 392 | 168 |
| after W4-4 #758 (F4) | 394 | 168 |

core_ported moved +16 across the wave (378 → 394); all-layers moved +3 (165 → 168), one short of the
plan's Track F ceiling of +4 (`RULES_WAVE4_2026-09-06.md` §1) because F5's `Sturdy` and
`Quick Readjustment` — the two names carrying the remaining `all-layers +1` each — never shipped
(§2 below).

## 2. The ledger — claimed vs delivered, per family

| family | PR | claim | delivered | verdict |
|---|---|---|---|---|
| F1 Boost bases | #756 | core_ported +6 | **+6** | exact |
| F2 Conditional-AP | #757 | core_ported +8 | **+8** | exact |
| F3 Registry-only | — | registry +4 | **+0** | **superseded** |
| F4 Renames | #758 | core_ported +2 | **+2** | exact |
| F5 Singles | — | core_ported +3, all-layers +2 | **0** | **blocked** |

**Four of five families delivered exactly what they claimed.** The two that did not are plan errors
caught before code was written, not build failures: no job ran against a wrong claim, no PR shipped
a broken port, no gate had to catch a regression. The plan's own §0 already modelled this risk
("Plan wave 4 off the fresh census, not off the map") — F3 and F5 are that risk landing.

### F3 — superseded before it launched

The plan reserved F3 (Aircraft, Morale, Split, Shrouded) for a registry-only PR: `registry +4`, zero
core diff. It never launched. By the time W4-1 would have been cut, in-flight table PRs had already
registered all four names with mechanics entries — `RULES_WAVE4_2026-09-06.md` §2 flagged this exact
race before wave 4 started ("three OPEN table PRs overlap F3... whatever those PRs land is
subtracted from F3's claim"). The subtraction went to zero. **No job was spent**: F3 was never
sliced into a branch, so there is no wasted PR, no wasted review, no wasted farm run — only a wasted
line item in the plan.

### F5 — blocked with evidence, not merely unachieved

Three names, three separate reasons, all found by reading rule text rather than by a failed port
attempt:

- **Sturdy** — the plan required a registry remap `Guarded → Shielded`. The remap is **wrong**: the
  twin's own quoted rule text contradicts it (`scripts/main.gd:4658`ff,
  `scripts/solo/ai_combat_math.gd:89`). Decision: **no remap.** The plan's premise was wrong, not
  merely unachieved.
- **Quick Readjustment** — **DESIGN, not a port.** #718 already declared it unportable: the core has
  no `moved_hit_penalty` field, so there is nothing for a name read to route to. It needs that
  primitive on both sides first.
- **Surprise Attack** — the table gates on the literal name `Infiltrate`
  (`scripts/solo/solo_controller.gd:9618`) and knows no `Surprise Attack` anywhere in `scripts/`. A
  core-only port would have produced another rule the core counts and the table cannot resolve. The
  **table** PR goes first; the core read follows it.

## 3. The table-gap ledger

Rules the census counts — or would count — while the table cannot resolve them. This is the wave's
most important finding, independent of any single family's score: **a coverage number can outrun the
game.**

- **Point-Blank Piercing / `ranged_within`** — #757 added the condition in the core
  (`core/nml-core/src/combat.rs:389`); `ranged_within` appears in **zero** files under `scripts/`,
  and `Point-Blank Piercing` likewise, while the registry carries 5 entries for it. Table PR in
  flight.
- **Surprise Attack** — as in §2 above: the core has a name to read, the table has never heard of it.

The rule this establishes: **deduct a table gap from the claim that the table is covered, not from
the census.** The census measures the core honestly; "core knows the name" and "table can produce
the name" are different questions, and a gap between them is a table-PR backlog item, not a defect
in the core number.

## 4. The 21 UNCLEAR verdicts

Reproduced from `~/nml-mission/analysis/wave4_unclear/INDEX.md` (outside this worktree, not read
directly by this job — the verdicts below are the ones supplied in the brief).

**PORT (18):** Bloodthirsty Fighter, Coordinate, Crossing Attack, Delayed Action, Extended Buff
Range, Fatigue Debuff, Mind Control, Musician, Ranged Slayer, Re-Deployment, Reanimation, Reckless
Piercing, Reinforcement, Retreating Strike, Spell Accumulator, Takedown Strike, Transport, Vengeance

**DESIGN (2):** Spell Conduit, Takedown Shot

**DROP (1):** Sniper REMOVE

A **PORT** verdict is a claim about *shape* — an already-read mechanism expresses the rule — not a
promise about size. Each of the 18 still needs its own port before the census moves; "PORT" resolves
the question "is there a seam," not the work of using it.

`Sniper REMOVE` belongs in `NA_NAMES` beside `Unique` (`RULES_WAVE4_2026-09-06.md` §4 and
`docs/SOLO_AI_RULES_COVERAGE.md` §Registry — `Unique` is list-building only, `Sniper REMOVE` is
pending the same snapshot-curation treatment). Marking it N/A lowers the denominator honestly
instead of inflating the numerator by counting a book-hygiene marker as an unported rule.

## 5. Open decision

`encoder_slot` is **185/452 and did not move in wave 3 or wave 4.** It is now the binding constraint
on `all_layers`: however many families ship, all-layers is capped until the encoder vocabulary is
extended past its current unit-band ceiling (`RULES_WAVE4_2026-09-06.md` §1: unit band full at
200/200 in `data/encoder_rule_vocab_v1.json` v5, append-only). Extending it is a maintainer decision
— it invalidates every recorded corpus and every trained net that reads the current vocabulary — and
not a port. This is the single open decision this document adds to the plan's existing §8.
