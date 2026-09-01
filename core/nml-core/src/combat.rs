//! `AiCombatMath` (scripts/solo/ai_combat_math.gd) scalar helpers and the
//! `AiEv` expected-value core (scripts/solo/ai_ev.gd) — shooting AND melee.
//!
//! The melee half (`AiEv.melee_ev` :485-495, `impact_ev` :512-529, `ravage_ev`
//! :497-505 and the melee branch of `profile_ev` :330-350) arrived with M1-3;
//! `resolve()` reaches it only on a CHARGE (battle_sim.gd:631-646).

use crate::unit::{CondAp, Ctx, ShootProfile};

/// `AiEv.SIX_P` ai_ev.gd:27 — P(one specific d6 face).
pub const SIX_P: f64 = 1.0 / 6.0;
/// `AiCombatMath.BEST_HIT_TARGET` :56.
pub const BEST_HIT_TARGET: i64 = 2;
/// `AiCombatMath.UNMODIFIED_SIX` :21.
pub const UNMODIFIED_SIX: i64 = 6;
/// `AiCombatMath.LONG_RANGE_IN` :60 — the over-9" gate of Stealth/Artillery/
/// Relentless/Guarded/Versatile Attack.
pub const LONG_RANGE_IN: f64 = 9.0;
/// `AiCombatMath.STEALTH_HIT_PENALTY` :64 / `ARTILLERY_SHOOTER_HIT_BONUS` :68 /
/// `ARTILLERY_TARGET_HIT_PENALTY` :72 / `EVASIVE_HIT_PENALTY` :77.
pub const STEALTH_HIT_PENALTY: i64 = 1;
pub const ARTILLERY_SHOOTER_HIT_BONUS: i64 = 1;
pub const ARTILLERY_TARGET_HIT_PENALTY: i64 = 2;
pub const EVASIVE_HIT_PENALTY: i64 = 1;
/// `AiCombatMath.SHIELDED_DEFENSE_BONUS` :82.
pub const SHIELDED_DEFENSE_BONUS: i64 = 1;
/// `AiCombatMath.RENDING_AP_BONUS` :45.
pub const RENDING_AP_BONUS: i64 = 4;
/// `AiCombatMath.THRUST_TO_HIT_BONUS` :52 — a charging Thrust weapon's +1 to hit.
pub const THRUST_TO_HIT_BONUS: i64 = 1;
/// `AiCombatMath.IMPACT_HIT_TARGET` :25 — Impact dice hit on 2+.
pub const IMPACT_HIT_TARGET: i64 = 2;
/// `AiCombatMath.RAVAGE_WOUND_TARGET` :284 — a Ravage die wounds on a 6.
pub const RAVAGE_WOUND_TARGET: i64 = 6;
/// `AiCombatMath.SHROUD_RANGE_PENALTY_IN` :297 / `SHROUD_FLOOR_IN` :299.
pub const SHROUD_RANGE_PENALTY_IN: f64 = 6.0;
pub const SHROUD_FLOOR_IN: f64 = 6.0;
/// `AiCombatMath.SHROUD_CHARGE_PENALTY_IN` :298 — the CHARGE-band twin of
/// `SHROUD_RANGE_PENALTY_IN`, read by `SoloController.melee_shroud_charge_in`.
pub const SHROUD_CHARGE_PENALTY_IN: f64 = 3.0;
/// `AiCombatMath.THRUST_AP_BONUS` :53 — a charging Thrust weapon's AP(+1).
pub const THRUST_AP_BONUS: i64 = 1;
/// `RulesRegistry.unit_param(charger, "Heavy Impact", "ap", 1)` main.gd:6297 —
/// the AP of a Heavy Impact hit where the book fields no value of its own.
pub const HEAVY_IMPACT_AP: i64 = 1;
/// `AiCombatMath.FEARLESS_RECOVER_TARGET` :29 — a FAILED morale test rolls a
/// recovery die once and counts as passed on a 4+.
pub const FEARLESS_RECOVER_TARGET: i64 = 4;
/// `AiCombatMath.NO_RETREAT_SELF_WOUND_MAX` :41 — a No Retreat die of 1-3 is one
/// self-wound, so the SUCCESS target the tray records is `MAX + 1`: the tray
/// highlights the harmless faces (main.gd:8365).
pub const NO_RETREAT_SELF_WOUND_MAX: i64 = 3;
/// `AiCombatMath.BANNER_MORALE_BONUS` :106.
pub const BANNER_MORALE_BONUS: i64 = 1;
/// `AiEv.REGENERATION_TARGET` ai_ev.gd:41 / `SELF_REPAIR_TARGET` :45.
pub const REGENERATION_TARGET: i64 = 5;
pub const SELF_REPAIR_TARGET: i64 = 6;

