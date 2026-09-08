# The once-per-game FEAT primitive — design note for the five wave-5 group-(b) names

Date: 2026-09-08. Scope: DESIGN only. Names covered: **Takedown Shot**, **Speed Feat**
(+ **Speed Feat Aura**), **Precision Feat**, **Piercing Feat** —
`docs/plans/RULES_WAVE5_MAP_2026-09-07.md` group (b), "the highest-leverage DESIGN decision
on this page". Template: `docs/plans/REINFORCEMENT_DESIGN_2026-09-07.md`.

## 1. The rule texts and their common shape

| name | text (registry params, verbatim) | entry |
|---|---|---|
| Takedown Shot | "once per game, when this model shoots, it may make one extra attack at Quality 2+ with AP(2), Deadly(3), and Takedown" — `extra_attack_q: 2, ap: 2, uses_per_game: 1` | `rules_mechanics_gf.json` (two book entries, identical params) |
| Speed Feat | "once per game, this model's move bands gain +2\" Advance / +4\" Rush for one activation" — `advance_mod: 2, rush_mod: 4, uses_per_game: 1` (primitive: `Quick`) | gf + aof, identical |
| Speed Feat Aura | aura granting "Speed Feat" — `grants: "Speed Feat"` | gf + aof, identical |
| Precision Feat | "once per game, all this unit's shooting attacks gain +1 to hit for one activation" — `hit_bonus: 1, all_attacks: true, uses_per_game: 1` (primitive: `Shot Modifier`) | aof only, two identical entries |
| Piercing Feat | "once per game, this unit's attacks gain AP(+1) for one activation" — `ap_bonus: 1, condition: "any_attack", uses_per_game: 1` (primitive: `Piercing Assault`) | aof only |

Common shape — this is the primitive:

- **Latch:** ONCE PER GAME (`uses_per_game: 1` on every entry). Not once per round, not per
  activation — nothing resets it.
