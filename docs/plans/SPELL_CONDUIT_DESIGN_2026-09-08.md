# Spell Conduit — casting AS IF standing at the conduit (design note)

Date: 2026-09-08. Scope: DESIGN only. Name covered: **Spell Conduit** —
`docs/plans/RULES_WAVE5_MAP_2026-09-07.md` group (b). Template:
`docs/plans/FEAT_DESIGN_2026-09-08.md` and `docs/plans/TELEPORT_DESIGN_2026-09-08.md`.

## 1. The rule text and its shape

Verbatim (one identical text in all 11 books that carry the name; dedup confirmed across both
army systems):

> Casters within 12" that are from other friendly units may cast spells as if they were in this
> model's position, and get +1 to casting rolls when doing so. Friendly casters may only use this
> rule if this unit isn't Shaken.

Registry params (both systems, book_version 3.5.3):
`{range_in: 12, casting_mod: 1, requires_not_shaken: true}` — the name is its own primitive,
no alias, 11 occurrences (6 gf + 5 aof).

Shape, clause by clause:

- **The conduit** is the model CARRYING the rule. Any friendly **caster** from a DIFFERENT
  friendly unit within 12" of the conduit may use it (the caster must itself be a caster; a
  non-caster gains nothing). The rule lives at army-book level and reaches units via upgrades
  (banners, priests, palanquins); a few units carry it directly.
- **The choice is per spell.** "…may cast spells as if…" is discretionary, and the "+1 … when
  doing so" attaches to casts made THROUGH the conduit — so each spell independently picks
  origin = caster (no bonus) or origin = conduit (+1 and the conduit's position).
- **"As if standing at" substitutes the ORIGIN for range AND line of sight**: both are measured
  from the conduit's position, not the caster's. It does NOT substitute the caster itself — the
  caster still pays its own tokens, still rolls, and enemy interference is unaffected (the rule
  says nothing about it). It also does not move the caster.
- **The Shaken gate binds the CONDUIT** ("this unit isn't Shaken"), not the caster — an
  in-range conduit that is sitting it out simply offers neither its position nor the +1.

## 2. What the TABLE does today (measured on this commit)

| aspect | state | evidence |
|---|---|---|
| Roll half (+1 to casting) | **live** in the solo resolution path — scans friendly non-reserve conduits, edge-to-edge distance (NML-206) against the rule's own `range_in`, gates `requires_not_shaken` with a rules-must-log line, folds `casting_mod` into the clamped cast target | scripts/main.gd:3382-3417 |
| Position half (origin substitution) | **live in the AI target picker** — `spell_candidates` builds `origins = [caster] + every friendly non-reserve conduit bearer within reach`, then a target counts as legal if ANY origin has it within `range_in` AND in line of sight | scripts/solo/solo_controller.gd:4398-4424; AI cast list built at :4441 |
| Human casting | **no conduit support** — casting is manual (radial "C", CastsDialog, token ±); the highlight list reuses `spell_candidates` (main.gd:8642) so conduit-reachable targets glow, but the player gets no origin picker and the +1 fold never applies to a human cast (it lives only in `_solo_resolve_one_cast`) | scripts/main.gd:8642, :3350 |
| The mirror SIM | **does NOT cast through conduits** — `BattleSim._cast_phase`/`_pick_cast`/`_best_spell_target` measure range and LOS from the caster only | scripts/solo/battle_sim.gd:1202-1258 |
| One known inconsistency | the origin sweep gates the conduit's distance on the hardcoded `SPELL_ACCUMULATOR_REACH_IN` (= 12.0) instead of the rule's own `range_in` param — same number today, a divergence tomorrow | scripts/solo/solo_controller.gd:4413, :4525 |
| Recording | **no origin anywhere in the record** — the sim's cast event carries `{spell, kind, cost, target, p_success}`; no act token or ledger
key records which origin a cast used | scripts/solo/battle_sim.gd:1230-1236 |

So the wave-5 map's "MISSING" verdict is a CORE-census verdict (the Rust core has no reference
to the name); the table's real engine already implements both halves as approximations. What is
actually missing: (a) core fidelity for the origin, (b) the sim twin's parity, (c) any record of
the chosen origin.

## 3. The core seam proposal

**An `origin` override on the cast candidate** — caster position by default, conduit position
when the cast rides the conduit.

- **Candidate shape:** every cast candidate today is evaluated as `(spell, target)` with
  range/LOS from the caster. The candidate gains `origin: usize` (unit index; caster when
  absent). Range and LOS are evaluated AT the origin: `edge_gap_in(origin, target) <= range_in`
  and `los_clear(origin, target)` — the same edges the table measures (`nearest_melee_gap_in`,
  NML-206).
- **The +1 rides the origin.** When `origin` is a conduit bearer, `casting_net` gains the rule's
  `casting_mod` param (+1) — consumed by the existing `cast_success_chance(casting_net)`
  (core/nml-core/src/spell.rs:36) and the sim's `casting_net_of` fold. Param-driven, not a
  hardcoded +1.