#[inline]
fn clampi(v: i64, lo: i64, hi: i64) -> i64 {
    v.max(lo).min(hi)
}

/// `AiCombatMath.success_chance` :145-146 — bounded to [1/6, 5/6]: a 6 always
/// succeeds and a 1 always fails.
#[inline]
pub fn success_chance(target: i64) -> f64 {
    (7 - clampi(target, 2, 6)) as f64 / 6.0
}

/// `AiCombatMath.save_target` :127-128.
#[inline]
pub fn save_target(defense: i64, ap: i64) -> i64 {
    defense + ap.max(0)
}

/// `AiCombatMath.modified_hit_target` :222-223 — "+1 to hit" lowers the target.
#[inline]
pub fn modified_hit_target(base_target: i64, roll_mod: i64) -> i64 {
    clampi(base_target - roll_mod, BEST_HIT_TARGET, UNMODIFIED_SIX)
}

/// `AiCombatMath.shooting_hit_modifier` :230-243 — exactly 9" is not "over".
/// `shot_hit_bonus`/`shot_hit_bonus_over9` are NOT part of that GDScript
/// function; they are `_solo_hit_mod_info`'s own addition on top of it
/// (main.gd:5681-5701 — Good Shot / Bad Shot / Targeting Visor), folded in
/// here so the EV and tray callers below share one gated sum instead of each
/// re-deriving the over-9" test. `stealth_alias_penalty`/`stealth_alias_over_in`
/// are that SAME function's Stealth DATA-ALIAS leg (main.gd:5588-5610,
/// 5698-5701 — Changebound et al.): "at most one" penalty, so the alias is
/// skipped whenever the literal Stealth flag already fired over 9" — no
/// double-dip, exactly the table's `not (stealth and over_nine)` guard.
#[inline]
pub fn shooting_hit_modifier(
    dist_in: f64,
    attacker_artillery: bool,
    target_stealth: bool,
    target_artillery: bool,
    target_evasive: bool,
    shot_hit_bonus: i64,
    shot_hit_bonus_over9: i64,
    stealth_alias_penalty: i64,
    stealth_alias_over_in: f64,
) -> i64 {
    let mut m = 0;
    let over_nine = dist_in > LONG_RANGE_IN;
    if over_nine {
        if attacker_artillery {
            m += ARTILLERY_SHOOTER_HIT_BONUS;
        }
        if target_stealth {
            m -= STEALTH_HIT_PENALTY;
        }
        if target_artillery {
            m -= ARTILLERY_TARGET_HIT_PENALTY;
        }
        m += shot_hit_bonus_over9;
    }
    if stealth_alias_penalty > 0
        && !(target_stealth && over_nine)
        && (stealth_alias_over_in <= 0.0 || dist_in > stealth_alias_over_in)
    {
        m -= stealth_alias_penalty;
    }
    if target_evasive {
        m -= EVASIVE_HIT_PENALTY;
    }
    m + shot_hit_bonus
}

/// `AiCombatMath.shielded_defense` :254-255 / `covered_defense` :261-262 /
/// `guarded_defense` :276-277 — all three are the same floored -1.
#[inline]
pub fn shielded_defense(defense: i64, is_shielded: bool) -> i64 {
    if is_shielded {
        (defense - SHIELDED_DEFENSE_BONUS).max(BEST_HIT_TARGET)
    } else {
        defense
    }
}

#[inline]
pub fn covered_defense(defense: i64, in_cover: bool) -> i64 {
    if in_cover {
        (defense - 1).max(BEST_HIT_TARGET)
    } else {
        defense
    }
}

