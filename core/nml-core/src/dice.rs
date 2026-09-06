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
    conditional_ap_bonus, covered_defense, deadly_multiplier, fortified_ap, guarded_defense,
    impact_total_dice, melee_hit_modifier, modified_hit_target, reliable_quality, save_target,
    shielded_defense, morale_target, shooting_hit_modifier, shrouded_reach, thrust_to_hit,
    versatile_best_mode, BEST_HIT_TARGET, FEARLESS_RECOVER_TARGET, HEAVY_IMPACT_AP,
    IMPACT_HIT_TARGET, LONG_RANGE_IN, NO_RETREAT_SELF_WOUND_MAX, RAVAGE_WOUND_TARGET,
    RENDING_AP_BONUS, THRUST_AP_BONUS, UNMODIFIED_SIX,
};
use crate::rng::GodotRng;
use crate::unit::{CondAp, Ctx, ShieldedAlias, ShootProfile};

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
    /// Block B13 — the rules-must-log lines THIS activation wrote, in order:
    /// the twin has no battle log, so an applied rule names itself here (the
    /// table's `battle_log.log_event`, e.g. "Retaliate: %s lashes back — %d
    /// hits", main.gd:6162-6165). Carried beside the dice stream, never a roll
    /// of its own.
    pub log: Vec<String>,
    /// WAVE 3 — the family's alias/boost arm ACTUALLY lowered a save target
    /// this activation (main.gd's `ap < ap_before` guard), as read by
    /// `save_batch`; the orchestrators turn it into the rules-must-log line.
    pub fortified_fired: bool,
    /// Wave 4 (`rules-wave4-boostbases`) — the volley's ACTIVE Bane Boost
    /// window for THIS batch (the "Mischievous Boost" stamp, strictly past
    /// the entry's own `over_in`; 0 = the base 6s-only window). Set by the
    /// volley per weapon, read by `save_batch`; the melee resolve never sets
    /// it — its save batches run on fresh results, the base window.
    pub bane_low: i64,
    /// How many saves the WIDENED window added to the re-roll batches (the
    /// successful 5s the base 6s leg would never have touched) — the volley
    /// turns a non-zero count into the one rules-must-log line.
    pub bane_rerolled: i64,
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
        self.log.extend(other.log);
        self.fortified_fired = self.fortified_fired || other.fortified_fired;
        self.bane_rerolled += other.bane_rerolled;
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

/// Block B6 — the extra-ATTACK-DIE form of the "unmodified 6 to hit" family
/// (Bloodborn / Clan Warrior / Primal / Predator / Royal Warrior / Crazed /
/// Psychotic and their book aliases, `unit.rs::stamp`'s `surge_attack` /
/// `surge_attack_low`, `_solo_hits` main.gd:4417-4432): for each unmodified 6
/// among `faces` — plus each unmodified 5 too, once `surge_attack_low < 6`
/// (the Primal-Boost-style upgrade) — draw ONE more attack die at
/// `count_target`, as its own tray slot; the extras are counted as hits but
/// never re-trigger (`faces` here is always the ORIGINAL roll, never the
/// extras). Shared by `resolve_volley_with_tray` and `resolve_melee_with_tray`
/// — the table resolves both through the same `_solo_hits`.
/// Wave 2 grant stand-ins — the family's printed shapes, uniform on every
/// shipped occurrence (HIT_AND_RUN_MOVE_IN precedent).
fn primal_boost_grant_profile() -> ShootProfile {
    ShootProfile { surge_attack: true, surge_attack_low: 5, ..Default::default() }
}

fn slayer_grant_cond() -> CondAp {
    CondAp {
        ap_bonus: 2, condition: "vs_tough_ge".into(), threshold: 3,
        gate: "ranged_over_or_charge".into(), over_in: 9.0, ..Default::default()
    }
}

fn piercing_assault_grant_cond() -> CondAp {
    CondAp { ap_bonus: 1, condition: "on_charge".into(), ..Default::default() }
}

