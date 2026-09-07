# Table-side parity audit B — the wave-4 family names and today's Opus-class ports: do they RESOLVE on the table?

Measured at `da2c4f3d` (origin/main, 2026-09-07); the evidence lines are unchanged at the audit PR's
base. Method per name: (1) the registry entry + the core's read (the port PR bodies of #756/#757/#758/
#780), (2) the table handler for that primitive in `scripts/`, (3) a verdict with `file:line` evidence.
Verdict scale: RESOLVES (the table produces the same behaviour at runtime, cited), PARTIAL (a handler
exists, a measured clause is missing), GAP (no handler / the name never reaches the table),
NOT-A-TABLE-THING (core-only bookkeeping). Follows `docs/plans/TABLE_PARITY_AUDIT_A_2026-09-07.md`
(13 names, 1 gap) and the accounting rule of `RULES_WAVE4_ACCOUNTING_2026-09-06.md` §3: a table gap
is a table-PR backlog item, never a census correction.

**Tally: 15 RESOLVES · 2 PARTIAL · 2 GAP · 0 NOT-A-TABLE-THING** (19 rows). The two GAPs and the two
PARTIALs are the same two rules plus their auras (the auras only grant the base name, so they stand
or fall with it) — each has its own fix PR, both RED→GREEN proven on the box:

- `fix(table): Bestial Boost — the widened Bane save re-roll window fires` (GAP; serves
  Mischievous Boost on the same seam),
- `fix(table): Rending in Melee — the unit-level Regeneration bypass fires` (PARTIAL).

## The two table gaps

### Bestial Boost (+ Bestial Boost Aura) — GAP

Registry (aof/beastmen): Bane `{reroll_save_low: 5, over_in: 9, bypass_regen: false, upgrades:
"Bestial"}`. The core widens the Bane window off the entry's own params behind the `upgrades` carry
gate (`core/nml-core/src/unit.rs:3639-3675` `stamp_bane_boost`, consumed by `dice.rs`
`blocks_with_bane_from` at `core/nml-core/src/dice.rs:251-262`), shot array only — ported by #756.

The table resolved **nothing for the boost**. Both Bane readers demand `reroll_save_sixes`:
`_solo_bane_facet_name` (`scripts/main.gd:6579-6586`) and the EV Bane block
(`scripts/solo/ai_ev.gd:310-322`) — and the boost entry does not carry that param, while
`reroll_save_low` appears in **zero** files under `scripts/`. A boost-only carrier collects nothing
at all; a `Bestial` + `Bestial Boost` carrier keeps the base's always-6s leg and never widens past
9". The aura (Aura Channel `grants: "Bestial Boost"`) lands the dead name on the members
(`ai_ev.gd:57-69` + `opr_army_manager.gd:2140-2166`) and inherits the gap.

