//! NML-1073 M5 D1-B3 — the table's DICE TRAY as a pure stream.
//!
//! The shipped game rolls every combat die through `_solo_tray_roll`
//! (main.gd:7126-7180). In batch mode — the only reproducible one
//! (arena_match.gd:253) — that is exactly this, main.gd:7152-7159:
//!
//! ```text
//! for _di in maxi(1, count):
//!     _inst.append(_tray_rng.randi_range(1, 6))
//! ```
//!
//! TWO things a naive port gets wrong, both pinned by the tests below:
//!
//!   1. `maxi(1, count)` — a ZERO-die roll STILL BURNS ONE DRAW. Skip it and
//!      the whole stream shifts from the first empty volley onward, and every
//!      activation after it is a different game.
//!   2. The tray has its OWN generator. `seed_tray_rng` (main.gd:7120-7121) is
//!      a plain `_tray_rng.seed = seed_value`, i.e. `GodotRng::new(seed)`, and
//!      the arena hands it `_dice_seed` AFTER deployment (arena_match.gd:478),
//!      where `_dice_seed` defaults to the game seed (arena_match.gd:984-985).
//!      Deployment and the roll-off draw from OTHER generators — see the
//!      stream split in `selfplay.py`.
//!
//! Nothing here is new randomness: `GodotRng` is the fixture-proven Godot 4.6
//! `RandomPCG` twin (GATE R, 6003/6003), and a tray face is one
//! `randi_range(1, 6)` on it.

use crate::combat::{
    covered_defense, deadly_multiplier, fortified_ap, guarded_defense, modified_hit_target,
    reliable_quality, save_target, shielded_defense, shooting_hit_modifier, shrouded_reach,
    versatile_best_mode, LONG_RANGE_IN, RENDING_AP_BONUS, SHROUD_FLOOR_IN,
    SHROUD_RANGE_PENALTY_IN,
};
use crate::rng::GodotRng;
use crate::unit::{Ctx, ShootProfile};

/// One dice tray: the generator `seed_tray_rng` seeds, and nothing else.
#[derive(Debug, Clone, Copy)]
pub struct Tray {
    rng: GodotRng,
}

impl Tray {
    /// `main.seed_tray_rng(dice_seed)` — `RandomNumberGenerator.seed = seed`.
    ///
    /// The seed is `i64`, not `u64`, because that is what GDScript hands the
    /// engine and what `GodotRng::new` mirrors; a negative seed must land on
    /// the same stream on both sides.
    pub fn seeded(seed: i64) -> Tray {
        Tray { rng: GodotRng::new(seed) }
    }

    /// A tray that continues a generator already in flight — how a replay
    /// reaches a recorded position in the stream.
    pub fn from_rng(rng: GodotRng) -> Tray {
        Tray { rng }
    }

    /// Re-seeds in place, as a second `seed_tray_rng` call would.
    pub fn seed(&mut self, seed: i64) {
        self.rng.seed(seed);
    }

    /// One roll: `maxi(1, count)` faces of `randi_range(1, 6)`, in draw order.
    /// `count == 0` returns ONE face — the die the table burns and reads as
    /// nothing. Callers that asked for zero dice must ignore the value, not
    /// the draw.
    pub fn roll(&mut self, count: usize) -> Vec<u8> {
        (0..count.max(1)).map(|_| self.rng.randi_range(1, 6) as u8).collect()
    }

    /// `rng.state` — the cheap replay checkpoint GATE R already compares.
    pub fn state_i64(&self) -> i64 {
        self.rng.state_i64()
    }
}

/// Successes in a roll — `DiceRules.count_successes(faces, target, 0)`
/// (dice_rules.gd:55-71), the OPR quality/defense test:
/// a 6 ALWAYS succeeds, a 1 ALWAYS fails, anything else needs `>= target`.
///
/// The modifier is fixed at 0 on purpose: `_solo_tray_roll` sets
/// `_success_modifier = 0` (main.gd:7143) for every scripted roll, so an AI
/// tray roll is never modifier-counted — the modified threshold is baked into
/// `target` by the caller before the dice leave the cup.
pub fn faces_to_hits(faces: &[u8], target: u8) -> usize {
    if target == 0 {
        return 0; // `TARGET_NONE` — dice_rules.gd:57, nothing is being tested.
    }
    faces.iter().filter(|&&f| f >= 6 || (f > 1 && f >= target)).count()
}

// ------------------------------------------------- D1-B4: SHOOTING on the tray ---

/// One tray roll, in the shape `AiDiceRecorder` writes to `dice.jsonl`
/// (main.gd:7170-7178) — the gate compares these tuples line by line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Roll {
    /// `_solo_tray_roll`'s `roll_kind`: "attack" for hit/Regeneration dice,
    /// "defense" for a save batch and its Bane re-roll.
    pub kind: &'static str,
    pub count: i64,
    pub target: i64,
    pub faces: Vec<u8>,
    /// `_solo_tray_roll`'s `owner` (main.gd:7173), WITHOUT the `"AI (%s)"`
    /// wrapper `_solo_owner_label` (:7039-7040) puts on it: the firing MEMBER's
    /// name for an attack roll (main.gd:3199-3200 — `shooter_name` is
    /// `member.get_name()`, so an attached hero signs its own dice) and the
    /// DEFENDER's for a save batch (:6448) and the Regeneration roll (:6543).
    pub owner: String,
}

