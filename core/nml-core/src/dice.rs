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
    covered_defense, deadly_multiplier, fortified_ap, guarded_defense, impact_total_dice,
    melee_hit_modifier, modified_hit_target, reliable_quality, save_target, shielded_defense,
    morale_target, shooting_hit_modifier, shrouded_reach, thrust_to_hit, versatile_best_mode,
    BEST_HIT_TARGET, FEARLESS_RECOVER_TARGET, HEAVY_IMPACT_AP, IMPACT_HIT_TARGET, LONG_RANGE_IN,
    NO_RETREAT_SELF_WOUND_MAX, RAVAGE_WOUND_TARGET, RENDING_AP_BONUS, SHROUD_FLOOR_IN,
    SHROUD_RANGE_PENALTY_IN, THRUST_AP_BONUS, UNMODIFIED_SIX,
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
    /// D1-B5: wounds caused BEFORE Regeneration, which is the tally the table's
    /// melee-winner comparison runs on — `caused += w` sits inside the weapon
    /// loop (main.gd:6113/:6148) and `caused += rv_wounds` inside Ravage
    /// (:6001), both ahead of the pooled `_solo_land_wounds` (:6161). Land
    /// `wounds`; compare `caused`. Using the landed number instead lets a
    /// Regeneration roll decide who tests morale, which the table never does.
    pub caused: i64,
    /// Every roll drawn, in draw order.
    pub rolls: Vec<Roll>,
    /// Table branches this port does NOT reproduce that THIS activation hit.
    /// Never silent: a flagged activation is a reported divergence, not a skip.
    pub unported: Vec<&'static str>,
}

impl ShootResult {
    /// Flag a table branch this activation hit and this port does not
    /// reproduce. Public because D1-B5's melee sub-phases are orchestrated from
    /// `sim.rs`, where the state-level branches are the visible ones.
    pub fn mark(&mut self, what: &'static str) {
        if !self.unported.contains(&what) {
            self.unported.push(what);
        }
    }

