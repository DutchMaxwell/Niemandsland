# Utility Buff: the four runtime seams behind sixteen unported names

Design analysis, 2026-09-05. Follow-up to PR #694 ("Utility Buff family — 18 names
ported"; the census moved by 2) and the #708 closure audit, which examined the
sixteen remaining names and found every one **NOT READ — deliberately**, with no
`CONSUMED_PARAM_KEYS["Utility Buff"]` addition (the row stays
`frozenset({"hit_mod","morale_mod"})`, `core/nml-core-py/tools/rule_universe_census.py:106`).

The reason is not a missing registry entry or a missing param key. It is that the
core has no RUNTIME SEAM that reads these effects. This document says, per seam:
where the seam would live, what data it needs, where the epoch gate sits, and the
PR-sized steps — so the next session can execute rather than re-measure.

This file is analysis only. It changes no code, adds no param key, and no step
below may be executed without its own reviewed diff.

## 0. Verified code map (current tree, `docs-utility-buff-seams` @ 1d29e17f)

#708's line citations were measured against a different revision. The drift is
small; these are the verified locations:

| What | Where |
| --- | --- |
| `UtilityBuff` struct — no `ap_mod`/`def_mod`/`defense_mod`/`move_mod`/`range_bonus_in` | `core/nml-core/src/unit.rs:2272-2294` |
| Param parse (`hit_mod`, `casting_mod`, `morale_mod`, `grants_rule`, pick gates) | `unit.rs:2353-2367` |
| The Unimplemented note naming the unmodeled knobs | `unit.rs:2369-2379` |
| `record_buff` all-zero guard + ledger push | `sim.rs:553-566` (guard at `:554`) |
| `LiveMod` — deliberately lacks `def_mod`/`range_in`/`advance_in`/`rush_in` | `mods.rs:18-40` |
| `Role::Casting` matched but never summed | `mods.rs:65`; zero `mods::sum(.., Role::Casting, ..)` call sites |
| The four reads that DO exist | hit: `sim.rs:1400-1401`; morale: `sim.rs:2251`; grants: `sim.rs:1402-1445`, `1478-1494`, marks `1461-1467`; `spend_once`: `sim.rs:641-642`, `2268` |
| Cast path (EV, no roll) | `spell.rs:16-23` (`CAST_BASE_TARGET=4`, fixed 0.5), called at `sim.rs:2698` |
| `EPOCH_6_TABLE_RULES` (frozen `6`) | `acts.rs:378` |

### The sixteen names, reconciled against the registry

The registry (`assets/solo/rules_mechanics_*.json`) carries no "Defensive Buff /
Defensive Debuff" — the pair #708 spelled both ways is **Defense Buff / Defense
Debuff** (`def_mod: 1` / `defense_mod: -1`). The sixteenth name the four seams
above under-count is **Increased Shooting Range Buff** (`range_bonus_in: 6`), the
only Utility-Buff carrier of the last knob the census comment lists
(`rule_universe_census.py:100-102`). Verified sixteen:

| # | Name | Effect (registry) | Seam |
| --- | --- | --- | --- |
| 1 | Casting Buff | `casting_mod +1`, `friendly_caster` | 1 |
| 2 | Casting Debuff | `casting_mod -1`, enemy | 1 |
| 3 | Speed Debuff | grants `Slow` (enemy) | 2 |
| 4 | Speed Buff | grants `Fast` | 2 |
| 5 | Swift Buff | grants `Swift` | 2 |
| 6 | Great Musician | `move_mod +1` (a param, not a grant) | 2 |
| 7 | Rapid Advance Buff | grants `Rapid Advance` | 2 |
| 8 | Rapid Rush Buff | grants `Rapid Rush` | 2 |
| 9 | Rapid Charge Mark | grants `Rapid Charge`, `beneficiary: attackers` | 2 |
| 10 | Dangerous Terrain Debuff | grants `Dangerous Terrain` (enemy) | 3 |
| 11 | Difficult Terrain Debuff | grants `Difficult Terrain` (enemy) | 3 |
| 12 | Entrenched Buff | grants `Entrenched` | 3 |
| 13 | Piercing Debuff | `ap_mod -1` (enemy; self-net on the debuffed unit) | 4 |
| 14 | Defense Buff | `def_mod +1` | 4 |
| 15 | Defense Debuff | `defense_mod -1` | 4 |
| 16 | Increased Shooting Range Buff | `range_bonus_in 6` | 4 (range half) |