- **Enumeration without a search explosion:** the origin set is `[caster] + eligible conduit
  bearers` — a LINEAR scan over friendly units (the exact walk `spell_candidates` runs), not a
  placement search. Conduit bearers are rare (typically 0-2 per army); per target the walk stops
  at the FIRST reachable origin (the table's `break`), so cost is O(targets × origins) distance
  checks, at most one LOS probe per non-reachable check. A hard cap of 3 origins is not needed
  but may be asserted in a test. With no conduit in range the set is `[caster]` and every
  existing byte path is unchanged — this is the zero-cost gate.
- **Recorder / replayer:** extend the recorded cast act with `origin` (the unit id; absent =
  the caster). The table's cast event dict (battle_sim.gd:1230-1236) gains one key; io.rs folds
  it next to the other cast fields; the replay applies range/LOS at the recorded origin. One
  key, one fold — no new ledger family.
- **Epoch gate:** like every cast-sub-phase token, gate the `origin` fold on the current rules
  epoch (the `rule_on(rules_epoch, …)` pattern of sim.rs:1375): recordings below the epoch never
  carry the key, so replay bytes are untouched.
- **Census by NAME:** "Spell Conduit" — 11 occurrences, 6 gf + 5 aof, exact display-name census
  as the map does it; aliases resolve to the primitive but the census stays on the name.

## 4. The smallest honest first PR on each side — and the order

**Recommendation: TABLE FIRST, then core — because a record must exist before a replay can
consume it.** A core-first PR would replay synthetic cast acts with a hand-written `origin`
key — testing the core against an imagined table. Table-first means the first recording that
carries a real origin is then the core's RED test, the same order and reasoning as the Teleport
note (TELEPORT_DESIGN_2026-09-08.md §4).

- **PR 1 — table: parity + record (≤ 80 lines GDScript).** Give the mirror SIM the same origin
  walk the real engine has: `_pick_cast`/`_best_spell_target` accept an origin list built once
  per cast phase (caster + eligible non-Shaken conduits, distance measured on the sim's
  positions), evaluate range AND `_los_clear` at the origin, add `casting_mod` to the cast
  chance when the origin is a conduit, and write `origin` into the cast event. While there,
  switch the real engine's sweep to the rule's own `range_in` param (one line; kills the
  hardcoded-12.0 divergence). RED test: a fixture with a conduit and a target reachable only
  through it — the sim twin casts it, the event carries `origin`, a no-conduit fixture is
  byte-identical.
- **PR 2 — core: candidate + replay (≤ 120 lines).** The `origin` field on the cast candidate,
  the epoch-gated io fold, range/LOS at the origin, and the param-driven `casting_mod` fold.
  RED tests: replay a real recorded cast with `origin` → target legality and cast chance
  evaluated at the recorded origin; an epoch-below recording → no origin key, byte-identical;
  a recording with `origin` absent → the current bytes.

## 5. Open decisions for the maintainer (max 3)

1. Origin scope: all eligible conduits (the table's walk) vs nearest-conduit-per-spell —
   **recommend all eligible** (it mirrors the engine, is already O(1)-bounded in practice;
   nearest-only would invent a second interpretation the core must keep alive forever).
2. Per-spell origin freedom for the AI: try every (origin, spell) pair for the best EV vs the
   official pick order with the first reachable origin — **recommend the official walk**
   (origin = first reachable per spell, exactly what `spell_candidates` does today; EV-shopping
   over origins would break parity with the table's own AI).
3. Order table-first vs core-first — **recommend table-first** (a record must exist to replay;
   §4).

## 6. Risks

- **Replay byte-identity below the epoch:** a new key on recorded cast acts changes replay
  bytes for old corpora. Mitigation: epoch gate like every cast-sub-phase seam (sim.rs:1375
  pattern); the fold and the token only exist above the epoch.
- **Planner branching:** origin enumeration multiplies cast candidates by the number of eligible
  conduits. Mitigation: the set is `[caster] + conduits` (roster-bounded, typically ≤ 2), the
  walk stops at the first reachable origin per target, and with no conduit in range the code
  path is byte-for-byte today's.
- **Table/core divergence on LOS from the conduit:** the engine's `_solo_has_los` and the
  core's `los_clear` matrix must agree on conduit→target sight, and the core's matrix may lack
  origin-pair answers entirely (the recorder never probed them). Mitigation: the table's PR 1
  writes the origin into the event and the sim twin uses `_los_clear` on the same state the
  matrix was captured from; for pairs the matrix does not cover, `los_clear` falls back to
  clear (its documented no-matrix behavior) — and the core PR states that fallback explicitly
  so the divergence cannot hide.
- **The +1 half vs the position half:** if the two halves are ported in different PRs the
  census can claim one while the other is missing. Mitigation: both halves ride the same
  `origin` seam in the same PRs (PR 1 and PR 2 above each carry both).