    /// Fold a SUB-PHASE's draw into this activation's report, in draw order, and
    /// hand back its wounds so the caller lands them itself. One activation is
    /// one report: Impact, the strikes and the strike-back all queue here, which
    /// is what lets the replay gate compare a whole melee roll by roll. `caused`
    /// accumulates with it, so the melee-winner tally is the pre-Regeneration
    /// one the table compares.
    pub fn absorb(&mut self, other: ShootResult) -> i64 {
        self.rolls.extend(other.rolls);
        self.caused += other.caused;
        for u in other.unported {
            self.mark(u);
        }
        other.wounds
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
///
/// PORTED in NML-1150: SPLIT FIRE (:2996-3005) — one call of THIS function per
/// target group, in the table's group order, on the same tray (sim.rs builds
/// the groups from the act's `split` aim). A multi-member volley at ONE target
/// is not split fire and no longer raises any flag.
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
///   * Stealth / Evasive data aliases, Vengeance, Instinctive. `Shot Modifier`
///     itself: PORTED for its three flat/over-9" carriers (block B4 — Good
///     Shot, Bad Shot, Targeting Visor; `unit.rs::stamp_shot_modifier`). The
///     melee-/charge-/terrain-scoped family members (Grounded Precision,
///     Precision Fighter/Charge Aura) are NOT — they never reach the shooting
///     branch this function resolves anyway (main.gd:5627-5636's
///     `all_attacks` / `melee_only` / `when: charge` gate keeps them out).
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
        // Good Shot / Bad Shot / Targeting Visor (main.gd:5681-5701) — the
        // table's DICE path folds these in; `p.hit_bonus`/`p.hit_bonus_over9`
        // are this shot's own profile stamp (unit.rs::stamp_shot_modifier).
        // `def.stealth_alias_penalty`/`def.stealth_alias_over_in` are the
        // SAME dice path's Stealth data-alias leg (Changebound et al.,
        // main.gd:5588-5610/5698-5701) — `unit.rs::stealth_alias_of`.
        let mut m = shooting_hit_modifier(
            dist_in, att.artillery, def.stealth, def.artillery, def.evasive,
            p.hit_bonus, p.hit_bonus_over9,
            def.stealth_alias_penalty, def.stealth_alias_over_in,
        );
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
    out.caused = regen_proof + regenable;
    out.wounds = regen_proof + regen_batch(regenable, def, def_owner, tray, &mut out.rolls);
    out
}

/// `main._solo_apply_regeneration` :6543 — one tray die per incoming wound, each
/// `regen_target`+ ignoring it; the wounds that survive come back. Split out of
/// the volley tail because D1-B5's melee needs it three more times: Ravage lands
/// at once (:6002), each Impact pool lands at once (:6337), and the strike phase
/// pools its own (:6161).
fn regen_batch(
    w: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> i64 {
    if w <= 0 || !def.regeneration || def.regen_target <= 0 {
        return w.max(0);
    }
    let faces = tray.roll(w as usize);
    let ignored = faces.iter().filter(|&&f| f as i64 >= def.regen_target).count() as i64;
    rolls.push(Roll {
        kind: "attack",
        count: w,
        target: def.regen_target,
        faces,
        owner: def_owner.into(),
    });
    (w - ignored).max(0)
}

// ------------------------------- D1-B5a: MELEE and IMPACT on the same tray ---

/// The melee to-hit target `_solo_melee_strike_phase` hands the tray
/// (main.gd:6046-6062), in the table's own order and with its own clamping.
///
/// FATIGUE IS NOT A MODIFIER. main.gd:6062 reads
/// `to_hit = 6 if fatigued else modified_hit_target(..)`, so a fatigued striker
/// hits on an unmodified 6 and NOTHING — not Unpredictable's +1, not Thrust —
/// reaches it (p.9). Applying a bonus on top of the 6 turns it into a 5+ and the
/// recorded target stops matching.
///
/// ONE CLAMP, ON THE SUM. main.gd:6053-6055 builds `m_mod = p_mod.mod + uf_hit`,
/// clamps THAT to 0 for an Unstoppable weapon, and calls `modified_hit_target`
/// exactly once. Clamping the defender's modifier alone and then folding
/// `uf_hit` in through a second `modified_hit_target` clamps twice: Quality 6,
/// Evasive, Unpredictable's +1 is a 6+ on the table (-1 +1 = 0) and a 5+ that
/// way.
///
/// Reliable sets the base Quality FIRST — "Reliable only changes the Quality
/// value, so the roll can still be modified" (p.14) — then Thrust's charge
/// bonus. This is deliberately NOT `profile_ev`'s melee branch, which drops
/// Reliable (ai_ev.gd:336-341) and would roll a Reliable weapon at the unit's
/// plain Quality: a recorded target the port could never match.
fn melee_hit_target(p: &ShootProfile, att: &Ctx, def: &Ctx, charging: bool, uf_hit: i64) -> i64 {
    if att.fatigued {
        return UNMODIFIED_SIX;
    }
    let base = thrust_to_hit(reliable_quality(att.quality, p.reliable), charging && p.thrust);
    let mut m = melee_hit_modifier(def.evasive, def.melee_evasion) + uf_hit;
    if p.unstoppable && m < 0 {
        m = 0;
    }
    modified_hit_target(base, m)
}

/// ONE melee strike phase on the tray — `main._solo_melee_strike_phase` :5941,
/// in its own draw order (main.gd line in brackets):
///
///   Unpredictable's one die for the whole phase [:5957] -> Ravage per MEMBER,
///   each landing at once with its own Regeneration roll [:5983/:6002] -> per
///   member, per profile: hit dice [:6060] -> the on-6 AP sub-batch and then the
///   rest of the saves [:6337], Bane's re-roll inside -> the phase's pooled
///   Regeneration roll [:6161].
///
/// `strikers` are the table's attack GROUPS in build order
/// (`_solo_attack_groups` :4284-4290): the unit, then each attached hero, each
/// with its own melee set, Quality and fatigue. `Shooter::keep` is every melee
/// profile — melee has no range gate (`melee_profiles_of` sim.rs).
///
/// PORTED: Reliable/Thrust/Evasive/Melee Evasion/Unstoppable on the to-hit, both
/// variants of the Unpredictable die and both of its halves, Ravage, Furious's
/// unmodified-6 bonus hits on the charge, Surge, Sergeant, Blast, the
/// Rending/Destructive/on-6 AP sub-batch, Thrust's charge AP, Bane's re-roll,
/// Shred, the pooled Deadly multiplier and every Regeneration roll in its place.
///
/// FLAGGED per activation, never skipped in silence: `deadly` (the table lands
/// Deadly per model with its OWN Regeneration roll on the raw unsaved count,
/// :6120, so the regen die count moves), `takedown`, `hazardous`,
/// `surge_gates`, and `counter_strikes_first` (a defender Counter weapon runs a
/// whole EXTRA strike phase before Impact, :8058).
///
/// NOT PORTED, in the order they cost the most, and none of them has a field
/// this port can flag them by:
///   1. UNWIELDY's chain half. The swap itself IS ported (`sim::tray_charge`
///      reads `Ctx::unwieldy`), but the table asks the whole joined chain
///      (:16677) and an attached hero reaches this port as rule NAMES only, so
///      an Unwieldy ALIAS carried only by a hero is missed.
///   2. The STRIKE REACH. The table scales each member's attacks by
///      `striking_models_for` (:4331), the models within 2"; this port scales by
///      `alive`, as the EV path does. That is the melee twin of shooting's
///      per-model sighting and the largest die-COUNT class in the replay gate.
///   3. Bloodthirsty Fighter's extra attacks off the defender's blocked 1s
///      (:6123), Retaliate (:6175), Deathstrike / Self-Destruct (:6198).
///   4. Reckless Piercing's round AP stamp (:5974), Versatile Attack's melee
///      half (:6076), vs-target Marks, Takedown's unit-of-[1] pick and its bonus
///      groups, Limited's once-per-game ledger.
///   5. Guarded / Versatile Defense's charged-from-over-9" +1 Defense (:5948):
///      the port never measured a pre-charge gap.
pub fn resolve_melee_with_tray(
    strikers: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    charging: bool,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    // (1) Unpredictable :5957 — ONE die for the whole phase, before anything
    //     else: 1-3 is AP(+1) on every melee weapon, 4-6 is +1 to hit
    //     (`unpredictable_fighter_effect` ai_combat_math.gd:387-388).
    let mut uf_ap = 0;
    let mut uf_hit = 0;
    if strikers.first().is_some_and(|sh| sh.att.unpredictable) {
        let faces = tray.roll(1);
        if faces[0] <= 3 {
            uf_ap = 1;
        } else {
            uf_hit = 1;
        }
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: BEST_HIT_TARGET,
            faces,
            owner: strikers[0].owner.into(),
        });
    }
    // (2) Ravage :5983 — X dice per alive bearer, per MEMBER, each 6+ a DIRECT
    //     wound: no hit roll, no save. They land at once (:6002), so their
    //     Regeneration rolls here and not into the phase pool, and the tally
    //     takes the PRE-regeneration count (:6001).
    for sh in strikers {
        let n = sh.att.ravage * sh.att.models.max(0);
        if n <= 0 {
            continue;
        }
        let faces = tray.roll(n as usize);
        let w = faces.iter().filter(|&&f| f as i64 >= RAVAGE_WOUND_TARGET).count() as i64;
        out.rolls.push(Roll {
            kind: "attack",
            count: n,
            target: RAVAGE_WOUND_TARGET,
            faces,
            owner: sh.owner.into(),
        });
        out.caused += w;
        out.wounds += regen_batch(w, def, def_owner, tray, &mut out.rolls);
    }
    // (3) the strikes :6060-6148. `regenable`/`regen_proof` are the PHASE's, not
    //     the member's — the table declares them before the group loop and lands
    //     them once after it (:6161).
    let (mut regenable, mut regen_proof) = (0i64, 0i64);
    for sh in strikers {
        for (k, &pi) in sh.keep.iter().enumerate() {
            let p = &sh.profiles[pi];
            let n = sh.attacks[k];
            if n <= 0 {
                continue;
            }
            if p.counter {
                out.mark("counter_strikes_first");
            }
            if p.takedown {
                out.mark("takedown");
            }
            if p.hazardous {
                out.mark("hazardous");
            }
            let target = melee_hit_target(p, sh.att, def, charging, uf_hit);
            let faces = tray.roll(n as usize);
            out.rolls.push(Roll {
                kind: "attack",
                count: n,
                target,
                faces: faces.clone(),
                owner: sh.owner.into(),
            });
            // Precise scores one better than it ROLLS — `_solo_hits` :4405-4406
            // applies the +1 when counting, so the recorded target stays raw.
            let count_target = if p.precise { modified_hit_target(target, 1) } else { target };
            let mut hits = faces_to_hits(&faces, count_target as u8) as i64;
            if p.surge {
                hits += sixes(&faces);
                out.mark("surge_gates");
            }
            // Furious :4477 — the unit-level rule the table stamps onto every
            // melee profile (main.gd:4343): unmodified 6s, charge only.
            if charging && sh.att.furious {
                hits += sixes(&faces);
            }
            if p.sergeant_attacks > 0 {
                hits += sixes(&faces).min(p.sergeant_attacks);
            }
            if hits > 0 && p.blast > 1 {
                hits *= p.blast.clamp(1, def.models.max(1));
            }
            if hits <= 0 {
                continue;
            }
            let on6 = if p.on6_ap > 0 {
                p.on6_ap
            } else if p.rending || p.destructive {
                RENDING_AP_BONUS
            } else {
                0
            };
            let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
            // Melee reads neither Cover nor Guarded (`profile_ev` keeps both on
            // the shooting side); Shielded is the whole Defense ladder here.
            let save_def = shielded_defense(def.defense, def.shielded);
            let ap = p.ap + uf_ap + if charging && p.thrust { THRUST_AP_BONUS } else { 0 };
            let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, tray, &mut out);
            w += save_batch(p, def, def_owner, hits - ap4, save_def, ap, tray, &mut out);
            if p.deadly > 0 {
                out.mark("deadly");
            }
            if p.bane || p.rending || p.unstoppable {
                regen_proof += w;
            } else {
                regenable += w;
            }
        }
    }
    out.caused += regen_proof + regenable;
    out.wounds += regen_proof + regen_batch(regenable, def, def_owner, tray, &mut out.rolls);
    out
}

