# B2b — the buff-consumption bridge (Utility Buff, block B2b)

## Goal
A buff written onto a unit is READ when that unit — or the unit attacking it — later rolls dice.
One ledger, one fold, one set of read sites. Then the six remaining "Utility Buff" names on top.
## The one read path
`State.buffs: Vec<Vec<LiveMod>>` — per unit, the live modifier RECORDS, mirroring `main.gd`'s
`_solo_spell_mods` (:370). NOT `State.mods`: that is the f64 EV stamp of `BattleSim._apply_cast_effect`
(battle_sim.gd:1309-1323), which the table's own imagination writes and reads NOWHERE
(battle_sim.gd:1529 says so in as many words) — the twin stays blind there, or it stops mirroring.
`ctx_of_live(us, state, i, melee)` = `ctx_of` + the fold. The tray path calls it; the EV path keeps
calling `ctx_of` and stays buff-blind, like `BattleSim._ctx_of` (which never sets the `spell_hit_mod`
key `AiEv.profile_ev` ai_ev.gd:331 reads). `Ctx` carries the numbers into the rolls it already reaches:
- `Ctx.hit_mod` — the bearer's own net (`_solo_spell_hit_mod` :3789), role `attacker_own`
- `Ctx.vs_hit_mod` — the attackers-beneficiary net ON this unit (`_solo_spell_hit_mod_vs` :3800)
- `Ctx.morale_bonus` — the existing field, `+ morale_mod` (main.gd:8286-8292)
- `Ctx.unstoppable_grant` — `mods::granted(state, i, "Unstoppable")`, the dynamic rule-grant path

Read sites, all TRAY only: `dice.rs` shooting to-hit (:448), `melee_hit_target` (:606), `tray_morale`
(sim.rs:1183), the Regeneration bypass (`dice.rs:539/773`, `_solo_ignores_regen` :6941). Casting has
NO tray consumer: this core has no cast die (`cast_phase` is EV-only) — write half only.
## Precedence when mods stack
The table SUMS every matching record, then applies ONE `modified_hit_target` clamp with the rest of
the modifiers; Unstoppable's `m<0 -> 0` clamp runs AFTER that sum (`melee_hit_target` already does).
Scope filter (`AiSpell.mods_for` ai_spell.gd:364-400): `charging` never applies; a `melee` record is
skipped on a shooting roll and vice versa; `beneficiary=="attackers"` never joins the bearer's own net.
Chain: hit/morale read self+host (`_solo_mods_of_chain` :3812); a rule GRANT reaches the whole joined
chain (`_solo_apply_grant` :3730). `once` records are spent by the exchange that could have used them
(`_solo_consume_once_mods` :3823), per role.
## Steps (one diff each, <= ~80 changed lines)
- [x] 1. `mods.rs`: `LiveMod`/`Scope`/`Role`/`matches`/`sum`/`granted`/`spend_once`; `State.buffs` + `vs_mark_round`.
- [x] 2. `Ctx` + 3 fields; `ctx_of_live`; the tray read swaps in `sim.rs` and `dice.rs`.
- [x] 3. `unit.rs`: `UnitStatic.utility_buffs` from `rules_of_primitive(reg, p, "Utility Buff")`.
- [x] 4. `sim.rs`: `utility_targets` — `_solo_utility_targets` :16317-16359 minus Extended Buff Range.
- [x] 5. `sim.rs`: `tray_utility_buff`'s buff arm — record the pick (the five friendly/enemy names).
- [x] 6. `sim.rs`: `tray_vs_marks` at the attack seam (main.gd:3042 volley, :8035 melee) — the Mark.
- [x] 7. `sim.rs`: `spend_once` at the exchange and morale seams.
- [x] 8. Rust fixture tests; 9. gate / census / RED runs — no production diff.
## Log
1. mods.rs + State.buffs/vs_mark_round, 5 construction sites. 154 changed lines / ~80 non-comment — over the ~80 *changed* line rule, but splitting a struct from its only readers gives a non-compiling commit.
2. Ctx +3 fields, `ctx_live`, six read sites. nml-core still 118/118: the fold is inert until something writes.
3. `utility_buffs_of` — the params ARE reachable in Rust (`RulesMap::lookup`), so the six names are ONE data-driven arm, not six.
4. `utility_targets`. Extended Buff Range deliberately out.
5. The buff arm. Kept `reposition_artillery_active` as B2a left it; the only Utility Buff co-carried by a Re-Position carrier is a `vs_target` Mark, a no-op at this seam, so the split loop order is unobservable.
6. `tray_vs_marks`; `tray_charge` gained a `seams` argument.
7. `spend_exchange` + the morale spend. 7b: the `Scope` enum became the GDScript's own strings — 15 lines, and closer to `mods_for`.
8. Six fixture tests, 124/124. 8b: an entry whose only knob the arm never reads pushes a named `unimplemented` row. FOUND while writing it: main.gd:16534 builds only hit/casting/morale + grants_rule, so such an entry is a no-op on the TABLE too — the note says so.
9. Gate + census. FOUND: `--hide Fortified` DOES hold (295->283); the earlier "dead knob" reading was a truncated `head -3`. FOUND (pre-existing, reported not fixed): `stamp_unit_strikers` gives an "Unstoppable Mark" carrier `unstoppable` on every weapon on the TRAY path, mirroring battle_sim instead of main.gd's dice path.
Lines: production non-comment 297 (cap 300), tests 201.