/// What one shooting activation did on the tray.
#[derive(Debug, Default, Clone)]
pub struct ShootResult {
    /// Unsaved wounds after Deadly, Shred and Regeneration — handed to the
    /// trainer's OWN casualty machinery, which decides who dies.
    pub wounds: i64,
    /// Every roll drawn, in draw order.
    pub rolls: Vec<Roll>,
    /// Table branches this port does NOT reproduce that THIS activation hit.
    /// Never silent: a flagged activation is a reported divergence, not a skip.
    pub unported: Vec<&'static str>,
}

impl ShootResult {
    fn mark(&mut self, what: &'static str) {
        if !self.unported.contains(&what) {
            self.unported.push(what);
        }
    }
}

#[inline]
fn sixes(faces: &[u8]) -> i64 {
    faces.iter().filter(|&&f| f == 6).count() as i64
}

/// `AiCombatMath.blocks_with_bane` :354-363 — each unmodified Defense 6 is
/// replaced by the next re-roll face, in order; a re-rolled 6 still blocks.
fn blocks_with_bane(faces: &[u8], reroll: &[u8], target: i64) -> i64 {
    let mut ri = 0usize;
    let mut blocks = 0i64;
    for &f in faces {
        let eff = if f == 6 {
            let r = reroll.get(ri).copied().unwrap_or(6);
            ri += 1;
            r
        } else {
            f
        };
        if eff >= 6 || (eff > 1 && eff as i64 >= target) {
            blocks += 1;
        }
    }
    blocks
}

/// `AiCombatMath.shred_bonus_wounds` :475-485 — unmodified Defense 1s on the
/// FINAL faces (a 6 that Bane re-rolled into a 1 counts, the 6 itself never).
fn shred_ones(faces: &[u8], reroll: &[u8]) -> i64 {
    let mut ri = 0usize;
    let mut ones = 0i64;
    for &f in faces {
        if f == 6 && ri < reroll.len() {
            if reroll[ri] == 1 {
                ones += 1;
            }
            ri += 1;
        } else if f == 1 {
            ones += 1;
        }
    }
    ones
}

/// `main._solo_save_batch` :6385-6483 — ONE batch for the whole defender (not
/// per model), Fortified first, then the dice, then Bane's re-roll of the
/// unmodified 6s, then Shred and the pooled Deadly multiplier.
#[allow(clippy::too_many_arguments)]
fn save_batch(
    p: &ShootProfile,
    def: &Ctx,
    def_owner: &str,
    count: i64,
    defense: i64,
    ap: i64,
    tray: &mut Tray,
    out: &mut ShootResult,
) -> i64 {
    if count <= 0 {
        return 0;
    }
    let target = save_target(defense, fortified_ap(ap, def.fortified));
    let faces = tray.roll(count as usize);
    out.rolls.push(Roll {
        kind: "defense",
        count,
        target,
        faces: faces.clone(),
        owner: def_owner.into(),
    });
    let mut reroll: Vec<u8> = Vec::new();
    if p.bane {
        let n = sixes(&faces);
        if n > 0 {
            reroll = tray.roll(n as usize);
            out.rolls.push(Roll {
                kind: "defense",
                count: n,
                target,
                faces: reroll.clone(),
                owner: def_owner.into(),
            });
        }
    }
    let unsaved = (count - blocks_with_bane(&faces, &reroll, target)).max(0);
    let shred = if p.shred { shred_ones(&faces, &reroll) } else { 0 };
    let mult = if p.deadly > 0 { deadly_multiplier(p.deadly, def.tough.max(1)) } else { 1 };
    unsaved * mult + shred
}