Every row already lands in the ledger (`record_buff` pushes `hit/casting/morale/
grants_rule`), which is why the census classes them STAMPED, not MISSING — except
rows 13-16, whose only knobs are unmodeled, so the guard at `sim.rs:554` drops
them before anything could read them.

## 1. Seam 1 — the casting roll

**(a) Where it would live.** There is no casting roll in the core to read the
ledger: the cast path is an EV walk. `cast_phase` (`sim.rs:2670-2712`) computes
`p_success = cast_success_chance_base()` (`sim.rs:2698`), a constant
`success_chance(4)` = 0.5 (`spell.rs:21-23`), then applies effects scaled by it
(`apply_cast_effect`, `sim.rs:2612-2659`). The seam is therefore a parameterised
`cast_success_chance(state, caster)` in `spell.rs` whose target becomes
`(CAST_BASE_TARGET - casting_net).clamp(2, 6)`, with `casting_net =
mods::sum(state, caster, Role::Casting, false, |r| r.casting_mod)` folded at the
`sim.rs:2698` call site. Why there and not the next-nearest candidate: `Role::Casting`
already matches (`mods.rs:65`) — a sum with no call site changes nothing — and
`apply_cast_effect` is the wrong site because a casting mod shifts the chance the
attempt LANDS (the table's cast target, `main.gd:3294`), not the size of a landed
effect. The `state.mods` imagination stamps are write-only by the table's own
admission (`mods.rs:4-8`); they are not a consumer.

**(b) What data it needs.** Nothing new. `casting_mod` is parsed
(`unit.rs:2362`), recorded (`sim.rs:559`), and already present in recorded corpora
verbatim (`io.rs:151` reads it from `spell_records`). The honest census addition
once the read exists: `"Utility Buff": frozenset({"hit_mod", "morale_mod",
"casting_mod"})` — in the same diff as the reader, never before.

**(c) The epoch gate.** `rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES)` around
the sum at the `sim.rs:2698` fold (the `seams.rules_epoch` precedent,
`sim.rs:724`). A record stamped below epoch 6 (the Gen-3 recorder's live window
stamps 5) must keep seeing the flat 0.5 chance and an inert ledger row — recorded
corpora replay byte-exact.

**(d) PR-sized steps.**

1. One diff, well under 150 lines: parameterise the chance, fold the sum behind
   the gate, plus the census row. RED test `casting_buff_buffs_the_cast_attempt_
   at_epoch_6_and_not_below` (pattern of `unit.rs:3459`: epoch 6 asserts the
   shifted chance, epoch 5 asserts flat 0.5). Unblocks: **Casting Buff, Casting
   Debuff** (2 names).
2. Caveat to resolve in review: the core's cast is the battle-sim twin's EV path
   (`NML_SIM_CAST`, `io.rs:317`); the table's casting sum lives on its played
   path. Whether the recorded solo corpora ever exercise a mod-shifted cast is a
   measurement — if none does, the RED test must build the record core-side, and
   the shift is an epoch-6 divergence the review must accept explicitly.

## 2. Seam 2 — runtime movement (the hard one)

**(a) Where it would live — and why that is not an answer yet.** Movement is
consumed precomputed at three layers:

- The loader pass `list_to_profile.py::_move_bands` (`:509-574`) folds LIST-TIME
  rules (name pass: Fast/Slow/Quick/Rapid Advance/Rapid Rush; registry pass:
  `MOVE_PRIMITIVES`, `:129`) into the profile `move_bands`, floored at 0, once
  per game. This precomputation is why replays are fast and deterministic — it is
  not a bug to be removed.
- The core re-walks the same carriers census-only: `move_rule_mods_of`
  (`unit.rs:2763-2860`) → `UnitStatic.move_rule_mods` (`unit.rs:657`) — stamped
  "never a simulation input" because "a live re-fold at the move seam would
  double-count a recorded band" (`unit.rs:643-648`, same warning for Royal
  Legion `unit.rs:675-679`).
- Runtime consumption is the recorded dynamic layer `State.bands`
  (`state.rs:419`, written from the recorder's `state_to_plain` bands,
  `io.rs:755`) — read at `sim.rs:3413-3414` (ADVANCE/RUSH/CHARGE execution),
  `sim.rs:3147` (charge reach), `gate.rs:59`, `tokens.rs:153`, `tokens.rs:414`,
  `score.rs:88`, `rows.rs:618`, `rows.rs:632`, `menu.rs:299`, `menu.rs:514`,
  `menu.rs:666`. There is no single seam function that owns "movement distance".