/// The charge's two Impact pools in the table's order — plain Impact (2+, no AP)
/// and then Heavy Impact (saves at AP(1)), with the defender's Counter models
/// stripping the HEAVY dice first, defender-optimal (`_solo_charge_impact`
/// :6292-6303). A fatigued charger rolls nothing at all (p.13).
///
/// `def.counter_models` is hard 0 in this port (see `unit.rs`), so the Counter
/// reduction is inert here — `resolve_melee_with_tray` raises
/// `counter_strikes_first` for the activations where it would have bitten.
pub fn impact_pools(att: &Ctx, def: &Ctx) -> [(i64, i64); 2] {
    if att.fatigued {
        return [(0, 0), (0, 0)];
    }
    let models = att.models.max(0);
    let heavy_raw = att.heavy_impact * models;
    let heavy_cut = def.counter_models.min(heavy_raw);
    [
        (impact_total_dice(att.impact, models, def.counter_models - heavy_cut), 0),
        (heavy_raw - heavy_cut, HEAVY_IMPACT_AP),
    ]
}

/// ONE Impact pool on the tray: the hit roll at 2+, then ONE save batch (no
/// to-hit faces reach it, so no Rending sub-batch and no Bane), then its own
/// Regeneration roll — the pool LANDS at once (`_solo_land_wounds` :6337).
///
/// One pool per call on purpose. main.gd:6304 re-checks
/// `_solo_combined_alive(defender) <= 0` before EVERY pool, so an Impact pool
/// that wiped the defender means the Heavy pool never rolls; only the caller,
/// which lands the wounds, can answer that.
///
/// FLAGGED: `guarded_over9` — the table raises the Impact save by 1 when the
/// charge came from over 9" (:6309), a pre-charge gap this port never measured.
pub fn resolve_impact_pool_with_tray(
    dice: i64,
    ap: i64,
    att_owner: &str,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if dice <= 0 {
        return out;
    }
    if def.guarded {
        out.mark("guarded_over9");
    }
    let faces = tray.roll(dice as usize);
    let hits = faces_to_hits(&faces, IMPACT_HIT_TARGET as u8) as i64;
    out.rolls.push(Roll {
        kind: "attack",
        count: dice,
        target: IMPACT_HIT_TARGET,
        faces,
        owner: att_owner.into(),
    });
    if hits <= 0 {
        return out;
    }
    // "Impact is not a weapon": no Deadly, no Bane, no Shred — a bare profile
    // carrying only the pool's AP, exactly as :6325 builds it.
    let bare = ShootProfile { ap, ..Default::default() };
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded), ap, tray, &mut out);
    out.caused = w;
    out.wounds = regen_batch(w, def, def_owner, tray, &mut out.rolls);
    out
}