#[inline]
pub fn guarded_defense(defense: i64, applies: bool) -> i64 {
    if applies {
        (defense - 1).max(BEST_HIT_TARGET)
    } else {
        defense
    }
}

/// `AiCombatMath.fortified_ap` :268-269.
#[inline]
pub fn fortified_ap(ap: i64, is_fortified: bool) -> i64 {
    if is_fortified {
        (ap - 1).max(0)
    } else {
        ap
    }
}

/// `AiCombatMath.thrust_to_hit` :215-216 — Thrust's +1 to hit while charging,
/// floored at 2+. Fatigue is handled by the caller (a fatigued unit hits only
/// on unmodified 6s, so no modifier applies then).
#[inline]
pub fn thrust_to_hit(quality: i64, is_charging: bool) -> i64 {
    if is_charging {
        (quality - THRUST_TO_HIT_BONUS).max(BEST_HIT_TARGET)
    } else {
        quality
    }
}

/// `AiCombatMath.melee_hit_modifier` :248-249 — Evasive OR Melee Evasion costs
/// the striker 1 to hit; the two never stack.
#[inline]
pub fn melee_hit_modifier(target_evasive: bool, target_melee_evasion: bool) -> i64 {
    if target_evasive || target_melee_evasion {
        -EVASIVE_HIT_PENALTY
    } else {
        0
    }
}

/// `AiCombatMath.impact_total_dice` :309-310.
#[inline]
pub fn impact_total_dice(impact_x: i64, charging_models: i64, counter_models: i64) -> i64 {
    (impact_x.max(0) * charging_models.max(0) - counter_models.max(0)).max(0)
}

/// `AiCombatMath.reliable_quality` :379-380.
#[inline]
pub fn reliable_quality(quality: i64, is_reliable: bool) -> i64 {
    if is_reliable {
        quality.min(2)
    } else {
        quality
    }
}

/// `AiCombatMath.deadly_multiplier` :396-398.
#[inline]
pub fn deadly_multiplier(deadly_x: i64, target_tough: i64) -> i64 {
    clampi(deadly_x, 1, target_tough.max(1))
}

/// `AiCombatMath.shrouded_reach` :300-303.
#[inline]
pub fn shrouded_reach(reach_in: f64, penalty_in: f64, floor_in: f64) -> f64 {
    if reach_in <= floor_in {
        reach_in
    } else {
        (reach_in - penalty_in).max(floor_in)
    }
}

/// `AiCombatMath.armored_defense` :501-504.
#[inline]
pub fn armored_defense(defense: i64, armor_x: i64) -> i64 {
    if armor_x < BEST_HIT_TARGET {
        defense
    } else {
        defense.min(armor_x)
    }
}

/// `AiCombatMath.morale_target` :511-512.
#[inline]
pub fn morale_target(quality: i64, morale_bonus: i64) -> i64 {
    clampi(quality - morale_bonus, BEST_HIT_TARGET, UNMODIFIED_SIX)
}

/// `AiCombatMath.at_or_below_half` :524-527.
#[inline]
pub fn at_or_below_half(alive: i64, total: i64) -> bool {
    if total <= 0 {
        return true;
    }
    alive * 2 <= total
}

/// `AiCombatMath.should_test_shooting_morale` :542-545.
#[inline]
pub fn should_test_shooting_morale(alive_before: i64, alive_now: i64, total: i64) -> bool {
    if alive_now <= 0 || alive_now >= alive_before {
        return false;
    }
    at_or_below_half(alive_now, total)
}

/// `SoloController.effective_attacks` solo_controller.gd:7147-7150 — dead models
/// stop attacking. `round()` is GDScript's half-away-from-zero rounding.
#[inline]
pub fn effective_attacks(base_attacks: i64, alive: i64, max_models: i64) -> i64 {
    if max_models <= 0 {
        return base_attacks;
    }
    let v = (base_attacks as f64) * (alive as f64) / (max_models as f64);
    (gd_round(v) as i64).max(0)
}

/// Godot's `round()`: half away from zero, which is what Rust's `f64::round` does.
#[inline]
fn gd_round(v: f64) -> f64 {
    v.round()
}

