# Encoder-slot gap — the 12 ported names the value net cannot see (07.09.2026)

Measured at `6b7da754` (origin/main, 2026-09-07) with a live run of
`core/nml-core-py/tools/rule_universe_census.py` against the private book snapshot (89 books).
This is the follow-up to the 06.09. slot decision (option c, the `unit2` trailing band shipped
as vocab v6 in #762): v6 closed the then-current gap, and the porting wave has since re-opened
it — exactly the mechanism that memo predicted.

## 1. Census numbers

| metric | value |
|---|---|
| registry-primitive | 450/452 |
| mechanics-entry | 452/452 |
| core-ported (consumed) | 411/450 (2 N/A excluded) |
| **encoder-slot** | **411/452** |
| all-layers | 399/452 |
| slotless names overall | 41 |
| **core-PORTED but slotless (the blind set)** | **12** |

(The commissioning brief's numbers — encoder-slot 411/452, core-ported 409/450 — were taken just
before tip; #782's census correction and the last two port merges moved core-ported to 411. The
fresh run above supersedes them.)

## 2. The blind set — core=PORTED, encoder_slot=false

A rule in this list is applied by the core: the search layer plays it, but the value net never
sees it (the encoder drops unknown names from the row). 12 names, 41 book occurrences combined:

| name | band candidate | book occurrences |
|---|---|---|
| Re-Deployment | unit2 | 15 |
| Spell Accumulator | unit2 | 6 |
| Fatigue Debuff | unit2 | 3 |
| Ranged Slayer | unit2 | 3 |
| Ranged Slayer Aura | unit2 | 3 |
| Coordinate | unit2 | 2 |
| Musician | unit2 | 2 |
| Reanimation | unit2 | 2 |
| Reanimation Aura | unit2 | 2 |
| Reckless Piercing | unit2 | 1 |
| Reckless Piercing Aura | unit2 | 1 |
| Retreating Strike | unit2 | 1 |

Every one of them carries in the same place under the v6 scheme: the open-ended `unit2` trailing
band (base = 300 + spell length, currently slots 763–988 taken). The `unit` band is full
(200/200) and must not be touched — that constraint is unchanged since the 06.09. memo.

## 3. All 41 slotless names, grouped by primitive

The other 29 do not qualify for a slot under the v6 criterion (core-consumed PORTED) — their
core status is still stamped-only / partial / grant-missing / missing / n-a:

| primitive | names (core status) | count |
|---|---|---|
| Utility Buff | Dangerous Terrain Debuff, Defense Buff, Defense Debuff, Difficult Terrain Debuff, Entrenched Buff, Great Musician, Increased Shooting Range Buff, Piercing Debuff, Rapid Advance Buff, Rapid Charge Mark, Rapid Rush Buff, Speed Buff, Speed Debuff, Swift Buff (all STAMPED) | 14 |
| Aura Channel | Ranged Slayer Aura, Reanimation Aura, Reckless Piercing Aura (PORTED); Rapid Rush Aura, Swift Aura, Teleport Aura (GRANT-MISSING) | 6 |
| Mind Control | Fatigue Debuff (PORTED) | 1 |
| Musician | Musician (PORTED) | 1 |
| Coordinate | Coordinate (PORTED) | 1 |
| Re-Deployment | Re-Deployment (PORTED) | 1 |
| Reanimation | Reanimation (PORTED) | 1 |
| Reckless Piercing | Reckless Piercing (PORTED) | 1 |
| Ravage | Retreating Strike (PORTED) | 1 |
| Slayer | Ranged Slayer (PORTED) | 1 |
| Spell Accumulator | Spell Accumulator (PORTED) | 1 |
| Fast | Grounded Speed (PARTIAL) | 1 |
| Piercing Assault | Piercing Feat (PARTIAL) | 1 |
| Quick | Speed Feat (PARTIAL) | 1 |
| Rapid Advance | Rapid Advance (PARTIAL) | 1 |
| Rapid Rush | Rapid Rush (PARTIAL) | 1 |
| Infiltrate | Surprise Attack (STAMPED) | 1 |
| Reinforcement | Reinforcement (MISSING) | 1 |
| Shot Modifier | Precision Feat (MISSING) | 1 |
| Spawn | Spawn (MISSING) | 1 |
| Vengeance | Vengeance (MISSING) | 1 |
| Swift | Swift (N/A) | 1 |
| UNMAPPED-registered | Sniper REMOVE (MISSING) | 1 |

(The PORTED names in this table are the 12 from §2; the count of 41 includes them.)

## 4. Today's 14 ported names — slot status

Of the 14 names ported since the v6 bump (#762), 5 hold a `unit`-band slot and 9 are blind,
dragging 3 aura variants with them:

| name | slot | band |
|---|---|---|
| Bloodthirsty Fighter | yes | unit |
| Takedown Strike | yes | unit |
| Crossing Attack | yes | unit |
| Delayed Action | yes | unit |
| Extended Buff Range | yes | unit |
| Ranged Slayer | **no** | → unit2 |
| Fatigue Debuff | **no** | → unit2 |
| Musician | **no** | → unit2 |
| Reckless Piercing | **no** | → unit2 |
| Retreating Strike | **no** | → unit2 |
| Spell Accumulator | **no** | → unit2 |
| Reanimation | **no** | → unit2 |
| Coordinate | **no** | → unit2 |
| Re-Deployment | **no** | → unit2 |

(`Mind Control` is deliberately absent: since the #782 census correction its core status is
MISSING — a docs-only name read — so it is neither core-ported nor counted in the 14.)

## 5. The v7 band — estimate and compatibility cost

**Shape (same as v6, one small PR):** append the 12 names of §2 to the open-ended `unit2` band —
slots 989–1000 (base 763 + 226 existing). Vocab version 6→7, `legacy_lengths['6']` recorded
(`unit 200, weapon 25, spell 463, unit2 226`), the census tool's band fallback and the rows.rs
append tests mirror the existing v6 pattern. ~30 lines of production change plus tests.

**Compatibility cost: zero slot moves, zero re-records.** The append is strictly after every
existing slot (that is the property the v6 tests already pin), so every corpus recorded or
re-exported under v6 keeps every slot index it ever used. No checkpoint's embedding table
shifts. Nothing needs re-export for correctness; a re-export of an existing generation becomes
desirable only when a future training corpus should actually carry the 12 names' signal — and
then it is a replay of the banked records with a v7-aware build (no new self-play search), plus
re-pinning the recording-sha in the export launch scripts to the v7 merge commit.

**Headroom:** `unit2` is open-ended (spell-style), so the other 29 names of §3 append later,
one PR-free vocab edit at a time, as their core status reaches consumed-PORTED — no second
cliff, no new band, no further version bump required by design.

## 6. Recommendation (5 lines)

1. Bump v7 (the 12-name `unit2` append) **before** recording the next generation.
2. It is the same append-only shape as v6 — one small PR, ~30 lines, zero corpus invalidation.
3. Recording the next generation on v6 would make it permanently blind to 12 core-applied names,
   and fixing that later costs a replay re-export plus a sha re-pin — strictly more work for the
   same end state.
4. The 12 names are low-frequency today (41 occurrences across 89 books), but they are exactly
   the names the current porting wave just made real; the blind set otherwise keeps growing at
   the port rate, as 06.09. predicted and §1 confirms.
5. Ship v7 now while it is inert and cheap; keep the 29 not-yet-ported names out until the core
   consumes them.
