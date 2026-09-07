# Table-side parity audit A — do the 13 names ported to the core since 06.09. evening RESOLVE on the table?

Measured at `48b3c231` (origin/main, 2026-09-07). Method per name: (1) the core's read of the name
(rg over `core/nml-core/src` + the port PR), (2) the table handler for that primitive in `scripts/`,
(3) a verdict with `file:line` evidence. Verdict scale: RESOLVES (the table produces the same
behaviour at runtime, cited), PARTIAL (handler exists, a measured clause is missing), GAP (no
handler / the name never reaches the table), NOT-A-TABLE-THING (core-only bookkeeping).

**Tally: 12 RESOLVES · 0 PARTIAL · 1 GAP · 0 NOT-A-TABLE-THING.** The one GAP has its own fix PR.

## The one gap

### Ranged Slayer — GAP, fixed in #784

The core resolves it via the named conditional-AP arm since #763: the gate `ranged_over`
(`core/nml-core/src/combat.rs:370-379` — AP(+2) on shots strictly over 9", no charge leg), stamped
by name at `core/nml-core/src/unit.rs:3325`.

The table resolved **nothing**. The name exists only in the mechanics data
(`assets/solo/rules_mechanics_gf.json:2752`, identical in all five systems; "Ranged Slayer Aura"
at `:2768` grants the base) — and that entry carries the whole range leg in `gate`
(`"ranged_over"`) with **no** target-property `condition`. Every table seam that consumes
conditional-AP specs required `params.has("condition")`:

- dice path: `_solo_conditional_ap_parts` (`scripts/main.gd:6949-6964`) — the spec never collected,
- EV path: `AiEv.stamp_conditional_ap` (`scripts/solo/ai_ev.gd:361-372`) — same predicate,
- and `AiCombatMath.conditional_ap_bonus` (`scripts/solo/ai_combat_math.gd:417-446`) matched only
  on `condition`, so a gate-only spec fell through to 0 even if reached.

Fix: #784 — the seams accept gate-bearing specs and `conditional_ap_bonus` treats a gate-only
spec's `gate` as its condition (mirroring the core arm). RED→GREEN proven on the box (gdUnit full,
2803 cases, 0 failures at `f7561627`).

## The 12 that resolve

| # | Name | Verdict | Evidence (table) | Core read | Notes |
|---|------|---------|------------------|-----------|-------|
| 1 | Fatigue Debuff | RESOLVES | `main.gd:17022-17029` (failed morale test fatigues the target's joined chain instead of displacing); consumed at `main.gd:6098` (fatigued units hit only on unmodified 6s); round-scoped reset `main.gd:16345-16355` | `sim.rs:1006-1045` (`tray_fatigue_debuff`) | Reached via the Mind Control primitive's `effect == "fatigue"` param — the core's stamp reads the same shape |
| 2 | Bloodthirsty Fighter | RESOLVES | `main.gd:6162-6188` (extra attacks per unmodified blocking 1, pooled, never chained); counter of the batch's 1s `main.gd:6505-6508` / var `main.gd:5969` | port PR #767 family (resolver wave A) | Applies to the melee save step only, as printed |
| 3 | Musician | RESOLVES | `solo_controller.gd:5525-5528` (`musician_move_bonus_in`, system-scoped registry param with constant fallback `ai_combat_math.gd:110`); applied to every move band `solo_controller.gd:1642-1647`, sim bands `:5517-5523` | wave 5 | Bearer facet automated; the GFF/AoFS pick facet stays manual (documented) |
| 4 | Takedown Strike | RESOLVES | `main.gd:16758-16800` (once-per-game extra attack, per-member flag, AP/Deadly(3)/Takedown); wired into the melee strike phase `main.gd:6047`, wound routing to the pre-picked model `main.gd:6138` | resolver wave A | Once-per-game flag is per member name |
| 5 | Reckless Piercing | RESOLVES | Roll + round-scoped stamps `main.gd:16944-16987`; read at every AP seam `_solo_reckless_ap` `main.gd:16989-17007`; seams `main.gd:1452`, `:3125`, `:6015` | `sim.rs` twin (epoch-7) | Real tray die, once per unit per round, opt-in always for the AI |
| 6 | Crossing Attack | RESOLVES | `_solo_apply_crossing_attack` `main.gd:17089-17160` (trail-vs-base test, nearest crossed enemy, direct wounds, Regeneration applies) | `sim.rs:640-710` | Fires at the Strafing trigger seam; AI-side automation mirrors the core twin |
| 7 | Retreating Strike | RESOLVES | `_solo_retreating_strike` `main.gd:5845-5880` — via the Ravage primitive with `trigger == "post_melee_move"`, once-per-round stamp `:5858`, 3" gap gate, no save | `sim.rs:4846` | Documented scope: fires on the automated post-melee Hit-&-Run step; the human's manual post-melee drag is untracked (Versatile precedent) |
| 8 | Spell Accumulator | RESOLVES | Token battery via the casts machinery `game_unit.gd:415-427` (accumulating grant, cap 6, `is_caster()` stays false); neighbour spend within 12" `solo_controller.gd:4528` | wave B | Transfer across Caster Group is inherent (tokens live on the unit) |
| 9 | Reanimation | RESOLVES | Gate `main.gd:4695-4726` (exact-name, no prefix trap), activation door `main.gd:8550/8589`, roll + narration `main.gd:4729-4806`, owner allocation `main.gd:5022-5079` | port #777 | Aura carrier ("Reanimation Aura") expands via the army import, provenance-tracked `opr_army_manager.gd:2156` |
| 10 | Delayed Action | RESOLVES (verified, not re-derived) | Stateful `delayed_action_round` stamp `solo_controller.gd:7950/7965-7978`; pass choice + AI pass `main.gd:1484-1570/1607/1927`; radial entry `radial_menu.gd:464-469`; pass driver `radial_menu_controller.gd:648` | `unit.rs:4293` | Known stateful — confirmed, including the strictly-more surplus gate `solo_controller.gd:7959` |
| 11 | Extended Buff Range | RESOLVES | Gate + params `solo_controller.gd:871-960`; the relay waiver on the ONE range line `main.gd:16465-16548`; spells explicitly excluded `main.gd:16595`; once-per-unit-per-round stamp `main.gd:16633` | `sim.rs` twin + #773 | Negative half (nearest carrier that did NOT relay) also logs `main.gd:16548` |
| 12 | Re Deployment (Ambush Re-Deployment) | RESOLVES | Once-per-game leave-and-return `main.gd:1225-1280` (keeps its use on refusal `:1240/1258`, returns at next round start `:1274`); trigger at activation end `main.gd:1108/1149-1152/1459`; registry lists `main.gd:7916-7917` | `unit.rs:2965-3000` + #781 | Reserves machinery shared with Ambush (`solo_controller.gd:404/436`) |

## What a fix needed (and where it went)

Only #1 in the gap list: Ranged Slayer. The fix needed no new handler — the primitive layer
(`conditional_ap_bonus`) already had a `ranged_over` arm (written for Piercing Hunter, where
`ranged_over` is the `condition`); the gap was the acceptance predicate at the two stamp seams plus
the gate-only data shape. Fixed code-side (not by editing the emitted mechanics maps) so the
core's gate-field semantics stay the source of truth. PR: #784. No further gaps found; nothing
queued for a next job.