/// `AiEv.block_chance` ai_ev.gd:441-446 — one save die at Defense+AP; Bane
/// re-rolls the defender's unmodified 6s once.
#[inline]
pub fn block_chance(defense: i64, ap: i64, bane: bool) -> f64 {
    let mut p = success_chance(save_target(defense, ap));
    if bane {
        p = (p - SIX_P) + SIX_P * p;
    }
    p.clamp(0.0, 1.0)
}

/// `AiEv.versatile_best_mode` ai_ev.gd:454-462 — returns (hit_mod, ap).
#[inline]
pub fn versatile_best_mode(hit_target: i64, defense: i64, ap: i64, bane: bool) -> (i64, i64) {
    let ev_hit = success_chance(modified_hit_target(hit_target, 1)) * (1.0 - block_chance(defense, ap, bane));
    let ev_ap = success_chance(hit_target) * (1.0 - block_chance(defense, ap + 1, bane));
    if ev_ap >= ev_hit {
        (0, 1)
    } else {
        (1, 0)
    }
}

/// `AiCombatMath.conditional_ap_bonus` ai_combat_math.gd:410-437 — the extra AP
/// one conditional-AP rule grants against THIS defender. Four conditions carry a
/// bonus and every other spelling returns 0, exactly like the GDScript `match`:
///   * `vs_tough_ge`  Shatter / Tear / Slayer / Melee Slayer — target Tough >= threshold
///   * `vs_armor`     Disintegrate — target Defense <= threshold (a BETTER save)
///   * `on_charge`    Piercing Assault — charging only
///   * `ranged_over`  Piercing Hunter — shooting from beyond `over_in`
/// `charge_only` is an extra gate on top of the condition (Melee Slayer), and the
/// `ranged_over_or_charge` GATE (Slayer) adds "charging OR shot from over 9 in".
/// `dist_in < 0` means the caller has no range context: the ranged legs stay shut.
pub fn conditional_ap_bonus(
    c: &CondAp,
    target_tough: i64,
    target_defense: i64,
    is_charging: bool,
    dist_in: f64,
    melee: bool,
) -> i64 {
    if c.ap_bonus <= 0 {
        return 0;
    }
    if c.charge_only && !is_charging {
        return 0;
    }
    if c.gate == "ranged_over_or_charge" && !(is_charging || (!melee && dist_in > c.over_in)) {
        return 0;
    }
    match c.condition.as_str() {
        "vs_tough_ge" if target_tough >= c.threshold => c.ap_bonus,
        "vs_armor" if target_defense <= c.threshold => c.ap_bonus,
        "on_charge" if is_charging => c.ap_bonus,
        "ranged_over" if !melee && dist_in > c.over_in => c.ap_bonus,
        _ => 0,
    }
}