Fix: the dice path reads the Bane-primitive Boost entries generically (`AiEv.bane_boost_window`,
the core's carry gate, shooting-only via the caller's past-9" flag) and widens the re-roll beside
the base 6s leg (`AiCombatMath.bane_reroll_count_from` / `blocks_with_bane_from` — the `dice.rs`
`blocks_with_bane_from` twins; `low` 6 keeps plain Bane byte-identical). Serves Mischievous Boost
(aof/goblins, same shape) on one seam. RED→GREEN on the box (gdUnit full: RED parse-fail on the
named seams; GREEN 2805 cases, 0 failures at `21edc7bb`).

### Rending in Melee (+ Rending in Melee Aura) — PARTIAL

Registry (aof common): Rending `{on6_ap: 4, bypass_regen: true, melee_only: true}`. The RENDING
half resolves: the facet stamp (`scripts/solo/ai_ev.gd:294-303`) puts `rending` on the melee
profiles only, the AP(+4) sub-batch reads it (`scripts/main.gd:6412-6420`), and the stamping is
shared by the AI volley (`main.gd:3027`), the shared attack groups (`main.gd:4416`) and the human
volley (`main.gd:9913`).

The Regeneration-bypass half did not: `_solo_ignores_regen` (`main.gd:7000-7033`) consults the
profile's weapon rules and the Lacerate-primitive aliases — a unit-level "Rending in Melee"
(direct or aura-granted, the only way the books field it) reaches neither, so its melee wounds
stayed Regeneration-able against the entry's own `bypass_regen: true`. The EV side already agreed
(the stamped facet flag skips Regeneration at `ai_ev.gd:505-509`); the dice path now matches it.
Fix: the Rending alias loop beside the Lacerate one (10 lines, facet-gated). RED→GREEN on the box
(RED: 2806 cases, exactly 1 failure = the named test at `f2109bc0`; GREEN: 0 failures at
`2240bec0`).

## The 17 that resolve

| # | Name | Verdict | Evidence (table) | Core read | Notes |
|---|------|---------|------------------|-----------|-------|
| 1 | Coordinate | RESOLVES | The beat fires at the end of EVERY AI activation: `main.gd:1112-1115` (`_solo_try_coordinate_ai` → `scripts/solo/solo_controller.gd:818-868` candidates/pick/hand-off, refusals `:792-799`); human offer/pick/decline `main.gd:1374-1428`; anti-chain stamp `game_unit.gd:301-351`; ledger export `act_recorder.gd:440-446` | #780 (`rollout.rs` `coordinate_receiver`) | #780's stated driver gap is literally true (`_solo_after_activation` is never called by the arena driver) but Coordinate does not live on that seam — the arena reaches the beat through `_solo_activate_one_ai` (`main.gd:1935` → `:934-938` → `:1112-1115`). Box-proven: PR #801 (test-only) and this job's probe (the hand-off fired, receiver stamped + logged; the probe's single failure was its own last-side alternation claim, not the hand-off). No fix needed |
| 2 | Delayed Action | RESOLVES (verified, not re-derived) | Stateful `delayed_action_round` stamp `solo_controller.gd:7950/7965-7972`; strictly-more gate `:7959-7960`; AI pass choice `:8050-8074` + `main.gd:1524-1538`; human radial entry `radial_menu.gd:464-469` + driver `radial_menu_controller.gd:648-652`; arena pass `main.gd:1918-1932` | #778 | The unused pass buys a LATER act: `_solo_pass_turn` (`main.gd:1499-1505`) books no activation, the passer stays eligible and may act the same round ("may still be activated later", `solo_controller.gd:7921-7932`) |
| 3 | Bestial Boost | GAP | no reader — see above | #756 | fix PR |
| 4 | Bestial Boost Aura | GAP | grant lands the dead name (`ai_ev.gd:57-69`, `opr_army_manager.gd:2140-2166`) | #756 | same fix PR (base + aura, one PR) |
| 5 | Wave-Step Boost | RESOLVES | Alias scan picks the longest placement `solo_controller.gd:1661-1680`; `bounding_dice_count` reads `place_die` "2d3" → 2 dice `:1389-1396`; sim-band twin `:5616-5624` | #756 (evidence-only core twin, per its own flag) | the NML-937 upgrade rule: carrier of base + boost uses the boost |
| 6 | Wave-Step Boost Aura | RESOLVES | grant + row 5 | #756 | |
| 7 | Empyrean Spirit Boost | RESOLVES | Evasive-primitive alias loop (ungated −1) `main.gd:5656-5664`; melee `:5698-5699`; shooting `:5734`/`:5755-5756` | #756 | matches the core's "at any range" reading exactly |
| 8 | Empyrean Spirit Boost Aura | RESOLVES | grant + row 7 | #756 | |
| 9 | Melee Slayer | RESOLVES | `conditional_ap_bonus` `ai_combat_math.gd:433-435` (vs_tough_ge) + `:415-416` (charge_only); dice seam `main.gd:6935-6966` (registry lookup by the carried name) applied at `:6398-6408` with the per-defender log line; EV stamp `ai_ev.gd:349-382`; fast sim `battle_sim.gd:1012` | #757 | |
| 10 | Melee Slayer Aura | RESOLVES | grant + row 9 | #757 | |
| 11 | Rending in Melee | PARTIAL | rending facet `ai_ev.gd:294-303` + AP(+4) `main.gd:6412-6420`; regen bypass was dead for unit-level carriers (`main.gd:7000-7033`) | #757 | fix PR |
| 12 | Rending in Melee Aura | PARTIAL | the aura-granted name is unit-level — exactly the shape the fix covers | #757 | same fix PR |
| 13 | Piercing Fighter | RESOLVES | Piercing Assault `{ap_bonus 1, condition in_melee}`: `ai_combat_math.gd:438-439`; dice seam `main.gd:6951-6954/6963-6966` with melee=true from the strike phase `:6136`; EV `ai_ev.gd:357-363` | #757 | |
| 14 | Piercing Fighter Aura | RESOLVES | grant + row 13 | #757 | |
| 15 | Point-Blank Piercing | RESOLVES | `ranged_within` arm `ai_combat_math.gd:450-453` (inclusive cap, unknown distance shut); EV stamp `ai_ev.gd:362`; dice-path acceptance `main.gd:6949-6951` | #757 | the wave-4 accounting §3 gap — fixed by #760 (EV reader) + #784 (gate-only acceptance) |
| 16 | Point-Blank Piercing Aura | RESOLVES | grant + row 15 | #757 | |
| 17 | Piercing Warrior | RESOLVES | Piercing Hunter `{ap_bonus 1, condition ranged_over_or_charge, over_in 9}`: `ai_combat_math.gd:442-443` (+ gate `:429-431`); dice seam as row 13 with the volley distance `:6401`; EV cond_ap with dist `ai_ev.gd:483-485` | #758 | |
| 18 | Takedown when Shooting | RESOLVES | Takedown `{shooting_only}`: `takedown_rule_for_profile` `ai_ev.gd:210-215` (facet `:109-114`) stamps ranged profiles only, dice + EV ("one stamping, one truth", `:228-235`); consumed `main.gd:3074`/`:3205-3295` | #758 | the melee Takedown seam (audit A row 4) is untouched by it |
| 19 | Reinforcement | RESOLVES | All five beats shipped table-side: trigger `solo_controller.gd:5984/6041`, sacrifice + radial `main.gd:10192-10447`, arrival strip `solo_controller.gd:5981` + `placement_ghost.gd:36/80`, timing after the Ambushers `main.gd:10183-10186` (arena twin `:2010`), riders `solo_controller.gd:6055`; hotseat/MP `:11576` | #779: core stays DESIGN (S5) | the withdraw/return IS a table feature today. The once-per-game form is Ambush Re-Deployment (`main.gd:1225-1280`, audit A row 12); Reinforcement itself is trigger-bound (Shaken or fully destroyed → remove → fresh copy next round), not once-per-game — its "may" is the owner's sacrifice choice |

## Queued for a next job (not gaps)

- **EV half of the widened Bane window.** The Bestial Boost fix is dice-path only (the runtime
  truth). The EV metric keeps the base 6s-leg valuation for a boost carrier (`block_chance`
  `ai_ev.gd:513-517` has no `reroll_from`), so the AI slightly undervalues shooting one past 9".
  The versatile chooser is consistent on both sides (both call the same un-widened seam), so plan
  and dice never disagree — only the magnitude is conservative. A `reroll_from` param through
  `block_chance` + the stamp would close it.
- **Plain unit-level `Rending` / `Bane` carriers.** The Rending fix deliberately skips the base
  name (`"Rending"` exact) and the Bane fix requires a `reroll_save_low` param — a unit carrying a
  base rule only as a UNIT rule (never on a weapon) is a pre-existing shape this audit did not
  measure. No name in this batch is affected; listed so the next audit looks at it deliberately.
