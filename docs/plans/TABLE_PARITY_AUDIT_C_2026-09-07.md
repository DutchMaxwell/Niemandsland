# Table-side parity audit C — 2026-09-07 (evening)

Six names ported to the core today (#783, #787, #790, #800, #797, #793): do they
RESOLVE on the table? Evidence, not opinion — every verdict cites `file:line` of a
live table-side handler (the table reads by NAME via `RulesRegistry.unit_rules_of_primitive`
/ the band name fallbacks, per the #782 census rule).

Method: (1) the core port's PR body for the primitive + clause list; (2) the table
handler for that primitive in `scripts/`; (3) verdict per row.

## Verdict tally

RESOLVES 6 · PARTIAL 0 · GAP 0 · NOT-A-TABLE-THING 0 — **no fix PRs required from this audit.**

| # | Name | Port PR | Verdict | Table evidence | What a fix would need |
|---|------|---------|---------|----------------|----------------------|
| 1 | Mind Control | #783 | RESOLVES | `scripts/main.gd:16999-17042` `_solo_apply_mind_control`: per bearer, `unit_rules_of_primitive(member, "Mind Control")` (by NAME, main.gd:17009), target within `range_in` 18" + LOS (main.gd:17013), ONE tray die vs Quality (main.gd:17017), on FAIL the displacement arm — away from nearest uncontrolled objective (main.gd:17036-17038) else away from bearer, shared `forced_straight_move` with `move_in` 6" (main.gd:17039); the fatigue-effect branch mirrors the core's untouched arm (main.gd:17026-17032). No aura/grant side in any book (PR #783: "there is no Mind Control Aura"). | nothing — the core port explicitly mirrors this handler. Note: the automation is the AI's arm (`_solo_is_ai_unit` gate, main.gd:17000); the human plays the rule through the manual tray/forced-move flow, the repo-wide solo-automation pattern, not a gap. |
| 2 | Transport | #787 | RESOLVES | `scripts/transport_state.gd:64-77` `capacity_of_rules` parses `Transport(X)` off the unit's OWN rule string; `scripts/opr_army_manager.gd:2893-2897` `transport_capacity` reads it (registry params ignored — the table ignores `rating` too, as #787 records); embark/unload radial intents at `scripts/radial_menu_controller.gd:2380-2385` (`_append_transport_items`); embarked activation doors (`scripts/main.gd:1758-1765`, #338); destroyed-transport spill with dangerous test (`scripts/main.gd:7139-7153`, `opr_army_manager._spill_destroyed_transport`); reserve/arrival cargo riding (`scripts/main.gd:10585-10596`). | nothing. |
| 3 | Vengeance | #790 | RESOLVES | Placement: `scripts/main.gd:5884-5902` `_solo_vengeance_on_destroyed` — marker count = START size of every chain carrier (main.gd:5893, the exact fold the core uses); fired at the three shared kill seams (main.gd:3310 volley, main.gd:8230-8233 melee both-sides guard, main.gd:10045). To-hit fold: `scripts/main.gd:5806-5817` `_solo_vengeance_bonus`, consumed at main.gd:5721 (shooting) and main.gd:5791 (melee). No aura/grant side (PR #790: `aura_live: false`). | nothing — the core's win-by-wipe-only melee seam was declared identical to the table's own if/elif at main.gd:8230-8233. |
| 4 | Slow | #800 | RESOLVES | `scripts/movement_range_controller.gd:116-121` name fallback: advance −`FAST_ADVANCE_BONUS` / rush −`FAST_RUSH_BONUS` (the −2"/−4"); registry pass allowlist includes the primitive (movement_range_controller.gd:153) applying the entry's own `advance_mod`/`rush_mod` (movement_range_controller.gd:159-164; entry `assets/solo/rules_mechanics_gf.json:849-856`, `aof.json:823-831`, both −2/−4). Swift cancels Slow BY NAME (movement_range_controller.gd:95-109). Solo AI resolves through the same static band source (movement_range_controller.gd:80-83). Evidence-only stamp in the core — table keeps the live penalty, no double-count by construction. | nothing. |
| 5 | Rapid Advance (+ Aura) | #797 | RESOLVES | `scripts/movement_range_controller.gd:132-135` name fallback: advance +`RAPID_ADVANCE_BONUS` (4), advance band only; registry pass applies the entry's own `advance_mod` 4 (movement_range_controller.gd:158-159; entry `assets/solo/rules_mechanics_gf.json:4046-4052`). Aura grant lands the base name: "Rapid Advance Aura" → `grants` param, and `scripts/solo/ai_ev.gd:57-68` `aura_granted_rules` derives the base NAME from the " Aura" suffix, stamped into `special_rules` by `scripts/opr_army_manager.gd:2140-2166` `expand_auras_of` — so the name fallback (the #782 read-by-NAME rule) sees "Rapid Advance" on granted units. | nothing. |
| 6 | Rapid Rush (+ Aura) | #793 | RESOLVES | `scripts/movement_range_controller.gd:122-125` name fallback: rush +`RAPID_RUSH_BONUS` (6), rush band only; registry pass applies the entry's own `rush_mod` (movement_range_controller.gd:161-163). Aura grant lands the base name identically to row 5 (`assets/solo/rules_mechanics_gf.json:1420-1427` `"Rapid Rush Aura"` → `grants: "Rapid Rush"`; `ai_ev.gd:57-68` + `opr_army_manager.gd:2140-2166`). | nothing. |

## Per-port clause notes

- **#783 Mind Control**: the table handler predates the port and is the port's
  mirror source; morale-test die, 18"/LOS range gate, straight-line ≤6"
  displacement, away-from-objective direction — all present and cited above.
- **#787 Transport**: the core port reads `capacity_of_rules` as its parse
  (PR body: "the table's own parse"); capacity, embark/unload, spill-on-wreck,
  reserve-cargo all live on the table.
- **#790 Vengeance**: marker bank at destruction, +1 to hit per marker for the
  fallen's friends — both arms live, both kill-seam guards identical to the
  core's declared simplification.
- **#800 Slow**: the -2/-4 reach the table live through the band fold; the
  core's stamp is evidence-only, so parity is table-authoritative here.
- **#797/#793 Rapid Advance / Rapid Rush**: band bonuses live in the table's
  name fallback + registry pass; the aura leg lands the base name on granted
  units via the structured expand path, so nothing is primitive-literal-only.

## Excluded per brief

Sturdy and Surprise Attack: not audited here (ports still running / #761
already fixed the table).