/// `AiEv.profile_ev` ai_ev.gd:322-437 — both halves. `melee` is the GDScript's
/// own derivation (`profile.range <= 0`, :330), never a caller's opinion;
/// `charging` only ever reaches it from `melee_ev(.., true)`.
///
/// `attacks` is the survivor-scaled count `BattleSim._profiles_of` writes over
/// the merged profile (battle_sim.gd:738-739), passed in rather than stored so
/// the immutable profile table can be shared across every rollout node.
///
/// Not modelled, and not reachable from this call site (with the GDScript line
/// that would produce it): `spell_hit_mod` (:331 — `_ctx_of` never sets it).
///
/// NML-1103: `cond_ap` (:412) IS modelled now — `BattleSim._profiles_of` stamps
/// it (battle_sim.gd:927), so the twin stamps it too (`unit::stamp_conditional_ap`).
pub fn profile_ev(
    p: &ShootProfile,
    attacks: i64,
    att: &Ctx,
    def: &Ctx,
    dist_in: f64,
    charging: bool,
) -> f64 {
    let attacks_f = attacks.max(0) as f64;
    if attacks_f <= 0.0 {
        return 0.0;
    }
    let melee = p.range <= 0;
    // --- to-hit target (ai_ev.gd:335-357) ---
    let mut target;
    if melee {
        if att.fatigued {
            // Fatigue (p.9): hits ONLY on an unmodified 6 — a hard target
            // OUTSIDE the modifier pipeline (ai_ev.gd:336-341).
            target = 6;
        } else {
            target = thrust_to_hit(att.quality, charging && p.thrust);
            let mut melee_mod = melee_hit_modifier(def.evasive, def.melee_evasion);
            if p.unstoppable && melee_mod < 0 {
                melee_mod = 0;
            }
            target = modified_hit_target(target, melee_mod);
        }
    } else {
        target = reliable_quality(att.quality, p.reliable);
        // ai_ev.gd:352 never reads Shot Modifier (Good Shot / Bad Shot /
        // Targeting Visor) OR the Stealth data-alias family (ai_ev.gd:151's
        // `ctx_for` reads only the literal "Stealth" name too) — the EV
        // imagination stays blind to both, like Mend; only the tray path
        // (dice.rs) supplies non-zero values.
        let mut shoot_mod = shooting_hit_modifier(
            dist_in, att.artillery, def.stealth, def.artillery, def.evasive, 0, 0, 0, 0.0,
        );
        if p.unstoppable && shoot_mod < 0 {
            shoot_mod = 0; // GF v3.5.1 p.15, head wave 1 — clamp BEFORE weapon bonuses.
        }
        target = modified_hit_target(target, shoot_mod);
    }
    // --- Versatile Attack (ai_ev.gd:361-368) ---
    let mut versatile_ap = 0;
    if p.versatile_attack && dist_in > LONG_RANGE_IN && (!melee || charging) {
        let choose_def = shielded_defense(def.defense, def.shielded);
        let (hit_mod, ap_mod) = versatile_best_mode(target, choose_def, p.ap, p.bane);
        versatile_ap = ap_mod;
        target = modified_hit_target(target, hit_mod);
    }
    if p.precise {
        target = modified_hit_target(target, 1);
    }
    let mut hits = attacks_f * success_chance(target);
    // --- per-unmodified-6 bonus hits (ai_ev.gd:373-385) ---
    if !melee && p.relentless && dist_in > LONG_RANGE_IN {
        hits += attacks_f * SIX_P;
    }
    if p.surge {
        hits += attacks_f * SIX_P;
    }
    // Furious: the weapon never carries the flag (`AiShooting._profile` sets no
    // "furious" key), so only the unit-level context can fire it — ai_ev.gd:379.
    if melee && charging && att.furious {
        hits += attacks_f * SIX_P;
    }
    let sergeant_attacks = p.sergeant_attacks.min(attacks_f as i64) as f64;
    if sergeant_attacks > 0.0 {
        hits += sergeant_attacks * SIX_P;
    }
    // --- on-6 AP sub-batch (ai_ev.gd:389-395) ---
    let mut on6_ap = p.on6_ap;
    if on6_ap == 0 && (p.rending || p.destructive) {
        on6_ap = RENDING_AP_BONUS;
    }
    let mut six_hits = if on6_ap > 0 { attacks_f * SIX_P } else { 0.0 };
    // --- Blast (ai_ev.gd:397-400) ---
    if p.blast > 1 {
        hits *= clampi(p.blast, 1, def.models.max(1)) as f64;
    }
    six_hits = six_hits.min(hits);
    // --- saves: Shielded, then Cover, then Guarded (ai_ev.gd:403-411) ---
    // Cover and Guarded are SHOOTING-only reads: melee EV always values at
    // dist 0, so the charge halves of both live in the dice path only.
    let mut defense = shielded_defense(def.defense, def.shielded);
    if !melee && p.blast <= 1 && !p.indirect && !p.ignores_cover {
        defense = covered_defense(defense, def.in_cover);
    }
    if !melee {
        defense = guarded_defense(defense, def.guarded && dist_in > LONG_RANGE_IN);
    }
    // NML-1103 — target-property conditional AP (ai_ev.gd:412-417): Shatter,
    // Tear, Disintegrate, Melee Slayer, Piercing Assault, Piercing Hunter. The
    // `is_charging` argument is the GDScript's `def_ctx.get("charging", false)`
    // and `AiEv.ctx_for` never writes that key, so the charge-gated members are
    // inert in BOTH twins — the table's own EV path has them inert as well.
    // `def.defense` is the RAW context Defense, not the ladder above.
    let mut ap = p.ap + versatile_ap;
    for c in &p.cond_ap {
        ap += conditional_ap_bonus(c, def.tough.max(1), def.defense, false, dist_in, melee);
    }
    let bane = p.bane;
    let fort = def.fortified;
    let mut unsaved = (hits - six_hits) * (1.0 - block_chance(defense, fortified_ap(ap, fort), bane))
        + six_hits * (1.0 - block_chance(defense, fortified_ap(ap + on6_ap, fort), bane));
    // --- Deadly, Shred, Regeneration (ai_ev.gd:423-436) ---
    if p.deadly > 0 {
        unsaved *= deadly_multiplier(p.deadly, def.tough.max(1)) as f64;
    }
    if p.shred {
        unsaved += hits * SIX_P;
    }
    if def.regeneration && !(bane || p.rending || p.unstoppable) {
        unsaved *= 1.0 - success_chance(def.regen_target);
    }
    unsaved
}