/// ONE shooting activation resolved on the tray, in the TABLE's draw order
/// (`main._solo_resolve_ai_volley` :3047, per shot, main.gd line in brackets):
///
///   hit dice [:3200] -> Hazardous reads those faces, draws nothing [:16555]
///   -> surge/extra-attack dice [:4454] -> the defender's saves as ONE batch
///   [:6448] -> Bane re-roll [:6463] -> (next weapon) -> Regeneration, pooled
///   over the whole volley [:6543/:6624] -> morale [:8313].
///
/// The stream is left standing exactly BEFORE the morale roll: morale, Fearless
/// and No Retreat are B5's, and drawing them here would shift every later
/// activation.
///
/// PORTED: the to-hit target (`profile_ev`'s shooting branch verbatim —
/// Reliable, the range/Stealth/Artillery/Evasive modifiers, Unstoppable's
/// clamp, Versatile Attack, Precise), the unmodified-6 bonus hits of Relentless
/// and Surge, Blast, the Rending/Destructive/on-6 AP sub-batch, Fortified,
/// Shielded/Guarded/Cover on the save target, Bane's re-roll, Shred, the pooled
/// Deadly multiplier and the pooled Regeneration roll.
///
/// NOT PORTED. Nothing here is a silent skip: everything the trainer's own
/// profile model can SEE is flagged per activation in `unported`; everything
/// below the line has no field to detect it by and is listed instead.
///
/// FLAGGED (a counter per activation):
///   * `surge_gates` — Surge fires unconditionally; the table gates it on
///     `surge_within_in` and `surge_low` (main.gd:4427-4435).
///   * `hazardous`   — Hazardous wounds the FIRER on its natural 1s (:16555).
///   * `deadly`      — the table lands Deadly per model with its OWN
///     Regeneration roll on the RAW unsaved count (:6634), not the pooled one
///     this port uses, so the regen roll's die count moves.
///   * `takedown`    — resolved "as a unit of [1]" against a picked model, with
///     that model's own Defense (:3155).
///   * `strafing`    — the table splits a Strafing weapon per model (:2918).
///   * `split_fire`  — D1-B4b, raised whenever the volley has MORE THAN ONE
///     member. The table picks a target per SHOT under that weapon's overlay
///     (`_solo_pick_overlay_target` :2996-3005) and resolves one volley per
///     target, so an attached hero whose overlay prefers another unit fires
///     somewhere else entirely; this port aims every member at the
///     activation's one recorded `shoot` key, and the hero's wounds would
///     otherwise land on the wrong unit SILENTLY. Measured on the reference
///     corpus, that is not rare: of the 70 acts whose recording carries a
///     hero-owned attack roll, several save their dice under a third unit's
///     name. Flagged, therefore, not skipped.
///
/// STREAM-DESYNCING DRAWS — these ROLL DICE on the table and nothing here does,
/// so from the first one onward a `dice="table"` corpus is on a different
/// stream than the recording. They are the top of the B5+ list for that reason:
///   * the Unpredictable die, ONE per volley before any weapon fires (:3114).
///   * the extra-ATTACK dice of the Bloodborn / Primal / Predator / Clan
///     Warrior family, rolled for each unmodified 6 to hit (:4454).
///
/// SHOT SELECTION AND SCALING (all of them change the die COUNT, which is the
/// largest divergence class the replay gate measures):
///   * per-model SIGHTING — the table scales attacks by `_solo_sighted_count`
///     (:4131), a per-model geometric LOS plus base-edge range gate
///     (:4283-4304); this port scales by `alive` through `effective_attacks`.
///   * PORTED in D1-B4b: attached HEROES fire as their own shots inside the
///     host's volley (:2954-2990), through `resolve_volley_with_tray`. With
///     `hero_attach="off"` the state carries no attachment at all, so that
///     path is never entered.
///   * PORTED in D1-B4b, for EVERY `dice="table"` volley and not only the ones
///     with a hero in them: the Takedown -> Deadly -> rest resolve-first sort
///     of the shot list (:3033-3040/:3052-3062). It is the table's order, it
///     changes which models die, and it moved the replay gate on its own
///     (87 -> 88 of 670 FULL-equal acts with no hero shots added) — a
///     deliberate B4 fidelity fix, declared rather than smuggled.
///   * per-copy bearer scaling of a weapon's carriers
///     (solo_controller.gd:457-467).
///   * SPLIT FIRE (:2996-3005) — see `split_fire` in the flag list above.
///
/// TO-HIT AND SAVE MODIFIERS with no field in the profile/context model:
///   * Indirect's moved -1 and its Quick Readjustment opt-out (:3163-3169).
///   * Spot markers, the Piercing tag, Reckless AP, vs-target Marks,
///     `AiEv.stamp_conditional_ap` (Shatter / Tear / Disintegrate).
///   * unit-level Bane / Lacerate — the STRIKER's own special rules, not just
///     the weapon's (:6490-6500) — so a unit-level Bane neither re-rolls the
///     defender's 6s nor bypasses Regeneration here.
///   * the Fortified DATA ALIASES (Guardian, Primeborn and their over-9" gate)
///     and Fortified Growth's marker-driven AP reduction (:6411-6441): only the
///     plain `Fortified` flag reaches this port.
///   * Stealth / Evasive data aliases, `Shot Modifier`, Vengeance, Instinctive.
///
/// AND morale, Fearless and No Retreat (:8313-8342) — B5's, deliberately left
/// undrawn so the stream stands exactly where the table's morale roll begins.
///
/// `keep`/`attacks` are `shoot_ev`'s, so the range gate and the survivor
/// scaling are the ones the EV path already agreed on. NOTE: this path never
/// touches `State::wound_frac` — deliberately. The remainder carry is an
/// artefact of resolving a volley in EXPECTATION; real dice produce whole
/// wounds, so there is no sub-wound remainder to carry and no coin flip to
/// spend. A `dice="table"` game therefore leaves `wound_frac` wherever the
/// last expected-value activation (melee, spells — B5's) left it.
pub fn resolve_shooting_with_tray(
    profiles: &[ShootProfile],
    keep: &[usize],
    attacks: &[i64],
    att: &Ctx,
    def: &Ctx,
    dist_in: f64,
    tray: &mut Tray,
) -> ShootResult {
    let one = [Shooter { profiles, keep, attacks, att, owner: "" }];
    resolve_volley_with_tray(&one, def, "", dist_in, tray)
}

