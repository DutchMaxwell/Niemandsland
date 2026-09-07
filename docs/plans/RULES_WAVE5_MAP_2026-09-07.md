# The wave-5 map — what is left after 07.09.'s ports (07.09.2026, for the next grill)

Measured at `623b8a3d` (origin/main) with one run of `core/nml-core-py/tools/rule_universe_census.py`
against the private army-book snapshot (89 books). Census at main:

- registry-primitive 450/452 · mechanics-entry 452/452
- core-ported **413/450** (STAMPED 15, PARTIAL 8, MISSING 9, GRANT-MISSING 5, N/A 2 excluded)
- encoder-slot 423/452 · **all-layers 412/452**

**39 (name, system) rows are not core-ported, rolling up to 30 names.** Every remaining name is below,
grouped by what unlocks it. "Table side" names what is known about the table handler; the table-side
parity audit B (the core names this map adds) does not exist yet — marked **UNKNOWN** where only the
book text is verified and no handler citation is in hand.

## Group (a) — unlocked by the S5 withdraw-and-recreate seam (#788 landed; #792 in flight; part 3 = the round-start arrival driver)

`REINFORCEMENT_DESIGN_2026-09-07.md` §3 prices the seam honestly: two new state transitions
(`withdraw_as_destroyed`, a round-start arrival driver) plus the already-landed signature change.
Once funded, these flip:

| name | now | book occ (gf+aof) | table side | closes |
|---|---|---|---|---|
| Reinforcement | MISSING both | 4 (2+2) | RESOLVES (the table builds runtime units, `main.gd` shared mid-game creation path) | **#792 in flight, claimed core-ported +1** |
| Spawn | MISSING both | 9 (4+5) | known (same runtime-unit path) | bounded port riding the same seam; ~30-50 lines on top of part 3, no new primitive |
| Teleport | PARTIAL both | 12 (9+3) | UNKNOWN (audit B) | bounded port: reposition action, own-position anchor, band-dependent cap, once-per-activation latch; ~60-90 lines. A stamp would misstate the discretionary pick-up-and-place as a band widening (`GRANT_MISSING_2026-09-07.md` §3) |
| Teleport Aura | GRANT-MISSING both | 4 (3+1) | follows its base | flips with Teleport (grant rule) |
| Ethereal | PARTIAL (aof) | 2 (0+2) | UNKNOWN (audit B) | the SAME once-per-activation reposition (6") minus the band anchor variant — rides the Teleport seam; ~20-30 extra lines |
| Ambush Re-Deployment (withdraw beat) | base PORTED (not a census row) | — | known (once-per-game flag, return-round gate) | fidelity-only: the withdraw beat the core stamps but does not decide; the seam plus a policy closes it. NOT a census claim |

## Group (b) — DESIGN verdicts (the wave-4 index's 21 UNCLEAR verdicts + 07.09.'s notes)

| name(s) | now | book occ | why DESIGN | what unlocks it |
|---|---|---|---|---|
| Spell Conduit | MISSING both | 11 (6+5) | cast AS IF standing at the conduit — a spell-origin substitution | a spell-targeting/origin seam (none exists) |
| Takedown Shot | MISSING (gf) | 2 (2+0) | once-per-game extra shot at Quality 2+ | the per-game feat mechanism AND a shooting seam |
| Quick Readjustment | MISSING both | 4 (2+2) | the core has no `moved_hit_penalty` field (#718) | that field first |
| Speed Feat (+ its Aura) | PARTIAL both / GRANT-MISSING both | 2 (1+1) + 2 (1+1) | once-per-game feat; statics-time stamps cannot answer the latch, and the loader's band passes deliberately skip `uses_per_game` entries (`GRANT_MISSING_2026-09-07.md` §4) | a State-level used-flag feat primitive (the Storm Attack pattern); then the aura flips by grant |
| Precision Feat | MISSING (aof) | 2 (0+2) | same feat latch, to-hit half | the same feat mechanism |
| Piercing Feat | PARTIAL (aof) | 1 (0+1) | same feat latch, AP(+1) half | the same feat mechanism |

One feat primitive closes Speed Feat, Precision Feat, Piercing Feat (and Takedown Shot's latch half)
— that is the highest-leverage DESIGN decision on this page.

## Group (c) — DROP / N-A / census hygiene

| name | now | book occ | state |
|---|---|---|---|
| Swift | N/A both | 8 (2+6) | correct: the loader folds Slow-and-negations into one static band before the core runs; a core read would be dead code or a double-count |
| Swift Aura | GRANT-MISSING both | 5 (1+4) | flips ONLY by a census-policy change (treat N/A grant targets as satisfied). Recommended: keep the strict rule; needs the maintainer's word |
| Unique | N/A both | 26 (14+12) | list-building only; already excluded from the denominator |
| Sniper REMOVE | MISSING both | 2 (1+1) | pending the same snapshot-curation treatment as `Unique` (NA_NAMES), not a port |

## Group (d) — bounded ports nobody has claimed

Size estimated from the closest merged port of the same primitive (cited). No new primitive in any
row unless said.

| name | now | book occ | shape | est. lines | closest port | table side |
|---|---|---|---|---|---|---|
| Rapid Advance | PARTIAL both | 5 (3+2) | evidence-only stamp: the loader already folds `advance_mod` into the recorded bands (double-count guard) | ~25 | Rapid Rush grant-close #793 (open) — same shape | loader twin (known) |
| Rapid Rush Aura / Rapid Advance Aura | GRANT-MISSING both | 13 (12+1) / 3 (1+2) | follow the base stamps by grant, same PRs | +0 | #793's claim: encoder-slot/aure flip with the base | follows base |
| Surprise Attack | STAMPED both | 5 (2+3) | "counts as Infiltrate" name read (the table already resolves it, #761) + first-activation 6" dice-burst tray arm | ~70-90 | Crossing Attack #770 (tray arm on a move/activation beat) | RESOLVES via #761 (the pick/dice half is the audit-B question) |
| Sturdy | MISSING both | 2 (1+1) | +1 to DEFENSE rolls when shot/charged from over 9" — the defense-side twin of the conditional-AP channel | ~50-70 | Ranged Slayer #763/#764 (gate-bearing conditional spec) | UNKNOWN (audit B) |
| Slow | PARTIAL both | 10 (3+7) | evidence-only stamp like Rapid Advance: the loader already folds the -2"/-4" band penalty | ~25 | #793 | loader twin (known) |
| Transport | MISSING both | 2 (1+1) | census name read only — the capacity is ALREADY live since #787 (the loader parses the unit's own `Transport(X)` string); the name token is the honest evidence arm | ~15 | Musician #766 (param-stamp arm) | RESOLVES (#787) |
| Grounded Speed | PARTIAL (aof) | 1 (0+1) | +2"/+4" bands ONLY while most models are within 1" of terrain at activation — a per-activation conditional band, not a static one. A stamp would lie; a live read needs the core's terrain picture at the move seam | ~60-80, flag as DESIGN-risk | closest is none; the Fatigue Debuff tray (#764) is the nearest per-activation read | UNKNOWN (audit B) |
| Great Musician | STAMPED (aof) | 2 (0+2) | `move_mod +1` runtime read — seam 2 of `UTILITY_BUFF_SEAMS_2026-09-05.md`, the "hard one" with the architectural tension | beyond a port; measurement first (#766's own deferral) | — | UNKNOWN (audit B) |
| Utility Buff STAMPED family (Dangerous Terrain Debuff, Defense Buff, Defense Debuff, Difficult Terrain Debuff, Entrenched Buff, Increased Shooting Range Buff, Piercing Debuff, Rapid Advance Buff, Rapid Charge Mark, Rapid Rush Buff, Speed Buff, Speed Debuff, Swift Buff) | STAMPED | 22 rows total | seams 3 + 4 + 1 of `UTILITY_BUFF_SEAMS_2026-09-05.md` (terrain/defense fold, attacker-side AP, casting roll): strong in-repo precedents, no new architecture | ~8-9 of the 16 seam names for real; the rest stay honestly STAMPED | Shielded fold, `growth_def_mod`, pierce grants | UNKNOWN (audit B) |

## Recommendation (5 lines)

1. Land the S5 seam (#792 + part 3) — one piece of work closes Reinforcement, Spawn, Teleport (+ Aura),
   Ethereal, and the Ambush Re-Deployment withdraw beat: five census/fidelity wins for one seam.
2. Fund the per-game feat primitive next: one State-level latch closes Speed Feat (+ Aura),
   Precision Feat, Piercing Feat and Takedown Shot's latch — and it is the only unlock for the four.
3. Slice the bounded stamps as one small PR each: Rapid Advance + Slow (+ their auras), Transport's
   name read, then Surprise Attack and Sturdy as the two real tray/conditional ports.
4. Utility Buff seams 3/4/1 are a pre-priced backlog (8-9 names); seam 2 (Great Musician, Speed
   Buff/Debuff) stays documented-NO unless the measurement proves new divergence.
5. Maintainer's word needed on three policy points: the census's N/A-grant strictness (Swift Aura),
   Sniper REMOVE's NA_NAMES curation, and whether Grounded Speed's conditional band is a port or a
   DESIGN (a stamp would misstate it).