/// `AiEv.shoot_ev` ai_ev.gd:468-482 — every ranged profile that REACHES fires;
/// totals are additive, in profile order.
///
/// `keep` indexes `profiles` (the unit's whole merged ranged set) with the
/// entries `BattleSim._profiles_of` would have built for this distance, and
/// `attacks[k]` is the survivor-scaled attack count of `profiles[keep[k]]` —
/// passed in so the immutable profile table is shared, never rebuilt per call.
pub fn shoot_ev(
    profiles: &[ShootProfile],
    keep: &[usize],
    attacks: &[i64],
    att: &Ctx,
    def: &Ctx,
    dist_in: f64,
) -> f64 {
    let mut total = 0.0;
    let shrouded = def.ranged_shrouding;
    let reach_gate = dist_in.ceil();
    for (k, &pi) in keep.iter().enumerate() {
        let p = &profiles[pi];
        let reach = if shrouded {
            shrouded_reach(p.range as f64, SHROUD_RANGE_PENALTY_IN, SHROUD_FLOOR_IN)
        } else {
            p.range as f64
        };
        if reach >= reach_gate && p.range > 0 {
            total += profile_ev(p, attacks[k], att, def, dist_in, false);
        }
    }
    total
}

/// `AiEv.ravage_ev` ai_ev.gd:497-505 — X dice per ALIVE bearer model, each a
/// direct wound on a 6; no hit roll, no save, only Regeneration thins it.
pub fn ravage_ev(att: &Ctx, def: &Ctx) -> f64 {
    let dice = att.ravage * att.models.max(0);
    if dice <= 0 {
        return 0.0;
    }
    let mut wounds = dice as f64 * success_chance(RAVAGE_WOUND_TARGET);
    if def.regeneration {
        wounds *= 1.0 - success_chance(def.regen_target);
    }
    wounds
}

/// `AiEv.impact_ev` ai_ev.gd:512-529 — the charge's Impact pool (2+ to hit, no
/// AP) plus the Heavy Impact pool (saves at AP(1)); the defender's Counter
/// models strip the HEAVY dice first, defender-optimal.
///
/// `counter_models` is always 0 in the sim: `BattleSim._ctx_of` calls
/// `AiEv.ctx_for(unit, in_cover)` and leaves the third argument at its default
/// (battle_sim.gd:702, ai_ev.gd:135). Modelled anyway so the function is the
/// GDScript's, not a specialisation of it.
pub fn impact_ev(att: &Ctx, def: &Ctx) -> f64 {
    let models = att.models.max(0);
    let counter = def.counter_models;
    let heavy_raw = att.heavy_impact * models;
    let heavy_cut = counter.min(heavy_raw);
    let heavy_dice = heavy_raw - heavy_cut;
    let dice = impact_total_dice(att.impact, models, counter - heavy_cut);
    if dice + heavy_dice <= 0 {
        return 0.0;
    }
    let p_hit = success_chance(IMPACT_HIT_TARGET);
    let defense = shielded_defense(def.defense, def.shielded);
    let mut wounds = dice as f64 * p_hit * (1.0 - block_chance(defense, 0, false))
        + heavy_dice as f64 * p_hit * (1.0 - block_chance(defense, 1, false));
    if def.regeneration {
        wounds *= 1.0 - success_chance(def.regen_target);
    }
    wounds
}