**(b) What data it needs.** Two shapes. The grant-only six (names 3-5, 7-9) land
in the ledger as `grants_rule` records and would be read by
`mods::granted`/`granted_vs` — no new field. Great Musician (name 6) carries a
`move_mod` param that `UtilityBuff` does not model, so its row is dropped by the
`sim.rs:554` guard today; porting it needs the same plumbing as seam 4's step 1.
No `CONSUMED_PARAM_KEYS` addition is honest for any of them until a read exists
(see §5).

**(c) The epoch gate.** If a delta ever lands, it folds behind
`rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` at the consumption point; a record
stamped below epoch 6 must keep seeing exactly today's behaviour — the recorded
band, untouched, with the ledger row riding inert.

**(d) Can a runtime delta coexist with the precomputation? The honest answer.**

- For LIST-TIME rules: no — proven, documented double-count (`unit.rs:646`,
  `unit.rs:678`). The loader pass already folded them into the recorded band.
- For MID-GAME ledger grants (these seven names): the loader never saw them, so
  a delta on top is arithmetically coherent. BUT the decisive fact is
  unknowable from this repo: the table's own per-activation band derivation
  (`move_bands_for_props`, `movement_range_controller.gd:80`) works from "a dict
  that GROWS during a live game" (`state.rs:117-124`) — if the grant overlay
  feeds that dict, the recorder's dynamic-layer bands ALREADY carry the table's
  answer and a core delta double-counts; if it does not, the table itself never
  moves a buffed unit differently, and porting a runtime movement effect would
  be a deliberate divergence from the twin — the core would do something the
  table's solo mode does not. In-repo evidence points the second way: the
  table's four ledger reads are hit/casting/morale plus the grants bridge
  (`mods.rs:8-11`), no movement read.
- Cost even if the measurement says go: the delta must be folded at every band
  read or centralised by mutating `state.bands` at activation start — which
  rewrites recorded state, the thing replay determinism rests on. The
  EV/planner reads (`score.rs:88`, `rows.rs`, `menu.rs`, `tokens.rs`) and the
  executor reads (`sim.rs:3413`) would need one consistent answer across seven
  files, or an explicitly documented EV/roll asymmetry (the `ctx_of`/`ctx_live`
  precedent, `sim.rs:1454-1460`).

**Verdict: a documented NO, with one measurement that can reopen it.** The
default answer is that the seven names stay STAMPED: the table's own ledger reads
do not touch movement, and every in-repo movement effect this core consumes
arrives precomputed. Reopening requires the measurement below to prove the table
DOES move differently; a core-side delta proven to diverge from the table is not
a port, it is a new rule.

Steps (only if pursued):

1. Measurement (offline Python tool, no core change, watcher on its report
   artifact): replay recorded activations; for units with a live move-grant
   record, diff the dynamic-layer `bands` against the profile `move_bands`. If
   no corpus ever carries a live move grant into a later activation, the
   measurement is inconclusive and the NO stands.
2. Conditional delta at `sim.rs:3413-3414` and `sim.rs:3147`, epoch-gated,
   EV paths left blind, RED test `speed_buff_extends_advance_over_the_recorded_
   band_at_epoch_6` — only after step 1 says go. Unblocks: the seven names in
   the table above, the largest block — which is exactly why it must not be
   done sloppily.

## 3. Seam 3 — terrain / defense

**(a) Where it would live.** In `ctx_live` (`sim.rs:1370-1510`), inside the
existing epoch-6 arm — the Shielded-alias precedent is the exact shape:
`mods::granted(state, i, name) && (!terrain || c.in_cover)` raises the working
defense (`sim.rs:1478-1494`). The save-side consumer already has a live-mod
precedent: `growth_def_mod` is stamped in `ctx_live` (`sim.rs:1502-1506`) and
consumed in the save rung at `dice.rs:309` (`defense + def.growth_def_mod`,
traced at `sim.rs:1622`). A terrain/defense grant folds the same way: a granted
name + (cover-conditional where the rule says so) → a Ctx defense-mod field →
the `dice.rs:309` rung. Why not the next-nearest candidate:
`combat::shielded_defense` is the Shielded armor-rung helper, not a per-record
ledger read; and the EV `ctx_of` must stay blind — the sighting seam's own
documented asymmetry (`sim.rs:1458-1459`).