/// NML-1073 M5 D1-B4b — ONE member of a shooting activation's volley.
///
/// The table builds the shot list over `members = [unit] + unit
/// .get_attached_heroes()` (`main._run_ai_shooting` :2954-2958), one shot per
/// (member, ranged weapon), each stamped with THAT member's `quality` and its
/// own `alive`/`max` scaling (:2985-2990) — so a joined hero fires its own
/// guns, at its own Quality, under the host's activation, and signs the dice
/// with its own name (:3199-3200).
pub struct Shooter<'a> {
    /// The member's own ranged set (`UnitStatic::shoot`).
    pub profiles: &'a [ShootProfile],
    /// Indices into `profiles` that passed the range gate, in `profiles_of`
    /// order — which IS the member's weapon order, the table's build order.
    pub keep: &'a [usize],
    /// Survivor-scaled attack counts, index-parallel to `keep`.
    pub attacks: &'a [i64],
    /// The member's own shooting context (its Quality above all).
    pub att: &'a Ctx,
    /// The member's name, for `Roll::owner`.
    pub owner: &'a str,
}

/// The volley of `shooters` — the host first, then each attached hero — against
/// one defender, on one tray. Everything the single-shooter form documents
/// holds; the members are simply walked in the table's build order, and
/// Regeneration stays pooled over the WHOLE volley (`_solo_land_wounds` :6623),
/// not per member.
///
/// STILL NOT PORTED here, and now visible because the members are:
///
///   * SPLIT FIRE. The table picks a target per SHOT under that weapon's
///     overlay (`_solo_pick_overlay_target` :2996-3005) and resolves one volley
///     per target, so a hero whose overlay prefers another unit fires elsewhere
///     entirely; this port aims every member at the activation's one recorded
///     `shoot` key. A multi-member volley therefore raises `split_fire`.
///   * The hero's RANGE is the host's. `dist_in` is the one distance the caller
///     measured between the host and the target (sim.rs) — the hero's own model
///     positions are never read, so a hero standing 3" behind its unit is gated
///     and modified as if it stood in the front rank. The table measures per
///     member (`_solo_nearest_model_gap_in` :4370-4386).
///   * The Takedown SHOT bonus groups (`_solo_takedown_bonus_groups`, appended
///     to the shot list at :3057-3062 before the sort) are absent: this port has
///     no once-per-game ledger to spend.
///
/// SORT STABILITY, the one caveat on the order below: Godot's `sort_custom`
/// is an introsort whose quicksort half only engages above 16 elements
/// (`SortArray::__introsort_loop`, INTROSORT_THRESHOLD), below which the final
/// insertion sort leaves equal-priority shots where they were. `sort_by_key` is
/// stable ALWAYS, so a volley of more than 16 shots may order its equal-priority
/// shots differently from the table's. Nothing in the reference corpus is that
/// wide, and the gate would show it as a `kind`/`count` part.
pub fn resolve_volley_with_tray(
    shooters: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    dist_in: f64,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if shooters.len() > 1 {
        out.mark("split_fire");
    }
    let (mut regenable, mut regen_proof) = (0i64, 0i64);
    let reach_gate = dist_in.ceil();
    // FLATTENED on purpose: one pass over the (member, profile) pairs, so the
    // body below stays the single-shooter one.
    //
    // ORDER — `_solo_resolve_ai_volley` :3052-3062, GF v3.5.1 p.14: "Takedown
    // attacks must be resolved before other weapons" and "Hits from Deadly must
    // be resolved first", the ladder `_solo_shot_priority` :3033-3040 spells
    // out. It runs over the WHOLE shot list, host and heroes together, which is
    // why an attached hero's Deadly gun fires before the host's plain rifles.
    // `sort_custom` on a volley-sized array is Godot's final insertion sort and
    // therefore stable, so equal-priority shots keep the build order (the host's
    // weapons, then each hero's) — `sort_by_key` is stable and is the twin.
    let mut shots: Vec<(&Shooter<'_>, usize, usize)> = shooters
        .iter()
        .flat_map(|sh| sh.keep.iter().enumerate().map(move |(k, &pi)| (sh, k, pi)))
        .collect();
    shots.sort_by_key(|&(sh, _, pi)| {
        let p = &sh.profiles[pi];
        if p.takedown {
            0
        } else if p.deadly > 0 {
            1
        } else {
            2
        }
    });
    for (sh, k, pi) in shots {
        let att = sh.att;
        let p = &sh.profiles[pi];
        let reach = if def.ranged_shrouding {
            shrouded_reach(p.range as f64, SHROUD_RANGE_PENALTY_IN, SHROUD_FLOOR_IN)
        } else {
            p.range as f64
        };
        if p.range <= 0 || reach < reach_gate {
            continue;
        }
        let n = sh.attacks[k];
        if n <= 0 {
            continue; // main.gd:3163 — a silent weapon leaves before any die
        }
        // --- to-hit, `profile_ev` ai_ev.gd:335-370's shooting branch ---
        let mut target = reliable_quality(att.quality, p.reliable);
        let mut m =
            shooting_hit_modifier(dist_in, att.artillery, def.stealth, def.artillery, def.evasive);
        if p.unstoppable && m < 0 {
            m = 0;
        }
        target = modified_hit_target(target, m);
        let mut versatile_ap = 0;
        if p.versatile_attack && dist_in > LONG_RANGE_IN {
            let (hit_mod, ap_mod) = versatile_best_mode(
                target,
                shielded_defense(def.defense, def.shielded),
                p.ap,
                p.bane,
            );
            versatile_ap = ap_mod;
            target = modified_hit_target(target, hit_mod);
        }
        // Precise is NOT in the rolled target. `_solo_tray_roll` is handed the
        // plain `to_hit` (main.gd:3200) and `_solo_hits` applies the +1 when it
        // COUNTS (:4405-4406) — so the die count is scored one better while the
        // RECORDED target stays raw, which is what `dice.jsonl` carries.
        let faces = tray.roll(n as usize);
        out.rolls.push(Roll {
            kind: "attack",
            count: n,
            target,
            faces: faces.clone(),
            owner: sh.owner.into(),
        });
        let count_target = if p.precise { modified_hit_target(target, 1) } else { target };
        if p.hazardous {
            out.mark("hazardous");
        }
        if p.strafing {
            out.mark("strafing");
        }
        if p.takedown {
            out.mark("takedown");
        }
        // --- `_solo_hits` :4404-4487 ---
        let mut hits = faces_to_hits(&faces, count_target as u8) as i64;
        if p.relentless && dist_in > LONG_RANGE_IN {
            hits += sixes(&faces);
        }
        if p.surge {
            // The two GATES this port cannot see — `surge_within_in` (Point-Blank
            // Surge: only within 12") and `surge_low` (Devout Boost: successful
            // unmodified 5s count too, over 9") — have no field in
            // `ShootProfile`, so Surge fires UNCONDITIONALLY here and every
            // Surge activation says so (main.gd:4427-4435).
            hits += sixes(&faces);
            out.mark("surge_gates");
        }
        // `AiCombatMath.sergeant_bonus_hits` :493-494 — the bearer's unmodified
        // 6s, capped at its own attack share. The EV path values this
        // (combat.rs:339-342); the dice path must not be the poorer twin, even
        // though `stamp_sergeant` leaves the field at 0 in this port today.
        if p.sergeant_attacks > 0 {
            hits += sixes(&faces).min(p.sergeant_attacks);
        }
        if hits > 0 && p.blast > 1 {
            hits *= p.blast.clamp(1, def.models.max(1));
        }
        if hits <= 0 {
            continue; // :3210 — no hits, no save batch
        }
        // --- `_solo_resolve_saves` :6337-6376: the on-6 AP sub-batch first ---
        let on6 = if p.on6_ap > 0 {
            p.on6_ap
        } else if p.rending || p.destructive {
            RENDING_AP_BONUS
        } else {
            0
        };
        let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
        // Defense, in main.gd's own order: Shielded, then Guarded (over 9"),
        // then Cover — which Blast / Indirect / Ignores Cover skip (:3221).
        let mut base = shielded_defense(def.defense, def.shielded);
        base = guarded_defense(base, def.guarded && dist_in > LONG_RANGE_IN);
        let save_def = if p.blast > 1 || p.indirect || p.ignores_cover {
            base
        } else {
            covered_defense(base, def.in_cover)
        };
        let ap = p.ap + versatile_ap;
        let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, tray, &mut out);
        w += save_batch(p, def, def_owner, hits - ap4, save_def, ap, tray, &mut out);
        if p.deadly > 0 {
            out.mark("deadly");
        }
        // `_solo_ignores_regen` :6927-6933 — Bane / Rending (and Unstoppable,
        // ai_ev.gd:433) cut through Regeneration; everything else is poolable.
        if p.bane || p.rending || p.unstoppable {
            regen_proof += w;
        } else {
            regenable += w;
        }
    }
    // --- `_solo_land_wounds` :6623 -> `_solo_apply_regeneration` :6543 ---
    if regenable > 0 && def.regeneration && def.regen_target > 0 {
        let faces = tray.roll(regenable as usize);
        let ignored = faces.iter().filter(|&&f| f as i64 >= def.regen_target).count() as i64;
        out.rolls.push(Roll {
            kind: "attack",
            count: regenable,
            target: def.regen_target,
            faces,
            owner: def_owner.into(),
        });
        regenable = (regenable - ignored).max(0);
    }
    out.wounds = regen_proof + regenable;
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// THE TRAP. Two trays on one seed: burning a zero-die roll must cost
    /// exactly one draw, so the first tray's next three faces are the second's
    /// faces 2..4.
    #[test]
    fn a_zero_die_roll_burns_exactly_one_draw() {
        let mut burned = Tray::seeded(27);
        let mut straight = Tray::seeded(27);
        let zero = burned.roll(0);
        assert_eq!(zero.len(), 1, "maxi(1, count): a zero-die roll still rolls one");
        assert_eq!(burned.roll(3), straight.roll(4)[1..].to_vec());
        assert_eq!(burned.state_i64(), straight.state_i64(), "and only one");
    }

    /// RED PROOF for the rule above: the same two trays with `count` taken
    /// literally. The zero-die roll then costs nothing and every later face is
    /// off by one draw.
    #[test]
    fn red_proof_dropping_the_max_1_rule_shifts_the_stream() {
        let mut naive = GodotRng::new(27);
        let zero_count = 0usize; // `count` taken literally, without `maxi(1, ..)`
        let naive_zero: Vec<u8> =
            (0..zero_count).map(|_| naive.randi_range(1, 6) as u8).collect();
        assert!(naive_zero.is_empty(), "the naive form draws nothing for count 0");
        let after: Vec<u8> = (0..3).map(|_| naive.randi_range(1, 6) as u8).collect();
        let first_four = Tray::seeded(27).roll(4);
        assert_eq!(after, first_four[..3].to_vec(), "the naive form reads faces 1..3");
        assert_ne!(after, first_four[1..].to_vec(), "the table reads faces 2..4 — a shift");
    }

    #[test]
    fn every_face_is_a_d6_face_and_the_stream_is_deterministic() {
        let mut a = Tray::seeded(1_099_511_627_783);
        let mut b = Tray::seeded(1_099_511_627_783);
        let fa = a.roll(600);
        assert_eq!(fa.len(), 600);
        assert!(fa.iter().all(|&f| (1..=6).contains(&f)), "faces outside 1..=6");
        assert_eq!(fa, b.roll(600), "same seed, same faces");
        // Uniform enough that a broken mapping (e.g. `% 6` without the +1)
        // cannot hide: all six faces must actually appear.
        for face in 1u8..=6 {
            assert!(fa.contains(&face), "face {face} never came up in 600 rolls");
        }
    }

    /// A tray is `randi_range(1, 6)` on the twin and nothing else — one draw
    /// per die, in order, sharing the generator's state.
    #[test]
    fn the_tray_is_randi_range_1_6_on_the_twin() {
        let mut tray = Tray::seeded(12345);
        let mut rng = GodotRng::new(12345);
        let faces = tray.roll(64);
        let want: Vec<u8> = (0..64).map(|_| rng.randi_range(1, 6) as u8).collect();
        assert_eq!(faces, want);
        assert_eq!(tray.state_i64(), rng.state_i64());
    }

    // ------------------------------------------ D1-B4: the shooting order ---

    /// A plain rifle: `quality`+ to hit at `defense`+ to save, nothing else.
    fn rifle(attacks: i64) -> ShootProfile {
        ShootProfile { name: "Rifle".into(), attacks, count: 1, range: 24, ..Default::default() }
    }

    fn shooter(quality: i64) -> Ctx {
        Ctx { quality, ..Default::default() }
    }

    fn defender(defense: i64, models: i64) -> Ctx {
        Ctx { defense, models, tough: 1, ..Default::default() }
    }

    /// THE DRAW ORDER: hit dice first, then ONE save batch for the whole
    /// defender (main.gd:6448 — not one per model), and the save batch's die
    /// count is the HIT count, so the tray's faces line up with the recorded
    /// ones only if both are right.
    #[test]
    fn a_volley_draws_hit_dice_then_one_save_batch_of_exactly_the_hits() {
        let p = [rifle(6)];
        let mut tray = Tray::seeded(27);
        let want_hits = Tray::seeded(27).roll(6);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[6], &shooter(4), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls.len(), 2, "one hit roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[0].kind, "attack");
        assert_eq!(out.rolls[0].count, 6);
        assert_eq!(out.rolls[0].target, 4, "Quality 4+ at 12\", no modifiers");
        assert_eq!(out.rolls[0].faces, want_hits, "the hit dice are the tray's first six");
        let hits = faces_to_hits(&want_hits, 4) as i64;
        assert_eq!(out.rolls[1].kind, "defense");
        assert_eq!(out.rolls[1].count, hits, "one save die per hit");
        assert_eq!(out.rolls[1].target, 4, "Defense 4+, AP(0)");
        assert!(out.unported.is_empty(), "a plain rifle hits no unported branch");
    }

    /// A weapon that scores nothing draws NO save batch — the table `continue`s
    /// at main.gd:3210. Drawing an empty one would burn a die (`maxi(1, count)`)
    /// and shift every later activation.
    #[test]
    fn a_volley_that_misses_everything_draws_no_save_batch() {
        // Quality 6+ against a single die: seed 12345's first face is not a 6.
        let first = Tray::seeded(12345).roll(1)[0];
        assert!(first < 6, "fixture seed no longer misses — pick another");
        let mut tray = Tray::seeded(12345);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(6), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls.len(), 1, "a miss must not roll saves: {:?}", out.rolls);
        assert_eq!(out.wounds, 0);
        assert_eq!(out.rolls[0].count, 1, "and exactly one die left the cup");
        let mut one = Tray::seeded(12345);
        one.roll(1);
        assert_eq!(tray.state_i64(), one.state_i64(), "the tray advanced by exactly one draw");
    }

    /// RED-GREEN on Blast(X): the save batch is `hits * min(X, models)` dice
    /// (AiCombatMath.blast_hits :370-375). Drop the multiply and the batch is
    /// `hits` — a different die COUNT, so every face after it shifts. Both
    /// counts are computed here so the red half cannot silently become green.
    #[test]
    fn blast_multiplies_the_save_batch_and_dropping_it_shifts_the_stream() {
        let p = [ShootProfile { blast: 3, ..rifle(2) }];
        let mut tray = Tray::seeded(27);
        let faces = Tray::seeded(27).roll(2);
        let hits = faces_to_hits(&faces, 2) as i64;
        assert!(hits > 0, "fixture seed no longer hits — pick another");
        let out = resolve_shooting_with_tray(
            &p, &[0], &[2], &shooter(2), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].count, hits * 3, "Blast(3) vs 5 models multiplies by 3");
        assert_ne!(out.rolls[1].count, hits, "the un-multiplied count is a DIFFERENT stream");
        // The cap: never more than there are models to spill onto.
        let mut tray2 = Tray::seeded(27);
        let capped = resolve_shooting_with_tray(
            &p, &[0], &[2], &shooter(2), &defender(4, 2), 12.0, &mut tray2,
        );
        assert_eq!(capped.rolls[1].count, hits * 2, "capped by the 2 models in the target");
    }

    /// Bane re-rolls the defender's unmodified 6s as a SEPARATE tray roll after
    /// the batch is fully read (main.gd:6463) — a third roll in the stream, and
    /// a Bane weapon's wounds bypass Regeneration entirely (:6927-6933).
    #[test]
    fn bane_draws_its_re_roll_after_the_save_batch_and_bypasses_regeneration() {
        let p = [ShootProfile { bane: true, ..rifle(8) }];
        let mut tray = Tray::seeded(27);
        let def = Ctx { regeneration: true, regen_target: 5, ..defender(4, 8) };
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(2), &def, 12.0, &mut tray);
        let saves = &out.rolls[1];
        let sixes = saves.faces.iter().filter(|&&f| f == 6).count() as i64;
        assert!(sixes > 0, "fixture seed rolls no Defense 6 — pick another");
        assert_eq!(out.rolls.len(), 3, "hit dice, saves, Bane re-roll: {:?}", out.rolls);
        assert_eq!(out.rolls[2].kind, "defense");
        assert_eq!(out.rolls[2].count, sixes, "one re-roll die per unmodified 6");
        assert_eq!(out.rolls[2].target, saves.target, "at the same save target");
        assert!(
            !out.rolls.iter().any(|r| r.target == 5 && r.kind == "attack" && r.count == out.wounds),
            "Bane bypasses Regeneration — no ignore roll may be drawn"
        );
    }

    /// Precise (+1 to hit) is applied when the hits are COUNTED, not when the
    /// dice leave the cup: the table rolls at the plain `to_hit` (main.gd:3200)
    /// and `_solo_hits` scores them one better (:4405-4406). Recording the
    /// improved target instead would part company with `dice.jsonl` on every
    /// Precise weapon while the faces themselves still matched.
    #[test]
    fn precise_rolls_at_the_plain_to_hit_and_scores_one_better() {
        let faces = Tray::seeded(27).roll(6);
        let plain = faces_to_hits(&faces, 4) as i64;
        let better = faces_to_hits(&faces, 3) as i64;
        assert!(better > plain, "fixture seed cannot tell the two targets apart");
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ShootProfile { precise: true, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "the RECORDED target is the raw to-hit");
        assert_eq!(out.rolls[0].faces, faces);
        assert_eq!(out.rolls[1].count, better, "but the hits are scored at 3+");
        assert_ne!(out.rolls[1].count, plain, "rolling at the improved target is a DIFFERENT stream");
    }

    /// Sergeant's bonus hits (`AiCombatMath.sergeant_bonus_hits` :493-494): the
    /// bearer's unmodified 6s, capped at its own attack share. The EV path
    /// already values these (combat.rs:339-342), so a dice path that dropped
    /// them would be the poorer twin of the thing it replaces.
    #[test]
    fn sergeant_adds_its_capped_share_of_unmodified_sixes() {
        let faces = Tray::seeded(5).roll(6);
        let sixes = faces.iter().filter(|&&f| f == 6).count() as i64;
        assert_eq!(sixes, 3, "seed 5 rolls [6, 2, 6, 1, 5, 6] — three unmodified 6s");
        let base = {
            let mut t = Tray::seeded(5);
            resolve_shooting_with_tray(&[rifle(6)], &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut t)
                .rolls[1].count
        };
        let mut tray = Tray::seeded(5);
        let out = resolve_shooting_with_tray(
            &[ShootProfile { sergeant_attacks: 1, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].count, base + 1, "the bearer's share is 1 attack");
        // And the cap is real: an uncapped share adds EVERY unmodified 6.
        let mut wide = Tray::seeded(5);
        let all = resolve_shooting_with_tray(
            &[ShootProfile { sergeant_attacks: 99, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut wide,
        );
        assert_eq!(all.rolls[1].count, base + sixes, "uncapped: one bonus hit per 6");
    }

    /// A Deadly weapon still resolves, and it says so: the table lands Deadly
    /// per model with its own Regeneration roll, which this port does not
    /// reproduce, so the activation is FLAGGED rather than quietly counted.
    #[test]
    fn an_unported_branch_is_reported_not_skipped() {
        let p = [ShootProfile { deadly: 3, hazardous: true, ..rifle(4) }];
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[4], &shooter(3), &defender(4, 3), 12.0, &mut tray,
        );
        assert!(out.unported.contains(&"deadly"), "{:?}", out.unported);
        assert!(out.unported.contains(&"hazardous"), "{:?}", out.unported);
        assert!(!out.rolls.is_empty(), "a flagged activation still resolves");
    }

    /// D1-B4b — the ATTACHED HERO fires its own shots inside the host's volley
    /// (main.gd:2954-2990): the host's rolls first, then the hero's, at the
    /// HERO's own Quality and with its own name on the dice. RED half: drop the
    /// hero's group and the stream is one roll and 24 faces short — a different
    /// game from the first hero onward.
    #[test]
    fn an_attached_hero_fires_its_own_shots_after_the_host() {
        let host_p = [rifle(6)];
        let hero_p = [ShootProfile { name: "Hero Gun".into(), ..rifle(2) }];
        let (host_q, hero_q) = (shooter(5), shooter(2));
        let def = defender(4, 5);
        let host = Shooter {
            profiles: &host_p, keep: &[0], attacks: &[6], att: &host_q, owner: "Shooter Grunts",
        };
        let hero = Shooter {
            profiles: &hero_p, keep: &[0], attacks: &[2], att: &hero_q, owner: "Vradhez",
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_volley_with_tray(&[host, hero], &def, "Pathfinders", 12.0, &mut tray);
        let attacks: Vec<_> = out.rolls.iter().filter(|r| r.kind == "attack").collect();
        assert_eq!(attacks.len(), 2, "host then hero: {:?}", out.rolls);
        assert_eq!((attacks[0].count, attacks[0].target, attacks[0].owner.as_str()),
                   (6, 5, "Shooter Grunts"), "the host fires first, at its own Quality");
        assert_eq!((attacks[1].count, attacks[1].target, attacks[1].owner.as_str()),
                   (2, 2, "Vradhez"), "then the hero, at ITS Quality — not the host's");
        assert!(out.rolls.iter().all(|r| r.kind != "defense" || r.owner == "Pathfinders"),
                "every save batch is signed by the DEFENDER");
        // RED: the host alone draws strictly fewer dice, so every later
        // activation reads different faces.
        let mut solo = Tray::seeded(27);
        let host_only = resolve_shooting_with_tray(
            &host_p, &[0], &[6], &host_q, &def, 12.0, &mut solo,
        );
        assert!(host_only.rolls.len() < out.rolls.len(), "the hero's rolls are missing");
        assert_ne!(solo.state_i64(), tray.state_i64(), "and the tray stands elsewhere");
    }

    /// `DiceRules.is_success` in full: the natural 6 beats an impossible
    /// target, the natural 1 fails an automatic one, and `TARGET_NONE` counts
    /// nothing.
    #[test]
    fn faces_to_hits_follows_the_natural_6_and_natural_1_rules() {
        let faces = [1u8, 2, 3, 4, 5, 6];
        assert_eq!(faces_to_hits(&faces, 4), 3, "4, 5, 6");
        assert_eq!(faces_to_hits(&faces, 2), 5, "everything but the 1");
        assert_eq!(faces_to_hits(&faces, 6), 1, "only the 6");
        assert_eq!(faces_to_hits(&faces, 7), 1, "the natural 6 still succeeds");
        assert_eq!(faces_to_hits(&faces, 1), 5, "the natural 1 still fails");
        assert_eq!(faces_to_hits(&faces, 0), 0, "TARGET_NONE tests nothing");
        assert_eq!(faces_to_hits(&[], 4), 0);
    }
}
