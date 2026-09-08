# Spawn — the named-profile loader seam (design note for review-7's HOLD on #823)

Date: 2026-09-08. Scope: DESIGN only, no production code. Names covered: **Spawn**
(book occ 9: gf 4 factions, aof 5; every shipped entry `{"place_in": 6,
"once_per_game": true}`, `primitive: "Spawn"`, `rated: true`). Template:
`docs/plans/REINFORCEMENT_DESIGN_2026-09-07.md`, `docs/plans/FEAT_DESIGN_2026-09-08.md`.
Resolves the review-7 HOLD on PR #823 (§2 of `REVIEW_821_823_2026-09-08`): #823 ported
the S5 seam but substituted a copy of the BEARER's profile for the NAMED unit, which
the rollout reading of the rule cannot honestly accept — the table's summon CREATES a
second, different unit, not a clone of the carrier.

## 1. The rule text and every clause

The table's operative text is built from the rule string carried ON THE MODEL:
`"Spawn(Rat Swarm [10])"` — a named unit reference with a model count in brackets.
Clause by clause:

| clause | reading | evidence |
|---|---|---|
| **who** | a STANDING (alive, not in reserve) carrier; every living model of the unit is checked individually, and attached heroes count as their own carriers | `scripts/main.gd:17401-17439` (`_solo_try_spawn` walks `members = [unit] + get_attached_heroes()`, then every alive model) |
| **what unit** | a FRESH runtime unit of the name in the rule string, with the bracketed model count, profile fetched by name from the army book (`named_unit_profile`), NOT a copy of the carrier | `scripts/main.gd:17486-17491` (the regex `^[^(]+\((.+) \[(\d+)\]\)$`), `:17494-17500` (`named_unit_profile`), `:17525-17527` (`create_runtime_unit`) |
| **where** | fully inside a CIRCLE of `place_in` (6") around the ANCHOR MODEL (the model bearing the rule string), anchor radius added, table-clamped; occupancy blockers respected | `scripts/placement_ghost.gd:31` (`circle_zone`), `main.gd:17505` (`circle_zone(center, reach_in * 0.0254 + anchor_radius)`) |
| **when** | DURING the carrier's activation (offered at every activation door) | `_solo_try_spawn` is reached from the activation doors; the offer stamp `spawn_offered_round` gates to at most once per ROUND |
| **how often** | ONCE PER GAME per (model, rule-string) key (`spawn_spent`), plus at most one offer per round per key | `main.gd:17413-17421` (`spent.has(key)` / `offered.get(key) == current_round`) |
| **profile source** | the ARMY BOOK by name at run time — the spawnable unit need not be in the carrier's own army list | `named_unit_profile(army.army_id, system, faction, unit_name, count)` at `main.gd:17494` |

The key fidelity point review-7 held on: the copy is a DIFFERENT profile from the
carrier's. A rollout that recreates the carrier's own statics creates a second bearer,
which inflates every rule the carrier carries and mis-sizes the copy.

## 2. The table today (measured)

- `scripts/main.gd:17401-17439` — `_solo_try_spawn`: per-model, per-key once-per-game
  and once-per-round latching, reach read as `place_in`.
- `scripts/main.gd:17441-17530` — `_solo_create_rule_unit`: the shared named-unit
  creation used by the Spawn/Split family — regex parse, `named_unit_profile`,
  `circle_zone`, blocker lattice, `create_runtime_unit(..., "spawn")`.
- `scripts/main.gd:17534-17546` — `_solo_rule_unit_shape`: the block/column lattice for
  the copy's models (square-root layout, base-edge gap).
- `scripts/placement_ghost.gd:31` — `PlacementGhost.circle_zone`: the circle the ghost
  and the spot search both test against.
- Core today (origin/main): **no Spawn read anywhere** (`rollout.rs`, `unit.rs` contain
  no `spawn` token) — #823 is the held PR, not merged.

## 3. The loader seam proposal

### 3.1 Shipping the NAMED profile into the record header

The record's first line is the profile header: `{"profiles": {key: profile}}}`
(`io.rs:2`, parsed at `io.rs:897-904`). `roster_of` (`io.rs:560-583`) errors on any
unit key without a profile — the roster/profile table is closed at load, which is why
#823 could not name a second profile.

The honest fix is at RECORD-WRITE time, not load time: the loader must not resolve
names from the army book at import (books are not part of a record; a record must stay
self-contained and byte-replayable). So:

- **The recorder resolves at export.** The table already holds the resolved profile
  (`named_unit_profile` at `main.gd:17494`). The act recorder ships the COPY's full
  profile (the same serialized `OPRUnit` shape the header already carries) into the
  header under a namespaced key, e.g. `spawn:<carrier_key>:<rule_string>`, alongside
  the base `profiles` map. The army list does NOT need to contain the spawnable unit —
  the book lookup at creation time is authoritative and gets frozen into the record.
- **The header grows one optional map** (`spawn_profiles`), absent in every record
  written today — an epoch-visible format change (§6).
- A record in which a Spawn beat fires but the copy's profile is missing stays
  INVALID (load error), mirroring `roster_of`'s unknown-key error. No silent fallback
  to the carrier's profile — that fallback is exactly the #823 fidelity break.

### 3.2 Holding an un-deployed template in `State`

Two shapes were considered:

- **(a) Roster entry at load:** the copy's profile enters `Profiles`/`Roster` as an
  extra unit key with `alive == 0`, `dormant == true` from the start. Cost: every
  construction site, census, encoder fold and parity check now sees a unit that never
  existed at deployment — wide blast radius.
- **(b) Side table (recommended):** `State.spawn_templates: Vec<(unit_key, profile_idx)>`
  is NOT needed at all if the copy is only ever instantiated at the beat — see 3.3.
  The template lives in `Profiles` (indexed, immutable) and the record header; no new
  `State` field, no new dormant slot, no construction-site churn. The carrier's
  `UnitStatic.spawn` (already in #823: `place_in`, `once_per_game`) gains the
  rule-string's name/count pair so the beat knows WHICH template to instantiate.

Recommendation: **(b)**. The copy exists only during the beat that creates it; the
seam has no reason to park a permanent un-deployed slot.

### 3.3 Instantiation at the S5 seam

`spawn_round_start` (#823's beat, `rollout.rs`) keeps its round-boundary position for
now, but the "fresh copy" step changes from "rebuild the carrier's statics" to:

1. resolve the template: `profiles.list[spawn_profile_idx]` from the header map;
2. `withdraw_as_destroyed`-style park is NOT used (nothing is withdrawn — the copy is
   brand new): mint a fresh `State` slot only for the beat's lifetime via the existing
   `arrive_one`/`arrive_unit` pair (`deployment.rs:2394`, `:2522`), passing the
   TEMPLATE's statics, not the carrier's;
3. the copy is census-excluded and objective-excluded on its arrival round by the same
   `ambush_arrived_round` machinery #803 shipped (`State` already carries the round
   stamp; `score.rs` consumes it).

Practically the beat needs `arrive_unit` to accept an explicit `UnitStatic` argument
today it derives from the roster — a narrow, additive parameter change on a function
with one production caller (the S5 beat itself) and one test caller.

### 3.4 Timing: round boundary vs per-activation beat

- **What the S5 seam offers today:** the round boundary is the only non-activation
  beat the core has (the part-3 Reinforcement precedent, `rollout.rs` right after
  `reinforcement_round_start`). One boundary late; no activation-menu change; the
  once-per-game latch reuses `reinforcement_used`.
- **What a per-activation beat would cost:** Spawn must be offered inside the
  carrier's activation, which in the core means an activation-menu candidate (the
  Teleport design's `Reposition` shape, `TELEPORT_DESIGN_2026-09-08.md` §3) plus a
  placement POLICY (where does the AI place the copy?) plus a recorded decision the
  replay can fold. That is the discretionary-decision seam the wave has repeatedly
  declined to invent mid-family. Estimate: the menu candidate + policy probes +
  recorder tokens is a separate 100+ line PR with its own epoch questions.
- **Recommendation:** keep the round boundary for the seam PR; the per-activation beat
  is a follow-up that can ride the Teleport/Reposition decision seam when that lands.
  Fidelity note in the PR body, same discipline as #823's declared simplifications —
  but now only ONE (timing), not three.

### 3.5 Circle shape for `ArrivalZone`

`ArrivalZone` (`deployment.rs:2318-2323`) has `Rect` and `EdgeStrip`. Add:

```
Circle { center: (f64, f64), radius_m: f64 }
```

- `best_spot` scans the circle's bounding square and rejects per spot where the base is
  not fully inside the circle — mirroring how the `EdgeStrip` variant already scans the
  whole table and rejects per spot (`deployment.rs:2326-2329` comment), so the
  y-outer/x-inner scan order is untouched.
- Size estimate: ~25-35 production lines (enum arm, the `best_spot` predicate branch,
  the py binding mirror in `nml-core-py/src/lib.rs`, one parity fold). The table's own
  predicate is `radius + anchor_radius` around the anchor (`main.gd:17505`) —
  the anchor radius is the caller's business, folded into `radius_m`.

### 3.6 Replay tokens and epoch gate

- The record-format change (optional `spawn_profiles` header map) is an **epoch bump**:
  records written with the map must not load under the previous epoch's loader without
  the explicit `rule_on(rules_epoch, EPOCH_8_SPAWN_SEAM)` gate (name to be chosen by
  the maintainer; the frozen-gate pattern is #823's `EPOCH_7_TABLE_RULES`).
- Replay byte-identity: the copy's arrival writes the same fold the Reinforcement
  arrival already writes (`arrive_unit` position + the arrival round stamp) PLUS one
  new fold for the template index. A replay of an old record never sees the new fold —
  gated identically to the header.
- Census by NAME: the beat reads the rule by the exact name token `Spawn` (the #823
  read survives unchanged); the copy's profile is data, not a rule read, and earns no
  census row of its own.

## 4. The smallest honest PR series

Order chosen so every PR falls RED on a behaviour, not on a format:

| # | PR | content | RED tests (must fall before the diff) | size est. |
|---|---|---|---|---|
| 1 | `feat(core): ArrivalZone::Circle` | the enum arm + `best_spot` predicate + py binding | a zone-binding test in the #803 f1f1b15d style: a copy that fits the circle but not the bounding square's corner must place; drops when the circle degrades to its `Rect` | 30-40 lines |
| 2 | `feat(core): spawn template in the record header` | the optional `spawn_profiles` map, loader read, epoch gate, the template-index replay fold | a loader test: a record with a Spawn beat + template loads and the copy's statics are the TEMPLATE's; drops when the loader ignores the map (the copy's profile would be unknown) | 50-70 lines (io.rs + tokens.rs + parity fold) |
| 3 | `feat(rules): Spawn — the named copy` (rework of #823's beat) | `UnitStatic.spawn` gains the name/count pair; the beat instantiates the template through `arrive_unit`; census-by-name read unchanged | the #823 test `the_carrier_spawns_a_fresh_copy_within_six_inches` re-pinned to assert the copy's PROFILE (statics fingerprint) is the template's — falls while the beat still rebuilds the carrier's statics (the current #823 behaviour) | 40-60 lines on top of #823's branch |

Recorder first? No — the table already resolves the profile at creation time
(`main.gd:17494`); the recorder only has to serialise what is in hand, so the
recorder fold rides PR 2 where the header shape is defined. Loader before beat, so
PR 3 changes behaviour against an already-accepted format. All three never stacked
on #823: PR 3's branch should cherry-pick #823's read (`unit.rs`) and rewrite the
beat; #823 itself stays HELD until PR 3 lands, then closes superseded.

## 5. Open decisions for the maintainer

1. **Stamp-only meanwhile: yes/no?** Recommendation: **NO.** The census already
   credited the name in #823; a stamp-only retreat buys nothing, and the loader seam
   (PR 1+2) is reusable by the Split family. If the time box for wave 5 does not fit
   the series, the honest interim is HOLD #823 as-is (review-7's status quo), not a
   stamp-only variant that concedes the fidelity break.
2. **Epoch for the header change:** new frozen gate on top of `EPOCH_7_TABLE_RULES`
   (recommendation: yes, `EPOCH_8_RECORD_SPAWN_PROFILES`) or fold into 7 while it is
   still unreleased? Recommendation: new gate — 7 is already pinned by #823's tests.
3. **Timing now or later:** round boundary now, per-activation beat as a follow-up on
   the Reposition seam (recommendation: later), vs. building the discretionary-decision
   seam in the same series. Recommendation: later — the decision seam is its own
   funded design, and coupling it here would blow every cap in §4.

## 6. Risks

- **Record-format change = epoch bump.** Real but contained: the map is optional, old
  records load byte-identically, and the gate makes the mismatch loud rather than
  silent. The risk to police is a record written by a NEW table but loaded with an OLD
  core — the loader must refuse (epoch check) rather than drop the map.
- **Replay byte-identity.** One new fold (template index) rides the gated path; the
  danger is the fold leaking into ungated parity rows. The parity fold must be gated
  with the same `rule_on` predicate as the beat, or old-record replays diverge.
- **A second unit's effect on objectives in rollouts.** The copy changes body-count on
  the table: it can seize/contest from its arrival round onward, shifting objective
  scoring in every rollout that fires the beat. Mitigation: the copy carries the
  #803 arrival-round stamp (no seize/contest on the arrival round, the rule's own
  rider), and the census-excluded test battery must include an objective-score
  before/after pin so the scoring delta is measured, not assumed.
- **Blast radius of a naive roster entry (rejected 3.2a).** Any path that adds the
  copy as a permanent dormant slot touches construction sites, census, encoder folds
  and parity — the note rejects it explicitly so a future PR does not re-invent it.