**(b) What data it needs.** Nothing new for the three grant names — the records
already carry `grants_rule` ("Entrenched", "Difficult Terrain", "Dangerous
Terrain"). The per-name DELTA is read from the granted rule's own registry entry
or takes the table's hardcode shape (the Shielded `defense_bonus` precedent,
`unit.rs:1298`). Name-only reads need no `CONSUMED_PARAM_KEYS` change (the name
token is the census's evidence rule, `rule_universe_census.py:1146`); if a step
consumes a registry PARAM of the granted rule's own primitive, that primitive's
row grows — never the "Utility Buff" row, or every grant-carrying name under it
would flip at once (the §5 trap). Honest split of the trio: Entrenched is a
cover/defense fold (this seam); Difficult/Dangerous Terrain's table semantics
are likely movement/movement-damage effects, which belong to seam 2's problem —
verify each name's granted-rule text before folding it into a save rung.

**(c) The epoch gate.** `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` around the
fold in `ctx_live` (the `sim.rs:1478` precedent). A record stamped below epoch 6
must keep seeing no save-rung raise — the row rides the ledger inert, replays
byte-exact.

**(d) PR-sized steps.**

1. The fold + Ctx field + `dice.rs:309` consumption + census note (~100 lines).
   RED tests `entrenched_grant_raises_the_save_rung_only_in_cover_at_epoch_6`
   and its epoch-5 twin (gate OFF, red before the fix). Unblocks: **Entrenched
   Buff**, and — pending the per-name semantics check — **Defense Buff, Defense
   Debuff** if their `def_mod`/`defense_mod` plumbing exists (seam 4 step 1
   below; Defense Buff/Debuff sit on the seam 3/4 boundary: the read is seam 3's
   shape, the data plumbing is seam 4's).
2. Dangerous/Difficult Terrain: do NOT fold into the save rung on speculation.
   Each needs its granted-rule semantics verified (§2's measurement answers the
   movement half). Until then they stay STAMPED, honestly.

## 4. Seam 4 — attacker-side AP (and the record-shape half)

**(a) Where it would live.** Two halves.

Write half: `ap_mod`/`def_mod`/`defense_mod`/`range_bonus_in` are not fields on
`UtilityBuff` (`unit.rs:2284-2293`), so `record_buff`'s all-zero guard
(`sim.rs:554`) drops the row before anything could read it. The plumbing is:
parse the params in `utility_buffs_of` (the `param_i` precedent,
`unit.rs:2361-2363`), add the fields to `LiveMod` (`mods.rs:24-40`) and to the
recorded-record reader `PlainBuff` (`io.rs:147-162` — serde currently IGNORES
`def_mod` and friends, `io.rs:143-145`, so corpora that carry them parse fine
once the field exists), and widen the guard. The guard widening itself must be
epoch-gated — see (c).

Read half: attacker-side AP folds where the pierce grants do — `ctx_live`
stamps `pierce_*_grant` (`sim.rs:1430-1432`), consumed at `dice.rs:871`
(shooting), `dice.rs:1264` (melee), `dice.rs:1285` (assault). An int `ap_mod`
needs a Ctx field summed like `hit_mod` (`sim.rs:1400-1401`) with a new matcher
arm (a boolean Role is not enough), then `ap + c.ap_mod` at the pierce sites.
Defender-side `defense_mod` is seam 3's `dice.rs:309` fold.

**(b) What data it needs.** The registry params exist (`ap_mod`, `def_mod`,
`defense_mod`, `range_bonus_in` — table in §0). Whether RECORDED corpora carry
them is doubtful: the table's own `_solo_record_spell_mod` builds "the same three
keys" and drops the all-zero row (`main.gd:16534/:3663`, quoted at
`unit.rs:2377-2378`), so most recorded `spell_records` for these names are absent
— RED tests must build records core-side; recorded-corpora coverage is only
possible where a table record does carry the knob. The honest census addition,
in the same diff as the reads: `"Utility Buff": frozenset({"hit_mod",
"morale_mod", "casting_mod", "ap_mod", "def_mod", "defense_mod"})` — minus any
knob the diff does not actually read.

**(c) The epoch gate.** Two gates, one seam. Write side: the widened
`record_buff` guard accepts the new knobs only behind
`rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES)` — below epoch 6 the row must
keep being dropped, or the core's own serialized states diverge from the
recorder's for old corpora. Read side: the `ctx_live`/dice folds carry the same
gate; a record stamped below epoch 6 keeps seeing nothing, exactly today's
behaviour.

**(d) PR-sized steps.**

1. Record shape (~120 lines: `UtilityBuff` + parser + guard + `LiveMod` +
   `PlainBuff` + round-trip test). RED test
   `ap_and_defense_only_buff_rows_survive_record_buff_at_epoch_6` (and the
   epoch-5 twin asserting the row is still dropped). Unblocks nothing alone.
2. The reads (~80 lines: Ctx fields, matcher arms, `dice.rs:871`/`1264` folds,
   `dice.rs:309` defense fold) + census row. RED test
   `piercing_debuff_cuts_the_bearer_ap_and_defense_debuff_softens_the_save_at_
   epoch_6`. Unblocks: **Piercing Debuff, Defense Buff, Defense Debuff** (3
   names; Defense Buff/Debuff also need seam 3 step 1's cover-conditional fold
   if their semantics are cover-gated — verify against the granted-rule text).
3. `range_bonus_in` (Increased Shooting Range Buff): **documented NO for now.**
   The core models no shooting-range bonus at all — `versatile_reach`'s range
   half was refused for exactly that reason (`unit.rs:658-662`), and Royal
   Legion's range half sits in the same boat (`unit.rs:670-685`). A range seam
   is its own project; until then the name stays STAMPED.

## 5. What must NOT be done

- **Do not add param keys to `CONSUMED_PARAM_KEYS["Utility Buff"]` without a
  reader in the same diff.** The census's PORTED test is "a
  `CONSUMED_PARAM_KEYS`-consumed primitive-param in non-test core code"
  (`rule_universe_census.py:1146`); a listed key with no reader flips the names
  to PORTED while nothing reads them — bug #489's exact shape, the
  trusted-whole over-credit this table exists to prevent
  (`rule_universe_census.py:102-105`; the Surge precedent, `:124`). An honest
  STAMPED beats a false PORTED.
- **Do not list the pick gates** (`range_in`, `target`, `needs_los`,
  `max_targets`, `once`, `beneficiary`) as consumed keys — they shape the pick,
  never the effect; listing one would flip all sixteen at once
  (`rule_universe_census.py:103-105`).
- **Do not widen the `record_buff` guard without a reader and without the epoch
  gate** — the same over-credit shape one layer down: a row that lands but is
  read by nothing, plus a replay-parity break for old corpora.
- **Do not remove or weaken the loader's `_move_bands` precomputation** — it is
  why replays are fast and deterministic; a runtime seam may only ever ride ON
  TOP of recorded bands, and only after §2's measurement.
- **Do not read the imagination stamps**: `state.mods` is the table's own
  write-only EV bookkeeping (`mods.rs:4-8`); it is not a consumer for any seam
  here.
- **Never the literal `6`** for the wave-3 gate — always
  `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` (the frozen constant,
  `acts.rs:378`).

## 6. Priority by coverage

1. **Seam 3 + 4** (steps 3.1, 4.1, 4.2): up to 6 names, all with strong
   in-repo precedents (Shielded fold, `growth_def_mod`, pierce grants), no new
   architecture, no parity unknowns beyond the two-sided epoch gate.
2. **Seam 1** (step 1.1): 2 names, small; blocked only on the one cast-roll
   measurement (§1 step 2's caveat).
3. **Seam 2**: 7 names — the largest block and the only one with a genuine
   architectural tension. Default: documented NO. Reopen only via the
   measurement; a divergence proven to be new behaviour is a rules decision,
   not a port.

Realistic ceiling without seam 2: 8-9 of 16 names ported for real; the rest stay
honestly STAMPED — which is the correct state until their seams exist.

## 7. Open decisions (maintainer)

- Accept the §0 reconciliation of the sixteen names (no "Defensive Buff/Debuff"
  in the registry; Increased Shooting Range Buff is the sixteenth)?
- Approve the seam-2 documented NO, or fund the measurement first?
- The `casting_mod` sign/roll convention (§1 step 2): verify against recorded
  corpora before implementing, or accept the epoch-6 divergence explicitly?
- Entrenched/Difficult/Dangerous Terrain granted-rule semantics: confirm from
  the rule text before seam 3 step 1 folds anything but Entrenched.