/// `AiEv.melee_ev` ai_ev.gd:485-495 — every melee profile strikes (profile
/// order, additive), then the charge's Impact hits, then Ravage.
///
/// `profiles` is the unit's whole merged MELEE set and `attacks[k]` the
/// survivor-scaled count of `profiles[k]` — the same split as `shoot_ev`, minus
/// the range filter (every melee profile is range 0, so all of them strike).
pub fn melee_ev(
    profiles: &[ShootProfile],
    attacks: &[i64],
    att: &Ctx,
    def: &Ctx,
    charging: bool,
) -> f64 {
    let mut total = 0.0;
    for (k, p) in profiles.iter().enumerate() {
        if p.range <= 0 {
            total += profile_ev(p, attacks[k], att, def, 0.0, charging);
        }
    }
    if charging {
        total += impact_ev(att, def);
    }
    total += ravage_ev(att, def); // every melee turn, not just charges
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scalar_helpers_match_the_book_values() {
        assert_eq!(success_chance(4), 0.5);
        assert_eq!(success_chance(1), 5.0 / 6.0, "a 1 always fails -> clamped to 2+");
        assert_eq!(success_chance(9), 1.0 / 6.0, "a 6 always succeeds -> clamped to 6+");
        assert_eq!(modified_hit_target(4, 1), 3);
        assert_eq!(modified_hit_target(2, 3), 2, "floored at 2+");
        assert_eq!(reliable_quality(5, true), 2);
        assert_eq!(deadly_multiplier(3, 1), 1, "no Tough -> one wound");
        assert_eq!(effective_attacks(10, 5, 10), 5);
        assert_eq!(effective_attacks(3, 1, 2), 2, "1.5 rounds away from zero");
        assert!(at_or_below_half(2, 4));
        assert!(!at_or_below_half(3, 4));
    }

    #[test]
    fn bane_forces_the_defender_to_re_roll_its_sixes() {
        // Bane re-rolls the defender's unmodified 6s, so it LOWERS the block
        // chance: P = P(2..5 blocks) + P(6) x P(the re-roll blocks).
        let plain = block_chance(4, 0, false);
        let baned = block_chance(4, 0, true);
        assert!((plain - 0.5).abs() < 1e-15);
        assert!((baned - (0.5 - SIX_P + SIX_P * 0.5)).abs() < 1e-15);
        assert!(baned < plain, "a re-rolled 6 blocks only half the time");
    }

    /// NML-1103, the twin of `parity_w1_cent_fixes_test.gd`
    /// `test_conditional_ap_reaches_sim_profiles_and_moves_the_ev` — the SAME
    /// fixture numbers: a Blade (melee, 2 attacks, AP 0) of a Quality 4 striker
    /// against 3 models of Tough 1, once at Defense 3+ and once at Defense 5+.
    /// Disintegrate is `{"condition": "vs_armor", "threshold": 3, "ap_bonus": 2}`
    /// (assets/solo/rules_mechanics_gf.json, blessed_sisters).
    #[test]
    fn disintegrate_raises_the_ev_against_armour_and_only_against_armour() {
        let disintegrate = CondAp {
            ap_bonus: 2,
            condition: "vs_armor".into(),
            threshold: 3,
            over_in: LONG_RANGE_IN,
            ..Default::default()
        };
        let plain = ShootProfile {
            attacks: 2,
            ..Default::default()
        };
        let armed = ShootProfile {
            cond_ap: vec![disintegrate],
            ..plain.clone()
        };
        let att = Ctx {
            quality: 4,
            models: 3,
            tough: 1,
            ..Default::default()
        };
        let hard = Ctx {
            quality: 4,
            defense: 3,
            tough: 1,
            models: 3,
            ..Default::default()
        };
        let soft = Ctx { defense: 5, ..hard };
        // RED before the stamp: `cond_ap` was never filled, so both were equal.
        assert!(
            profile_ev(&armed, 2, &att, &hard, 0.0, false)
                > profile_ev(&plain, 2, &att, &hard, 0.0, false),
            "AP(+2) against a Defense 3+ save must raise the expected wounds"
        );
        // The condition gates it: a Defense 5+ target is outside the threshold.
        assert_eq!(
            profile_ev(&armed, 2, &att, &soft, 0.0, false),
            profile_ev(&plain, 2, &att, &soft, 0.0, false),
            "vs_armor(3) must not fire against Defense 5+"
        );
    }

    /// The four conditions and the two extra gates, straight off
    /// `ai_combat_math.gd:410-437` — including the two the GDScript `match`
    /// answers with 0 (`ranged`, `in_melee`), which are printed rules the shared
    /// arithmetic has never implemented on either side.
    #[test]
    fn conditional_ap_bonus_matches_the_gdscript_match() {
        let spec = |cond: &str, gate: &str, charge_only: bool, threshold: i64| CondAp {
            ap_bonus: 2,
            charge_only,
            gate: gate.into(),
            over_in: LONG_RANGE_IN,
            condition: cond.into(),
            threshold,
        };
        // Shatter / Tear: vs_tough_ge, no gate.
        let shatter = spec("vs_tough_ge", "", false, 3);
        assert_eq!(conditional_ap_bonus(&shatter, 3, 4, false, 0.0, true), 2);
        assert_eq!(conditional_ap_bonus(&shatter, 2, 4, false, 0.0, true), 0);
        // Melee Slayer: the same condition behind `charge_only`.
        let melee_slayer = spec("vs_tough_ge", "", true, 3);
        assert_eq!(conditional_ap_bonus(&melee_slayer, 3, 4, false, 0.0, true), 0);
        assert_eq!(conditional_ap_bonus(&melee_slayer, 3, 4, true, 0.0, true), 2);
        // Piercing Assault: charge only, no target property.
        let assault = spec("on_charge", "", false, 0);
        assert_eq!(conditional_ap_bonus(&assault, 1, 6, true, 0.0, true), 2);
        assert_eq!(conditional_ap_bonus(&assault, 1, 6, false, 0.0, true), 0);
        // Piercing Hunter: shooting from beyond 9 in; a melee call never fires,
        // and an unknown distance (-1) keeps the ranged leg shut.
        let hunter = spec("ranged_over", "", false, 0);
        assert_eq!(conditional_ap_bonus(&hunter, 1, 6, false, 12.0, false), 2);
        assert_eq!(conditional_ap_bonus(&hunter, 1, 6, false, 6.0, false), 0);
        assert_eq!(conditional_ap_bonus(&hunter, 1, 6, false, -1.0, true), 0);
        // Slayer: vs_tough_ge behind the `ranged_over_or_charge` gate.
        let slayer = spec("vs_tough_ge", "ranged_over_or_charge", false, 3);
        assert_eq!(conditional_ap_bonus(&slayer, 3, 4, false, 12.0, false), 2);
        assert_eq!(conditional_ap_bonus(&slayer, 3, 4, true, 0.0, true), 2);
        assert_eq!(conditional_ap_bonus(&slayer, 3, 4, false, 4.0, false), 0);
        // Unimplemented spellings answer 0 on both sides.
        assert_eq!(conditional_ap_bonus(&spec("ranged", "", false, 0), 9, 2, true, 30.0, false), 0);
        assert_eq!(conditional_ap_bonus(&spec("in_melee", "", false, 0), 9, 2, true, 0.0, true), 0);
    }

    /// Block B4: ai_ev.gd:352's shooting branch never reads Good Shot / Bad
    /// Shot / Targeting Visor — the EV imagination stays blind to Shot
    /// Modifier, like Mend. A stamped `ShootProfile.hit_bonus`/`hit_bonus_over9`
    /// must not move `profile_ev`'s number; only the tray path (dice.rs) reads
    /// them.
    #[test]
    fn shot_modifier_never_reaches_the_ev_planner() {
        let att = Ctx { quality: 4, models: 1, ..Default::default() };
        let def = Ctx { defense: 4, models: 5, tough: 1, ..Default::default() };
        let plain = ShootProfile { attacks: 6, range: 24, ..Default::default() };
        let with_bonus = ShootProfile { hit_bonus: 1, hit_bonus_over9: 1, ..plain.clone() };
        assert_eq!(
            profile_ev(&plain, 6, &att, &def, 12.0, false),
            profile_ev(&with_bonus, 6, &att, &def, 12.0, false),
            "the EV planner must stay blind to Shot Modifier, like the table's own AiEv"
        );
    }
}