fn surge_attack_hits(
    p: &ShootProfile,
    faces: &[u8],
    count_target: i64,
    owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> i64 {
    if !p.surge_attack {
        return 0;
    }
    let mut xn = sixes(faces);
    if p.surge_attack_low < 6 {
        xn += faces.iter().filter(|&&f| f == 5 && count_target <= 5).count() as i64;
    }
    if xn <= 0 {
        return 0;
    }
    let extra_faces = tray.roll(xn as usize);
    rolls.push(Roll {
        kind: "attack",
        count: xn,
        target: count_target,
        faces: extra_faces.clone(),
        owner: owner.into(),
    });
    faces_to_hits(&extra_faces, count_target as u8) as i64
}

/// `AiCombatMath.blocks_with_bane` :354-363 — each unmodified Defense 6 is
/// replaced by the next re-roll face, in order; a re-rolled 6 still blocks.
fn blocks_with_bane(faces: &[u8], reroll: &[u8], target: i64) -> i64 {
    blocks_with_bane_from(faces, reroll, target, 6)
}

/// The widened window (wave 4, "Mischievous Boost"'s `reroll_save_low: 5`):
/// every SUCCESSFUL unmodified save at or above `from` re-rolls too, not
/// just 6s (`from` 6 = the base leg, byte-exact). A face below the save
/// target is no success — it never re-rolls.
fn blocks_with_bane_from(faces: &[u8], reroll: &[u8], target: i64, from: i64) -> i64 {
    let mut ri = 0usize;
    let mut blocks = 0i64;
    for &f in faces {
        let eff = if f == 6 || (f as i64 >= from && f as i64 >= target) {
            let r = reroll.get(ri).copied().unwrap_or(f);
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
/// The Shred Boost generalizes the window to `low` (failed rolls 1..=low — a
/// 1 always fails, a higher face only strictly under the save target);
/// `low = 1` is the base rule and this function's old shape.
fn shred_faces(faces: &[u8], reroll: &[u8], low: i64, target: i64) -> i64 {
    let mut ri = 0usize;
    let mut wounds = 0i64;
    for &f in faces {
        if f == 6 && ri < reroll.len() {
            let g = reroll[ri] as i64;
            ri += 1;
            if g <= low && (g == 1 || g < target) {
                wounds += 1;
            }
        } else if (f as i64) <= low && (f == 1 || (f as i64) < target) {
            wounds += 1;
        }
    }
    wounds
}

/// `main._solo_save_batch` :6385-6483 — ONE batch for the whole defender (not
/// per model), Fortified first, then the dice, then Bane's re-roll of the
/// unmodified 6s, then Shred and the pooled Deadly multiplier.
///
/// `shred_alias_dice` is the Shred-FAMILY epoch gate
/// (`sim.rs` passes `rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES)`): the
/// unit-level alias stamp (`ShootProfile.shred_alias` — Destroyer/Infected/
/// Warbound and the two scoped halves) reaches the batch only at the current
/// epoch, so every pre-port corpus replays byte-exact.
///
/// `shred_low` is the ACTIVE save-fail window for THIS batch (the Shred
/// Boost's widened faces 1-2, precomputed by the volley behind its own
/// epoch-4 gate; 1 = the base window — melee resolves at 1, it never has a
/// distance to clear).
#[allow(clippy::too_many_arguments)]
fn save_batch(
    p: &ShootProfile,
    def: &Ctx,
    def_owner: &str,
    count: i64,
    defense: i64,
    ap: i64,
    shred_grant: bool,
    shred_alias_dice: bool,
    shred_low: i64,
    tray: &mut Tray,
    out: &mut ShootResult,
) -> i64 {
    if count <= 0 {
        return 0;
    }
    // Plain Fortified first (main.gd:6440-6447), then the WAVE 3 alias arm in
    // its ELSE — Boost ungated, gated aliases past the volley's over-9" flag,
    // both clamped at AP(0) like `fortified_ap`.
    let mut eff_ap = fortified_ap(ap, def.fortified);
    if !def.fortified {
        let red = def
            .fortified_boost_ap
            .max(if def.fortified_alias_over9 { def.fortified_alias_ap } else { 0 });
        if red > 0 && ap > 0 {
            eff_ap = (ap - red).max(0);
            out.fortified_fired = true;
        }
    }
    // rules-wave3-growthmark (epoch 6) — the DEFENDER-side facets ride the
    // same save target: the +X-to-Defense ladder and Fortified Growth's
    // attacker-AP cut, floored at the hard 0 the rule prints. Both ctx
    // fields are zero unless `sim::ctx_live` folded them behind
    // `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`, so pre-epoch corpora
    // replay byte-exact.
    let target = save_target(defense + def.growth_def_mod, (eff_ap + def.growth_fortify_ap).max(0));
    let faces = tray.roll(count as usize);
    out.rolls.push(Roll {
        kind: "defense",
        count,
        target,
        faces: faces.clone(),
        owner: def_owner.into(),
    });
    let mut reroll: Vec<u8> = Vec::new();
    // Wave 4 — the widened window (0 = the base 6s-only leg, byte-exact):
    // successful unmodified saves from `bane_low` up re-roll too.
    let bane_from = if p.bane && out.bane_low > 1 { out.bane_low } else { 6 };
    if p.bane {
        let n = faces.iter().filter(|&&f| f == 6 || (f as i64 >= bane_from && f as i64 >= target)).count() as i64;
        if n > 0 {
            reroll = tray.roll(n as usize);
            out.rolls.push(Roll {
                kind: "defense",
                count: n,
                target,
                faces: reroll.clone(),
                owner: def_owner.into(),
            });
            // The widened window's own share — the successful 5s the base leg
            // would never have touched (rules-must-log count).
            out.bane_rerolled += faces.iter().filter(|&&f| out.bane_low > 1 && f < 6 && f as i64 >= out.bane_low && f as i64 >= target).count() as i64;
        }
    }
    let unsaved = (count - blocks_with_bane_from(&faces, &reroll, target, bane_from)).max(0);
    let shred = if p.shred || shred_grant || (p.shred_alias && shred_alias_dice) {
        // Wave 3: the per-face wound amount rides the profile's epoch-6
        // stamped `extra_wound_per_save_one` read (0 = unread -> the base
        // +1 the wave-1 alias arm hard-codes, byte-exact at every earlier
        // epoch). The firing names itself (rules-must-log) only when the
        // read actually rode along — every pre-epoch-6 corpus stays silent.
        let bonus = p.shred_ones_wound_bonus.max(1);
        let shreds = shred_faces(&faces, &reroll, shred_low.max(1), target as i64);
        let wound = shreds * bonus;
        if wound > 0 && p.shred_ones_wound_bonus > 0 {
            out.log.push(format!(
                "Shred ({}): {} — {} failed save rolls cost {} extra wounds against {}",
                p.shred_ones_rule, p.shred_ones_owner, shreds, wound, def_owner));
        }
        wound
    } else {
        0
    };
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
/// and Surge plus Surge's own gates (Point-Blank's within-12" cap, the Boosts'
/// successful 5s past 9" — epoch-3, ungated for pre-epoch records), block B6's
/// extra-ATTACK-DIE Surge siblings (Bloodborn / Primal /
/// Predator / Clan Warrior and their book aliases, `surge_attack_hits`), Blast,
/// the Rending/Destructive/on-6 AP sub-batch, Fortified, Shielded/Guarded/Cover
/// on the save target, Bane's re-roll, Shred, the pooled Deadly multiplier and
/// the pooled Regeneration roll.
///
/// NOT PORTED. Nothing here is a silent skip: everything the trainer's own
/// profile model can SEE is flagged per activation in `unported`; everything
/// below the line has no field to detect it by and is listed instead.
///
/// FLAGGED (a counter per activation):
///   * `surge_gates` — LEGACY REPLAY ONLY since the epoch-3 surge-gates port:
///     the volley now reads the table's own gates off the profile
///     (`surge_within_in`, `surge_low`/`surge_over_in`, main.gd:4465-4482) and
///     flags nothing; every pre-epoch record keeps the ungated read, and the
///     MELEE leg (whose gates are no-ops at dist 0) keeps the mark.
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
///     PORTED in B12 for the SHOOTING leg (`resolve_volley_with_tray`: the
///     exact "Unpredictable"/"Unpredictable Shooter" pair, never the
///     melee-only Fighter); the MELEE leg was already in
///     `resolve_melee_with_tray` (block D1-B5a).
///     (Block B6 ported the OTHER stream-desyncing draw this list used to
///     name here — the extra-ATTACK dice of the Bloodborn/Primal/Predator/Clan
///     Warrior family, :4454 — see `surge_attack_hits` and the PORTED line
///     above.)
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
///   * Indirect's moved -1 (:3163-3169). Its faction-level opt-out is
///     DECLARED, not ported (rules-wave3-indirect2): with no moved-penalty
///     primitive in this profile/context model, the opt-out's `no_moved_penalty`
///     param (the Indirect mechanics entry) has nothing to act on, so the core
///     registers neither the penalty nor its opt-out — needs primitive:
///     `moved_hit_penalty` (a firing-side to-hit modifier when the unit moved
///     this activation) before either can be stamped.
///   * Spot markers, Reckless AP, `AiEv.stamp_conditional_ap`
///     (Shatter / Tear / Disintegrate). The Piercing tag PORTED in wave 3
///     (the marker pool + the `tag_ap_mod` fold above); vs-target Marks
///     PORTED in B2b (`tray_vs_marks`).
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
    // Single-scalar convenience form (tests only — sim.rs's real caller
    // supplies the two distances separately): range gate and modifier gate
    // are the SAME point here. Assumes the shipped `cond_ap_dice=true` state
    // and the current rules epoch (both surge gates, the Shred-family alias
    // gate and the Shred Boost's epoch-4 gate on); a legacy-OFF test calls
    // `resolve_volley_with_tray` directly (see the RED/GREEN pairs below).
    resolve_volley_with_tray(&one, def, "", dist_in, dist_in, true, true, true, true, tray)
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
///     no once-per-game ledger to spend. That group IS the family's "Takedown
///     Shot" rule (resolver wave A, main.gd:3046-3086; its melee sibling
///     "Takedown Strike" joins the strike groups at :6032-6034): a synthetic
///     single-attack profile {ap, deadly, takedown} off the registry params at
///     its OWN Quality (`extra_attack_q` — the tray's per-Shooter Ctx could
///     carry that), spent once per game per bearer and name
///     (`unit_properties["takedown_bonus_used_<name>"]`). NEEDS PRIMITIVE: a
///     per-unit, per-name once-per-game ledger (the `limited_used` shape)
///     before either name can port exactly — a flat always-on stamp would be
///     the #489 over-credit.
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
    mod_dist_in: f64,
    cond_ap_dice: bool,
    surge_gates: bool,
    shred_alias_dice: bool,
    shred_boost_dice: bool,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    let (mut regenable, mut regen_proof) = (0i64, 0i64);
    // PORTED — Unpredictable's SHOOTING leg :3096-3110: ONE die for the whole
    // volley, before any weapon fires, off the FIRST shooter's context. A face
    // at or under `low_roll_max` is +ap_bonus on every profile of this volley
    // (folded into the shot's AP below, the duplicate-profile leg of
    // main.gd:3188-3190), above it +hit_bonus to hit (main.gd:3180, folded
    // into the per-shot modifier sum). The melee-only "Unpredictable Fighter"
    // is stamped out of `Ctx::unpredictable_shooting` (unit.rs).
    let mut upr_ap = 0i64;
    let mut upr_hit = 0i64;
    if shooters.first().is_some_and(|sh| sh.att.unpredictable_shooting) {
        let att0 = shooters[0].att;
        let faces = tray.roll(1);
        if (faces[0] as i64) <= att0.unpredictable_low_roll_max {
            upr_ap = att0.unpredictable_ap_bonus;
        } else {
            upr_hit = att0.unpredictable_hit_bonus;
        }
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: BEST_HIT_TARGET,
            faces,
            owner: shooters[0].owner.into(),
        });
    }
    // `dist_in` gates RANGE VALIDITY only (`reach_gate`, B11's edge/nearest-
    // model gap — main.gd:4098-4104). `mod_dist_in` is the table's SEPARATE
    // over-9" modifier distance (`geom::centre_dist_in`, main.gd:3029: unit
    // centre to unit centre) — NML-1152, found by a read-only corpus audit:
    // the twin was reusing the range gap as the modifier gate too.
    let reach_gate = dist_in.ceil();
    // Wave 3 — the Ranged-Shrouding clamp's own rules-must-log flag: set the
    // moment a profile's working reach actually drops below its raw range
    // (dice.rs `ShootResult.log` precedent), one line per volley below.
    let mut shroud_shortened = false;
    // Wave 3 — the Indirect family's rules-must-log flag: set the moment an
    // alias-marked profile's cover skip actually lands on an in-cover target
    // (`shroud_shortened`'s shape) — one line per volley below.
    let mut alias_cover_logged = false;
    // Wave 3 — the Shot Modifier family's two runtime-gated members name
    // themselves once per volley per firing member (rules-must-log): the
    // member's owner, its hit bonus and (Mobile Artillery only) its own
    // `over_in` gate, as first fired.
    let mut ma_fired: Vec<(&str, i64, f64)> = Vec::new();
    let mut gp_fired: Vec<(&str, i64)> = Vec::new();
    // Wave 4 — the evasive Boosts' once-per-volley rules-must-log flag (the
    // defender-side alias marker, the alias_cover_logged shape); the RULE
    // that fired is `def.evasive_alias_name` ("Machine-Fog Boost" at epoch 6,
    // "Empyrean Spirit Boost" at epoch 7).
    let mut evasive_boost_fired = false;
    // Wave 4 — and the widened Bane window's own rule name, sticky once a
    // weapon opened it ("Mischievous Boost" at epoch 6, "Bestial Boost" at
    // epoch 7); "" = the base 6s-only window fired nothing.
    let mut bane_rule = "";
    // Wave 3 — the Shielded-family alias's own rules-must-log flag: the +1
    // rode a family DATA alias rather than the literal name, one line per
    // volley below (`ShootResult.log` precedent).
    let mut shielded_alias_fired = false;
    // WAVE 3 — the aliases' over-9" SAVE gate (main.gd:3090/6415), ONCE per
    // volley on this local copy; non-volley paths leave it false — the
    // table's own reading (melee `dist_in: -1.0`, :6119). Stamp-gated.
    let def = &Ctx {
        fortified_alias_over9: def.fortified_alias_ap > 0
            && def.fortified_alias_over_in > 0.0
            && mod_dist_in > def.fortified_alias_over_in,
        ..*def
    };
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
        let mut reach = if def.ranged_shrouding {
            let r = shrouded_reach(p.range as f64, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in);
            shroud_shortened |= r < p.range as f64;
            r
        } else {
            p.range as f64
        };
        // WAVE 3 MARK (`acts::rule_on` inside `ctx_live`, EPOCH_6_TABLE_RULES):
        // the target's live "+6\" shooting range" record extends the reach the
        // range gate tests — `ctx_of` (the EV imagination) leaves it 0.
        reach += def.range_mark_in;
        if p.range <= 0 || reach < reach_gate {
            continue;
        }
        if def.range_mark_in > 0.0 && (p.range as f64) < reach_gate && reach >= reach_gate {
            out.log.push(format!(
                "Increased Shooting Range Mark: {} gains +{:.0}\" reach on {}",
                sh.owner, def.range_mark_in, def_owner
            ));
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
            mod_dist_in, att.artillery, def.stealth, def.artillery, def.evasive,
            p.hit_bonus, p.hit_bonus_over9,
            def.stealth_alias_penalty, def.stealth_alias_over_in,
        )
            // B2b: the LIVE ledger's own nets — `_solo_hit_mod_info`
            // :5703-5709 adds the shooter's `_solo_spell_hit_mod` and the
            // target's `_solo_spell_hit_mod_vs` to the SAME `mod` that then
            // goes through ONE `modified_hit_target`. Kept apart from the
            // STATIC `p.hit_bonus` stamp above (#487): that one is baked per
            // weapon at build time, these two are per-activation records.
            + att.hit_mod
            + def.vs_hit_mod
            // Block B7 — Precision Frenzy: main.gd:5677-5680's marker-driven
            // hit bonus, shooting only (`_solo_hit_mod_info`'s melee branch
            // returns before that code runs).
            + att.growth_hit_mod
            // Unpredictable's 4-6 half (main.gd:3180): folded into the SAME
            // sum, BEFORE the Unstoppable clamp, like the melee leg.
            + upr_hit;
        // Wave 3 — the Shot Modifier family's runtime-gated members
        // (main.gd:5761-5779) ride the SAME sum: Mobile Artillery's
        // `requires_stationary` gate is the shooter's act-scope `moved`
        // flag (Ctx::moved_this_round), Grounded Precision's
        // `terrain_within_in` gate the core's own cover read (Ctx::in_cover).
        let ma = mobile_artillery_mod(att, mod_dist_in);
        let gp = grounded_precision_mod(att);
        m += ma + gp;
        if ma != 0 && ma_fired.iter().all(|(o, _, _)| *o != sh.owner) {
            ma_fired.push((sh.owner, ma, att.mobile_artillery_over_in));
        }
        if gp != 0 && gp_fired.iter().all(|(o, _)| *o != sh.owner) {
            gp_fired.push((sh.owner, gp));
        }
        // Wave 4 — the evasive Boost names itself once per volley: the
        // unconditional -1 rode this weapon's to-hit sum (the defender-side
        // alias marker, Ctx::evasive_alias).
        evasive_boost_fired |= def.evasive_alias;
        if p.unstoppable && m < 0 {
            m = 0;
        }
        target = modified_hit_target(target, m);
        let mut versatile_ap = 0;
        if (p.versatile_attack || att.versatile_grant) && mod_dist_in > LONG_RANGE_IN {
            // Wave 3 — the "Vinci Tech Boost" form (`pick_one: false`,
            // stamped only under the frozen EPOCH_6_TABLE_RULES gate): BOTH
            // arms instead of the pick. The flag rides the same stamp the
            // generic buff rides, so a pre-epoch-6 record keeps the pick.
            let (hit_mod, ap_mod) = if p.versatile_both {
                (1, 1)
            } else {
                versatile_best_mode(
                    target,
                    shielded_defense(def.defense, def.shielded),
                    p.ap + upr_ap,
                    p.bane,
                )
            };
            versatile_ap = ap_mod;
            target = modified_hit_target(target, hit_mod);
            // Rules-must-log — only the wave-3 NAMED family forms log (the
            // named arm's stamp); the generic stamps stay silent, so every
            // earlier epoch's replay is byte-identical.
            if !p.versatile_name.is_empty() {
                let what = if p.versatile_both {
                    "AP(+1) and +1 to hit"
                } else if ap_mod > 0 {
                    "AP(+1)"
                } else {
                    "+1 to hit"
                };
                out.log.push(format!(
                    "{}: {} on {}'s volley over 9\"",
                    p.versatile_name, what, sh.owner
                ));
            }
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
        if (p.relentless || att.relentless_grant) && mod_dist_in > LONG_RANGE_IN {
            hits += sixes(&faces);
        }
        if p.surge {
            if surge_gates {
                // The table's own gates (main.gd:4465-4482): `surge_within_in`
                // (Point-Blank) caps the whole bonus at or under the centre
                // distance; a Boost adds successful unmodified 5s only PAST
                // `surge_over_in` — melee (0.0) never qualifies.
                if p.surge_within_in <= 0.0 || mod_dist_in <= p.surge_within_in {
                    hits += sixes(&faces);
                    if p.surge_low < 6 && mod_dist_in > p.surge_over_in {
                        hits += faces.iter().filter(|&&f| f == 5 && count_target <= 5).count() as i64;
                    }
                }
            } else {
                // LEGACY REPLAY ONLY — the ungated read, kept for every
                // pre-epoch record (epoch < 3), plus its divergence counter.
                hits += sixes(&faces);
                out.mark("surge_gates");
            }
        }
        // Block B6 — the extra-ATTACK-DIE Surge siblings, ported (see the
        // helper's own doc). Draws its own tray slot right after Surge's,
        // matching `_solo_hits`'s order.
        hits += surge_attack_hits(p, &faces, count_target, sh.owner, tray, &mut out.rolls);
        // Wave 2 — a granted "Primal Boost", the same low-surge form.
        if att.surge_grant {
            hits += surge_attack_hits(&primal_boost_grant_profile(), &faces, count_target, sh.owner, tray, &mut out.rolls);
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
        // The Shred Boost's widened window rides its own epoch-4 gate
        // (`shred_boost_dice`, sim.rs's `rule_on(seams.rules_epoch, 4)`
        // literal) plus the entry's own `over_in` distance — strictly past
        // 9", like every other over-9" read. `shred_low` 1 = the base window.
        let shred_low = if shred_boost_dice && p.shred_low > 1 && mod_dist_in > p.shred_over_in {
            p.shred_low
        } else {
            1
        };
        // Wave 4 — "Mischievous Boost"'s widened Bane window: strictly past
        // the entry's own over_in, the shred window's own volley gate shape.
        // 0 = the base 6s-only window; the melee resolve never sets it (its
        // save batches run on fresh results), so melee never widens — no
        // pre-charge gap (the shred2 precedent).
        out.bane_low = if p.bane_low > 1 && mod_dist_in > p.bane_over_in { p.bane_low } else { 0 };
        if out.bane_low > 1 {
            bane_rule = p.bane_rule;
        }
        let on6 = if p.on6_ap > 0 {
            p.on6_ap
        } else if p.rending || p.destructive || att.rending_grant {
            RENDING_AP_BONUS
        } else {
            0
        };
        let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
        // Defense, in main.gd's own order: Shielded, then Guarded (over 9"),
        // then Cover — which Blast / Indirect / Ignores Cover skip (:3221).
        let mut base = shielded_defense(def.defense, def.shielded);
        base = guarded_defense(base, def.guarded && mod_dist_in > LONG_RANGE_IN);
        shielded_alias_fired |= def.shielded && def.shielded_alias != ShieldedAlias::None;
        let save_def = if p.blast > 1 || p.indirect || p.ignores_cover {
            base
        } else {
            covered_defense(base, def.in_cover)
        };
        // Wave 3 — rules-must-log: the unit-level Indirect names ("Indirect
        // when Shooting" / "Ignores Cover when Shooting", unit.rs build_for's
        // epoch-6 walk) stamp their skip with an `*_alias` marker, so the
        // volley names the RULE — not the weapon tag — the one time its cover
        // skip lands (`Ranged Shrouding`'s one-line shape). An epoch-5 static
        // carries no markers and stays silent.
        if !alias_cover_logged
            && def.in_cover
            && p.blast <= 1
            && (p.indirect_alias || p.ignores_cover_alias)
        {
            alias_cover_logged = true;
            let rule = if p.ignores_cover_alias {
                "Ignores Cover when Shooting"
            } else {
                "Indirect when Shooting"
            };
            out.log
                .push(format!("{rule}: {} — {}'s cover save is skipped", sh.owner, def_owner));
        }
        // Block B7 — Piercing Growth: main.gd:4287's marker-driven AP delta,
        // shooting and melee both (`_solo_attack_groups` adds it to `prof
        // ["ap"]` regardless of which the caller built profiles for).
        let mut ap = p.ap + upr_ap + versatile_ap + att.growth_ap_mod
            // Ambush family (rules-wave2-ambush): "Ambushing Piercing Shot"'s
            // arrival-round AP(+1) — SHOOTING only, the melee fold at :992
            // never reads it (its own facet gate).
            + att.ambush_arrival_ap
            // Wave 3 — Piercing Tag's spent markers: +AP(markers) on THIS
            // volley only (main.gd:3123/:9857), stamped by the tray seam
            // after the pool zeroes (sim.rs). The melee fold never reads it —
            // the table's melee seams have no tag spend — and the EV
            // imagination stays blind, the table's own resolve-time spend.
            + att.tag_ap_mod;
        // Wave 2 — the "AP(+1) when shooting" mark's flat AP, off its
        // epoch-gated Ctx leg (`sim::ctx_live`).
        if att.pierce_shooting_grant {
            ap += 1;
        }
        // Rung I (audit 2026-09-02, DEFECT_LEDGER row 31) — the SAME `cond_ap`
        // fold `profile_ev` uses (combat.rs) now reaches the dice save target
        // too, gated by `Knobs::cond_ap_dice` (absent/OFF replays every
        // pre-PR corpus unchanged). Shooting never charges, so `is_charging`
        // is false here; the `ranged_over`/`ranged_over_or_charge` gates read
        // `mod_dist_in`, the NML-1152 modifier-distance split, not the plain
        // range gap.
            if cond_ap_dice {
            for c in &p.cond_ap {
                let d = conditional_ap_bonus(c, def.tough.max(1), def.defense, false, mod_dist_in, false);
                ap += d;
                // Rules-must-log: the wave-3 NAMED forms log their own AP
                // (rule, unit, what changed). The generic pass's specs carry
                // no name — old replays log nothing, byte-identical.
                if d > 0 && !c.name.is_empty() {
                    out.log.push(format!("{}: AP(+{}) on {}'s volley", c.name, d, sh.owner));
                }
            }
            // Wave 2 — the Slayer mark's granted conditional (epoch-gated).
            if att.slayer_grant {
                ap += conditional_ap_bonus(&slayer_grant_cond(), def.tough.max(1), def.defense, false, mod_dist_in, false);
            }
        }
        let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, att.shred_grant, shred_alias_dice, shred_low, tray, &mut out);
        w += save_batch(p, def, def_owner, hits - ap4, save_def, ap, att.shred_grant, shred_alias_dice, shred_low, tray, &mut out);
        if p.deadly > 0 {
            out.mark("deadly");
        }
        // `_solo_ignores_regen` :6927-6933 — Bane / Rending (and Unstoppable,
        // ai_ev.gd:433) cut through Regeneration; everything else is poolable.
        // B2b: `_solo_ignores_regen`'s last line (main.gd:6941) also answers
        // for a LIVE "Unstoppable" grant — the Unstoppable Mark seam.
        if p.bane || p.rending || p.unstoppable || att.rending_grant || att.unstoppable_grant {
            regen_proof += w;
        } else {
            regenable += w;
        }
    }
    // --- `_solo_land_wounds` :6623 -> `_solo_apply_regeneration` :6543 ---
    if shroud_shortened {
        out.log.push(format!(
            "Ranged Shrouding: {def_owner} — enemy weapon ranges -{:.0}\" (min {:.0}\") against it",
            def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in
        ));
    }
    for (owner, hit, over) in &ma_fired {
        out.log.push(format!(
            "Mobile Artillery: {owner} — {hit:+} to hit past {over:.0}\" (stationary)"
        ));
    }
    for (owner, hit) in &gp_fired {
        out.log.push(format!("Grounded Precision: {owner} — {hit:+} to hit (in terrain)"));
    }
    // Wave 4 — the two Boostbases rules-must-log lines, once per volley, each
    // naming the RULE that fired (wave 3's two spellings and wave 4's two).
    if evasive_boost_fired {
        out.log.push(format!(
            "{}: {def_owner} — attackers get -1 to hit (always)",
            def.evasive_alias_name
        ));
    }
    if out.bane_rerolled > 0 {
        out.log.push(format!(
            "{bane_rule}: {def_owner} — {} successful save(s) of 5-6 re-roll",
            out.bane_rerolled
        ));
    }
    if shielded_alias_fired {
        out.log.push(format!(
            "{}: {def_owner} — +1 to defense rolls (saves on {}+)",
            def.shielded_alias.name(),
            shielded_defense(def.defense, true)
        ));
    }
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

/// Block B13 — Retaliate(X)'s saves on the tray, `_solo_melee_strike_phase`
/// main.gd:6166-6170: the lashed-back hits are saved at the STRIKER's
/// Shielded-adjusted Defense (melee reads neither Cover nor Guarded — the
/// strike saves' own ladder, `shielded_defense`), AP 0, and NOT a weapon: the
/// table's rprofile is `{"name": "Retaliate", "ap": 0, "deadly": 0, "rules":
/// []}`, so no Bane re-roll, no Shred, no Deadly multiplier. The table lands
/// them with `_solo_land_wounds(striker, rw, 0)` — its `0` is the REGEN_PROOF
/// bucket, so every failed save stays regenerable and the STRIKER's own
/// Regeneration draws here, AFTER the save batch, exactly the table's draw
/// order (:6170). Returns `(unsaved, landed)`: the tally credit is the
/// PRE-Regeneration unsaved count (`_solo_retaliate_credit += rw`,
/// main.gd:6171), the landing is the post-Regeneration one.
pub fn retaliate_saves_with_tray(
    hits: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> (i64, i64) {
    if hits <= 0 {
        return (0, 0);
    }
    let save_def = shielded_defense(def.defense, def.shielded);
    let mut sub = ShootResult::default();
    let unsaved =
        save_batch(&ShootProfile::default(), def, def_owner, hits, save_def, 0, false, false, 1, tray, &mut sub);
    rolls.extend(sub.rolls);
    let landed = regen_batch(unsaved, def, def_owner, tray, rolls);
    (unsaved, landed)
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
    let base = thrust_to_hit(reliable_quality(att.quality, p.reliable), charging && (p.thrust || att.thrust_grant));
    // B2b: the melee half of `_solo_hit_mod_info` (:5637-5638) sums the same
    // two live nets into `mm` before the single clamp below.
    let mut m = melee_hit_modifier(def.evasive, def.melee_evasion) + uf_hit + att.hit_mod
        + def.vs_hit_mod;
    // Block C2 — the melee branch's Shot Modifier loop (main.gd:5658-5668):
    // `melee_only` names on every strike, `when: "charge"` names only on one.
    // Stamped per NAME in `ctx_for` (`melee_hit_bonus*`), never via the shared
    // primitive. Inside the Unstoppable clamp below, like the table's, whose
    // clamp reads `p_mod.mod + uf_hit` with the bonuses already in `p_mod`
    // (main.gd:6043-6045).
    m += att.melee_hit_bonus;
    if charging {
        m += att.melee_hit_bonus_charge;
    }
    // Wave 3 — the all-attacks Grounded Precision reaches melee too
    // (main.gd:5698-5713's coverage wave), gated on the core's own cover
    // read (Ctx::in_cover), inside the same Unstoppable clamp as the C2
    // bonuses above.
    m += grounded_precision_mod(att);
    if p.unstoppable && m < 0 {
        m = 0;
    }
    modified_hit_target(base, m)
}

/// Mobile Artillery's volley leg (main.gd:5773-5779): +N to hit strictly
/// past the entry's own `over_in`, only while the shooter has NOT moved this
/// round — Ctx::moved_this_round, the act-scope `moved` flag sim.rs stamps
/// over the template at its volley site (the twin of the table's
/// `moved_round == current_round` stamp, main.gd:7650).
fn mobile_artillery_mod(att: &Ctx, mod_dist_in: f64) -> i64 {
    if att.mobile_artillery_hit != 0
        && !att.moved_this_round
        && mod_dist_in > att.mobile_artillery_over_in
    {
        att.mobile_artillery_hit
    } else {
        0
    }
}

/// Grounded Precision's leg (main.gd:5710/:5771): +N on every attack while
/// the attacker stands in terrain (Ctx::in_cover — the core's own cover
/// read, the centre-probe stand-in for the table's majority-of-models gate,
/// `_solo_majority_in_cover` main.gd:7065-7083). 0 = silent.
fn grounded_precision_mod(att: &Ctx) -> i64 {
    if att.grounded_precision_hit != 0 && att.in_cover {
        att.grounded_precision_hit
    } else {
        0
    }
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
/// unmodified-6 bonus hits on the charge, Surge and its block-B6 extra-ATTACK-
/// DIE siblings (Predator Fighter et al., `surge_attack_hits`), Sergeant, Blast,
/// the Rending/Destructive/on-6 AP sub-batch, Thrust's charge AP, Bane's
/// re-roll, Shred, the pooled Deadly multiplier and every Regeneration roll in
/// its place.
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
///      half (:6076), vs-target Marks, Takedown's unit-of-[1] pick, its melee
///      bonus group ("Takedown Strike", main.gd:6032-6034 — see the shooting
///      leg's NEEDS PRIMITIVE note above: no once-per-game ledger to spend it
///      through) and Limited's once-per-game ledger.
///   5. Guarded / Versatile Defense's charged-from-over-9" +1 Defense (:5948)
///      and the Shred Boost's charge half (the widened 1-2 window "when it
///      charges enemies over 9" away"): the port never measured a pre-charge
///      gap — melee resolves the base 1s window only. The shooting half of
///      the Boost IS ported (the volley's `shred_boost_dice` gate), the
///      table's own Surge-Boost precedent is shooting-only too.
pub fn resolve_melee_with_tray(
    strikers: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    charging: bool,
    cond_ap_dice: bool,
    shred_alias_dice: bool,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    // Wave 3 — the Shielded-family alias's rules-must-log flag, the volley
    // fold's melee twin (Shielded is the whole melee Defense ladder here).
    let mut shielded_alias_fired = false;
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
    // Wave 3 — Grounded Precision's melee half names itself once per member
    // (rules-must-log, the volley's own flag shape).
    let mut gp_fired: Vec<(&str, i64)> = Vec::new();
    // Wave 4 — the evasive Boosts' once-per-melee rules-must-log flag.
    let mut evasive_boost_fired = false;
    for sh in strikers {
        let gp = grounded_precision_mod(sh.att);
        if gp != 0 && gp_fired.iter().all(|(o, _)| *o != sh.owner) {
            gp_fired.push((sh.owner, gp));
        }
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
            // Wave 4 — the unconditional -1 rode this strike's to-hit sum.
            evasive_boost_fired |= def.evasive_alias;
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
            // Block B6 — the extra-ATTACK-DIE Surge siblings (Predator Fighter
            // is melee-only, so this is the branch it actually fires on).
            hits += surge_attack_hits(p, &faces, count_target, sh.owner, tray, &mut out.rolls);
            // Wave 2 — a granted "Primal Boost", the same low-surge form.
            if sh.att.surge_grant {
                hits += surge_attack_hits(&primal_boost_grant_profile(), &faces, count_target, sh.owner, tray, &mut out.rolls);
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
            } else if p.rending || p.destructive || sh.att.rending_grant {
                RENDING_AP_BONUS
            } else {
                0
            };
            let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
            // Melee reads neither Cover nor Guarded (`profile_ev` keeps both on
            // the shooting side); Shielded is the whole Defense ladder here.
            let save_def = shielded_defense(def.defense, def.shielded);
            shielded_alias_fired |= def.shielded && def.shielded_alias != ShieldedAlias::None;
            // Block B7 — Piercing Growth's AP delta, melee half (see the
            // shooting site's own note above).
            let mut ap = p.ap + uf_ap + sh.att.growth_ap_mod
                + if charging && (p.thrust || sh.att.thrust_grant) { THRUST_AP_BONUS } else { 0 }
                + if sh.att.pierce_melee_grant { 1 } else { 0 };
            // Rung I — the melee half of the same `cond_ap` fold, same
            // `Knobs::cond_ap_dice` gate as the shooting half. Real `charging`
            // is already this function's own parameter (unlike `profile_ev`'s
            // EV call, which is structurally stuck at `false`), so
            // `on_charge`/`vs_tough_ge` gates fire correctly here.
            if cond_ap_dice {
                for c in &p.cond_ap {
                    let d = conditional_ap_bonus(c, def.tough.max(1), def.defense, charging, 0.0, true);
                    ap += d;
                    // Rules-must-log, the melee half: only the wave-3 NAMED
                    // forms log; unnamed specs stay silent (old replays).
                    if d > 0 && !c.name.is_empty() {
                        out.log.push(format!("{}: AP(+{}) on {}'s strike", c.name, d, sh.owner));
                    }
                }
                // Wave 2 — the Slayer mark and Piercing Assault on their
                // granted legs, the same ladder the weapon-stamped conds ride.
                if sh.att.slayer_grant {
                    ap += conditional_ap_bonus(&slayer_grant_cond(), def.tough.max(1), def.defense, charging, 0.0, true);
                }
                if sh.att.pierce_assault_grant {
                    ap += conditional_ap_bonus(&piercing_assault_grant_cond(), def.tough.max(1), def.defense, charging, 0.0, true);
                }
            }
            // 1 = the base shred window — melee NEVER widens: the Shred
            // Boost's charge half needs a pre-charge gap this port never
            // measured (see the NOT-PORTED list on resolve_melee_with_tray).
            let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, sh.att.shred_grant, shred_alias_dice, 1, tray, &mut out);
            w += save_batch(p, def, def_owner, hits - ap4, save_def, ap, sh.att.shred_grant, shred_alias_dice, 1, tray, &mut out);
            if p.deadly > 0 {
                out.mark("deadly");
            }
            if p.bane || p.rending || p.unstoppable || sh.att.rending_grant || sh.att.unstoppable_grant {
                regen_proof += w;
            } else {
                regenable += w;
            }
        }
    }
    for (owner, hit) in &gp_fired {
        out.log.push(format!("Grounded Precision: {owner} — {hit:+} to hit (in terrain)"));
    }
    // Wave 4 — the Boost's rules-must-log line, once per melee resolve.
    if evasive_boost_fired {
        out.log.push(format!(
            "{}: {def_owner} — attackers get -1 to hit (always)",
            def.evasive_alias_name
        ));
    }
    if shielded_alias_fired {
        out.log.push(format!(
            "{}: {def_owner} — +1 to defense rolls (saves on {}+)",
            def.shielded_alias.name(),
            shielded_defense(def.defense, true)
        ));
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
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded), ap, false, false, 1, tray, &mut out);
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
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded), ap, false, false, 1, tray, &mut out);
    out.caused = w;
    out.wounds = regen_batch(w, def, def_owner, tray, &mut out.rolls);
    out
}

/// The Storm Attack family's payload (wave 3): `hits` direct hits landed as
/// ONE save batch carrying the burst's keyword facet — Bane's six-re-roll and
/// Shred's save-fail +1 through the same `save_batch` legs every ported Bane/
/// Shred carrier rides, AP(1) as the batch's own AP. Bane's wounds cut through
/// Regeneration (`_solo_ignores_regen`, the volley tail's own ladder at the
/// `p.bane` arm above), the other facets land regenerable. The table twin is
/// `_solo_apply_storm_attack`'s `_solo_save_batch` call (main.gd:17287).
pub fn resolve_storm_hits_with_tray(
    hits: i64, ap: i64, bane: bool, shred_grant: bool, def: &Ctx, def_owner: &str, tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 { return out; }
    let bare = ShootProfile { ap, bane, ..Default::default() };
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded), ap, shred_grant, false, 1, tray, &mut out);
    out.caused = w;
    out.wounds = if bane { w } else { regen_batch(w, def, def_owner, tray, &mut out.rolls) };
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
#[path = "tests/dice/mod.rs"]
mod tests;