- **Declare-when:** the acting side chooses the moment ("may declare at a moment of its
  choice"); the effect window is then exactly ONE activation (the declaration's own).
- **Who chooses:** the acting side (owner's controller). In the table that means the same
  policy layer that already chooses moves, targets, and spell timing.
- **Effect shape:** a temporary modifier to an action the unit takes this activation —
  extra shot (Takedown Shot), band bonus (Speed Feat), to-hit bonus (Precision Feat),
  AP bonus (Piercing Feat). None of them is a statics-time stamp: the moment of
  declaration is part of the rule.

Statics-time stamping cannot answer this (the map's verdict): the latch must live in
mutable per-game state.

## 2. What the table does today, per name (measured)

| name | state | evidence |
|---|---|---|
| Takedown Shot | **automated (AI + human)** | `_solo_takedown_bonus_groups` (scripts/main.gd:16781) appends the extra attack as its own synthetic volley group at its own Quality; joined at the AI volley (scripts/main.gd:3092) and the human volley (scripts/main.gd:9932). The once-per-game flag is `unit_properties["takedown_bonus_used_<name>"]`, spent on first use. |
| Speed Feat | **automated (AI), manual-note only for humans** | The AI move planner spends it when `rounds_left <= 2` (scripts/solo/solo_controller.gd:1704-1726), flag `speed_feat_used_<snake>`, with `record_decision` + `_rule_note`. The range-band UI deliberately skips `uses_per_game` entries from the permanent bands (scripts/movement_range_controller.gd:156-157); the planner valuation path also adds only the advance bonus (scripts/solo/solo_controller.gd:5628). |
| Speed Feat Aura | **GRANT-MISSING** | The aura entry exists in both books; the loader's band passes skip `uses_per_game` grant targets (`GRANT_MISSING_2026-09-07.md` §4), so the aura grants nothing observable. |
| Precision Feat | **absent** | No occurrence of "Precision Feat" under `scripts/`. The core explicitly keeps it out of statics: core/nml-core/src/unit.rs:351 and unit.rs:2534 name it as dead data (`uses_per_game` stays out of the statics fingerprint). |
| Piercing Feat | **absent as a feat** | Registered only as an alias of primitive `Piercing Assault` (aof), and `uses_per_game` is dead data on the table's own resolver (core/nml-core/src/unit.rs:3210). No declaration moment exists. |

The existing once-per-X latches the primitive builds on:

- **Reinforcement** — once-per-game withdraw, `State.reinforcement_used: Vec<bool>`
  (core/nml-core/src/state.rs:521), recorder key `reinforcement_used`
  (scripts/solo/act_recorder.gd:439, folded in io.rs:843).
- **Storm Attack family (wave 3) — the closest template.** Once-per-game flags per unit
  per DISPLAY name: `State.storm_used: Vec<Vec<String>>` (core/nml-core/src/state.rs:543),
  stamped by the recorder off `unit_properties["storm_used_<snake>"]`
  (scripts/solo/act_recorder.gd:447-457), replayed via io.rs:213 and `rep!(storm_used)`
  (core/nml-core/src/tokens.rs:943).
- **Second Wind** — the simplest ledger shape, `second_wind_used` bool, no round
  derivation (act_recorder.gd:408).
- **Delayed Action** — a stateful ROUND stamp, `DELAYED_ACTION_STAMP`
  (scripts/solo/solo_controller.gd:7950), the contrast case: it resets every round.
- **Surprise Attack** — first-activation latch via the Infiltrate-family reserve handling
  (scripts/solo/solo_controller.gd:9837-9847, :10403-10426): the gate is deployment-side,
  not a declaration latch.

## 3. The core seam proposal

**Latch: `feats_used: Vec<Vec<String>>` on `State` — the Storm Attack shape, not a bitset.**

- Per unit, the DISPLAY names already declared this game. Never resets.
- Why `Vec<Vec<String>>` over a bitset: the recorder already records Storm Attack flags as
  display names, the registry keys every entry by display name, and a bitset would couple
  the core to a rule-index mapping that the recorder side does not have. Same reason wave 3
  chose names for `storm_used`.
- Why per-unit and not global: Takedown Shot and the feats are per-unit promises
  ("this model may..."); a global latch would spend one unit's feat when another declares.

**Where the declaration enters the action set.** Two options:

- (a) **Auto-policy inside the existing planner passes** (what Speed Feat does today):
  the move pass spends Speed Feat on `rounds_left <= 2`; the shoot pass spends Takedown
  Shot on every volley while unspent; Precision/Piercing would latch on the first
  attack of a good engagement. Cost in candidate count: **zero** — no new branch.
- (b) **An explicit "declare feat" candidate at activation start** per unspent feat per
  bearer: the planner can then genuinely CHOOSE the moment by EV. Cost: up to +1 candidate
  per bearer per activation per unspent feat (bounded by the fleet's feat density —
  currently ≤1-2 bearers per list, so +1-2 candidates at worst).

Recommendation: **(a) first, (b) as a later upgrade.** (a) matches every existing
once-per-game spend on the table and costs nothing; (b) is the honest end state but only
pays off once the five names are in at all.

**Recorder / replayer.** Exactly the wave-3 recipe, one key: the recorder's `_ledger_of`
gains a `feats_used` block that scans the five feats' primitives (or a shared
`uses_per_game` predicate, like the Storm Attack scan at act_recorder.gd:447) and records
display names whose `unit_properties["<feat>_used_<snake>"]` flag stands; io.rs folds it
into `State.feats_used`; tokens.rs gets `rep!(feats_used)` so a replayed act carries the
latch byte-identically. Gate on the CURRENT rules epoch like `storm_of` does
(core/nml-core/src/unit.rs:2686): older recordings must never carry the new key.

**Census.** The five names count by NAME, as the map already does: Takedown Shot (gf),
Speed Feat + Speed Feat Aura (gf+aof), Precision Feat (aof), Piercing Feat (aof). The aura
flips to satisfied only when the loader's grant path hands Speed Feat to the aura targets
— that is a loader change, not a core one.

## 4. The PR series

**PR 1 — the mechanism + Speed Feat (≤ 120 lines).** The smallest honest first PR:

- core: `State.feats_used: Vec<Vec<String>>` + io fold + tokens rep + the Speed Feat
  read (a `feats_used`-gated `advance_mod`/`rush_mod` band pass in the move seam).
- table: the recorder ledger block (the Storm Attack scan shape, ~15 lines GDScript).
- RED tests that can fall:
  - replay a recorded activation where the feat was spent → replayed `feats_used` matches,
    a second move in the replay gets NO bonus (latch holds below the epoch);
  - the statics fingerprint of a bearer is unchanged by an unspent feat (dead-data
    property preserved);
  - a fresh act after the spend shows no bonus (table→core parity, the #792 shape).

**PR 2 — Takedown Shot latch parity.** The table already automates the extra shot; the
core's shot seam learns to append one own-Quality group gated on `feats_used` and to stamp
the declaration. RED: replayed volley with the feat spent fires exactly one extra attack,
once per game.

**PR 3 — Precision Feat.** `hit_bonus: 1, all_attacks` gated on the latch, in the core's
hit-modifier seam. RED: replayed activation gains +1 to hit on all attacks, next
activation does not.

**PR 4 — Piercing Feat.** `ap_bonus: 1` rides the existing `Piercing Assault` primitive
handler, gated on the latch. RED: same one-activation window.

**PR 5 — Speed Feat Aura grant.** Loader change: the grant path accepts `uses_per_game`
targets and grants them as latch-carrying rules. RED: aura bearer's unit shows the rule
and its spend flips the aura target too.

One name per PR (not "mechanism + all five" in one): each PR stays reviewable and every
RED test falls for exactly one reason.

## 5. Open decisions for the maintainer (max 3)

1. Latch shape `Vec<Vec<String>>` vs bitset — **recommend names** (recorder already speaks
   display names; wave 3 precedent).
2. Declaration policy auto (a) vs explicit candidate (b) — **recommend (a) first**,
   zero candidate cost, matches every existing once-per-game spend.
3. PR series one-name-each — **recommend yes** (5 PRs incl. the aura), never stacked on
   each other.

## 6. Risks

- **Replay byte-identity below the epoch:** the new ledger key must be epoch-gated like
  `storm_of` (unit.rs:2686) — a wave-5 key in an epoch-5 recording would change replay
  bytes. Mitigation: gate + `rep!` only under the new epoch bit.
- **Planner branching:** option (b) adds candidates per bearer per activation; if ever
  shipped naively for all five feats it multiplies activation evaluation cost. Mitigation:
  (a) first, (b) only per feat with measured fleet density.
- **Table parity:** the table spends flags inside `unit_properties` at different seams
  (volley vs move pass); the recorder must scan ALL of them or a replay diverges exactly
  like the Reinforcement bug shape (#792/#493). Mitigation: one shared
  `uses_per_game` scan in `_ledger_of`, not per-rule copies.