/// BLOCK B3 — Breath Attack's hit->defense->wound leg on the tray:
/// `_solo_resolve_saves`/`_solo_save_batch` (main.gd:6310-6459) called with a
/// FIXED hit count — Blast(3) already applied by the caller (main.gd:5307-
/// 5308), so unlike Impact's `resolve_impact_pool_with_tray` this pool never
/// draws an "attack" roll of its own — then `_solo_land_wounds` (main.gd:
/// 6596-6600, Regeneration on the RAW unsaved count). A bare profile carrying
/// only the pool's AP, the Impact precedent's shape (no Bane, no Shred, no
/// Deadly — Breath Attack's own `bprofile` carries none of them either).
pub fn resolve_breath_attack_with_tray(
    hits: i64,
    ap: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 {
        return out;
    }
    let bare = ShootProfile { ap, ..Default::default() };
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded), ap, tray, &mut out);
    out.caused = w;
    out.wounds = regen_batch(w, def, def_owner, tray, &mut out.rolls);
    out
}

// ------------------------------------- D1-B5b: MORALE on the same tray ---

/// `AiCombatMath.Morale` — the three outcomes of a morale test.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Morale {
    Passed,
    Shaken,
    Routed,
}

/// ONE morale test on the tray — `main._solo_morale_test` :8305, in its order:
///
///   the test die at the Banner-modified Quality target [:8336] -> Fearless's
///   single re-roll of a FAILED test, a 4+ counting as passed [:8347] -> No
///   Retreat, which turns the still-failed test into a pass and pays for it in
///   self-wounds, one die per wound needed to destroy the unit [:8365].
///
/// TWO things a naive port gets wrong, both pinned by the tests below:
///
///   1. An ALREADY Shaken unit fails automatically and draws NO die at all
///      (:8310-8317). Burn one there and every later activation of the game is
///      on different faces.
///   2. ROUT exists only in MELEE (p.10, PDF-verified): a shooting-caused
///      failure is Shaken whatever the unit's strength. `melee` is that gate.
///
/// The morale die is stamped `roll_kind` "attack" like every other tray roll
/// (main.gd:8336), so the replay gate can only tell it apart by where it sits.
///
/// Returns the outcome and the report; `wounds` are No Retreat's self-wounds,
/// which land DIRECTLY — "can't be ignored", so no Regeneration roll follows.
///
/// NOT PORTED: the spell morale tokens that join the Banner bonus in the target
/// (:8348-8355) — this port carries no spell-token ledger.
pub fn resolve_morale_with_tray(
    unit: &Ctx,
    owner: &str,
    melee: bool,
    below_half: bool,
    shaken: bool,
    wounds_to_destroy: i64,
    tray: &mut Tray,
) -> (Morale, ShootResult) {
    let mut out = ShootResult::default();
    let failed = if below_half && melee { Morale::Routed } else { Morale::Shaken };
    let mut result = if shaken {
        failed // `morale_result_shaken` :558 — no Quality roll, and no draw.
    } else {
        let target = morale_target(unit.quality, unit.morale_bonus);
        let faces = tray.roll(1);
        let passed = faces_to_hits(&faces, target as u8) > 0;
        out.rolls.push(Roll { kind: "attack", count: 1, target, faces, owner: owner.into() });
        if passed {
            Morale::Passed
        } else {
            failed
        }
    };
    if result != Morale::Passed && unit.fearless {
        let faces = tray.roll(1);
        let passed = faces_to_hits(&faces, FEARLESS_RECOVER_TARGET as u8) > 0;
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: FEARLESS_RECOVER_TARGET,
            faces,
            owner: owner.into(),
        });
        if passed {
            result = Morale::Passed;
        }
    }
    if result != Morale::Passed && unit.no_retreat {
        // `maxi(1, wounds_to_destroy)` :8364 — the zero-die rule applies here
        // too, and the recorded target is the SAFE face, `MAX + 1`.
        let n = wounds_to_destroy.max(1);
        let faces = tray.roll(n as usize);
        out.wounds =
            faces.iter().filter(|&&f| (f as i64) <= NO_RETREAT_SELF_WOUND_MAX).count() as i64;
        out.caused = out.wounds;
        out.rolls.push(Roll {
            kind: "attack",
            count: n,
            target: NO_RETREAT_SELF_WOUND_MAX + 1,
            faces,
            owner: owner.into(),
        });
        result = Morale::Passed;
    }
    (result, out)
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

    // ------------------------------------ block B4: Shot Modifier family ---

    /// Good Shot (+1) and Bad Shot (-1) — main.gd:5681-5701 — are flat, no
    /// range gate: both move the target by exactly one at 6" (well inside 9").
    #[test]
    fn good_shot_and_bad_shot_move_the_to_hit_target_by_one() {
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut t1 = Tray::seeded(27);
        let out_good = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut t1,
        );
        assert_eq!(out_good.rolls[0].target, 3, "Good Shot +1 lowers Quality 4+ to 3+");

        let bad = [ShootProfile { hit_bonus: -1, ..rifle(1) }];
        let mut t2 = Tray::seeded(27);
        let out_bad = resolve_shooting_with_tray(
            &bad, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut t2,
        );
        assert_eq!(out_bad.rolls[0].target, 5, "Bad Shot -1 raises Quality 4+ to 5+");
    }

    /// Targeting Visor (+1) is gated behind `over_in: 9` — main.gd:5693-5694 —
    /// so it does nothing at or under 9" and only helps strictly past it.
    #[test]
    fn targeting_visor_only_helps_strictly_past_nine_inches() {
        let p = [ShootProfile { hit_bonus_over9: 1, ..rifle(1) }];
        let mut under = Tray::seeded(27);
        let out_under = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut under,
        );
        assert_eq!(out_under.rolls[0].target, 4, "under 9\": no bonus");

        let mut exactly = Tray::seeded(27);
        let out_exactly = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 9.0, &mut exactly,
        );
        assert_eq!(out_exactly.rolls[0].target, 4, "exactly 9\" is not \"over\" (main.gd's own wording)");

        let mut over = Tray::seeded(27);
        let out_over = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 12.0, &mut over,
        );
        assert_eq!(out_over.rolls[0].target, 3, "past 9\": the +1 lowers Quality 4+ to 3+");
    }

    /// Good Shot's flat +1 stacks with the target's Stealth -1 (both apply past
    /// 9", `AiCombatMath.shooting_hit_modifier` :230-243) — here they exactly
    /// cancel, so the carrier's Good Shot buys back Stealth's own penalty.
    #[test]
    fn good_shot_stacks_with_and_can_offset_the_stealth_penalty() {
        let stealthy = Ctx { stealth: true, ..defender(4, 5) };
        let mut plain = Tray::seeded(27);
        let out_plain = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &stealthy, 12.0, &mut plain,
        );
        assert_eq!(out_plain.rolls[0].target, 5, "Stealth alone: -1 raises Quality 4+ to 5+");

        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut offset = Tray::seeded(27);
        let out_offset = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(4), &stealthy, 12.0, &mut offset,
        );
        assert_eq!(out_offset.rolls[0].target, 4, "Good Shot +1 cancels Stealth's -1, back to 4+");
    }

    /// The book's floor and ceiling (`AiCombatMath.modified_hit_target` :222-223,
    /// clamped to [2, 6]) still hold once Shot Modifier stacks with the other
    /// modifiers in this function — real combinations, not synthetic numbers.
    #[test]
    fn shot_modifier_stacking_never_breaks_the_book_bounds() {
        // Floor: Quality 2+ (best already) + attacker Artillery (+1, past 9")
        // + Good Shot (+1 flat) would be target -2 unclamped; the book floors
        // it at 2+.
        let artillery_att = Ctx { artillery: true, ..shooter(2) };
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut floor = Tray::seeded(27);
        let out_floor = resolve_shooting_with_tray(
            &good, &[0], &[1], &artillery_att, &defender(4, 5), 12.0, &mut floor,
        );
        assert_eq!(out_floor.rolls[0].target, 2, "clamped at the 2+ floor");

        // Ceiling: Quality 6+ (worst already) into Stealth (-1, past 9") +
        // Evasive (-1, any range) + Bad Shot (-1 flat) would be target 9+
        // unclamped; the book ceilings it at 6+.
        let bad = [ShootProfile { hit_bonus: -1, ..rifle(1) }];
        let hard_target = Ctx { stealth: true, evasive: true, ..defender(4, 5) };
        let mut ceiling = Tray::seeded(27);
        let out_ceiling = resolve_shooting_with_tray(
            &bad, &[0], &[1], &shooter(6), &hard_target, 12.0, &mut ceiling,
        );
        assert_eq!(out_ceiling.rolls[0].target, 6, "clamped at the 6+ ceiling");
    }

    /// NO BEARER: a unit carrying none of Good Shot / Bad Shot / Targeting
    /// Visor stamps a default `ShootProfile` (`hit_bonus`/`hit_bonus_over9`
    /// both 0, `unit.rs::stamp_shot_modifier`'s no-op case) and must resolve
    /// exactly like the pre-B4 baseline — the first shooting-order test above.
    #[test]
    fn no_bearer_leaves_the_to_hit_target_unmodified() {
        let p = [rifle(1)];
        assert_eq!(p[0].hit_bonus, 0);
        assert_eq!(p[0].hit_bonus_over9, 0);
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "Quality 4+ at 12\", no Shot Modifier carrier");
    }

    // ------------------------ Stealth DATA-ALIAS leg (Changebound et al.) ---

    /// Changebound (`hit_penalty:1, over_in:9`, assets/solo/rules_mechanics_
    /// aof.json) is a Stealth-primitive alias, not the literal "Stealth" name
    /// — main.gd:5588-5610/5698-5701. Past 9" it penalizes the to-hit target
    /// by exactly its own `hit_penalty`, same direction as plain Stealth.
    #[test]
    fn changebound_penalizes_the_to_hit_target_past_nine_inches() {
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &changebound, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "Changebound -1 past 9\" raises Quality 4+ to 5+");
    }

    /// The SAME defender at or under 9" — Changebound's own `over_in` gate is
    /// closed, so the target is unmodified (main.gd's `gate <= 0.0 or dist_in
    /// > gate` reading; here `gate` is 9, `dist_in` is 9, not "over").
    #[test]
    fn changebound_does_nothing_at_or_under_nine_inches() {
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &changebound, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "at exactly 9\", Changebound has not fired");
    }

    /// Plain Stealth (the literal name) is unaffected by the new alias fields
    /// staying at their zero default — the pre-existing fixed-constant path
    /// (`Ctx.stealth` + `STEALTH_HIT_PENALTY`/`LONG_RANGE_IN`) stays exactly
    /// as before this leg was added. And when BOTH the literal flag and an
    /// alias are somehow set on the same Ctx, the alias must NOT also apply
    /// on top — "at most one" penalty (main.gd's `not (stealth and over_nine)`
    /// guard), so the net target is identical to plain Stealth alone.
    #[test]
    fn plain_stealth_is_unchanged_and_never_stacks_with_an_alias() {
        let plain = Ctx { stealth: true, ..defender(4, 5) };
        let mut t1 = Tray::seeded(27);
        let out_plain = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &plain, 12.0, &mut t1,
        );
        assert_eq!(out_plain.rolls[0].target, 5, "plain Stealth -1 past 9\" raises 4+ to 5+");

        let both = Ctx { stealth: true, stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut t2 = Tray::seeded(27);
        let out_both = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &both, 12.0, &mut t2,
        );
        assert_eq!(out_both.rolls[0].target, 5, "no double-dip: same target as plain Stealth alone");
    }

    /// The reported corpus finding itself: a Good Shot bearer (+1, block B4)
    /// shooting a Changebound-carrying target (-1, this leg) past 9" nets to
    /// UNMODIFIED — Quality stands as printed. This is the exact stack
    /// `dice_gate.py --only-rule "Good Shot"` found diverging against
    /// `qag_ref` before this fix (Chameleons, quality 5, vs Rift Daemons of
    /// Change's Changebound).
    #[test]
    fn good_shot_and_changebound_cancel_past_nine_inches() {
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(5, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(5), &changebound, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "Good Shot +1 and Changebound -1 cancel: Quality 5+ stands");
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
    // ------------------------------------- D1-B5a: the melee / impact order ---

    fn blade(attacks: i64) -> ShootProfile {
        ShootProfile { name: "Blade".into(), attacks, count: 1, range: 0, ..Default::default() }
    }

    fn striker<'a>(profiles: &'a [ShootProfile], keep: &'a [usize], attacks: &'a [i64],
                   att: &'a Ctx) -> Shooter<'a> {
        Shooter { profiles, keep, attacks, att, owner: "Striker" }
    }

    fn faces_of(r: &ShootResult) -> Vec<u8> {
        r.rolls.iter().flat_map(|x| x.faces.clone()).collect()
    }

    /// THE ORDER, and why it is a gate and not a preference: the table rolls the
    /// charge's Impact dice BEFORE the strikes (main.gd:8067 then :8081). Both
    /// phases draw from ONE tray, so swapping them hands the strikes the dice
    /// that belong to Impact — every face from the first roll on is a different
    /// number, and a recorded activation stops replaying.
    #[test]
    fn impact_is_drawn_before_the_strikes_and_swapping_them_desyncs_the_faces() {
        let p = [blade(3)];
        let att = Ctx { quality: 4, impact: 2, models: 2, ..Default::default() };
        let def = defender(5, 4);
        let pools = impact_pools(&att, &def);
        assert_eq!(pools[0], (4, 0), "Impact(2) x 2 models = 4 dice, no AP");
        // The table's order.
        let mut tray = Tray::seeded(27);
        let mut table = ShootResult::default();
        table.absorb(resolve_impact_pool_with_tray(
            pools[0].0, pools[0].1, "Striker", &def, "Target", &mut tray));
        table.absorb(resolve_melee_with_tray(
            &[striker(&p, &[0], &[3], &att)], &def, "Target", true, &mut tray));
        assert_eq!(table.rolls[0].count, 4);
        assert_eq!(table.rolls[0].target, IMPACT_HIT_TARGET);
        // RED PROOF: the same two phases, strikes first.
        let mut tray = Tray::seeded(27);
        let mut swapped = ShootResult::default();
        swapped.absorb(resolve_melee_with_tray(
            &[striker(&p, &[0], &[3], &att)], &def, "Target", true, &mut tray));
        swapped.absorb(resolve_impact_pool_with_tray(
            pools[0].0, pools[0].1, "Striker", &def, "Target", &mut tray));
        assert_ne!(faces_of(&table), faces_of(&swapped), "swapping the phases must move the faces");
        assert_ne!(table.rolls[0].faces, swapped.rolls[0].faces,
                   "and it must part on the very FIRST roll, not somewhere downstream");
    }

    /// Ravage is not a weapon: X dice per alive bearer, each 6+ a DIRECT wound
    /// with no hit roll and no save (main.gd:5983-6002), drawn BEFORE the
    /// strikes — so no save batch may ever follow it.
    #[test]
    fn ravage_wounds_directly_and_is_drawn_before_the_strikes() {
        let p = [blade(2)];
        let att = Ctx { quality: 4, ravage: 1, models: 3, ..Default::default() };
        let mut tray = Tray::seeded(9);
        let want = Tray::seeded(9).roll(3);
        let out = resolve_melee_with_tray(
            &[striker(&p, &[0], &[2], &att)], &defender(4, 4), "Target", false, &mut tray);
        assert_eq!(out.rolls[0].count, 3, "Ravage(1) x 3 alive models");
        assert_eq!(out.rolls[0].target, RAVAGE_WOUND_TARGET);
        assert_eq!(out.rolls[0].faces, want, "Ravage draws first");
        assert_eq!(out.rolls[1].kind, "attack", "the strike follows — no save batch between");
        assert_eq!(out.rolls[1].count, 2);
    }

    /// FATIGUE IS NOT A MODIFIER (main.gd:6062): a fatigued striker hits on an
    /// unmodified 6 and Unpredictable's +1 does not reach it. Applying the bonus
    /// on top turns the 6 into a 5 and the recorded target stops matching.
    #[test]
    fn fatigue_is_a_flat_six_that_no_bonus_reaches() {
        let mut p = blade(1);
        p.reliable = true;
        p.thrust = true;
        let att = Ctx { quality: 5, models: 1, ..Default::default() };
        assert_eq!(melee_hit_target(&p, &att, &defender(4, 1), true, 0), 2,
                   "Reliable 2+, and Thrust cannot go below the 2+ floor");
        let tired = Ctx { fatigued: true, ..att };
        assert_eq!(melee_hit_target(&p, &tired, &defender(4, 1), true, 0), 6);
        assert_eq!(melee_hit_target(&p, &tired, &defender(4, 1), true, 1), 6,
                   "Unpredictable's +1 must not turn a fatigued 6 into a 5");
    }

    /// ONE CLAMP, ON THE SUM (main.gd:6053-6055). Quality 6 into an Evasive
    /// defender with Unpredictable's +1 is `-1 + 1 = 0` -> a 6+. Clamping the
    /// defender's modifier alone and folding the +1 in through a second
    /// `modified_hit_target` clamps twice and answers 5+.
    #[test]
    fn unstoppable_clamps_the_summed_modifier_once() {
        let mut p = blade(1);
        p.unstoppable = true;
        let att = Ctx { quality: 6, models: 1, ..Default::default() };
        let evasive = Ctx { evasive: true, ..defender(4, 1) };
        assert_eq!(melee_hit_target(&p, &att, &evasive, false, 1), 6,
                   "the sum is 0, so the target stays the unmodified Quality");
        // RED: the two-step form the port used before.
        let two_step = modified_hit_target(
            modified_hit_target(6, { let m = -1i64; if m < 0 { 0 } else { m } }), 1);
        assert_eq!(two_step, 5, "clamping twice is one target too generous");
        let plain = Ctx { quality: 6, models: 1, ..Default::default() };
        assert_eq!(melee_hit_target(&blade(1), &plain, &evasive, false, 0), 6,
                   "without Unstoppable the -1 still cannot push past the 6+ ceiling");
    }

    /// D5 — the Heavy pool is its OWN call, so a caller that just watched the
    /// first pool wipe the defender can stop (main.gd:6304). A single-call form
    /// would roll it regardless and shift every later face.
    #[test]
    fn each_impact_pool_is_its_own_call_so_the_caller_can_stop() {
        let att = Ctx { impact: 1, heavy_impact: 2, models: 3, ..Default::default() };
        let pools = impact_pools(&att, &defender(4, 5));
        assert_eq!(pools, [(3, 0), (6, HEAVY_IMPACT_AP)]);
        let tired = Ctx { fatigued: true, ..att };
        assert_eq!(impact_pools(&tired, &defender(4, 5)), [(0, 0), (0, 0)],
                   "a fatigued charger rolls no Impact at all (p.13)");
        // Stopping after the first pool must leave the tray exactly where that
        // pool left it — the second pool's dice are never drawn.
        let mut one = Tray::seeded(5);
        let r = resolve_impact_pool_with_tray(pools[0].0, pools[0].1, "A", &defender(4, 5), "D", &mut one);
        let mut same = Tray::seeded(5);
        same.roll(3);
        assert_eq!(r.rolls[0].count, 3);
        if r.rolls.len() == 1 {
            assert_eq!(one.state_i64(), same.state_i64(), "no hits, no save batch, no extra draw");
        }
    }

    /// D6 — the melee tally is the PRE-Regeneration count (main.gd:6001/:6113),
    /// while the wounds that LAND are the post-Regeneration ones. Comparing the
    /// landed number lets a Regeneration roll decide who tests morale.
    #[test]
    fn the_melee_tally_is_pre_regeneration_and_the_landed_wounds_are_not() {
        let p = [blade(6)];
        let att = Ctx { quality: 2, models: 6, ..Default::default() };
        // Defense 6+ so nearly everything gets through, Regeneration on 2+ so
        // nearly everything is then ignored: the two numbers cannot coincide.
        let def = Ctx { regeneration: true, regen_target: 2, ..defender(6, 6) };
        let mut tray = Tray::seeded(4);
        let out = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &att)], &def, "Target", false, &mut tray);
        assert!(out.caused > 0, "the strike caused wounds: {:?}", out.rolls);
        assert!(out.wounds < out.caused, "Regeneration ignored some: {} vs {}", out.wounds, out.caused);
    }

    /// An attached hero strikes under the host's activation and signs its own
    /// dice (`_solo_attack_groups` :4284-4290), host first.
    #[test]
    fn an_attached_hero_strikes_after_the_host_and_signs_its_own_dice() {
        let hp = [blade(4)];
        let hero = [blade(1)];
        let att = Ctx { quality: 4, models: 2, ..Default::default() };
        let mut tray = Tray::seeded(21);
        let out = resolve_melee_with_tray(
            &[
                Shooter { profiles: &hp, keep: &[0], attacks: &[4], att: &att, owner: "Host" },
                Shooter { profiles: &hero, keep: &[0], attacks: &[1], att: &att, owner: "Hero" },
            ],
            &defender(6, 3), "Target", false, &mut tray);
        let attacks: Vec<(&str, i64)> = out.rolls.iter().filter(|r| r.kind == "attack")
            .map(|r| (r.owner.as_str(), r.count)).collect();
        assert_eq!(attacks, vec![("Host", 4), ("Hero", 1)], "host first, then the hero");
    }

    // ------------------------------------------------ D1-B5b: the morale dice ---

    /// One test die at the Banner-modified Quality target, and Fearless's single
    /// recovery die as a SECOND batch after it (main.gd:8336 then :8347).
    #[test]
    fn a_morale_test_is_one_die_and_fearless_rolls_a_recovery_die() {
        let unit = Ctx { quality: 6, fearless: true, ..Default::default() };
        let mut tray = Tray::seeded(11);
        let (_, out) = resolve_morale_with_tray(&unit, "Unit", true, false, false, 4, &mut tray);
        assert_eq!(out.rolls[0].count, 1);
        assert_eq!(out.rolls[0].target, 6, "Quality 6+, no Banner");
        let failed = faces_to_hits(&out.rolls[0].faces, 6) == 0;
        assert_eq!(out.rolls.len(), if failed { 2 } else { 1 });
        if failed {
            assert_eq!(out.rolls[1].target, FEARLESS_RECOVER_TARGET, "the 4+ rescue die");
        }
    }

    /// An ALREADY Shaken unit fails automatically and draws NO die (:8310-8317).
    /// Burn one and every later activation of the game is on other faces.
    #[test]
    fn an_already_shaken_unit_fails_morale_without_drawing_a_die() {
        let unit = Ctx { quality: 4, ..Default::default() };
        let mut tray = Tray::seeded(5);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", true, true, true, 3, &mut tray);
        assert!(out.rolls.is_empty(), "no Quality roll for a Shaken unit");
        assert_eq!(res, Morale::Routed, "Shaken + at half + melee = Rout");
        assert_eq!(tray.state_i64(), Tray::seeded(5).state_i64(), "and not one draw spent");
    }

    /// ROUT is melee-only (p.10). The same failed test at half strength is a
    /// Rout in melee and only Shaken after shooting.
    #[test]
    fn only_a_melee_test_can_rout() {
        let unit = Ctx { quality: 4, ..Default::default() };
        let melee = resolve_morale_with_tray(&unit, "U", true, true, true, 2, &mut Tray::seeded(1));
        let shot = resolve_morale_with_tray(&unit, "U", false, true, true, 2, &mut Tray::seeded(1));
        assert_eq!(melee.0, Morale::Routed);
        assert_eq!(shot.0, Morale::Shaken);
    }

    /// No Retreat turns the still-failed test into a PASS and pays for it in
    /// self-wounds: one die per wound needed to destroy the unit, 1-3 wounding
    /// (:8365). The target the tray records is `MAX + 1`, the safe face.
    #[test]
    fn no_retreat_pays_a_failed_test_in_self_wounds() {
        let unit = Ctx { quality: 6, no_retreat: true, ..Default::default() };
        let mut tray = Tray::seeded(2);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", true, true, true, 5, &mut tray);
        assert_eq!(res, Morale::Passed, "No Retreat counts as passed");
        assert_eq!(out.rolls.len(), 1, "Shaken drew no test die; only the self-wound roll");
        assert_eq!(out.rolls[0].count, 5, "one die per wound needed to destroy it");
        assert_eq!(out.rolls[0].target, NO_RETREAT_SELF_WOUND_MAX + 1);
        let want = out.rolls[0].faces.iter().filter(|&&f| f <= 3).count() as i64;
        assert_eq!(out.wounds, want, "each 1-3 is one self-wound");
    }

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
