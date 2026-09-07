# The 5 "core-grant-missing" auras — what they are and what closes them (07.09.2026)

Measured at `f728b24d` (origin/main, 2026-09-07) with a live run of
`core/nml-core-py/tools/rule_universe_census.py` against the private book snapshot (89 books).

The census's grant rule: an aura entry whose own evidence reads PORTED still does not count as
ported when its `params.grants` target does not itself resolve PORTED in the same system — the
census follows the grant, so the aura rides its base rule. The strict reading is deliberate and
test-pinned: an N/A grant target flips the aura too ("an N/A grant target is not PORTED").

The commissioning brief said 8/450; the fresh run at tip measures **5**. The difference is the
same mechanism this memo documents working in reverse — today's base-rule ports closed some
grants between brief and execution (#784 landed Ranged Slayer, whose aura now resolves PORTED
through the grant). The numbers below supersede the brief's.

## 1. The five names

| name | grants | book occ (gf+aof) | granted rule's status | verdict |
|---|---|---|---|---|
| Rapid Rush Aura | Rapid Rush | 13 (12+1) | PARTIAL — move-band pass only | PORT (done, see §2) |
| Rapid Advance Aura | Rapid Advance | 3 (1+2) | PARTIAL — move-band pass only | PORT (done, see §2) |
| Teleport Aura | Teleport | 4 (3+1) | PARTIAL — move-band pass only | DESIGN (see §3) |
| Speed Feat Aura | Speed Feat | 2 (1+1) | PARTIAL — move-band pass only | DESIGN (see §4) |
| Swift Aura | Swift | 5 (1+4) | N/A — census hygiene | DROP (see §5) |

In every case the aura entry's own evidence is already core-read (a name token in the wave-3
Aura Channel family, or the generic `Aura Channel` primitive token) — the ONLY thing missing is
the grant target. The import expansion (and its loader twin) already hands the bare base rule to
the bearer and its unit, so on the table the effect is live; the gap is that the core's own
per-entry evidence for the base rule reads only "recognized, not consumed".

## 2. PORT — Rapid Rush and Rapid Advance (bounded, epoch 7)

Both base rules are plain move-band entries with a single uniform param across every registry
occurrence: `Rapid Rush` carries `rush_mod: 6` ("This model moves +6" when using Rush actions"),
`Rapid Advance` carries `advance_mod: 4`. Both band passes (the table's name pass and the
loader's twin) already fold exactly these magnitudes into the profile `move_bands` the core
consumes as `state.bands` — so a live re-fold at the move seam would double-count a recorded
band. The bounded port is therefore the accepted evidence-only stamp shape (the `bounding`
precedent, PR #653): a named epoch-7 arm in `move_rule_mods_of` reads each entry's own param at
its own literal, which gives the census its rule-NAME read and flips the base rule to PORTED —
the aura follows through the grant, one PR per name, aura and base in the same PR.

Both ports landed on 07.09. (epoch 7, frozen-gated; census claim equals the measured delta in
each PR body).

## 3. DESIGN — Teleport Aura

`Teleport` is not a band rule: "Once per activation, before attacking, you may place this model
anywhere fully within 3" of its position when using Advance/Charge actions, or fully within 6"
when using Rush actions." A bounded stamp of its `advance_bonus_in`/`rush_bonus_in` params would
misstate a discretionary once-per-activation pick-up-and-place as a permanent band widening —
the #489 over-credit shape. A live port needs a placement mechanic: a reposition action with an
own-position anchor, a distance cap that depends on the move band chosen, and a once-per-
activation latch. That is exactly the seam the S5 arrival work (#788, `arrive_one` taking an
arrival zone) is building for Ambush — Teleport becomes a bounded port once that seam exists,
and not before. Until then the aura stays grant-missing honestly.

## 4. DESIGN — Speed Feat Aura

`Speed Feat` is a once-per-game feat ("Once per game, when this unit moves and all its models
have this rule ... +2" Advance / +4" Rush/Charge", registry `uses_per_game: 1`). Two blockers,
both structural: the once-per-game latch needs per-game state no statics-time stamp can answer,
and the loader's band passes deliberately skip `uses_per_game` entries so the permanent bands
never carry it. The core's own precedent already declines this name for exactly these reasons
(the move-band family's field documentation: "no statics-time answer, and stamping them flat
would claim coverage the core does not have"). Needs a per-activation feat mechanism (a
`State`-level used-flag family like the Storm Attack's), which is a primitive, not a diff.

## 5. DROP — Swift Aura

`Swift` ("This model may ignore the Slow rule", registry `negates: "Slow"`) is consumed before
the core ever runs: the loader's move-band pass resolves Slow and its negations into one static
`mv`/band value per unit, which is why the census carries Swift as N/A census hygiene, excluded
from the denominator. There is no core resolver to write — a core-side read of `negates` would
be dead code or a double-count of a band the loader already folded. The aura's play effect is
live table-side through the import expansion. The entry can therefore never resolve PORTED
while Swift stays N/A, and the strict grant rule flips it by design (test-pinned). Closing the
ENTRY would take a census-policy change — treat N/A grant targets as satisfied, since their
effect is provably live pre-core — which is a maintainer decision on the census's strictness,
not a port. Recommended: keep the strict rule, add this memo's reasoning to the census's N/A
note so the next reader does not re-derive it.

## 6. What closes what

| work | closes |
|---|---|
| epoch-7 named stamps for Rapid Rush / Rapid Advance (2 PRs) | 2 of 5 names |
| S5 arrival seam (in progress, #788) then a Teleport port | 1 of 5 |
| a per-game feat mechanism (design, no code yet) | 1 of 5 |
| census-policy decision on N/A grant targets | 1 of 5 |
