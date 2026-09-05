//! The per-unit STATIC layer: everything `resolve`/`reply_threat` read off a
//! live `GameUnit`, resolved once per game.
//!
//! Four GDScript functions are folded in here, in their original order:
//!   * `AiShooting.profiles_in_range` ai_shooting.gd:14-26 + `merge_identical`
//!     :63-77 + `_profile` :90-152 — the ranged weapon profiles;
//!   * `AiShooting.melee_profiles` :44-56 — the same shape at range 0, minus the
//!     Strafing filter, which lives in `profiles_in_range` alone;
//!   * `AiEv.stamp_sergeant` ai_ev.gd:203-274 — the registry-driven facets;
//!   * `AiEv.ctx_for` ai_ev.gd:135-165 + `_regen_target` :171-177 — the context.
//!
//! Merge-then-stamp is load-bearing, not convenience: `Devout` stamps `surge`
//! onto EVERY profile, so stamping first would let a Surge weapon and a plain
//! one collapse into one merged line that GDScript keeps apart (the merge
//! signature ai_shooting.gd:81-89 is taken before any stamping).
//!
//! Range filtering commutes with the merge — every member of a merge group has
//! the same `range` (it is part of the signature) — so the whole ranged set is
//! merged once here and filtered per call.

use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::acts::{
    rule_on, EPOCH_3_TABLE_RULES, EPOCH_4_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES,
};
use crate::combat::{
    armored_defense, BANNER_MORALE_BONUS, LONG_RANGE_IN, REGENERATION_TARGET, RESISTANCE_TARGET,
    RESISTANCE_TARGET_SPELL, SELF_REPAIR_TARGET, SHROUD_CHARGE_PENALTY_IN, SHROUD_FLOOR_IN,
    SHROUD_RANGE_PENALTY_IN,
};
use crate::rules::{
    base_rule_name, has_special_rule, rule_rating, unit_rating, Registries, Spell,
};
use crate::state::{Bands, Profile, Profiles, Weapon};

/// `AiEv` unit context — `ctx_for`'s dictionary as a struct. `models`,
/// `in_cover` and `fatigued` are the DYNAMIC three `BattleSim._ctx_of`
/// (battle_sim.gd:701-712) writes over the template per call.
#[derive(Debug, Clone, Copy, Default)]
pub struct Ctx {
    pub quality: i64,
    pub defense: i64,
    pub morale_bonus: i64,
    pub tough: i64,
    pub models: i64,
    pub artillery: bool,
    pub furious: bool,
    pub fearless: bool,
    /// `Fear(X)` — the melee WINNER comparison and nothing else
    /// (`AiCombatMath.fear_adjusted_wounds` :338, main.gd:8110-8112). It never
    /// changes a wound applied, only which side ends up testing morale, so
    /// both the D1 dice path (`tray_charge`) and the EV path
    /// (`expected_melee_morale`) ask who won and both need it.
    pub fear: i64,
    /// `main._solo_unpredictable_rule(striker, true)` :5414-5418 — the melee
    /// form of the Unpredictable die, EITHER variant: the melee-only
    /// "Unpredictable Fighter" on all models, or the generic army-book
    /// "Unpredictable" (exact rule AND registry-active). One die per melee
    /// phase, before any strike.
    pub unpredictable: bool,
    /// `main._solo_unpredictable_rule(striker, false)` :5403-5412 — the
    /// SHOOTING leg of the same die: the generic army-book "Unpredictable"
    /// (exact rule AND registry-active) OR the shooting-only alias
    /// "Unpredictable Shooter" (same gates). The melee-only "Unpredictable
    /// Fighter" NEVER reaches this flag. One die per volley, before any
    /// weapon fires (main.gd:3096-3110).
    pub unpredictable_shooting: bool,
    /// The volley die's own registry params (`assets/solo/rules_mechanics_*
    /// .json`, both "Unpredictable" and "Unpredictable Shooter"): a face at
    /// or under `low_roll_max` is AP(+ap_bonus) on every profile of the
    /// volley, above it +hit_bonus to hit (main.gd:3180/:3188-3190,
    /// `unpredictable_fighter_effect` ai_combat_math.gd:387-388). Read off
    /// the carried rule's entry in `_ctx_of`, defaults 1/1/3.
    pub unpredictable_ap_bonus: i64,
    pub unpredictable_hit_bonus: i64,
    pub unpredictable_low_roll_max: i64,
    /// `RulesRegistry.unit_rule_active(unit, "No Retreat")` main.gd:8360 — a
    /// failed morale test counts as PASSED instead, and is paid for in
    /// self-wounds that cannot be ignored.
    pub no_retreat: bool,
    /// `main._solo_unit_has_unwieldy` :16675 — "strikes last when charging":
    /// the CHARGER's strikes swap BEHIND the defender's strike-back
    /// (main.gd:8073-8078). Counter and Impact keep their slots.
    pub unwieldy: bool,
    /// `Impact(X)` / `Heavy Impact(X)` / `Ravage(X)` ratings — read only by the
    /// melee side (`impact_ev` / `ravage_ev`, ai_ev.gd:497-529).
    pub impact: i64,
    pub heavy_impact: i64,
    pub ravage: i64,
    pub stealth: bool,
    /// The DEFENDER's best Stealth-primitive DATA ALIAS (Changebound et al.)
    /// OTHER than the literal "Stealth" name, which `stealth` above (and the
    /// fixed `STEALTH_HIT_PENALTY`/`LONG_RANGE_IN` constants) already cover
    /// byte-identically — the registry's own "Stealth" entry is
    /// `{hit_penalty:1, over_in:9}`, exactly those constants.
    /// `unit.rs::stealth_alias_of`. 0 = no alias carried.
    pub stealth_alias_penalty: i64,
    /// The alias's own `over_in` gate (0.0 = unconditional for shooting, the
    /// same `gate <= 0.0` reading `_solo_hit_mod_info` uses, main.gd:5602).
    pub stealth_alias_over_in: f64,
    pub evasive: bool,
    /// `Melee Evasion` — the melee twin of Evasive (ai_ev.gd:150).
    pub melee_evasion: bool,
    pub fortified: bool,
    pub guarded: bool,
    pub ranged_shrouding: bool,
    /// The clamp pair the three ranged reads share (dice.rs's volley,
    /// combat.rs's shoot_ev, sim.rs's sight_reach_in): the carried entry's
    /// own `range_penalty_in`/`floor_in` — the literal "Ranged Shrouding"
    /// resolves to exactly the `SHROUD_RANGE_PENALTY_IN`/`SHROUD_FLOOR_IN`
    /// constants its entry prints. Read only while `ranged_shrouding`;
    /// `ctx_for` always sets them beside the flag.
    pub ranged_shroud_penalty_in: f64,
    pub ranged_shroud_floor_in: f64,
    pub shielded: bool,
    pub in_cover: bool,
    /// `AiEv.ctx_for`'s third argument, which `BattleSim._ctx_of` never passes
    /// (battle_sim.gd:702) — always 0 in the sim, modelled for `impact_ev`.
    pub counter_models: i64,
    pub regeneration: bool,
    pub regen_target: i64,
    /// Block B10 — the SPELL-wound twin (`main._solo_regen_pick`'s
    /// `from_spell` key, main.gd:6595): a whole-unit Resistance carrier folds
    /// the registry's `ignore_target_spell` (2+) into the MIN; every other
    /// unit repeats `regen_target`, so spell.rs's leg is byte-identical for
    /// non-carriers.
    pub regen_target_spell: i64,
    /// The DYNAMIC melee flag `BattleSim._ctx_of(su, true)` writes over the
    /// template (battle_sim.gd:705-707): a fatigued striker hits only on 6s.
    pub fatigued: bool,
    /// Block B13 — `Retaliate(X)`'s hits one carrier throws back FOR EACH wound
    /// it takes in melee (`_solo_retaliate_hits_per_wound` main.gd:4521-4529):
    /// the rule's own rating ("Retaliate(3)" -> 3, a bare "Retaliate" -> the
    /// wave-7 fallback 1), overridden by the registry's `hits_per_wound` param
    /// ONLY when it is numeric — the shipped registry carries the string "X",
    /// which reads as "the rating" and keeps the rating answer. 0 = the rule is
    /// not on this unit under the registry gate (`unit_rule_active`), so a
    /// carrier whose system map fields no Retaliate primitive stays silent
    /// exactly like the table's `_solo_retaliate_hits` gate (main.gd:4568).
    /// Read only by the tray path (`sim::strike_phase`); the EV imagination
    /// never asks who lashes back.
    pub retaliate_hits_per_wound: i64,
    /// Block C4 — `Deathstrike` / `Self-Destruct`'s death-half
    /// (`_solo_deathstrike_hits` main.gd:16698-16731, called at :6174 right
    /// after the Retaliate block): the hits the STRIKER takes for each of this
    /// unit's models KILLED by the phase's strikes. Stamped in `ctx_for` as the
    /// SUM of both literals, each registry-gated (`unit_rule_active`) at its
    /// own `maxi(rating, 1)` off the rule's own rating — a unit carrying both
    /// pays both, like the table's two primitive loops per chain member
    /// (main.gd:16709-16720). 0 = the unit carries neither. The attached-hero
    /// facet of the table's chain loop is not ported: this twin's
    /// `land_wounds` never kills a hero's models in the defender's strike
    /// phase. Read only by `sim::strike_phase`, which takes NO tally credit
    /// from it (main.gd:6174 never touches `_solo_retaliate_credit`).
    pub death_hits_per_kill: i64,
    /// Block C5 — `Instinctive`'s carried +1 (`_solo_instinctive_mod`
    /// main.gd:5774-5799): `param_i("hit_bonus", 1)` off the unit's
    /// registry-gated "Instinctive" entry, 0 when it carries none. NOT folded
    /// here — the bonus is positional, so only `sim::strike_phase` and the
    /// volley builder add it into the member's `hit_mod`, and only when
    /// `sim::instinctive_applies` says the attacked unit IS the closest enemy.
    pub instinctive_hit_bonus: i64,
    // --- NML block B2b, the live-buff fold (`sim::ctx_live`). ZERO on every
    // `ctx_of`, which is what keeps the EV imagination buff-blind exactly like
    // `BattleSim._ctx_of` (it never sets `AiEv.profile_ev`'s `spell_hit_mod`
    // key, ai_ev.gd:331). Only the TRAY path folds them in. ---
    /// `_solo_spell_hit_mod(member, melee)` main.gd:3789 — the BEARER's own net.
    pub hit_mod: i64,
    /// `_solo_spell_hit_mod_vs(target, melee)` main.gd:3800 — the net every unit
    /// attacking THIS one gets (`beneficiary: "attackers"`).
    pub vs_hit_mod: i64,
    /// A live `grants_rule: "Unstoppable"` on this unit's joined chain — the
    /// dynamic half of `_solo_ignores_regen`'s last line (main.gd:6941,
    /// `AiEv.has_exact_rule`). It reaches the Regeneration bypass and NOTHING
    /// else, because the table's dice path bridges `profile["unstoppable"]`
    /// only from the TARGET's attackers-side records (`_solo_bridge_granted_
    /// flags` :16576-16589 folds relentless/furious/rending from the attacker,
    /// never unstoppable).
    pub unstoppable_grant: bool,
    /// A live `grants_rule: "Rending"` on this unit's joined chain — the
    /// rending leg of `_solo_bridge_granted_flags` (main.gd:16576-16589),
    /// which folds granted rending into the striker's roll flags. Read by the
    /// TRAY's on-6 AP and Regeneration-bypass tests (dice.rs) and by nothing
    /// else — the EV imagination never calls `ctx_live`.
    pub rending_grant: bool,
    /// A live `grants_rule: "Thrust"` — the same bridge's thrust leg, read by
    /// the tray's charging to-hit and AP bonuses (dice.rs) only.
    pub thrust_grant: bool,
    /// A live `grants_rule: "Relentless"` — the relentless leg of the same
    /// bridge (AiSpell.BRIDGE_FLAGS ai_spell.gd:415), folded into the
    /// striker's roll flags where the WEAPON's own `p.relentless` is read
    /// (dice.rs, over-9" volleys). Zero on every `ctx_of`.
    pub relentless_grant: bool,
    /// A live `grants_rule: "Shred"` — the same bridge's shred leg, folded
    /// into the save batch the way the weapon's own `p.shred` is (dice.rs).
    /// Zero on every `ctx_of`.
    pub shred_grant: bool,
    // --- Wave 2 "Utility Buff" family (gated `acts::rule_on(.., EPOCH_5_TABLE_RULES)`). ---
    /// A live `grants_rule: "Slayer"` — AP(+2) vs Tough 3+, charge or over 9".
    pub slayer_grant: bool,
    /// A live `grants_rule: "Primal Boost"` — the Surge primitive's low form.
    pub surge_grant: bool,
    /// A live `grants_rule: "Versatile Attack"` — the shoot-arm flag fold.
    pub versatile_grant: bool,
    /// A live `grants_rule: "AP(+1) when shooting"` (Piercing Shooting Mark).
    pub pierce_shooting_grant: bool,
    /// A live `grants_rule: "AP(+1) in melee"` (Piercing Fighting Mark).
    pub pierce_melee_grant: bool,
    /// A live `grants_rule: "Piercing Assault"` — AP(+1) while charging.
    pub pierce_assault_grant: bool,
    // --- Wave 3 "Utility Buff" marks (epoch-gated `acts::rule_on(.., 6)`). ---
    /// A live attackers-side `grants_rule: "Indirect"` on this unit (Indirect
    /// Mark) — whoever SHOOTS at it may waive the sight test. Zero on every
    /// `ctx_of`; only `sim::ctx_live` folds the ledger's once-record.
    pub indirect_mark: bool,
    /// A live attackers-side `grants_rule: "+6\" shooting range"` (Increased
    /// Shooting Range Mark) — the shooter's volley reach gains this many
    /// inches. `0.0` on every `ctx_of`.
    pub range_mark_in: f64,
    // --- Block B7, the Growth-Marker family. ZERO on every `ctx_of` (baked
    // into `ctx_for` below), like `hit_mod` — only `sim::ctx_live` reads the
    // live marker count and folds it in, so the EV imagination stays
    // growth-blind exactly like `BattleSim._ctx_of` (`ai_ev.gd`/`ai_combat_
    // math.gd`/`battle_sim.gd` never mention "growth"). Set for every
    // `ctx_live` call regardless of attacker/defender role — only the
    // ATTACKER side is ever read downstream, the same shape as
    // `unstoppable_grant`. ---
    /// `_solo_growth_attack_bonus(member).get("ap")` main.gd:17069/:4287 — the
    /// bearer's own marker-driven AP delta, added to `ShootProfile.ap` on both
    /// the shooting and the melee tray (Piercing Growth/Frenzy).
    pub growth_ap_mod: i64,
    /// The same bonus's `"hit"` half, main.gd:17069/:5677-5680 — folded into
    /// the SHOOTING to-hit target only (`_solo_hit_mod_info`'s melee branch
    /// returns before that code runs, main.gd:5608-5648).
    pub growth_hit_mod: i64,
    // --- Ambush family (rules-wave2-ambush). ZERO on every `ctx_of` (baked
    // into `ctx_for`), like `growth_ap_mod` — only `sim::ctx_live` reads the
    // arrival stamp and folds it in, so the EV imagination stays blind to it
    // exactly like the growth markers above. ---
    /// "Ambushing Piercing Shot": the AP(+N) its weapons shoot with on the
    /// very round the unit ARRIVES via Ambush (GF v3.5.3, "AP(+1) when
    /// shooting on the round in which it deploys via this rule"). SHOOTING
    /// only — the melee fold never reads it. Stamped in `ctx_live` off
    /// `State.ambush_arrived_round` (the stamp `arrive_unit` writes).
    pub ambush_arrival_ap: i64,
    // --- Block C2 — the melee / charge leg of the Shot Modifier family,
    // `_solo_hit_mod_info`'s melee branch (main.gd:5658-5668): an entry is
    // kept when `all_attacks` OR `melee_only` OR (`when: "charge"` on a
    // charge), and a kept entry adds `hit_bonus` to the melee modifier.
    // Stamped in `ctx_for` from an explicit name allowlist — the three family
    // names that pass with NO runtime gate. Grounded Precision
    // (`terrain_within_in`) and Precision Feat (`uses_per_game`) carry
    // `all_attacks` but need runtime state, so they stay unported. SEPARATE
    // from `hit_mod` on purpose: the table's shooting branch skips
    // `melee_only`/`when: charge` entries (main.gd:5721-5722), and a
    // melee-only bonus leaking into a shot is bug #489's exact shape. ---
    /// The `melee_only` names (Good Fighter, Precision Fighter Aura): every
    /// melee strike, charge or not.
    pub melee_hit_bonus: i64,
    /// The `when: "charge"` names (Precision Charge Aura): only while the
    /// strike is a charge.
    pub melee_hit_bonus_charge: i64,
}

/// One conditional-AP spec — the registry `params` block of a Shatter / Tear /
/// Disintegrate / Melee Slayer / Piercing Assault / Piercing Hunter / Slayer
/// entry, as `AiEv.stamp_conditional_ap` ai_ev.gd:283-315 hands it to
/// `AiCombatMath.conditional_ap_bonus`. Carried verbatim rather than resolved
/// here: the bonus depends on the DEFENDER, which the static layer never sees.
#[derive(Debug, Clone, Default)]
pub struct CondAp {
    pub ap_bonus: i64,
    pub charge_only: bool,
    /// The extra situational gate (`"ranged_over_or_charge"`), "" for none.
    pub gate: String,
    pub over_in: f64,
    pub condition: String,
    pub threshold: i64,
}

/// One merged, stamped weapon profile — `AiShooting._profile` ai_shooting.gd:90-152
/// plus the `stamp_sergeant` facets `profile_ev` actually reads.
#[derive(Debug, Clone, Default)]
pub struct ShootProfile {
    pub name: String,
    /// The MERGED raw attack count; the survivor scaling happens per call.
    pub attacks: i64,
    pub count: i64,
    pub range: i64,
    pub ap: i64,
    pub deadly: i64,
    pub blast: i64,
    pub hazardous: bool,
    pub relentless: bool,
    pub reliable: bool,
    pub strafing: bool,
    pub ignores_cover: bool,
    pub precise: bool,
    pub surge: bool,
    pub rending: bool,
    pub bane: bool,
    pub thrust: bool,
    /// The WEAPON's own "Unstoppable" rule, exact name — `_has_rule(w,
    /// "Unstoppable")` ai_shooting.gd:132, the table's DICE path (to-hit clamp
    /// main.gd:3149/6012/9857; Regeneration bypass main.gd:6941 via
    /// `AiEv.has_exact_rule`, which an "Unstoppable Mark" carrier never
    /// matches — see `unstoppable_ev` below). `dice.rs` reads this field
    /// alone; `combat.rs` (the EV port) reads `unstoppable_ev`.
    pub unstoppable: bool,
    pub counter: bool,
    pub destructive: bool,
    pub shred: bool,
    /// A unit-level Shred-FAMILY rule — the plain name or any carried
    /// Shred-primitive entry ("Shred in Melee"/"when Shooting" facet-scoped,
    /// Destroyer/Infected/Warbound ungated — main.gd:3001/:4355's
    /// `unit_rule_active(member, "Shred") or _solo_shred_facet_applies`).
    /// Kept APART from `shred` (the weapon's own flag) so the epoch gate
    /// (`dice.rs` `save_batch`, `rule_on(rules_epoch, CURRENT_RULES_EPOCH)`)
    /// can keep every pre-port corpus byte-exact. `profile_ev` reads neither
    /// leg — ai_ev.gd:429's EV imagination sees the weapon flag only.
    pub shred_alias: bool,
    /// The Shred Boost's widened save-fail window top face (unit.rs::stamp's
    /// arm 6b: `save_fail_max` / `extra_wound_save_low` off the carried Boost
    /// entry, stamped only when the model also carries its `upgrades` base
    /// rule): failed defense rolls up to this face each take the shred extra
    /// wound. 1 = no boost — the base shred window, the same "no boost"
    /// default shape as `surge_low`. Read by the volley's epoch-4 shred
    /// window (`shred_boost_dice`, `rule_on(rules_epoch, 4)`); the melee
    /// resolve never widens (no pre-charge gap measured, dice.rs NOT-PORTED).
    pub shred_low: i64,
    /// The Shred Boost's distance gate (the entry's own `over_in`): the
    /// widened window counts only past this centre distance, exactly 9" not
    /// "over" — same strict gate as every other over-9" read in this port.
    pub shred_over_in: f64,
    pub indirect: bool,
    pub limited: bool,
    pub takedown: bool,
    pub rules: Vec<String>,
    // --- stamped facets (ai_ev.gd:203-274) ---
    pub versatile_attack: bool,
    pub on6_ap: i64,
    /// `AiEv.stamp_sergeant` :267-274 writes the bearer's own attack share here.
    /// ALWAYS 0 in this port — see `UnitStatic::unimplemented`.
    pub sergeant_attacks: i64,
    /// NML-1103 — `AiEv.stamp_conditional_ap` ai_ev.gd:296-313, read by
    /// `combat::profile_ev`. Stamped AFTER the merge, like every other facet.
    pub cond_ap: Vec<CondAp>,
    /// Good Shot (+1) / Bad Shot (-1) — `_solo_hit_mod_info` main.gd:5681-5701,
    /// a flat shooting-only hit-roll bonus with no range gate.
    pub hit_bonus: i64,
    /// Targeting Visor (+1) — same site, gated behind `over_in`: applies only
    /// past `combat::LONG_RANGE_IN` (exactly 9" is not "over", same as every
    /// other over-9" gate in this port).
    pub hit_bonus_over9: i64,
    /// EV-only sibling of `unstoppable` — `BattleSim._profiles_of`'s UNIT-level
    /// prefix scan (battle_sim.gd:1003-1021, mirrored by `stamp_unit_strikers`
    /// below) ORs in ANY unit-level rule whose name starts with "Unstoppable",
    /// so an "Unstoppable Mark" carrier reads `unstoppable` in the table's EV
    /// imagination (ai_ev.gd:347/355/434-435) but never on its dice. Stamped
    /// AFTER the merge, like every other facet in this block.
    pub unstoppable_ev: bool,
    /// The extra-ATTACK form of the "unmodified 6 to hit" family — Bloodborn /
    /// Clan Warrior / Primal / Predator (Fighter/Shooter) / Royal Warrior /
    /// Crazed / Psychotic and every other `Surge` primitive carrier with
    /// `extra_attack: true` (main.gd:4417-4432): each unmodified 6 among the
    /// original hit roll draws one MORE attack die at the same to-hit target,
    /// as its own tray slot — dice, not auto-hits, and the extras never
    /// re-trigger. Stamped per `unit.rs::stamp`, gated by `facet_applies`
    /// exactly like `surge` above (Predator Fighter is melee-only).
    pub surge_attack: bool,
    /// The Boost upgrade's `surge_low` (Primal Boost, Clan Warrior Boost, ...):
    /// a successful unmodified 5 ALSO draws an extra die when this is < 6.
    /// 6 = no boost — `main.gd`'s own `int(profile.get("surge_attack_low",
    /// 6))` default, mirrored so an unboosted carrier reads as unboosted
    /// without a separate bool field.
    pub surge_attack_low: i64,
    /// The plain auto-hit form's `surge_within_in` (Point-Blank Surge, stamped
    /// by `ai_ev.gd:228-231`): main.gd:4465-4467 — the WHOLE surge bonus
    /// (sixes and Boost 5s alike) fires only at or under this centre
    /// distance; 0.0 = no gate. Read by the volley's epoch-gated surge block.
    pub surge_within_in: f64,
    /// The Boost upgrade's `surge_low` (Devout/Ferocious/Lucky Boost et al.,
    /// stamped by `stamp`'s upgrades arm, ai_ev.gd:243): a successful
    /// unmodified 5 ALSO adds a hit when this is < 6. 6 = no boost —
    /// main.gd:4469's `profile.get("surge_low", 6)` default, so an unboosted
    /// carrier reads as unboosted without a separate bool field.
    pub surge_low: i64,
    /// The Boost's distance gate (main.gd:4469): the 5s count only past this
    /// centre distance — melee resolves at 0.0, so a Boost NEVER fires its 5s
    /// in melee, exactly the table's own reading.
    pub surge_over_in: f64,
}

impl ShootProfile {
    /// `AiShooting._merge_signature` ai_shooting.gd:81-89 — every key except the
    /// two summable ones. Compared field by field instead of stringified; the
    /// stamped facets are still at their defaults when this runs.
    fn merges_with(&self, o: &ShootProfile) -> bool {
        self.name == o.name
            && self.range == o.range
            && self.ap == o.ap
            && self.deadly == o.deadly
            && self.blast == o.blast
            && self.hazardous == o.hazardous
            && self.relentless == o.relentless
            && self.reliable == o.reliable
            && self.strafing == o.strafing
            && self.ignores_cover == o.ignores_cover
            && self.precise == o.precise
            && self.surge == o.surge
            && self.rending == o.rending
            && self.bane == o.bane
            && self.thrust == o.thrust
            && self.unstoppable == o.unstoppable
            && self.counter == o.counter
            && self.destructive == o.destructive
            && self.shred == o.shred
            && self.shred_alias == o.shred_alias
            && self.indirect == o.indirect
            && self.limited == o.limited
            && self.takedown == o.takedown
            && self.rules == o.rules
    }
}

/// A rule the port knows it does not implement, with the reason.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Unimplemented {
    pub rule: String,
    pub why: String,
}

/// `SoloController.INFILTRATE_MIN_ENEMY_DIST_M` (solo_controller.gd:9607) read
/// back into INCHES the way the table's own fallback expression reads it
/// (`:9620`, `INFILTRATE_MIN_ENEMY_DIST_M / INCHES_TO_METERS`) — deliberately
/// NOT the literal `3.0`. `0.0762 / 0.0254` is `3.0000000000000004`, and only
/// that value multiplies back to exactly `0.0762` m; a hard-coded `3.0` lands
/// on `0.07619999999999999` m, one ULP short of the ring the table measures.
/// The registry (`min_enemy_dist_in: 3.0` in every shipped entry) hands back
/// the exact `3.0` instead, so the two readings are one ULP apart BY DESIGN
/// and the tests below tell them apart.
pub const INFILTRATE_MIN_ENEMY_DIST_IN: f64 = 0.0762 / 0.0254;
/// `SoloController.REPEL_AMBUSHERS_DIST_IN` (solo_controller.gd:9723) — the
/// book's *"Enemy units using Ambush must be set up over 12\" away from this
/// model's unit"*. An inch literal on the table too, so no such seam here.
pub const REPEL_AMBUSHERS_DIST_IN: f64 = 12.0;

/// The immutable per-unit closure of `resolve`/`reply_threat`.
#[derive(Debug, Default)]
pub struct UnitStatic {
    pub ctx: Ctx,
    /// `Profile.name` — `GameUnit.get_name()`, which is what `_solo_tray_roll`
    /// signs every die with (main.gd:3199-3200, :6448).
    pub name: String,
    /// Merged + stamped RANGED profiles, unfiltered (range > 0, any distance).
    pub shoot: Vec<ShootProfile>,
    /// Merged + stamped MELEE profiles (range 0) — `AiShooting.melee_profiles`
    /// ai_shooting.gd:44-56, the set `_profiles_of(su, true)` builds.
    pub melee: Vec<ShootProfile>,
    pub model_count: i64,
    pub wounds_max: Vec<i64>,
    pub quality: i64,
    pub fearless: bool,
    pub is_caster: bool,
    pub spells: Vec<Spell>,
    /// `GameUnit.has_special_rule("Caster Group")` — the round-start refill
    /// resets such a unit to its BEARER COUNT instead of accumulating
    /// (ai_planner.gd:487-492 via game_unit.gd:426-434).
    pub caster_group: bool,
    /// `GameUnit.casts_per_round`, which `GameUnit._ready` sets from
    /// `get_caster_value()` (game_unit.gd:420) — the profile's `caster_value`
    /// IS that number.
    pub casts_per_round: i64,
    /// `RulesRegistry.unit_rule_active(gu, "Battleborn" | "Steadfast")`
    /// (rules_registry.gd:136-142) — the two rules that clear Shaken for free at
    /// a round start (ai_planner.gd:493-495). Static per unit, so the registry
    /// is read here once instead of per imagined round.
    pub battleborn_active: bool,
    pub steadfast_active: bool,
    /// Battleborn family wave 3 (rules-wave3-battleborn) — the LOWEST
    /// `recover_target` off the unit's die-roll recover aliases ("Honor Code",
    /// "Vale Oath", "Vale Oath Boost", "Unmovable" — main.gd
    /// `:_solo_round_start_recovery_rule`'s generic Battleborn-primitive alias
    /// layer, rolled by `:_solo_battleborn_recovery`). 0 = the unit rolls no
    /// recovery die at a round start. Static per unit, so the registry answers
    /// once here and the round-start leg reads the number only.
    pub battleborn_recover_target: u32,
    /// `RulesRegistry.unit_rule_active(gu, "Mend")` main.gd:5236 — the heal
    /// primitive's registry gate; the import folds item-granted rules into
    /// `special_rules` (opr_api_client.gd:261-263), so a Paternal Bond item
    /// counts here exactly as it does on the table.
    pub mend_active: bool,
    /// `RulesRegistry.unit_rule_active(gu, "Breath Attack")` main.gd:5279 — the
    /// breath-weapon primitive's registry gate, block B3's `mend_active`
    /// precedent.
    pub breath_attack_active: bool,
    /// `GameUnit.is_hero()` game_unit.gd:273-275 — "Hero" in the rule list.
    /// Mend's patient tiebreak prefers heroes (main.gd:5361).
    pub is_hero: bool,
    /// NML-1152 B14 step 1 (Bounding): `unit_rule_active(gu, "Bounding")`'s own
    /// named-rule gate, `Some(place_d3_plus)` when active — census evidence
    /// that this core reads the registry's `place_d3_plus` param (see
    /// `rule_universe_census.py` CONSUMED_PARAM_KEYS). The DATA-alias family
    /// (Wolfborn, Rapid Blink, …) stays table-only: only the RECORDED
    /// `Action::traced` draw (`sim::bounding_bonus_in`) ports its value; this
    /// stamp is the named rule's own evidence, not a simulation input.
    pub bounding: Option<f64>,
    /// The Quick/Fast move-band family — the named carriers' own registry
    /// params, summed the way BOTH band passes stack them (per rule NAME:
    /// `movement_range_controller.gd:164-188`'s `counted` dict,
    /// `list_to_profile.py::_move_bands`'s twin). `Some` only when a carrier
    /// is active AND the registry's epoch has reached `CURRENT_RULES_EPOCH`
    /// (`rule_on(rules_epoch, CURRENT_RULES_EPOCH)`); a pre-port header
    /// reads `None`.
    ///
    /// Census/evidence-only on this core (the accepted `bounding` shape, PR
    /// #653): the effect reaches it precomputed — the two band passes fold
    /// these same params into the profile `move_bands` this core consumes as
    /// `state.bands` — so a live re-fold at the move seam would double-count
    /// a recorded band; this stamp is the core's own per-entry read, never a
    /// simulation input. The conditions the entries also record
    /// (`charge_only`, `upgrades`, `terrain_within_in`, `uses_per_game`) are
    /// read by nobody on this core — neither twin's band pass reads them
    /// either, so the flat fold IS the shipped behaviour. The conditional
    /// names (Speed Feat, Grounded Speed, Highborn Boost, Scurry Boost) stay
    /// OUT of this loop for exactly that reason: their entries express the
    /// magnitudes but not the conditions, so stamping them would claim
    /// coverage the core does not have.
    pub move_rule_mods: Option<Bands>,
    /// Versatile Reach (solo_controller.gd:1787-1789) — `Some(charge_bonus_in)`
    /// when the unit carries the rule, i.e. the CHARGE half of the per-activation
    /// "pick one". The `range_bonus_in` half is NOT stamped: this core models no
    /// shooting range bonus at all (state.rs:172-176, sim.rs:727-730), so a field
    /// for it would claim coverage that does not exist.
    /// "Versatile Reach Aura" is an UNMAPPED-registered name (primitive null, so
    /// `unit_rule_active` is false for it by construction, rules.rs:213-218); the
    /// import expands it to the base rule on the bearer AND its attached heroes
    /// (opr_army_manager.gd:2106-2140, "This model and its unit get Versatile
    /// Reach", tutorial_board.nml:5423), so the raw-name arm is what makes this
    /// core independent of that expander rather than a second effect.
    pub versatile_reach_charge_in: Option<f64>,
    /// `RulesRegistry.unit_rule_active(gu, "Re-Position Artillery")` — the
    /// "Utility Buff" movement primitive's registry gate (block B2).
    pub reposition_artillery_active: bool,
    /// Block B5 — `hit_and_run_move` solo_controller.gd:9657-9713's rule pick,
    /// scoped to this ticket's three named carriers of the "Hit & Run"
    /// primitive: the literal name plus its data aliases "Guerrilla" and
    /// "Harassing" (identical `move_in: 3.0` on every occurrence). The two
    /// half-primitives follow in block C1, below.
    pub hit_and_run_active: bool,
    /// Block C1 — `hit_and_run_move`'s half pick solo_controller.gd:9667: the
    /// Shooter half fires ONLY on its own trigger (`after_shoot`, the caller's
    /// shoot leg) and only on an EXACT name match (`AiEv.has_exact_rule`),
    /// never through the "Hit & Run" alias loop (:9669-9681). Every registry
    /// occurrence carries `move_in: 3.0`, so `HIT_AND_RUN_MOVE_IN` stays exact.
    pub hit_and_run_shooter_active: bool,
    /// Block C1 — the mirror half of solo_controller.gd:9667: the Fighter half
    /// fires only on the melee leg (`after_shoot == false`), exact name only.
    pub hit_and_run_fighter_active: bool,
    /// Block B11 — `RulesRegistry.unit_rule_active(gu, "Quick Shot")`
    /// solo_controller.gd:1846/:4033 — a carrier's move-and-shoot band becomes
    /// its RUSH distance, so RUSH may also shoot (normally HOLD/ADVANCE only).
    pub quick_shot_active: bool,
    /// Block B8 — `RulesRegistry.unit_rules_of_primitive(gu, "Second Wind")`
    /// (solo_controller.gd:10448/:10477). Only two literal names resolve to
    /// this primitive anywhere in the registry (`assets/solo/rules_mechanics_
    /// {gf,gff}.json`, no `aof` occurrence): "Inquisitorial Agent" (human_
    /// inquisition, the training pool's own carrier) and "Martial Prowess"
    /// (dark_elf_raiders) — both set `uses_per_game: 1, army_cap_fraction: 3`
    /// on every occurrence (verified), so sim.rs stands in a const for both,
    /// the `HIT_AND_RUN_MOVE_IN` precedent.
    pub second_wind_active: bool,
    /// Ambush arrival S2 — `SoloController._reserve_min_enemy_dist_m`
    /// (solo_controller.gd:9617-9621): the ring an ARRIVING ambusher must keep
    /// from every enemy model. `0.0` means "not an infiltrator", i.e. the plain
    /// 9" `AMBUSH_MIN_ENEMY_DIST_M` path (`:9606`) the caller owns.
    ///
    /// The gate is the PLAIN rule name `"Infiltrate"`
    /// (`GameUnit.has_special_rule`, `:9618`), NOT the registry's
    /// `unit_rule_active` — a faction whose map fields no `Infiltrate` entry
    /// still arrives at the fallback ring, and the twin copies that. The value
    /// is `RulesRegistry.unit_param(unit, "Infiltrate", "min_enemy_dist_in",
    /// …)` (`:9620`), so a book that moves the ring moves it here too.
    pub infiltrate_min_enemy_dist_in: f64,
    /// Ambush family (rules-wave2-ambush) — the four registry names that ride
    /// the "Ambush" primitive, each read at its OWN literal with the entry's
    /// own params (`ambush_family_of`). Every field is its zero-value when the
    /// unit carries no such name or the record predates `rules_epoch` 4.
    pub ambush_family: AmbushFamily,
    /// Ambush arrival S2 — `SoloController.repel_ambush_dist_m`
    /// (solo_controller.gd:9724-9727): the ring THIS unit projects onto enemy
    /// ambushers arriving near it, `0.0` without the rule. A defender's rule —
    /// nothing about the carrier changes; it only enlarges the arriving unit's
    /// no-go radius, and the `max` against the arriver's own ring is why 12"
    /// beats even the 3" Infiltrate concession.
    ///
    /// Here the gate IS `RulesRegistry.unit_rule_active(enemy,
    /// "Repel Ambushers")` (`:9725`), the opposite of the field above: a
    /// faction whose map fields no entry projects nothing at all. Value from
    /// `min_dist_in` (`:9727`), `12.0` in all 21 shipped GF+AoF entries.
    pub repel_ambushers_dist_in: f64,
    /// Block B2b — every "Utility Buff" entry this unit carries, params and
    /// all, in the table's own loop order (`utility_buffs_of`).
    pub utility_buffs: Vec<UtilityBuff>,
    /// Block B7 — every "Growth Markers" entry this unit carries whose params
    /// this port consumes (`growth_of`); the live marker count itself lives on
    /// `State.growth_markers`, not here.
    pub growth: Vec<GrowthRule>,
    /// Rules this unit carries that the port does NOT model — reported by name
    /// with a node count instead of being silently skipped.
    pub unimplemented: Vec<Unimplemented>,
}

fn weapon_has(w: &Weapon, rule: &str) -> bool {
    w.rules.iter().any(|r| r.trim().starts_with(rule))
}

/// `AiShooting._rating_of` ai_shooting.gd:176-182 — no max(0) here, unlike the
/// unit-level `AiEv.unit_rating`.
fn weapon_rating(w: &Weapon, rule_name: &str) -> i64 {
    let prefix = format!("{rule_name}(");
    for r in &w.rules {
        let s = r.trim();
        if s.starts_with(&prefix) && s.ends_with(')') {
            let inner: String = s[prefix.len()..s.len() - 1].chars().filter(|c| *c != '+').collect();
            return inner.parse::<i64>().unwrap_or(0);
        }
    }
    0
}

/// `AiShooting._profile` ai_shooting.gd:90-152.
fn base_profile(w: &Weapon, attacks: i64, range_in: i64) -> ShootProfile {
    let ap = weapon_rating(w, "AP");
    ShootProfile {
        name: w.name.clone(),
        attacks,
        count: w.count.max(1),
        range: range_in,
        // Hazardous grants AP(4) — ai_shooting.gd:104-107.
        ap: if weapon_has(w, "Hazardous") { ap.max(4) } else { ap },
        hazardous: weapon_has(w, "Hazardous"),
        deadly: weapon_rating(w, "Deadly"),
        relentless: weapon_has(w, "Relentless"),
        blast: weapon_rating(w, "Blast"),
        reliable: weapon_has(w, "Reliable"),
        strafing: weapon_has(w, "Strafing"),
        ignores_cover: weapon_has(w, "Ignores Cover"),
        precise: weapon_has(w, "Precise"),
        surge: weapon_has(w, "Surge"),
        rending: weapon_has(w, "Rending"),
        // Lacerate is a straight data-alias of Bane — ai_shooting.gd:126-129.
        bane: weapon_has(w, "Bane") || weapon_has(w, "Lacerate"),
        thrust: weapon_has(w, "Thrust"),
        unstoppable: weapon_has(w, "Unstoppable"),
        counter: weapon_has(w, "Counter"),
        destructive: weapon_has(w, "Destructive"),
        shred: weapon_has(w, "Shred"),
        indirect: weapon_has(w, "Indirect"),
        limited: weapon_has(w, "Limited"),
        takedown: weapon_has(w, "Takedown"),
        rules: w.rules.clone(),
        // main.gd's own default ("no boost yet") — see both fields' docs.
        surge_attack_low: 6,
        surge_low: 6,
        // The base shred window ("no boost") — see `shred_low`'s doc.
        shred_low: 1,
        ..Default::default()
    }
}

/// `AiShooting.merge_identical` ai_shooting.gd:63-77 — Limited and Takedown keep
/// their own line (per-identity bookkeeping); first-appearance order is kept.
fn merge_identical(profiles: Vec<ShootProfile>) -> Vec<ShootProfile> {
    let mut out: Vec<ShootProfile> = Vec::with_capacity(profiles.len());
    for p in profiles {
        if p.limited || p.takedown {
            out.push(p);
            continue;
        }
        match out.iter_mut().position(|t| t.merges_with(&p)) {
            Some(i) => {
                out[i].attacks += p.attacks;
                out[i].count += p.count;
            }
            None => out.push(p),
        }
    }
    out
}

/// `AiEv.facet_applies` ai_ev.gd:105-110 — the melee/shooting gate of a
/// unit-level facet; `profile_range` 0 means a melee profile.
fn facet_applies(melee_only: bool, shooting_only: bool, profile_range: i64) -> bool {
    if melee_only && profile_range > 0 {
        return false;
    }
    if shooting_only && profile_range <= 0 {
        return false;
    }
    true
}

/// `AiEv.has_exact_rule` ai_ev.gd:88-96 — rating stripped, no prefix match.
fn has_exact_rule(rules: &[String], rule: &str) -> bool {
    rules.iter().any(|r| base_rule_name(r) == rule)
}

/// `AiEv.rule_on_all_models` ai_ev.gd:74-85 — the unit carries the rule AND
/// every ALIVE attached hero carries it too.
fn rule_on_all_models(p: &Profile, rule: &str) -> bool {
    if !has_special_rule(&p.special_rules, rule) {
        return false;
    }
    p.attached_hero_rules
        .iter()
        .all(|hr| has_special_rule(hr, rule))
}

/// `_solo_hit_mod_info`'s Stealth-primitive DATA-ALIAS loop (main.gd:5588-
/// 5610): the best (`maxi`) `hit_penalty` among the DEFENDER's Stealth-
/// primitive rules other than the literal "Stealth" name (`n == "Stealth"`
/// skips there too), each still gated by `_solo_rule_on_all_models`. Scans
/// `p.special_rules` only — item-granted rules already reach it through the
/// import's fold (the `mend_active` precedent). `terrain_within_in`
/// (Grounded Stealth / Machine-Fog's cover gate) and `requires_stationary`
/// (Entrenched) are NOT modelled: no per-call "moved this round" state
/// reaches this static layer, and there is no majority-in-cover read at
/// build time either — both stay unimplemented, like the rest of this
/// crate's documented gaps (dice.rs:317-330).
fn stealth_alias_of(reg: &mut Registries, p: &Profile) -> (i64, f64) {
    let mut best_penalty = 0;
    let mut best_over_in = 0.0;
    let map = reg.rules_for(&p.game_system);
    for r in &p.special_rules {
        let name = base_rule_name(r);
        if name.is_empty() || name == "Stealth" || !rule_on_all_models(p, &name) {
            continue;
        }
        let Some(e) = map.lookup(&p.faction_folder, &name) else {
            continue;
        };
        if e.primitive.as_deref() != Some("Stealth") {
            continue;
        }
        let pen = e.param_i("hit_penalty", 0);
        if pen > best_penalty {
            best_penalty = pen;
            best_over_in = e.param_f("over_in", 0.0);
        }
    }
    (best_penalty, best_over_in)
}

/// Battleborn family wave 3 (rules-wave3-battleborn) — main.gd
/// `:_solo_round_start_recovery_rule`'s generic Battleborn-primitive alias
/// layer, stamped BY NAME: each die-roll recover alias the unit carries
/// resolves its OWN registry entry and the LOWEST `recover_target` wins
/// ("Vale Oath Boost"'s text recovers on 3+ INSTEAD of only on 4+).
/// 0 = the unit rolls no recovery die at a round start. Gated on
/// `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` (frozen at 6, never the
/// literal 5 or `CURRENT_RULES_EPOCH`) — an epoch-5 corpus replays the
/// Battleborn/Steadfast free-clear reading byte-exact.
fn battleborn_recover_target_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> u32 {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return 0;
    }
    let carried = |name: &str| {
        has_special_rule(&p.special_rules, name) || has_special_rule(&p.item_grants, name)
    };
    let mut best = 0u32;
    for name in ["Honor Code", "Vale Oath", "Vale Oath Boost", "Unmovable"] {
        if !carried(name) {
            continue;
        }
        let target = match reg.rules_for(&p.game_system).lookup(&p.faction_folder, name) {
            Some(e) => e.param_i("recover_target", 0),
            None => 0,
        };
        if target > 0 && (best == 0 || (target as u32) < best) {
            best = target as u32;
        }
    }
    best
}

/// `RulesRegistry.unit_rule_active` rules_registry.gd:132-137 — the unit carries
/// it AND the map fields it for this (system, faction). A MISSING map answers
/// true (the wave-1..4 fallback).
fn unit_rule_active(reg: &mut Registries, p: &Profile, rule: &str) -> bool {
    if !has_special_rule(&p.special_rules, rule) {
        return false;
    }
    let map = reg.rules_for(&p.game_system);
    if map.empty {
        return true;
    }
    map.has_primitive(&p.faction_folder, rule)
}

/// `RulesRegistry.unit_param` rules_registry.gd:83-93 — one numeric param off
/// the (system, faction) entry for `rule`, `fallback` when either the map or
/// the entry is missing. No rule-carried gate: the caller owns that, exactly as
/// the two call sites at solo_controller.gd:9620 and :9727 do.
fn unit_param_f(reg: &mut Registries, p: &Profile, rule: &str, key: &str, fallback: f64) -> f64 {
    let map = reg.rules_for(&p.game_system);
    match map.lookup(&p.faction_folder, rule) {
        Some(e) => e.param_f(key, fallback),
        None => fallback,
    }
}

/// One `unit_rules_of_primitive` hit — rules_registry.gd:155-176.
struct PrimitiveHit {
    name: String,
    melee_only: bool,
    shooting_only: bool,
    extra_attack: bool,
    upgrades: String,
    cover_only: bool,
    ignores_cover: bool,
    /// Primal Boost et al.'s own `surge_low` param — read only when
    /// `extra_attack` is also set (`unit.rs::stamp`'s block 3b).
    surge_low: i64,
    /// The Bane family's coverage-wave gate (main.gd:6553-6560) — an alias
    /// with `reroll_save_sixes` re-rolls the defender's sixes.
    reroll_save_sixes: bool,
    /// The Lacerate family's bypass gate (main.gd:6996-6997) — an entry with
    /// `bypass_regen` cuts through Regeneration, facet-scoped per profile.
    bypass_regen: bool,
    /// Point-Blank Surge's own `within_in` (0.0 = no gate) and the Boost
    /// variants' `over_in` (ai_ev.gd's stamp default 9.0), read off the
    /// SAME `Surge` primitive entry. The Shred Boosts carry the same
    /// `over_in` pair (`stamp`'s arm 6b).
    within_in: f64,
    over_in: f64,
    /// The Shred Boost's widened save-fail window (`save_fail_max` on
    /// Infected/Destroyer Boost, `extra_wound_save_low` on Warbound Boost —
    /// one meaning, two key spellings across the systems), read off the
    /// carried `Shred` primitive entry. 0 = not a Boost.
    save_fail_max: i64,
}

/// `RulesRegistry.unit_rules_of_primitive` rules_registry.gd:155-176 — every
/// effective rule (own + item-granted, each name once, in that order) whose
/// registry entry resolves to `primitive`.
fn rules_of_primitive(reg: &mut Registries, p: &Profile, primitive: &str) -> Vec<PrimitiveHit> {
    let mut out = Vec::new();
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    let map = reg.rules_for(&p.game_system);
    let mut seen: Vec<String> = Vec::new();
    for raw in raws {
        let n = base_rule_name(raw);
        if n.is_empty() || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        if let Some(e) = map.lookup(&p.faction_folder, &n) {
            if e.primitive.as_deref() == Some(primitive) {
                out.push(PrimitiveHit {
                    name: n,
                    melee_only: e.param_b("melee_only"),
                    shooting_only: e.param_b("shooting_only"),
                    extra_attack: e.param_b("extra_attack"),
                    upgrades: e.param_s("upgrades").to_string(),
                    cover_only: e.param_b("cover_only"),
                    ignores_cover: e.param_b("ignores_cover"),
                    surge_low: e.param_i("surge_low", 5),
                    reroll_save_sixes: e.param_b("reroll_save_sixes"),
                    bypass_regen: e.param_b("bypass_regen"),
                    within_in: e.param_f("within_in", 0.0),
                    over_in: e.param_f("over_in", 9.0),
                    save_fail_max: e.param_i("save_fail_max", 0).max(e.param_i("extra_wound_save_low", 0)),
                });
            }
        }
    }
    let _ = rule_rating("", 0); // keep the import honest: ratings are unread here
    out
}

/// The capture-time registry reads that do NOT live on the profile — the ones
/// `BattleSim.capture` (battle_sim.gd:1329/1332) and
/// `AiActRecorder._stamp_gate_reads` (act_recorder.gd:251-256) take off the LIVE
/// `GameUnit` and write into the plain unit dict. A Godot-free capture has to
/// answer them from the same mechanics maps the search already loaded, or it
/// would need a second registry reader of its own.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct CaptureReads {
    /// `SoloController.morale_bonus_of` solo_controller.gd:5407-5423.
    pub morale_bonus: i64,
    /// `SoloController.is_aircraft` :5501.
    pub aircraft: bool,
    /// `u.has_special_rule("Strider") or u.has_special_rule("Flying")` — the p.13
    /// difficult-terrain exemption, a PLAIN rule-name read (no registry).
    pub charge_no_difficult: bool,
    /// `AiActRecorder._melee_shroud_params` :276-295 — `[penalty_in, floor_in]`.
    pub shroud: Option<[f64; 2]>,
}

/// `SoloController.morale_bonus_of`, evaluated over one member's rule list:
/// the named "Banner" (when the map fields it) and every DATA ALIAS whose entry
/// resolves to the Banner primitive.
fn banner_bonus_of(reg: &mut Registries, p: &Profile, rules: &[String]) -> i64 {
    let mut best = 0;
    let map = reg.rules_for(&p.game_system);
    if has_special_rule(rules, "Banner") && (map.empty || map.has_primitive(&p.faction_folder, "Banner")) {
        best = best.max(match map.lookup(&p.faction_folder, "Banner") {
            Some(e) => e.param_i("morale_bonus", BANNER_MORALE_BONUS),
            None => BANNER_MORALE_BONUS,
        });
    }
    let mut seen: Vec<String> = Vec::new();
    for raw in rules {
        let n = base_rule_name(raw);
        if n.is_empty() || n == "Banner" || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        if let Some(e) = map.lookup(&p.faction_folder, &n) {
            if e.primitive.as_deref() == Some("Banner") {
                best = best.max(e.param_i("morale_bonus", 0));
            }
        }
    }
    best
}

/// `AiActRecorder._melee_shroud_params` act_recorder.gd:276-295 — the named rule
/// first, then the DATA aliases of the two Shrouding primitives, in that order.
fn melee_shroud_params(reg: &mut Registries, p: &Profile) -> Option<[f64; 2]> {
    if rule_on_all_models(p, "Melee Shrouding") {
        let map = reg.rules_for(&p.game_system);
        let e = map.lookup(&p.faction_folder, "Melee Shrouding");
        return Some(match e {
            Some(e) => [
                e.param_f("move_penalty_in", SHROUD_CHARGE_PENALTY_IN),
                e.param_f("floor_in", SHROUD_FLOOR_IN),
            ],
            None => [SHROUD_CHARGE_PENALTY_IN, SHROUD_FLOOR_IN],
        });
    }
    for prim in ["Melee Shrouding", "Ranged Shrouding"] {
        for hit in rules_of_primitive(reg, p, prim) {
            if hit.name == "Melee Shrouding"
                || hit.name == "Ranged Shrouding"
                || !rule_on_all_models(p, &hit.name)
            {
                continue;
            }
            let map = reg.rules_for(&p.game_system);
            let Some(e) = map.lookup(&p.faction_folder, &hit.name) else { continue };
            let pen = e.param_f("move_penalty_in", e.param_f("melee_move_penalty_in", 0.0));
            if pen <= 0.0 {
                continue;
            }
            return Some([pen, e.param_f("melee_floor_in", e.param_f("floor_in", SHROUD_FLOOR_IN))]);
        }
    }
    None
}

/// `SoloController.ranged_shroud_reach_in` solo_controller.gd:5642-5661 — the
/// literal name first (its own entry's `range_penalty_in`/`floor_in`, the
/// SHROUD_* constants as defaults), then the DATA aliases of the primitive
/// (Darkborn, Shadowborn, Wild Veil and their Boosts — "-4\"/-8\" range to a
/// min. of 6\""), each on all models like the base form. `None` = the unit
/// carries no rule of the family. The composite aliases' melee half already
/// rides `melee_shroud_params` above. EPOCH-GATED (`acts::rule_on`): the
/// alias walk is wave-3 behaviour, so a record below `EPOCH_6_TABLE_RULES`
/// keeps the pre-port reading — the bare literal with the fixed constants.
fn ranged_shroud_params(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> Option<[f64; 2]> {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return rule_on_all_models(p, "Ranged Shrouding")
            .then_some([SHROUD_RANGE_PENALTY_IN, SHROUD_FLOOR_IN]);
    }
    if rule_on_all_models(p, "Ranged Shrouding") {
        let map = reg.rules_for(&p.game_system);
        let e = map.lookup(&p.faction_folder, "Ranged Shrouding");
        return Some(match e {
            Some(e) => [
                e.param_f("range_penalty_in", SHROUD_RANGE_PENALTY_IN),
                e.param_f("floor_in", SHROUD_FLOOR_IN),
            ],
            None => [SHROUD_RANGE_PENALTY_IN, SHROUD_FLOOR_IN],
        });
    }
    for hit in rules_of_primitive(reg, p, "Ranged Shrouding") {
        if hit.name == "Ranged Shrouding" || !rule_on_all_models(p, &hit.name) {
            continue;
        }
        let map = reg.rules_for(&p.game_system);
        let Some(e) = map.lookup(&p.faction_folder, &hit.name) else { continue };
        return Some([
            e.param_f("range_penalty_in", SHROUD_RANGE_PENALTY_IN),
            e.param_f("floor_in", SHROUD_FLOOR_IN),
        ]);
    }
    None
}

/// The four reads above for one unit profile.
pub fn capture_reads(reg: &mut Registries, p: &Profile) -> CaptureReads {
    let mut morale_bonus = banner_bonus_of(reg, p, &p.special_rules);
    for hero in &p.attached_hero_rules {
        morale_bonus = morale_bonus.max(banner_bonus_of(reg, p, hero));
    }
    CaptureReads {
        morale_bonus,
        aircraft: unit_rule_active(reg, p, "Aircraft"),
        charge_no_difficult: has_special_rule(&p.special_rules, "Strider")
            || has_special_rule(&p.special_rules, "Flying"),
        shroud: melee_shroud_params(reg, p),
    }
}

/// `AiEv._regen_target` ai_ev.gd:171-177, plus block B10's Resistance leg
/// (`main._solo_regen_pick` main.gd:6591-6599): the Regeneration family's
/// whole-unit rule ignores normal wounds on 6+, SPELL wounds on 2+. The
/// whole-unit gate is the Self-Repair shape; `unit_rule_active` says the
/// registry fields the rule for this (system, faction). The candidate joins
/// the MIN fold — the most generous (lowest) threshold binds (main.gd:6581).
/// Against SPELL wounds the key choice is `from_spell`'s (main.gd:6595), so
/// the spell twin folds in the same pass. Returns (target, target_spell).
///
/// The Regeneration family's DATA-ALIAS wave (main.gd:6637-6652, the table's
/// coverage wave over `RulesRegistry.unit_rules_of_primitive(unit,
/// "Regeneration")`): every carried rule whose registry entry resolves to the
/// "Regeneration" primitive folds its own `ignore_target` /
/// `ignore_target_spell` into the same MIN — Plaguebound (6+), Protected
/// (6+), Cursed Undead (6+), Knightborn (6+, spells 4+), Angelic Blessing
/// (6+, spells 4+), their Boosts (the 5-6/2-5 upgrades), Protection Feat,
/// Grounded Protection, Regeneration Buff, Self-Repair Boost. Whole-unit
/// entries (`all_models`) gate on every model like Self-Repair; the three
/// named forms above stay the one truth (main.gd:6639-6641) and are skipped.
/// `uses_per_game`, `terrain_within_in`, `upgrades` and `spell_only` are
/// unread — the table's own alias layer reads none of them either
/// (main.gd:6643-6650). EPOCH-GATED (`acts::rule_on`): new behaviour, so
/// epoch 0/2 corpora replay byte-exact and epoch CURRENT_RULES_EPOCH (= 3)
/// folds the aliases in.
fn regen_targets(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> (i64, i64) {
    let base = if has_special_rule(&p.special_rules, "Regeneration")
        || has_special_rule(&p.special_rules, "Medical Training")
    {
        let map = reg.rules_for(&p.game_system);
        match map.lookup(&p.faction_folder, "Regeneration") {
            Some(e) => e.param_i("ignore_target", REGENERATION_TARGET),
            None => REGENERATION_TARGET,
        }
    } else if rule_on_all_models(p, "Self-Repair") {
        let map = reg.rules_for(&p.game_system);
        match map.lookup(&p.faction_folder, "Self-Repair") {
            Some(e) => e.param_i("ignore_target", SELF_REPAIR_TARGET),
            None => SELF_REPAIR_TARGET,
        }
    } else {
        0
    };
    let mut picked = (base, base);
    if rule_on_all_models(p, "Resistance") && unit_rule_active(reg, p, "Resistance") {
        let map = reg.rules_for(&p.game_system);
        let e = map.lookup(&p.faction_folder, "Resistance");
        let rs = match e {
            Some(e) => e.param_i("ignore_target", RESISTANCE_TARGET),
            None => RESISTANCE_TARGET,
        };
        let rs_spell = match e {
            Some(e) => e.param_i("ignore_target_spell", RESISTANCE_TARGET_SPELL),
            None => RESISTANCE_TARGET_SPELL,
        };
        let most_generous = |cand: i64| base == 0 || cand < base;
        picked = (
            if most_generous(rs) { rs } else { base },
            if most_generous(rs_spell) { rs_spell } else { base },
        );
    }
    // The DATA-ALIAS wave itself (main.gd:6642-6652): the carrier walk is
    // `rules_of_primitive`'s (own + item-granted, each name once), the gate
    // and the two thresholds are the table's per-entry reads, the fold is the
    // running MIN. Gated whole by `rule_on` — see the doc above.
    if rule_on(rules_epoch, EPOCH_3_TABLE_RULES) {
        let map = reg.rules_for(&p.game_system);
        let mut raws: Vec<&String> = p.special_rules.iter().collect();
        raws.extend(p.item_grants.iter());
        let mut seen: Vec<String> = Vec::new();
        for raw in raws {
            let n = base_rule_name(raw);
            if n.is_empty()
                || seen.iter().any(|s| *s == n)
                || n == "Regeneration"
                || n == "Medical Training"
                || n == "Self-Repair"
                || n == "Resistance"
            {
                continue;
            }
            seen.push(n.clone());
            let Some(e) = map.lookup(&p.faction_folder, &n) else {
                continue;
            };
            if e.primitive.as_deref() != Some("Regeneration") {
                continue;
            }
            if e.param_b("all_models") && !rule_on_all_models(p, &n) {
                continue;
            }
            let normal = e.param_i("ignore_target", 0);
            let spell = e.param_i("ignore_target_spell", normal);
            if normal > 0 && (picked.0 == 0 || normal < picked.0) {
                picked.0 = normal;
            }
            if spell > 0 && (picked.1 == 0 || spell < picked.1) {
                picked.1 = spell;
            }
        }
    }
    picked
}

/// The SHOOTING leg's three die params (`ap_bonus`/`hit_bonus`/`low_roll_max`)
/// off the carried rule's own registry entry — "Unpredictable" first, then the
/// alias "Unpredictable Shooter" (`_ctx_of`'s flag order), defaults 1/1/3
/// (`unpredictable_fighter_effect` ai_combat_math.gd:387-388).
fn unpredictable_shooting_params(reg: &mut Registries, p: &Profile) -> (i64, i64, i64) {
    for name in ["Unpredictable", "Unpredictable Shooter"] {
        if has_exact_rule(&p.special_rules, name) && unit_rule_active(reg, p, name) {
            let map = reg.rules_for(&p.game_system);
            if let Some(e) = map.lookup(&p.faction_folder, name) {
                return (
                    e.param_i("ap_bonus", 1),
                    e.param_i("hit_bonus", 1),
                    e.param_i("low_roll_max", 3),
                );
            }
        }
    }
    (1, 1, 3)
}

/// Block B13 — `_solo_retaliate_hits_per_wound` main.gd:4521-4529, gated by
/// `_solo_retaliate_hits`'s `unit_rule_active` (main.gd:4568): 0 when the unit
/// does not carry the rule for its (system, faction). The scale is the rating
/// (`maxi(1, rating)` — a bare "Retaliate" lashes back ONE hit per wound); the
/// registry's `hits_per_wound` knob overrides only when NUMERIC. The shipped
/// entries carry the string "X" = "the rule's own rating", and a non-numeric
/// string falls back to the rating (main.gd:4524-4526), so a missing map keeps
/// the shipped wave-7 hardcoding byte-identical.
fn retaliate_hits_per_wound(reg: &mut Registries, p: &Profile) -> i64 {
    if !unit_rule_active(reg, p, "Retaliate") {
        return 0;
    }
    let rating = unit_rating(&p.special_rules, "Retaliate").max(1);
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map.lookup(&p.faction_folder, "Retaliate") else { return rating };
    match e.params.get("hits_per_wound") {
        Some(serde_json::Value::Number(n)) => n.as_f64().map(|f| f as i64).unwrap_or(rating).max(1),
        Some(serde_json::Value::String(s)) => s.trim().parse::<i64>().map(|v| v.max(1)).unwrap_or(rating),
        _ => rating,
    }
}

/// Block C4 — the death-half of `Deathstrike` / `Self-Destruct`
/// (`_solo_deathstrike_hits` main.gd:16709-16720): each rule pays
/// `maxi(rating, 1)` hits PER MODEL KILLED this strike phase, so one unit
/// stamps the SUM of both literals, each gated by `unit_rule_active` — a
/// faction whose map fields neither stays silent (the shipped maps field
/// Deathstrike only in gf goblin_reclaimers/infected_colonies and aof
/// kingdom_of_angels, Self-Destruct only in gf alien_hives/ratmen_clans).
/// The rating is the rule's own ("Deathstrike(2)" -> 2, a bare name -> 1),
/// the `retaliate_hits_per_wound` read; the registry's `rating` param is the
/// string "X" = the rule's own rating, so no knob override exists here.
fn death_hits_per_kill(reg: &mut Registries, p: &Profile) -> i64 {
    let mut hits = 0;
    for name in ["Deathstrike", "Self-Destruct"] {
        if unit_rule_active(reg, p, name) {
            hits += unit_rating(&p.special_rules, name).max(1);
        }
    }
    hits
}

/// `AiEv.ctx_for` ai_ev.gd:135-165. `models` stays at the live-unit reading;
/// `BattleSim._ctx_of` overwrites it with the snapshot's `alive` on every call.
fn ctx_for(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> Ctx {
    let armor = if unit_rule_active(reg, p, "Armor") {
        unit_rating(&p.special_rules, "Armor")
    } else {
        0
    };
    let morale_bonus = if unit_rule_active(reg, p, "Banner") {
        let map = reg.rules_for(&p.game_system);
        match map.lookup(&p.faction_folder, "Banner") {
            Some(e) => e.param_i("morale_bonus", BANNER_MORALE_BONUS),
            None => BANNER_MORALE_BONUS,
        }
    } else {
        0
    };
    let (stealth_alias_penalty, stealth_alias_over_in) = stealth_alias_of(reg, p);
    let upr_shooting = (has_exact_rule(&p.special_rules, "Unpredictable")
        && unit_rule_active(reg, p, "Unpredictable"))
        || (has_exact_rule(&p.special_rules, "Unpredictable Shooter")
            && unit_rule_active(reg, p, "Unpredictable Shooter"));
    let (upr_ap_bonus, upr_hit_bonus, upr_low_roll_max) = if upr_shooting {
        unpredictable_shooting_params(reg, p)
    } else {
        (1, 1, 3)
    };
    let regen_targets = regen_targets(reg, p, rules_epoch);
    // Block C2 — the melee/charge leg of the Shot Modifier family (see the
    // `Ctx` fields). The name list IS the port: these three are exactly the
    // family's entries with no runtime gate, and naming them one by one keeps
    // the rest of the primitive (Grounded Precision, Precision Feat, Mobile
    // Artillery, ...) uncredited — #489's lesson.
    let (mut melee_hit_bonus, mut melee_hit_bonus_charge) = (0, 0);
    for (name, charge_only) in [
        ("Good Fighter", false),
        ("Precision Fighter Aura", false),
        ("Precision Charge Aura", true),
    ] {
        if !unit_rule_active(reg, p, name) {
            continue;
        }
        let map = reg.rules_for(&p.game_system);
        let Some(e) = map.lookup(&p.faction_folder, name) else {
            continue;
        };
        let hb = e.param_i("hit_bonus", 0);
        if charge_only {
            melee_hit_bonus_charge += hb;
        } else {
            melee_hit_bonus += hb;
        }
    }
    // Block C5 — Instinctive's carried amount, off the rule's own literal and
    // its registry params (`unit_rules_of_primitive(shooter, "Instinctive")`'s
    // `hit_bonus`, default 1 — main.gd:5780-5782). The closest-target GATE is
    // positional and lives in `sim::instinctive_applies`.
    let instinctive_hit_bonus = if unit_rule_active(reg, p, "Instinctive") {
        match reg.rules_for(&p.game_system).lookup(&p.faction_folder, "Instinctive") {
            Some(e) => e.param_i("hit_bonus", 1),
            None => 1,
        }
    } else {
        0
    };
    let ranged_shroud = ranged_shroud_params(reg, p, rules_epoch);
    Ctx {
        quality: p.quality,
        defense: armored_defense(p.defense, armor),
        morale_bonus,
        tough: unit_rating(&p.special_rules, "Tough").max(1),
        models: 1, // placeholder; `_ctx_of` always writes the snapshot's alive
        artillery: has_special_rule(&p.special_rules, "Artillery"),
        furious: has_special_rule(&p.special_rules, "Furious"),
        fearless: has_special_rule(&p.special_rules, "Fearless"),
        fear: unit_rating(&p.special_rules, "Fear"),
        no_retreat: unit_rule_active(reg, p, "No Retreat"),
        // BOTH variants, in `_solo_unpredictable_rule`'s own order and with its
        // own gates: the melee-only Fighter form needs the rule on every model,
        // the generic form an EXACT rule name plus a registry that fields it.
        unpredictable: rule_on_all_models(p, "Unpredictable Fighter")
            || (has_exact_rule(&p.special_rules, "Unpredictable")
                && unit_rule_active(reg, p, "Unpredictable")),
        // The SHOOTING leg, `_solo_unpredictable_rule(striker, false)`'s own
        // two branches (:5406/:5409-5410) — see `upr_shooting` above. The
        // melee-only "Unpredictable Fighter" is never consulted here.
        unpredictable_shooting: upr_shooting,
        // The die's three params come off the carried rule's own registry
        // entry (defaults 1/1/3, the table's `unpredictable_fighter_effect`).
        unpredictable_ap_bonus: upr_ap_bonus,
        unpredictable_hit_bonus: upr_hit_bonus,
        unpredictable_low_roll_max: upr_low_roll_max,
        // The table asks the whole joined chain (`_solo_joined_chain`
        // main.gd:16677). The port sees an attached hero only as a list of rule
        // NAMES, so the primitive layer answers for the unit itself and an exact
        // name answers for the heroes — an alias carried ONLY by a hero is the
        // one case this misses, and it is named in `resolve_melee_with_tray`.
        unwieldy: !rules_of_primitive(reg, p, "Unwieldy").is_empty()
            || p.attached_hero_rules.iter().any(|hr| has_exact_rule(hr, "Unwieldy")),
        impact: unit_rating(&p.special_rules, "Impact"),
        heavy_impact: unit_rating(&p.special_rules, "Heavy Impact"),
        ravage: unit_rating(&p.special_rules, "Ravage"),
        stealth: rule_on_all_models(p, "Stealth"),
        stealth_alias_penalty,
        stealth_alias_over_in,
        evasive: rule_on_all_models(p, "Evasive"),
        melee_evasion: rule_on_all_models(p, "Melee Evasion"),
        fortified: rule_on_all_models(p, "Fortified"),
        // Guarded OR Versatile Defense — ai_ev.gd:157-158.
        guarded: rule_on_all_models(p, "Guarded") || rule_on_all_models(p, "Versatile Defense"),
        ranged_shrouding: ranged_shroud.is_some(),
        ranged_shroud_penalty_in: ranged_shroud.map_or(SHROUD_RANGE_PENALTY_IN, |s| s[0]),
        ranged_shroud_floor_in: ranged_shroud.map_or(SHROUD_FLOOR_IN, |s| s[1]),
        shielded: rule_on_all_models(p, "Shielded"),
        in_cover: false,
        // HARD 0, and it stays 0: `BattleSim._ctx_of` never passes
        // `AiEv.ctx_for`'s third argument either (battle_sim.gd:702,
        // ai_ev.gd:135). The table counts the DEFENDER's alive models whose
        // melee weapons carry Counter (`SoloController.counter_models_of`), a
        // per-MODEL loadout read the capture does not carry — so Counter's
        // Impact reduction is inert in this port, and `resolve_melee_with_tray`
        // raises `counter_strikes_first` whenever it would have mattered.
        counter_models: 0,
        regeneration: regen_targets.0 > 0,
        regen_target: regen_targets.0,
        regen_target_spell: regen_targets.1,
        fatigued: false,
        retaliate_hits_per_wound: retaliate_hits_per_wound(reg, p),
        death_hits_per_kill: death_hits_per_kill(reg, p),
        instinctive_hit_bonus,
        hit_mod: 0,
        vs_hit_mod: 0,
        melee_hit_bonus,
        melee_hit_bonus_charge,
        unstoppable_grant: false,
        rending_grant: false,
        thrust_grant: false,
        relentless_grant: false,
        shred_grant: false,
        slayer_grant: false,
        surge_grant: false,
        versatile_grant: false,
        pierce_shooting_grant: false,
        pierce_melee_grant: false,
        pierce_assault_grant: false,
        indirect_mark: false,
        range_mark_in: 0.0,
        growth_ap_mod: 0,
        growth_hit_mod: 0,
        ambush_arrival_ap: 0,
    }
}

/// The stamping pass `AiEv.stamp_sergeant` ai_ev.gd:203-291 runs over ONE
/// profile array. The melee and the ranged set each get their own call in
/// `BattleSim._profiles_of` (battle_sim.gd:719-720), so it runs twice here too;
/// the `facet_applies` gates read each profile's own range.
fn stamp(
    reg: &mut Registries,
    p: &Profile,
    shoot: &mut [ShootProfile],
    unimplemented: &mut Vec<Unimplemented>,
) {
    // 1. Versatile Attack, unit-wide (ai_ev.gd:209-217).
    if has_special_rule(&p.special_rules, "Versatile Attack")
        || !rules_of_primitive(reg, p, "Versatile Attack").is_empty()
    {
        for sp in shoot.iter_mut() {
            sp.versatile_attack = true;
        }
    }
    // 2. Ferocious = Surge on every weapon, EXACT match (ai_ev.gd:218-224).
    if p.special_rules.iter().any(|r| r.trim() == "Ferocious") {
        for sp in shoot.iter_mut() {
            sp.surge = true;
        }
    }
    // 3. Surge-family data aliases (ai_ev.gd:225-249). `extra_attack`
    //    (surge_attack — block B6, the extra-ATTACK-DIE form: Bloodborn/Clan
    //    Warrior/Primal/Predator/Royal Warrior/Crazed/Psychotic) is now PORTED,
    //    read by `dice.rs`'s `surge_attack_hits`; the plain auto-hit form now
    //    stamps its `within_in` gate too (ai_ev.gd:228-231), read by `dice.rs`'s
    //    epoch-gated surge block.
    for hit in rules_of_primitive(reg, p, "Surge") {
        if hit.name == "Surge" || hit.name == "Ferocious" || !hit.upgrades.is_empty() {
            continue;
        }
        for sp in shoot.iter_mut() {
            if facet_applies(hit.melee_only, hit.shooting_only, sp.range) {
                if hit.extra_attack {
                    sp.surge_attack = true;
                } else {
                    sp.surge = true;
                    if hit.within_in > 0.0 {
                        sp.surge_within_in = hit.within_in;
                    }
                }
            }
        }
    }
    // 3b. Surge UPGRADE entries (ai_ev.gd:250-260): the extra-attack-die
    //  family's own Boost variants (Primal Boost et al.) move `surge_attack_low`,
    //  and the plain auto-hit Boosts (Devout/Ferocious/Lucky Boost) stamp
    //  `surge_low`/`surge_over_in` onto every profile the base rule already
    //  gave `surge` — both read by `dice.rs`'s epoch-gated surge block.
    //  `profile_ev` (combat.rs) stays blind to all of them, exactly like
    //  ai_ev.gd:373-385's EV metric.
    for hit in rules_of_primitive(reg, p, "Surge") {
        if hit.upgrades.is_empty() || !has_exact_rule(&p.special_rules, &hit.upgrades) {
            continue;
        }
        if hit.extra_attack {
            for sp in shoot.iter_mut() {
                if sp.surge_attack {
                    sp.surge_attack_low = hit.surge_low;
                }
            }
            continue;
        }
        for sp in shoot.iter_mut() {
            if sp.surge {
                sp.surge_low = hit.surge_low;
                sp.surge_over_in = hit.over_in;
            }
        }
    }
    // 4. Rending data aliases (ai_ev.gd:261-272).
    for hit in rules_of_primitive(reg, p, "Rending") {
        if hit.name == "Rending" {
            continue;
        }
        for sp in shoot.iter_mut() {
            if facet_applies(hit.melee_only, hit.shooting_only, sp.range) {
                sp.rending = true;
            }
        }
    }
    // 5. Cover-ignore facet from the Indirect primitive's alias form (ai_ev.gd:273-281).
    for hit in rules_of_primitive(reg, p, "Indirect") {
        if hit.name != "Indirect" && hit.cover_only && hit.ignores_cover {
            for sp in shoot.iter_mut() {
                if sp.range > 0 {
                    sp.ignores_cover = true;
                }
            }
        }
    }
    // 6. The Shred data-alias FAMILY (main.gd:3001/:4355 — the dead-aura
    //    wave's `unit_rule_active(member, "Shred") or
    //    _solo_shred_facet_applies`): the plain unit-level name (whose
    //    empty-map fallback the primitive walk cannot see) plus EVERY carried
    //    Shred-primitive entry — "Shred in Melee"/"when Shooting" facet-scoped,
    //    Destroyer/Infected/Warbound ungated. On `shred_alias`, never `shred`:
    //    the weapon's own flag keeps its meaning and the dice-path epoch gate
    //    (dice.rs `save_batch`, `rule_on(rules_epoch, CURRENT_RULES_EPOCH)`)
    //    keeps every pre-port corpus byte-exact. `profile_ev` reads neither
    //    leg — ai_ev.gd's EV imagination sees the weapon flag only.
    let plain_shred = unit_rule_active(reg, p, "Shred");
    let shred_hits = rules_of_primitive(reg, p, "Shred");
    for sp in shoot.iter_mut() {
        if plain_shred
            || shred_hits
                .iter()
                .any(|h| facet_applies(h.melee_only, h.shooting_only, sp.range))
        {
            sp.shred_alias = true;
        }
    }
    // 6b. Shred UPGRADE entries (the Boost family): fires only when the model
    //     ALSO carries the entry's `upgrades` base rule, stamps the widened
    //     save-fail window + `over_in` gate onto every shredding profile.
    //     Read by the volley's epoch-4 shred window (`rule_on(rules_epoch, 4)`,
    //     dice.rs `save_batch`); melee never widens (no pre-charge gap
    //     measured — dice.rs NOT-PORTED, the Surge Boosts' 5s shape).
    for hit in &shred_hits {
        if hit.save_fail_max <= 0
            || hit.upgrades.is_empty()
            || !has_exact_rule(&p.special_rules, &hit.upgrades)
        {
            continue;
        }
        for sp in shoot.iter_mut() {
            if sp.shred_alias {
                sp.shred_low = hit.save_fail_max;
                sp.shred_over_in = hit.over_in;
            }
        }
    }
    // 7. Sergeant (ai_ev.gd:282-291). Its share reads the LIVE alive count,
    //    which the static profile does not carry — reported, never guessed.
    if unit_rule_active(reg, p, "Sergeant") {
        unimplemented.push(Unimplemented {
            rule: "Sergeant".into(),
            why: "sergeant_attacks needs GameUnit.get_alive_count() at the moment of the call (ai_ev.gd:284) — not in the static profile".into(),
        });
    }
}

/// `BattleSim._profiles_of`'s UNIT-level striker scan (battle_sim.gd:1003-1021,
/// EV imagination only): Bane / Rending / Unstoppable carried by the UNIT are
/// OR-ed onto every profile — prefix scan, no registry gate. Bane/Rending have
/// a real weapon-OR-unit fallback on the table's own DICE path too (main.gd:
/// 6396/6852/6880) and keep applying to both `shoot`/`melee` fields here.
/// Unstoppable does NOT: the table's dice path (ai_shooting.gd:132) reads
/// only the weapon's own exact rule, so `u_unstop` lands on `unstoppable_ev`
/// alone — an "Unstoppable Mark" carrier must stay non-Unstoppable on the
/// tray. Found by #489, caveat 4; this is that ticket.
///
/// CLASS FIX (`acts::rule_on`): at `rules_epoch >= CURRENT_RULES_EPOCH` the
/// Bane half becomes the table's own scope ladder (`_solo_striker_has_bane`
/// main.gd:6525-6560) — "Bane in Melee"/"Bane in Melee Buff" melee-only,
/// "Bane when Shooting" shooting-only, a striker's own "… Aura" never fires,
/// and the Bane-primitive DATA-ALIAS wave (Bestial, Mischievous, Scrapper —
/// non-"Bane", non-"Aura", `reroll_save_sixes`) joins it, exactly main.gd:
/// 6553-6560. Every record below that epoch keeps the flat prefix reading.
fn stamp_unit_strikers(reg: &mut Registries, p: &Profile, shoot: &mut [ShootProfile], rules_epoch: u32) {
    let table_ladder = rule_on(rules_epoch, EPOCH_3_TABLE_RULES);
    let mut u_bane = false;
    let mut melee_bane = false;
    let mut shooting_bane = false;
    let mut u_rending = false;
    let mut u_unstop = false;
    for r in &p.special_rules {
        let rs = r.trim();
        if rs.starts_with("Bane") || rs.starts_with("Lacerate") {
            if table_ladder && rs.ends_with("Aura") {
                continue; // a striker's own aura rule never fires — main.gd:6540
            }
            if table_ladder && !rs.starts_with("Lacerate") {
                if rs.starts_with("Bane in Melee") {
                    melee_bane = true;
                } else if rs.starts_with("Bane when Shooting") {
                    shooting_bane = true;
                } else {
                    u_bane = true; // plain "Bane", "Bane Mark", "… Buff"
                }
            } else {
                u_bane = true;
            }
        } else if rs.starts_with("Rending") {
            u_rending = true;
        } else if rs.starts_with("Unstoppable") && !rs.contains(" in ") && !rs.contains(" when ") {
            u_unstop = true;
        }
    }
    if table_ladder {
        // The coverage wave (main.gd:6553-6560): Bane-primitive data aliases
        // whose own entry carries `reroll_save_sixes` — no scope qualifier.
        for hit in rules_of_primitive(reg, p, "Bane") {
            if hit.name.starts_with("Bane") || hit.name.ends_with("Aura") {
                continue;
            }
            u_bane |= hit.reroll_save_sixes;
        }
    }
    // Lacerate family (rules-wave2-lacerate2): main.gd:6990-7001's unit-level
    // coverage wave — every carried Lacerate-primitive entry whose params
    // carry `bypass_regen` bypasses Regeneration, facet-scoped per profile
    // ("Ignores Regeneration" ungated, "… in Melee" melee-only); the plain
    // "Lacerate" name keeps its own prefix reading above (main.gd:6995-6997).
    // EPOCH GATES BY RECORDING SHA (05.09.): Lacerate merged (`cf8831d1`)
    // BEFORE the Gen-2b recording fleet launched, so it needs its OWN frozen
    // value, `acts::EPOCH_4_TABLE_RULES` — NOT `EPOCH_5_TABLE_RULES`, which is
    // for the four wave-2 families that merged after the fleet launched.
    if rule_on(rules_epoch, EPOCH_4_TABLE_RULES) {
        for hit in rules_of_primitive(reg, p, "Lacerate") {
            if !hit.bypass_regen || hit.name.starts_with("Lacerate") {
                continue;
            }
            melee_bane |= hit.melee_only;
            shooting_bane |= hit.shooting_only;
            u_bane |= !hit.melee_only && !hit.shooting_only;
        }
    }
    for sp in shoot.iter_mut() {
        sp.bane |= u_bane
            || (melee_bane && sp.range <= 0)
            || (shooting_bane && sp.range > 0);
        sp.rending |= u_rending;
        sp.unstoppable_ev = sp.unstoppable || u_unstop;
    }
}

/// `RulesRegistry.unit_rules_of_primitive(shooter, "Shot Modifier")`,
/// main.gd:5681-5701 — scoped to this port's eight named carriers: B4's
/// (Good Shot, Bad Shot, Targeting Visor) plus block C3's four flat/over-9"
/// shooting siblings (Targeting Visor Boost, Precision Shooter Aura,
/// Buccaneer, Buccaneer Boost; `assets/solo/rules_mechanics_gf/aof.json`) plus
/// the rung-C data alias Precision Hunter (Targeting Visor's word-for-word
/// twin — AUDIT_armybook_flanks_2026-09-02.md).
/// Buccaneer's `over_in: 9` alone routes it into `hit_bonus_over9` (strictly
/// past 9"); everything else is flat — `phase: "shoot"` is read by nobody in
/// the table loop, so Precision Shooter Aura is simply a flat shooting bonus.
/// None of the eight sets `melee_only` / `all_attacks` / `when: charge`, so —
/// unlike the unit-level strikers above — the bonus never reaches `melee`,
/// only `shoot` (main.gd:5627-5636 excludes it from the melee branch on that
/// same gate). The melee-/charge-scoped members (Good Fighter, Precision
/// Fighter Aura, Precision Charge Aura) are stamped onto `Ctx` by `ctx_for`
/// (block C2); the runtime-gated ones — Mobile Artillery
/// (`requires_stationary`), Grounded Precision (`terrain_within_in`),
/// Precision Feat (`uses_per_game`) — stay out: this core has no runtime gate
/// for them, so stamping them flat would be bug #489's over-credit.
fn stamp_shot_modifier(reg: &mut Registries, p: &Profile, shoot: &mut [ShootProfile]) {
    let mut flat = 0;
    let mut over9 = 0;
    for name in [
        "Good Shot",
        "Bad Shot",
        "Targeting Visor",
        "Targeting Visor Boost",
        "Precision Shooter Aura",
        "Buccaneer",
        "Buccaneer Boost",
        // Rung C data port (AUDIT_armybook_flanks_2026-09-02.md): Precision
        // Hunter is Targeting Visor's word-for-word twin ("+1 to hit rolls
        // when shooting at enemies over 9\" away") — same primitive, same
        // params shape, added here rather than a new name-literal branch.
        "Precision Hunter",
    ] {
        if !unit_rule_active(reg, p, name) {
            continue;
        }
        let map = reg.rules_for(&p.game_system);
        let Some(e) = map.lookup(&p.faction_folder, name) else {
            continue;
        };
        let hb = e.param_i("hit_bonus", 0);
        if e.param_f("over_in", 0.0) > 0.0 {
            over9 += hb;
        } else {
            flat += hb;
        }
    }
    for sp in shoot.iter_mut() {
        sp.hit_bonus += flat;
        sp.hit_bonus_over9 += over9;
    }
}

/// One "Utility Buff" registry entry's params — `_solo_apply_utility_buffs`
/// main.gd:16487-16545 reads exactly these keys. Baked per unit at build time
/// because the resolver walks `RulesRegistry.unit_rules_of_primitive(member,
/// "Utility Buff")` per bearer, once per activation.
#[derive(Debug, Clone, Default)]
pub struct UtilityBuff {
    pub name: String,
    /// `vs_target` — an ENEMY-side Mark, consumed at the attack seam
    /// (`_solo_apply_vs_marks` :16738), never at the pre-attack slot.
    pub vs_target: bool,
    /// `reposition_in` — the block-B2a movement arm (Re-Position Artillery).
    pub reposition_in: f64,
    pub range_in: f64,
    /// `target` — "friendly" / "friendly_caster" / "friendly_artillery" / "enemy".
    pub target: String,
    pub needs_los: bool,
    pub max_targets: i64,
    pub hit_mod: i64,
    pub casting_mod: i64,
    pub morale_mod: i64,
    pub grants_rule: String,
    pub scope: String,
    /// `beneficiary` — "attackers" on the Mark family: the record belongs to
    /// whoever ATTACKS the bearer, never to the bearer's own net
    /// (main.gd:3652).
    pub beneficiary: String,
    pub once: bool,
}

/// The twelve "Utility Buff" names the wave-2 port reads at runtime, stamped
/// only from `rules_epoch` 4 on. Of the other 18 family names wave 3 ported
/// the two marks whose records this core now consumes (`sim::ctx_live` +
/// the volley sight/range seams); the remaining 16 stay stamped-but-unconsumed
/// (audited 2026-09-05: the grant-only names' nine granted names are read at
/// no `mods::granted`/`granted_vs` call site, `casting_mod` is recorded but
/// `Role::Casting` is never summed, and `defense_mod`/`ap_mod`/`move_mod`/
/// `range_bonus_in` are not modeled on `UtilityBuff` — `record_buff` drops
/// the all-zero row — their seams still do not exist on this core).
const WAVE2_UTILITY_BUFF_RULES: [&str; 12] = [
    "Unwieldy Debuff",
    "Unpredictable Shooter Mark",
    "Versatile Attack Buff",
    "Slayer Mark",
    "Piercing Assault Buff",
    "Piercing Shooting Mark",
    "Piercing Fighting Mark",
    "Self-Repair Boost Buff",
    "Cursed Undead Boost Buff",
    "Angelic Blessing Boost Buff",
    "Hold the Line Boost Buff",
    "Primal Boost Buff",
];

/// Every "Utility Buff" entry the unit carries, in `unit_rules_of_primitive`'s
/// own order (own rules then item grants, each base name once — rules_registry
/// .gd:155-176). The two printed defaults that differ between the arms are
/// resolved HERE, where `vs_target` is known: the friendly pick is 12" and
/// sight-free (main.gd:16493/16552), the Mark is 18" and needs sight (:16752/
/// :16758).
fn utility_buffs_of(reg: &mut Registries, p: &Profile, rules_epoch: u32, un: &mut Vec<Unimplemented>) -> Vec<UtilityBuff> {
    let mut out = Vec::new();
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    let map = reg.rules_for(&p.game_system);
    let mut seen: Vec<String> = Vec::new();
    for raw in raws {
        let n = base_rule_name(raw);
        if n.is_empty() || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        let Some(e) = map.lookup(&p.faction_folder, &n) else { continue };
        if e.primitive.as_deref() != Some("Utility Buff") {
            continue;
        }
        // WAVE 2 GATE (`acts::rule_on`, `EPOCH_5_TABLE_RULES`): these twelve names
        // are NEW behaviour — a record below rules_epoch 5 (Gen-2b's
        // stamping-gap window at 4 included) must never carry them.
        if !rule_on(rules_epoch, EPOCH_5_TABLE_RULES) && WAVE2_UTILITY_BUFF_RULES.contains(&n.as_str()) {
            continue;
        }
        let vs_target = e.param_b("vs_target");
        let target = match e.param_s("target") {
            "" => "friendly",
            s => s,
        };
        out.push(UtilityBuff {
            name: n,
            vs_target,
            reposition_in: e.param_f("reposition_in", 0.0),
            range_in: e.param_f("range_in", if vs_target { 18.0 } else { 12.0 }),
            target: target.to_string(),
            needs_los: e.param_b_or("needs_los", vs_target),
            max_targets: e.param_i("max_targets", 1).max(1),
            hit_mod: e.param_i("hit_mod", 0),
            casting_mod: e.param_i("casting_mod", 0),
            morale_mod: e.param_i("morale_mod", 0),
            grants_rule: e.param_s("grants_rule").to_string(),
            scope: e.param_s("scope").to_string(),
            beneficiary: e.param_s("beneficiary").to_string(),
            once: e.param_b_or("once", true),
        });
        // The ledger models four knobs (hit / casting / morale / grant) and the
        // movement arm. An entry whose whole effect is a knob it does NOT carry
        // — `def_mod`, `defense_mod`, `ap_mod`, `move_mod`, `range_bonus_in` —
        // would record an all-zero row that `record_buff` drops on the floor.
        // Named here rather than skipped in silence.
        let b = out.last().expect("just pushed");
        if !b.vs_target && b.reposition_in <= 0.0 && b.grants_rule.is_empty()
            && (b.hit_mod, b.casting_mod, b.morale_mod) == (0, 0, 0) {
            un.push(Unimplemented { rule: b.name.clone(), why:
                "Utility Buff params carry no hit/casting/morale mod and no grants_rule, so this resolver records nothing — main.gd:16534 builds the same three keys and _solo_record_spell_mod:3663 drops the all-zero row. If the rule works on the table it does so at a seam this port does not claim".into() });
        }
    }
    out
}

/// The Ambush family's own stamp (rules-wave2-ambush, 2026-09-04): the four
/// registry names that ride the "Ambush" primitive, each read at its OWN
/// literal — never a `rules_of_primitive` loop, the #489 trusted-whole trap
/// (an untracked primitive's token alone over-credits every name under it).
/// Gated `rule_on(rules_epoch, EPOCH_5_TABLE_RULES)`, frozen at `5` (the
/// stamping-gap fix, NOT the naive `4` — see `acts::EPOCH_5_TABLE_RULES`): a
/// wave-3 bump of `CURRENT_RULES_EPOCH` must not re-date these reads.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct AmbushFamily {
    /// "Ambushing Piercing Shot": `counts_as: "Ambush"` — the unit deploys AS
    /// an ambusher. Read here; the deploy-flag seam itself (list-side
    /// `_deploy_flags` has no live-registry reading) is a future port.
    pub counts_as_ambush: bool,
    /// The same name's shooting half: AP(+1) on the round the unit ARRIVES
    /// via Ambush (GF v3.5.3 rule text; the registry fields no AP param, the
    /// fixed +1 is the table's own hardcode shape — the Shred precedent).
    pub deploy_round_ap: i64,
    /// "Ambush Beacon": the carrier's waiver-circle radius in inches
    /// (`beacon_in`, the table's `beacon_radius_m` :9775-9777), the registry
    /// 6" fallback when the entry carries no value. 0.0 = no beacon rule.
    pub beacon_radius_in: f64,
    /// "Rapid Ambush": the round the carrier may first arrive from
    /// (`arrive_from_round`), the table's `ambush_earliest_round` :9832-9835
    /// hardcode as fallback. 0 = no Rapid Ambush (plain Ambush "round 2", the
    /// caller owns that answer).
    pub arrive_from_round: i64,
    /// "Ambush Re-Deployment": `re_reserve` + `uses_per_game` — the entry's
    /// params, read and stamped. The once-per-game withdraw beat itself is a
    /// future port: an OPTIONAL end-of-activation choice needs a core seam
    /// (and a policy) this wave does not invent.
    pub re_reserve: bool,
    pub re_reserve_uses: i64,
}

/// The Ambush family's per-profile read (`UnitStatic.ambush_family`): each
/// name gated by `unit_rule_active` — the unit carries it AND the map fields
/// it for this (system, faction) — with the entry's own params on top.
fn ambush_family_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> AmbushFamily {
    let mut f = AmbushFamily::default();
    if !rule_on(rules_epoch, EPOCH_5_TABLE_RULES) {
        return f;
    }
    for n in [
        "Ambushing Piercing Shot",
        "Ambush Beacon",
        "Rapid Ambush",
        "Ambush Re-Deployment",
    ] {
        if !unit_rule_active(reg, p, n) {
            continue;
        }
        let Some(e) = reg.rules_for(&p.game_system).lookup(&p.faction_folder, n) else {
            continue;
        };
        match n {
            "Ambushing Piercing Shot" => {
                f.counts_as_ambush = e.param_s("counts_as") == "Ambush";
                f.deploy_round_ap = 1;
            }
            "Ambush Beacon" => {
                f.beacon_radius_in =
                    e.param_f("beacon_in", crate::deployment::AMBUSH_BEACON_RADIUS_IN);
            }
            "Rapid Ambush" => {
                f.arrive_from_round = e.param_i("arrive_from_round", 1).max(0);
            }
            _ => {
                f.re_reserve = e.param_b("re_reserve");
                f.re_reserve_uses = e.param_i("uses_per_game", 1).max(0);
            }
        }
    }
    f
}

/// One "Growth Markers" registry entry — `_solo_growth_markers`/`_growth_
/// facet_bonus` main.gd:16978/17060. Block B7 consumes only the two facets a
/// LIVE training-pool carrier actually uses, the ones `_solo_growth_attack_
/// bonus` folds into the tray (main.gd:4287 AP, :5675-5680 shooting-only hit):
/// Piercing Growth (`per_round`, `ap_per_two`) and Precision Frenzy
/// (`on_kill`, `hit_per_marker`). Defensive Frenzy/Growth (`defense_*`),
/// Fortified Growth (`enemy_ap_per_two`, the defender-side sister at
/// main.gd:17084) and Regenerative Strength (`on_ignore_wound`, extra
/// attacks) are registry-gated and would be STAMPED by the loop below, but
/// carry none of the four fields this struct reads — `growth_of` reports
/// them instead of silently modelling them as inert.
#[derive(Debug, Clone, Default)]
pub struct GrowthRule {
    pub name: String,
    pub per_round: bool,
    pub on_kill: bool,
    pub max_markers: i64,
    pub ap_per_marker: i64,
    pub ap_per_two: i64,
    pub hit_per_marker: i64,
    pub hit_per_two: i64,
}

/// Every "Growth Markers" entry the unit carries (own rules + item grants,
/// `unit_rules_of_primitive`'s own order/de-dup — rules_registry.gd:155-176).
/// `state.growth_markers` is ONE counter per unit (see `sim::growth_bonus_
/// of`): the training pool never carries two such rules on one bearer, so a
/// unit with both would wrongly share one count — out of this block's scope.
fn growth_of(reg: &mut Registries, p: &Profile, un: &mut Vec<Unimplemented>) -> Vec<GrowthRule> {
    let mut out = Vec::new();
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    let map = reg.rules_for(&p.game_system);
    let mut seen: Vec<String> = Vec::new();
    for raw in raws {
        let n = base_rule_name(raw);
        if n.is_empty() || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        let Some(e) = map.lookup(&p.faction_folder, &n) else { continue };
        if e.primitive.as_deref() != Some("Growth Markers") {
            continue;
        }
        let g = GrowthRule {
            name: n,
            per_round: e.param_b("per_round"),
            on_kill: e.param_b("on_kill"),
            max_markers: e.param_i("max_markers", 4),
            ap_per_marker: e.param_i("ap_per_marker", 0),
            ap_per_two: e.param_i("ap_per_two", 0),
            hit_per_marker: e.param_i("hit_per_marker", 0),
            hit_per_two: e.param_i("hit_per_two", 0),
        };
        if (g.ap_per_marker, g.ap_per_two, g.hit_per_marker, g.hit_per_two) == (0, 0, 0, 0) {
            un.push(Unimplemented { rule: g.name.clone(), why:
                "Growth Markers params carry no ap/hit facet — block B7 only consumes the attack-bonus facets (main.gd:4287/:5675-5680); defense_per_marker/defense_per_two/enemy_ap_per_two/on_ignore_wound are not read".into() });
        }
        out.push(g);
    }
    out
}

/// The registry read behind `AiEv.stamp_conditional_ap` ai_ev.gd:291-306: the
/// conditional-AP spec of ONE rule name (None when the book has no entry, or an
/// entry without a `condition` key — the presence of that key IS the gate) plus
/// the entry's `on6_ap`, which the same GDScript loop stamps on the way past.
fn cond_ap_of(reg: &mut Registries, p: &Profile, base: &str) -> (Option<CondAp>, i64) {
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map.lookup(&p.faction_folder, base) else {
        return (None, 0);
    };
    let on6 = e.param_i("on6_ap", 0);
    if e.params.get("condition").is_none() {
        return (None, on6);
    }
    (
        Some(CondAp {
            ap_bonus: e.param_i("ap_bonus", 0),
            charge_only: e.param_b("charge_only"),
            gate: e.param_s("gate").to_string(),
            over_in: e.param_f("over_in", LONG_RANGE_IN),
            condition: e.param_s("condition").to_string(),
            threshold: e.param_i("threshold", 0),
        }),
        on6,
    )
}

/// LEGACY REPLAY ONLY — skip the NML-1103 conditional-AP stamp, so
/// `profile_ev` prices Shatter / Tear / Disintegrate / Melee Slayer / Piercing
/// Assault / Piercing Hunter at their PRINTED AP the way the pre-NML-1103
/// `BattleSim` did. Nothing else in this crate reads it, and `false` (the
/// default, and the only setting a fresh corpus may use) is the shipped rule.
///
/// Why a switch exists at all: `AiEv.stamp_conditional_ap` was never called in
/// the sim path, so every frozen corpus under `~/selfplay_out` recorded a search
/// that valued those weapons at AP(0) while the TABLE resolved them with the
/// bonus (`main.gd:6319`). Replaying one of those games against the fixed EV
/// measures the fix, not the search loop the corpus was cut to pin.
///
/// NEITHER READING IS GAME-TRUE FOREVER. The corpora pin the SEARCH LOOP, not
/// the rule; a corpus re-recorded after NML-1105 (the `core_selfplay.gd` loader)
/// will differ from both, and this flag retires with it. Never set it to make a
/// NEW recording agree with an old one.
pub static LEGACY_NO_COND_AP: AtomicBool = AtomicBool::new(false);

/// `AiEv.stamp_conditional_ap` ai_ev.gd:283-315 — NML-1103. The pass
/// `BattleSim._profiles_of` (battle_sim.gd:927) runs right after `stamp_sergeant`,
/// on the melee and the ranged array alike. WEAPON rules stamp their own spec;
/// the MODEL-level members of the family (Slayer / Piercing Hunter: "when this
/// model shoots…") sit on the UNIT and are stamped onto every profile, deduped
/// against the weapon's own rules BY NAME.
fn stamp_conditional_ap(reg: &mut Registries, p: &Profile, shoot: &mut [ShootProfile]) {
    if LEGACY_NO_COND_AP.load(Ordering::Relaxed) {
        return; // frozen-corpus replay — see the flag's own note
    }
    let mut unit_specs: Vec<(String, CondAp)> = Vec::new();
    for r in &p.special_rules {
        let base = base_rule_name(r);
        if let (Some(c), _) = cond_ap_of(reg, p, &base) {
            unit_specs.push((base, c));
        }
    }
    for sp in shoot.iter_mut() {
        let rules = sp.rules.clone();
        let mut seen: Vec<String> = Vec::new();
        for r in &rules {
            let base = base_rule_name(r);
            let (spec, on6) = cond_ap_of(reg, p, &base);
            if let Some(c) = spec {
                sp.cond_ap.push(c);
                seen.push(base);
            }
            // Crack's on-6-to-hit AP upgrade (:305-307) — a plain assignment in
            // GDScript, so the LAST rule of the weapon wins, not the largest.
            if on6 > 0 {
                sp.on6_ap = on6;
            }
        }
        for (n, c) in &unit_specs {
            if !seen.contains(n) {
                sp.cond_ap.push(c.clone());
            }
        }
    }
}

/// `AiShooting.profiles_in_range` ai_shooting.gd:14-26 — the merged RANGED set,
/// UNSTAMPED (the `AiEv.stamp_sergeant` pass belongs to `BattleSim._profiles_of`,
/// not to this function). `UnitStatic::build` calls it at 0.0 and stamps after;
/// `rows::board_rows` calls it at `EV_REF_DIST_IN` and stamps NOT AT ALL, which
/// is exactly what battle_sim.gd:206 does.
pub(crate) fn profiles_in_range(weapons: &[Weapon], dist_in: f64) -> Vec<ShootProfile> {
    let mut raw: Vec<ShootProfile> = Vec::new();
    for w in weapons {
        // `AiShooting._field_i(w, "range_value", 0)` — an int read; the
        // recorded value is `OPRWeapon.range_value`, already an integer.
        let rng_in = w.range as i64;
        if rng_in <= 0 || (rng_in as f64) < dist_in {
            continue;
        }
        if weapon_has(w, "Strafing") {
            continue; // NML-002: fires only through the move-through trigger
        }
        let attacks = w.attacks.max(0) * w.count.max(1);
        if attacks <= 0 {
            continue;
        }
        raw.push(base_profile(w, attacks, rng_in));
    }
    merge_identical(raw)
}

/// `AiShooting.melee_profiles` ai_shooting.gd:44-56 — every range-0 weapon, also
/// UNSTAMPED. Strafing is NOT excluded here: that filter lives in
/// `profiles_in_range` alone, and a melee weapon never carries the move-through
/// trigger.
pub(crate) fn melee_profiles(weapons: &[Weapon]) -> Vec<ShootProfile> {
    let mut raw: Vec<ShootProfile> = Vec::new();
    for w in weapons {
        if w.range as i64 > 0 {
            continue;
        }
        let attacks = w.attacks.max(0) * w.count.max(1);
        if attacks <= 0 {
            continue;
        }
        raw.push(base_profile(w, attacks, 0));
    }
    merge_identical(raw)
}

/// Nimble is Bounding's word-for-word twin, own D3 reach vs Bounding's D3+1
/// (AUDIT_armybook_flanks_2026-09-02.md rung C) — same named-carrier loop as
/// `unpredictable_shooting_params` above.
fn bounding_of(reg: &mut Registries, p: &Profile) -> Option<f64> {
    for name in ["Bounding", "Nimble"] {
        if unit_rule_active(reg, p, name) {
            let map = reg.rules_for(&p.game_system);
            return Some(match map.lookup(&p.faction_folder, name) {
                Some(e) => e.param_f("place_d3_plus", 1.0),
                None => 1.0,
            });
        }
    }
    None
}

/// The Quick/Fast move-band family's own per-entry param read — a named-
/// carrier loop credited by each name's OWN literal, never by a shared
/// primitive token (the census's trusted-whole trap, #489; the bare `fast`
/// token already exists as `doctrine.rs::StyleLabel::Fast` and must not start
/// crediting Fast-primitive entries). Sums every carrier the way the two band
/// passes stack them: per rule NAME, each contributing its own
/// `advance_mod`/`rush_mod` (`charge_mod` as the fallback). Epoch-gated:
/// `None` below `CURRENT_RULES_EPOCH` — see `UnitStatic::move_rule_mods`.
fn move_rule_mods_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> Option<Bands> {
    if !rule_on(rules_epoch, EPOCH_3_TABLE_RULES) {
        return None;
    }
    // zero-banded, NOT `Bands::default()` — those serde defaults are the
    // 6"/12" OPR fallback, not zero.
    let (mut acc, mut hit) = (Bands { advance: 0.0, rush: 0.0 }, false);
    for name in ["Agile", "Highborn", "Quick", "Scurry", "Rapid Charge", "Rapid Charge Aura"] {
        if !unit_rule_active(reg, p, name) {
            continue;
        }
        let map = reg.rules_for(&p.game_system);
        if let Some(e) = map.lookup(&p.faction_folder, name) {
            acc.advance += e.param_f("advance_mod", 0.0);
            acc.rush += e.param_f("rush_mod", e.param_f("charge_mod", 0.0));
            hit = true;
        }
    }
    if hit { Some(acc) } else { None }
}

impl UnitStatic {
    /// The legacy epoch-0 build — every corpus recorded before
    /// `Knobs::rules_epoch` existed reads back that epoch, so this answers
    /// exactly what it always answered. The epoch-aware caller is
    /// `build_for` (and a `StaticsCache` built `with_epoch`).
    pub fn build(reg: &mut Registries, p: &Profile) -> UnitStatic {
        Self::build_for(reg, p, 0)
    }

    /// The epoch-aware build: `rules_epoch` is the RECORD's own
    /// `Knobs::rules_epoch`, and the epoch-gated rule ports inside
    /// (`regen_targets`' Regeneration-family alias wave, the Bane family's
    /// scope ladder) stamp their behaviour only when
    /// `acts::rule_on(rules_epoch, CURRENT_RULES_EPOCH)`. The statics of one
    /// record are built from that record's header —
    /// `lib::build_statics`/`act_statics` and the two host caches do — so the
    /// gate rides the same line the profile table does.
    pub fn build_for(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> UnitStatic {
        let mut unimplemented: Vec<Unimplemented> = Vec::new();
        let mut shoot = profiles_in_range(&p.weapons, 0.0);
        stamp(reg, p, &mut shoot, &mut unimplemented);
        stamp_conditional_ap(reg, p, &mut shoot);
        stamp_unit_strikers(reg, p, &mut shoot, rules_epoch);
        stamp_shot_modifier(reg, p, &mut shoot);

        let mut melee = melee_profiles(&p.weapons);
        // The same stamping runs on the melee array (`_profiles_of(su, true)`
        // battle_sim.gd:719-720 takes the identical path); a rule the port
        // cannot model is reported ONCE, not once per array.
        let mut melee_unimpl: Vec<Unimplemented> = Vec::new();
        stamp(reg, p, &mut melee, &mut melee_unimpl);
        stamp_conditional_ap(reg, p, &mut melee);
        stamp_unit_strikers(reg, p, &mut melee, rules_epoch);
        // Lacerate+Counter wave, epoch-gated (`acts::rule_on`, epoch 3): the
        // Counter DATA aliases live on the MODEL — the table's strike-first
        // gate reads them unit-level (`_solo_has_counter`'s coverage wave,
        // main.gd:5932-5935) — so they stamp the melee array's own `counter`
        // flag, the same field the weapon-level rule lands on
        // (ai_shooting.gd:135). Melee-only by nature: the shooting array never
        // sees the flag. `rules_epoch` defaults to 0, so every pre-wave
        // record replays the Gen-0 rule set untouched.
        if rule_on(rules_epoch, EPOCH_3_TABLE_RULES)
            && (rule_on_all_models(p, "Counter-Attack")
                || rule_on_all_models(p, "Counter in Melee"))
        {
            for sp in melee.iter_mut() {
                sp.counter = true;
            }
        }
        // Surge family wave 2 (rules-wave2-surge2), gated on
        // `EPOCH_5_TABLE_RULES` (frozen at 5, never the literal 4 or the
        // CURRENT_RULES_EPOCH symbol) so a wave-3 bump cannot re-date the
        // reading: the six bonus-hits-per-six names are the
        // plain auto-hit form's own aliases (ai_ev.gd's alias loop stamps each
        // exactly like block 3 above; `bonus_hits_per_six` is read by table
        // and twin alike, and Great Sergeant's printed 5-6 / Surge Mark's
        // once-per-activation pick are dead data in the table's own stamp
        // loop). The named walk states that facet BY NAME — the census's
        // own-token evidence — while the wave-2 gate keeps every epoch-3
        // replay on the generic walk alone.
        if rule_on(rules_epoch, EPOCH_5_TABLE_RULES) {
            for hit in rules_of_primitive(reg, p, "Surge").into_iter().filter(|hit| {
                matches!(
                    hit.name.as_str(),
                    "Brutal" | "Great Sergeant" | "Devout" | "Surge when Shooting" | "Lucky" | "Surge Mark"
                )
            }) {
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    if facet_applies(hit.melee_only, hit.shooting_only, sp.range) {
                        sp.surge = true;
                    }
                }
            }
        }
        for u in melee_unimpl {
            if !unimplemented.contains(&u) {
                unimplemented.push(u);
            }
        }

        let is_caster = has_special_rule(&p.special_rules, "Caster")
            || has_special_rule(&p.special_rules, "Caster Group");
        let spells = if is_caster {
            reg.spells_for(&p.game_system, &p.faction_folder).to_vec()
        } else {
            Vec::new()
        };

        UnitStatic {
            ctx: ctx_for(reg, p, rules_epoch),
            name: p.name.clone(),
            shoot,
            melee,
            model_count: p.model_count,
            wounds_max: p.wounds_max.clone(),
            quality: p.quality,
            fearless: has_special_rule(&p.special_rules, "Fearless"),
            is_caster,
            spells,
            caster_group: has_special_rule(&p.special_rules, "Caster Group"),
            casts_per_round: p.caster_value,
            battleborn_active: unit_rule_active(reg, p, "Battleborn"),
            steadfast_active: unit_rule_active(reg, p, "Steadfast"),
            // Battleborn family wave 3 (rules-wave3-battleborn): the four
            // die-roll recover aliases ride the Battleborn primitive; each
            // alias is stamped BY NAME (the census's own-token evidence,
            // mirroring main.gd:`_solo_round_start_recovery_rule`'s alias
            // loop) at the LOWEST `recover_target` it carries — "Vale Oath
            // Boost"'s text recovers on 3+ INSTEAD of only on 4+, so min is
            // the reading. Gated on `EPOCH_6_TABLE_RULES` (frozen at 6, never
            // the literal or `CURRENT_RULES_EPOCH`) so an epoch-5 corpus
            // replay stays byte-exact.
            battleborn_recover_target: battleborn_recover_target_of(reg, p, rules_epoch),
            mend_active: unit_rule_active(reg, p, "Mend"),
            breath_attack_active: unit_rule_active(reg, p, "Breath Attack"),
            is_hero: has_special_rule(&p.special_rules, "Hero"),
            bounding: bounding_of(reg, p),
            move_rule_mods: move_rule_mods_of(reg, p, rules_epoch),
            versatile_reach_charge_in: if unit_rule_active(reg, p, "Versatile Reach")
                || has_special_rule(&p.special_rules, "Versatile Reach Aura")
            {
                let map = reg.rules_for(&p.game_system);
                Some(match map.lookup(&p.faction_folder, "Versatile Reach") {
                    Some(e) => e.param_f("charge_bonus_in", 2.0),
                    None => 2.0,
                })
            } else {
                None
            },
            reposition_artillery_active: unit_rule_active(reg, p, "Re-Position Artillery"),
            hit_and_run_active: unit_rule_active(reg, p, "Hit & Run")
                || unit_rule_active(reg, p, "Guerrilla")
                || unit_rule_active(reg, p, "Harassing"),
            // BLOCK C1 — the half pick, solo_controller.gd:9667: credited by
            // each name's OWN literal, never by iterating a shared primitive
            // (the census's trusted-whole trap, #489).
            hit_and_run_shooter_active: unit_rule_active(reg, p, "Hit & Run Shooter"),
            hit_and_run_fighter_active: unit_rule_active(reg, p, "Hit & Run Fighter"),
            quick_shot_active: unit_rule_active(reg, p, "Quick Shot"),
            second_wind_active: unit_rule_active(reg, p, "Second Wind")
                || unit_rule_active(reg, p, "Inquisitorial Agent")
                || unit_rule_active(reg, p, "Martial Prowess"),
            infiltrate_min_enemy_dist_in: if has_special_rule(&p.special_rules, "Infiltrate") {
                unit_param_f(reg, p, "Infiltrate", "min_enemy_dist_in", INFILTRATE_MIN_ENEMY_DIST_IN)
            } else {
                0.0
            },
            repel_ambushers_dist_in: if unit_rule_active(reg, p, "Repel Ambushers") {
                unit_param_f(reg, p, "Repel Ambushers", "min_dist_in", REPEL_AMBUSHERS_DIST_IN)
            } else {
                0.0
            },
            ambush_family: ambush_family_of(reg, p, rules_epoch),
            utility_buffs: utility_buffs_of(reg, p, rules_epoch, &mut unimplemented),
            growth: growth_of(reg, p, &mut unimplemented),
            unimplemented,
        }
    }
}

/// NML-1073 M2-5b — the derived per-unit closure for a profile TABLE, memoised
/// by that table's identity (`Rc::ptr_eq`).
///
/// `ProfileCache` hands back the same `Rc<Profiles>` for as long as the game's
/// dynamic reading holds, so this cache rebuilds `UnitStatic` only on the
/// activation where something actually changed — a hero falling, a spell
/// granting a rule — and never once per activation.
///
/// Bounded on purpose: a long game produces one distinct reading per such
/// event, and `ProfileCache` only ever asks for two of them (the header's and
/// the current one). Slot 0 — the header's table — is never evicted, so a game
/// that returns to its deployment reading finds it still here.
#[derive(Default)]
pub struct StaticsCache {
    entries: Vec<(Rc<Profiles>, Rc<Vec<UnitStatic>>)>,
    /// How many tables were rebuilt (a diagnostic — the cost this cache exists
    /// to keep off the per-activation path).
    pub builds: u64,
    /// The record's `Knobs::rules_epoch` — handed to `UnitStatic::build_for`
    /// so the epoch-gated rule ports stamp on the cache's closures too.
    /// `new()` keeps 0 (the legacy reading every pre-epoch corpus replays);
    /// the host runners that know a fresh record's header take `with_epoch`.
    rules_epoch: u32,
}

impl std::fmt::Debug for StaticsCache {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("StaticsCache")
            .field("entries", &self.entries.len())
            .field("builds", &self.builds)
            .finish()
    }
}

/// Distinct profile tables kept at once. Two is the steady state (the header's
/// and the current reading); the rest is slack for a game that flips back.
const STATICS_CACHE_CAP: usize = 4;

impl StaticsCache {
    pub fn new() -> StaticsCache {
        StaticsCache::default()
    }

    /// The cache for ONE record's epoch — `rules_epoch` is that record's own
    /// `Knobs::rules_epoch` (0 for every header recorded before the field
    /// existed). Replacing a cache mid-record is the caller's business: the
    /// py host rebuilds `self.statics` at every `set_header`.
    pub fn with_epoch(rules_epoch: u32) -> StaticsCache {
        StaticsCache { rules_epoch, ..StaticsCache::default() }
    }

    /// Retune an existing cache to `rules_epoch` — the godot host's path, whose
    /// cache outlives the header it was built empty with. Entries built for a
    /// different epoch are stale by definition and dropped.
    pub fn set_epoch(&mut self, rules_epoch: u32) {
        if self.rules_epoch != rules_epoch {
            self.rules_epoch = rules_epoch;
            self.entries.clear();
        }
    }

    /// The closure for `profiles`, built once per distinct table.
    pub fn get(&mut self, reg: &mut Registries, profiles: &Rc<Profiles>) -> Rc<Vec<UnitStatic>> {
        if let Some((_, s)) = self.entries.iter().find(|(p, _)| Rc::ptr_eq(p, profiles)) {
            return Rc::clone(s);
        }
        let epoch = self.rules_epoch;
        let built: Vec<UnitStatic> =
            profiles.list.iter().map(|p| UnitStatic::build_for(reg, p, epoch)).collect();
        let rc = Rc::new(built);
        self.builds += 1;
        if self.entries.len() >= STATICS_CACHE_CAP {
            self.entries.remove(1); // slot 0 is the header's table — keep it
        }
        self.entries.push((Rc::clone(profiles), Rc::clone(&rc)));
        rc
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // Tests exercise "the current epoch" generically (bumped forward each
    // wave); production reads the FROZEN `EPOCH_3_TABLE_RULES` instead — see
    // acts.rs.
    use crate::acts::CURRENT_RULES_EPOCH;
    use crate::acts::read_act_header;
    use crate::rules::Registries;

    /// The checkout this crate lives in — mirrors `rows.rs`'s own helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// Two units: `mark_carrier` prints "Unstoppable Mark" as a UNIT-level
    /// special rule and its Rifle carries no weapon rule at all; `real_unstop`
    /// prints nothing unit-level but its Cannon carries the real "Unstoppable"
    /// weapon rule. Neither unit fires a spell/mark GRANT (`sim::tray_vs_marks`
    /// / `Ctx::unstoppable_grant`) — this fixture is about the static profile
    /// flags `UnitStatic::build` stamps, not the live ledger #489 already
    /// covers in `sim.rs`.
    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "mark_carrier":{"unit_id":"mark_carrier","name":"Mark Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Unstoppable Mark"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "real_unstop":{"unit_id":"real_unstop","name":"Real Unstoppable","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Cannon","range":24,"attacks":1,"count":1,"ap":0,"rules":["Unstoppable"]}]}}}"#;

    /// PROOF (1): a unit carrying only "Unstoppable Mark" has NO unstoppable
    /// on the tray path but keeps it on the EV path; a unit with a weapon's
    /// real "Unstoppable" rule has it on both. RED (revert `stamp_unit_
    /// strikers`'s `sp.unstoppable_ev = sp.unstoppable || u_unstop;` back to
    /// the pre-fix `sp.unstoppable |= u_unstop;`): this test fails, the tray
    /// assertion tripping on the now-true `unstoppable`.
    #[test]
    fn unstoppable_mark_carrier_is_ev_only_a_real_unstoppable_reaches_both() {
        let header = read_act_header(HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let mark_carrier = header.profiles.get("mark_carrier").expect("mark_carrier");
        let marked = UnitStatic::build(&mut reg, mark_carrier);
        assert!(
            !marked.shoot[0].unstoppable,
            "an Unstoppable MARK carrier is not Unstoppable on the tray — \
             ai_shooting.gd:132 reads only the weapon's own exact rule"
        );
        assert!(
            marked.shoot[0].unstoppable_ev,
            "the EV imagination's unit-level prefix scan (battle_sim.gd:1003-1021) \
             still ORs the Mark's name onto every profile — unchanged from before this fix"
        );

        let real_unstop = header.profiles.get("real_unstop").expect("real_unstop");
        let real = UnitStatic::build(&mut reg, real_unstop);
        assert!(
            real.shoot[0].unstoppable,
            "the weapon's own exact \"Unstoppable\" rule reaches the tray (ai_shooting.gd:132)"
        );
        assert!(
            real.shoot[0].unstoppable_ev,
            "and the EV field follows — `unstoppable_ev = unstoppable || u_unstop`"
        );
    }

    /// Bane family (rules-wave-bane) — end to end through the REAL registry,
    /// one test per ported name. Each carrier holds a ranged Rifle (24") and a
    /// melee Blade, so a scope suffix is observable per profile; each test
    /// reads the stamp at `rules_epoch: CURRENT_RULES_EPOCH` (the new reading)
    /// and `0` (the flat prefix reading every earlier corpus replayed). The
    /// DATA-ALIAS carriers need the REAL (system, faction) entry their books
    /// print: aof/beastmen (Bestial), aof/goblins (Mischievous), gf/jackals
    /// (Scrapper, Scrapper Boost).
    const BANE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Bane in Melee"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Ambush family (rules-wave2-ambush) — the rule-less carrier template:
    /// `ambush_family_of` swaps a rule into `special_rules` (empty = the
    /// no-rule arm) and the faction over so the REAL gf registry entry
    /// resolves — the same factions the mechanics map fields.
    const AMBUSH_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's family stamp at `epoch`: the `rule` swapped into the
    /// carrier's special_rules, the faction over so the real entry resolves.
    fn ambush_family_of(rule: &str, faction: &str, epoch: u32) -> AmbushFamily {
        let tpl = AMBUSH_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch).ambush_family
    }

    /// "Ambushing Piercing Shot" (gf/jackals): counts-as + the arrival-round
    /// AP(+1) at epoch 5 — and NOTHING at epoch 4 (Gen-2b's stamping-gap
    /// window — see `acts::EPOCH_5_TABLE_RULES`) or without the rule. Epoch
    /// literals 5/4, NOT `CURRENT_RULES_EPOCH`: a wave-3 bump must not
    /// re-date what these assertions mean.
    #[test]
    fn an_ambushing_piercing_shot_counts_as_ambush_with_its_arrival_round_ap_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambushing Piercing Shot", "jackals", 5),
            AmbushFamily { counts_as_ambush: true, deploy_round_ap: 1, ..Default::default() },
            "counts-as and the AP(+1) at the family's own epoch"
        );
        assert_eq!(
            ambush_family_of("Ambushing Piercing Shot", "jackals", 4),
            AmbushFamily::default(),
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "jackals", 5),
            AmbushFamily::default(),
            "no rule, no stamp"
        );
    }

    /// "Ambush Beacon" (gf/eternal_dynasty): the registry's `beacon_in` is
    /// the waiver radius at epoch 5; epoch 4 (Gen-2b's stamping-gap window)
    /// and the rule-less carrier stay 0.0 (the caller's constant answers for
    /// them).
    #[test]
    fn an_ambush_beacons_radius_is_the_registrys_beacon_in_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambush Beacon", "eternal_dynasty", 5).beacon_radius_in,
            6.0,
            "the registry's own beacon_in"
        );
        assert_eq!(
            ambush_family_of("Ambush Beacon", "eternal_dynasty", 4).beacon_radius_in,
            0.0,
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "eternal_dynasty", 5).beacon_radius_in,
            0.0,
            "no rule, no beacon"
        );
    }

    /// Battleborn family (rules-wave3-battleborn) — the rule-less carrier
    /// template: `battleborn_target_of` swaps the rule and the faction over
    /// so the REAL registry entry resolves — gf/titan_lords (Honor Code),
    /// aof/chivalrous_kingdoms (Vale Oath, Vale Oath Boost), aof/giant_tribes
    /// (Unmovable) — the same factions the mechanics maps field.
    const BATTLEBORN_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"titan_lords",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's family stamp at `epoch`: the LOWEST `recover_target` the
    /// carrier's Battleborn-primitive aliases carry.
    fn battleborn_target_of(rule: &str, system: &str, faction: &str, epoch: u32) -> u32 {
        let tpl = BATTLEBORN_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"titan_lords\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch).battleborn_recover_target
    }

    /// "Honor Code" (gf/titan_lords): `recover_target` 4 at epoch 6 — and
    /// NOTHING at epoch 5 (the flat Battleborn/Steadfast free-clear epoch) or
    /// without the rule. Epoch literals 6/5, NOT `CURRENT_RULES_EPOCH`: a
    /// wave-4 bump must not re-date what these assertions mean.
    #[test]
    fn an_honor_code_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Honor Code", "gf", "titan_lords", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Honor Code", "gf", "titan_lords", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "gf", "titan_lords", 6), 0, "no rule, no stamp");
    }

    /// "Vale Oath" (aof/chivalrous_kingdoms): `recover_target` 4 at epoch 6;
    /// epoch 5 and the rule-less carrier stay 0.
    #[test]
    fn a_vale_oath_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Vale Oath", "aof", "chivalrous_kingdoms", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Vale Oath", "aof", "chivalrous_kingdoms", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "chivalrous_kingdoms", 6), 0, "no rule, no stamp");
    }

    /// "Vale Oath Boost" (aof/chivalrous_kingdoms): the Boost's own
    /// `recover_target` 3 at epoch 6 — the 3+-instead-of-4+ text —; epoch 5
    /// and the rule-less carrier stay 0.
    #[test]
    fn a_vale_oath_boost_stamps_recover_target_3_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Vale Oath Boost", "aof", "chivalrous_kingdoms", 6),
            3,
            "the registry's own recover_target — the 3+ extension"
        );
        assert_eq!(
            battleborn_target_of("Vale Oath Boost", "aof", "chivalrous_kingdoms", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "chivalrous_kingdoms", 6), 0, "no rule, no stamp");
    }

    /// "Unmovable" (aof/giant_tribes): `recover_target` 4 at epoch 6; epoch 5
    /// and the rule-less carrier stay 0.
    #[test]
    fn an_unmovable_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Unmovable", "aof", "giant_tribes", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Unmovable", "aof", "giant_tribes", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "giant_tribes", 6), 0, "no rule, no stamp");
    }

    /// "Rapid Ambush" (gf/dark_brothers): `arrive_from_round` 1 at epoch 5 —
    /// the round the table's `ambush_earliest_round` hardcodes; epoch 4
    /// (Gen-2b's stamping-gap window) and the rule-less carrier stay 0 (the
    /// caller's own ladder answers).
    #[test]
    fn a_rapid_ambusher_arrives_from_the_registrys_round_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Rapid Ambush", "dark_brothers", 5).arrive_from_round,
            1,
            "the registry's own arrive_from_round"
        );
        assert_eq!(
            ambush_family_of("Rapid Ambush", "dark_brothers", 4).arrive_from_round,
            0,
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "dark_brothers", 5).arrive_from_round,
            0,
            "no rule, no first-round arrival"
        );
    }

    /// "Ambush Re-Deployment" (gf/elven_jesters): `re_reserve` +
    /// `uses_per_game` stamped at epoch 5; epoch 4 (Gen-2b's stamping-gap
    /// window) and the rule-less carrier stay false/0. The withdraw beat
    /// itself is a future port.
    #[test]
    fn an_ambush_re_deployment_stamps_its_once_per_game_params_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambush Re-Deployment", "elven_jesters", 5),
            AmbushFamily { re_reserve: true, re_reserve_uses: 1, ..Default::default() },
            "the registry's own re_reserve/uses_per_game"
        );
        assert_eq!(
            ambush_family_of("Ambush Re-Deployment", "elven_jesters", 4),
            AmbushFamily::default(),
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "elven_jesters", 5),
            AmbushFamily::default(),
            "no rule, no re-reserve"
        );
    }

    /// One rule's truth table through the template: the (shoot, melee) bane
    /// stamp at `epoch`, with `rule` swapped into the carrier's special_rules
    /// and (system, faction) set so the REAL registry entry resolves (the
    /// alias wave needs aof/beastmen, aof/goblins, gf/jackals).
    fn bane_stamp_of(rule: &str, system: &str, faction: &str, epoch: u32) -> (bool, bool) {
        let tpl = BANE_HEADER
            .replace("\"Bane in Melee\"", &format!("\"{rule}\""))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.shoot[0].bane, us.melee[0].bane)
    }

    /// "Bane in Melee" (main.gd:6543-6545): melee-only at the current epoch;
    /// the flat prefix reading (both profiles) at epoch 0 — and a rule-less
    /// unit never stamps bane.
    #[test]
    fn bane_in_melee_reaches_melee_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane in Melee", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, true),
            "melee-only: the rifle stays clean"
        );
        assert_eq!(bane_stamp_of("Bane in Melee", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH), (false, false));
    }

    /// "Bane in Melee Buff" (main.gd:6543's prefix arm — the Buff shares the
    /// "Bane in Melee" branch): melee-only at the current epoch, flat at 0.
    #[test]
    fn bane_in_melee_buff_reaches_melee_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane in Melee Buff", "gf", "human_defense_force", crate::acts::CURRENT_RULES_EPOCH),
            (false, true),
            "the Buff's melee scope"
        );
        assert_eq!(bane_stamp_of("Bane in Melee Buff", "gf", "human_defense_force", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane when Shooting" (main.gd:6546-6548): shooting-only at the current
    /// epoch; the flat prefix reading at epoch 0.
    #[test]
    fn bane_when_shooting_reaches_shooting_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane when Shooting", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (true, false),
            "shooting-only: the blade stays clean"
        );
        assert_eq!(bane_stamp_of("Bane when Shooting", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane in Melee Aura" (main.gd:6540): a striker's own "… Aura" rule
    /// never fires — nothing stamps at the current epoch (the aura expansion
    /// hands the base rule to the unit), while epoch 0 keeps the flat read.
    #[test]
    fn bane_in_melee_aura_never_fires_for_its_own_striker() {
        assert_eq!(
            bane_stamp_of("Bane in Melee Aura", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, false),
            "the aura name itself is skipped"
        );
        assert_eq!(bane_stamp_of("Bane in Melee Aura", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane when Shooting Aura" (main.gd:6540): the same aura skip.
    #[test]
    fn bane_when_shooting_aura_never_fires_for_its_own_striker() {
        assert_eq!(
            bane_stamp_of("Bane when Shooting Aura", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, false),
            "the aura name itself is skipped"
        );
        assert_eq!(bane_stamp_of("Bane when Shooting Aura", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane Mark" (main.gd:6550's plain arm — the table's dice path reads the
    /// Mark as plain always-on Bane; the once-per-activation pick is the
    /// table's own live state): both profiles at the current epoch, and the
    /// same at epoch 0 (the legacy prefix already caught it).
    #[test]
    fn bane_mark_reads_as_plain_bane() {
        assert_eq!(
            bane_stamp_of("Bane Mark", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "plain-bane arm, both profiles"
        );
        assert_eq!(bane_stamp_of("Bane Mark", "gf", "robot_legions", 0), (true, true), "the legacy prefix read too");
    }

    /// "Bestial" (aof/beastmen) — the coverage wave (main.gd:6553-6560):
    /// a Bane-primitive alias with `reroll_save_sixes` re-rolls the defender's
    /// sixes at the current epoch; the legacy prefix scan never caught it, so
    /// epoch 0 stays clean.
    #[test]
    fn bestial_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Bestial", "aof", "beastmen", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Bestial", "aof", "beastmen", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Mischievous" (aof/goblins) — the same coverage wave.
    #[test]
    fn mischievous_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Mischievous", "aof", "goblins", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Mischievous", "aof", "goblins", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Scrapper" (gf/jackals) — the same coverage wave.
    #[test]
    fn scrapper_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Scrapper", "gf", "jackals", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Scrapper", "gf", "jackals", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Scrapper Boost" (gf/jackals) — the gf entry carries `reroll_save_sixes`
    /// alongside its un-read 5-6 extension, so the wave joins it too (the
    /// reroll_save_low/over_in params stay read by nobody — the Boost's own
    /// documented gap).
    #[test]
    fn scrapper_boost_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Scrapper Boost", "gf", "jackals", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "the gf entry's reroll_save_sixes"
        );
        assert_eq!(bane_stamp_of("Scrapper Boost", "gf", "jackals", 0), (false, false), "the wave is epoch-gated");
    }

    /// Lacerate family (rules-wave2-lacerate2) — one test per ported name,
    /// through the same template as the Bane ladder. Epoch literals 5/4/3,
    /// NOT `CURRENT_RULES_EPOCH`: a wave-3 epoch bump must not re-date what
    /// these assertions mean.
    ///
    /// EPOCH GATES BY RECORDING SHA (05.09. correction): Lacerate's OWN merge
    /// commit (`cf8831d1`) landed BEFORE the Gen-2b recording fleet launched,
    /// so it was live in the recorder for every `rules_epoch: 4` record —
    /// `acts::EPOCH_4_TABLE_RULES`, not `EPOCH_5_TABLE_RULES` (that value is
    /// for the four families that merged AFTER the fleet launched). Epoch 4
    /// now GETS Lacerate; only epoch 3 and below replay the pre-wave reading.
    ///
    /// "Ignores Regeneration" (main.gd:6983-6989, common entries): bypass on
    /// BOTH profiles from epoch 4 onward; epoch 3 replays the pre-wave
    /// reading.
    #[test]
    fn ignores_regeneration_bypasses_regen_on_every_profile_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 5),
            (true, true),
            "ungated bypass: both profiles"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 4),
            (true, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    /// "Unstoppable in Melee" (main.gd:6986-6989): the melee_only facet keeps
    /// the rifle clean and the blade bypassing from epoch 4 onward.
    #[test]
    fn unstoppable_in_melee_bypasses_regen_in_melee_only_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 5),
            (false, true),
            "melee-only facet"
        );
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 4),
            (false, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    /// "Ignores Regeneration in Melee" (gf/gff common): the same melee-only
    /// facet, distinct name, same primitive.
    #[test]
    fn ignores_regeneration_in_melee_bypasses_regen_in_melee_only_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 5),
            (false, true),
            "melee-only facet"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 4),
            (false, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    /// Block B6, end to end through the REAL registry: `saurian_starhost/gf`'s
    /// "Primal" (`Surge`, `extra_attack: true`, no melee_only/shooting_only)
    /// reaches BOTH ranged and melee profiles, and "Primal Boost" moves
    /// `surge_attack_low` to 5 on both; `alien_hives/gf`'s "Predator Fighter"
    /// (same primitive, `melee_only: true`) reaches ONLY the melee profile.
    const SURGE_ATTACK_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "primal_beast":{"unit_id":"primal_beast","name":"Primal Beast","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost",
        "special_rules":["Primal","Primal Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "predator_fighter_unit":{"unit_id":"predator_fighter_unit","name":"Predator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Predator Fighter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Spitter","range":18,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Talons","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    #[test]
    fn primal_and_its_boost_reach_both_profiles_predator_fighter_only_melee() {
        let header = read_act_header(SURGE_ATTACK_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let primal = header.profiles.get("primal_beast").expect("primal_beast");
        let ps = UnitStatic::build(&mut reg, primal);
        assert!(ps.shoot[0].surge_attack, "Primal is ungated — it reaches the ranged profile too");
        assert_eq!(ps.shoot[0].surge_attack_low, 5, "Primal Boost's surge_low");
        assert!(ps.melee[0].surge_attack);
        assert_eq!(ps.melee[0].surge_attack_low, 5);
        assert!(
            ps.unimplemented.iter().all(|u| u.rule != "Primal" && u.rule != "Primal Boost"),
            "consumed, not stamped as unimplemented: {:?}", ps.unimplemented
        );

        let predator = header.profiles.get("predator_fighter_unit").expect("predator_fighter_unit");
        let pf = UnitStatic::build(&mut reg, predator);
        assert!(!pf.shoot[0].surge_attack, "melee_only — the ranged profile stays untouched");
        assert_eq!(pf.shoot[0].surge_attack_low, 6, "unboosted default");
        assert!(pf.melee[0].surge_attack, "but the melee profile gets it");
        assert_eq!(pf.melee[0].surge_attack_low, 6, "Predator Fighter carries no Boost upgrade");
    }

    /// Block C4 — the death-half field, end to end through the REAL registry:
    /// the rating is the rule's own (`maxi(rating, 1)`), each literal is
    /// registry-gated (`unit_rule_active`). gf goblin_reclaimers fields
    /// Deathstrike, gf alien_hives fields Self-Destruct, robot_legions fields
    /// neither (a carrier there stays silent). RED (drop a literal from
    /// `death_hits_per_kill`): its carrier's count falls to 0.
    const DEATH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "ds_goblin":{"unit_id":"ds_goblin","name":"DS Goblin","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Deathstrike(2)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "sd_hive":{"unit_id":"sd_hive","name":"SD Hive","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Self-Destruct(3)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "ds_bare":{"unit_id":"ds_bare","name":"DS Bare","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Deathstrike"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "ds_nomap":{"unit_id":"ds_nomap","name":"DS Nomap","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Deathstrike(2)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    #[test]
    fn deathstrike_and_self_destruct_stamp_their_ratings_registry_gated() {
        let header = read_act_header(DEATH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let built = |k: &str, reg: &mut Registries| {
            UnitStatic::build(reg, header.profiles.get(k).expect(k)).ctx.death_hits_per_kill
        };
        assert_eq!(built("ds_goblin", &mut reg), 2, "Deathstrike(2)");
        assert_eq!(built("sd_hive", &mut reg), 3, "Self-Destruct(3)");
        assert_eq!(built("ds_bare", &mut reg), 1, "a bare name rates maxi(0, 1)");
        assert_eq!(built("ds_nomap", &mut reg), 0, "no map for the faction — silent");
    }

    /// Block C5 — Instinctive stamped end to end through the REAL registry:
    /// gf goblin_reclaimers and aof vampiric_undead field
    /// `Instinctive {force_closest_target: true, hit_bonus: 1}`; a carrier
    /// whose faction map fields nothing stays 0. RED (drop the literal from
    /// `instinctive_hit_bonus`): every carrier falls to 0.
    const INSTINCTIVE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "inst_gf":{"unit_id":"inst_gf","name":"Inst GF","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "inst_aof":{"unit_id":"inst_aof","name":"Inst AoF","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "inst_nomap":{"unit_id":"inst_nomap","name":"Inst Nomap","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    #[test]
    fn instinctive_stamps_the_registry_hit_bonus_gated() {
        let header = read_act_header(INSTINCTIVE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let built = |k: &str, reg: &mut Registries| {
            UnitStatic::build(reg, header.profiles.get(k).expect(k)).ctx.instinctive_hit_bonus
        };
        assert_eq!(built("inst_gf", &mut reg), 1, "gf goblin_reclaimers hit_bonus");
        assert_eq!(built("inst_aof", &mut reg), 1, "aof vampiric_undead hit_bonus");
        assert_eq!(built("inst_nomap", &mut reg), 0, "no map for the faction — silent");
    }

    /// Block B10 — Resistance end to end through the REAL registry
    /// (`alien_hives/gf` fields it with `ignore_target:6,
    /// ignore_target_spell:2, all_models:true`). `resist_whole` carries it
    /// alone (whole unit = the models); `resist_partial` carries it but its
    /// attached hero does NOT — `_solo_rule_on_all_models` (main.gd:4599)
    /// gates the whole family, so the partial unit gets NO regeneration from
    /// Resistance. RED (disable the Resistance leg in `regen_targets`):
    /// `resist_whole`'s assertions trip on regen_target 0 vs 6.
    const RESISTANCE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "resist_whole":{"unit_id":"resist_whole","name":"Resist Whole","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Resistance"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "resist_partial":{"unit_id":"resist_partial","name":"Resist Partial","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Resistance"],"item_grants":[],
        "attached_hero_rules":[["Fearless"]],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    #[test]
    fn whole_unit_resistance_carries_the_6_plus_2_plus_legs() {
        let header = read_act_header(RESISTANCE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let p = header.profiles.get("resist_whole").expect("resist_whole");
        let us = UnitStatic::build(&mut reg, p);
        assert!(us.ctx.regeneration, "a whole-unit Resistance carrier regenerates");
        assert_eq!(us.ctx.regen_target, 6, "the registry's ignore_target");
        assert_eq!(us.ctx.regen_target_spell, 2, "the registry's ignore_target_spell");
    }

    #[test]
    fn resistance_needs_every_model_so_a_bare_hero_kills_the_leg() {
        let header = read_act_header(RESISTANCE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let p = header.profiles.get("resist_partial").expect("resist_partial");
        let us = UnitStatic::build(&mut reg, p);
        assert!(
            !us.ctx.regeneration,
            "an attached hero without Resistance breaks the all-models gate"
        );
        assert_eq!(us.ctx.regen_target, 0, "no regeneration family member fields");
        assert_eq!(us.ctx.regen_target_spell, 0);
    }

    // ====================================== Regeneration family alias wave ====

    /// The Regeneration family's DATA-ALIAS wave, end to end through the REAL
    /// registry — one unit per ported name, in the faction whose mechanics
    /// map fields the entry (`_forge/names.md`'s twelve, all primitive
    /// "Regeneration"). RED (drop the `rule_on` gate in `regen_targets`): the
    /// epoch-0 asserts trip — the alias layer is new behaviour, so the
    /// pre-epoch corpora must keep reading 0/0. RED (drop the `all_models`
    /// gate): `plague_partial`'s asserts trip.
    const REGEN_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "angelic":{"unit_id":"angelic","name":"Angelic","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":["Angelic Blessing"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "angelic_boost":{"unit_id":"angelic_boost","name":"Angelic Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":["Angelic Blessing Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "cursed":{"unit_id":"cursed","name":"Cursed","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Cursed Undead"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "cursed_boost":{"unit_id":"cursed_boost","name":"Cursed Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Cursed Undead Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague":{"unit_id":"plague","name":"Plague","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague_boost":{"unit_id":"plague_boost","name":"Plague Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague_partial":{"unit_id":"plague_partial","name":"Plague Partial","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound"],"item_grants":[],
        "attached_hero_rules":[["Fearless"]],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "protected":{"unit_id":"protected","name":"Protected","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"duchies_of_vinci",
        "special_rules":["Protected"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "protection_feat":{"unit_id":"protection_feat","name":"Protection Feat","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"saurians",
        "special_rules":["Protection Feat"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "grounded":{"unit_id":"grounded","name":"Grounded","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"volcanic_dwarves",
        "special_rules":["Grounded Protection"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "knightborn":{"unit_id":"knightborn","name":"Knightborn","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
        "special_rules":["Knightborn"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "self_repair_boost":{"unit_id":"self_repair_boost","name":"Self-Repair Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Self-Repair Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "regen_buff":{"unit_id":"regen_buff","name":"Regeneration Buff","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ossified_undead",
        "special_rules":["Regeneration Buff"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "bare_aof":{"unit_id":"bare_aof","name":"Bare Aof","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "bare_gf":{"unit_id":"bare_gf","name":"Bare Gf","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// (regen_target, regen_target_spell) for one fixture unit at one epoch.
    fn regen_pair_at(header: &crate::acts::ActHeader, key: &str, epoch: u32) -> (i64, i64) {
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(key).expect(key);
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.ctx.regen_target, us.ctx.regen_target_spell)
    }

    #[test]
    fn angelic_blessing_ignores_on_6_and_spells_on_4_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "angelic", CURRENT_RULES_EPOCH),
            (6, 4),
            "the registry's ignore_target 6 / ignore_target_spell 4"
        );
        assert_eq!(regen_pair_at(&header, "angelic", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(
            regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH),
            (0, 0),
            "without the rule: none"
        );
    }

    #[test]
    fn angelic_blessing_boost_is_spell_only_on_2_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "angelic_boost", CURRENT_RULES_EPOCH),
            (0, 2),
            "spell_only entry: no normal leg, spells ignored on 2+"
        );
        assert_eq!(regen_pair_at(&header, "angelic_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn cursed_undead_ignores_on_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "cursed", CURRENT_RULES_EPOCH),
            (6, 6),
            "no spell twin: the spell pick falls back to ignore_target (main.gd:6648)"
        );
        assert_eq!(regen_pair_at(&header, "cursed", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn cursed_undead_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "cursed_boost", CURRENT_RULES_EPOCH),
            (5, 5),
            "ignore_target 5 = rolls of 5-6"
        );
        assert_eq!(regen_pair_at(&header, "cursed_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn plaguebound_ignores_on_6_and_needs_every_model() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "plague", CURRENT_RULES_EPOCH), (6, 6));
        assert_eq!(regen_pair_at(&header, "plague", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(
            regen_pair_at(&header, "plague_partial", CURRENT_RULES_EPOCH),
            (0, 0),
            "all_models: an attached hero without the rule kills the leg"
        );
    }

    #[test]
    fn plaguebound_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "plague_boost", CURRENT_RULES_EPOCH), (5, 5));
        assert_eq!(regen_pair_at(&header, "plague_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn protected_ignores_on_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "protected", CURRENT_RULES_EPOCH), (6, 6));
        assert_eq!(regen_pair_at(&header, "protected", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn protection_feat_ignores_on_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "protection_feat", CURRENT_RULES_EPOCH),
            (5, 5),
            "uses_per_game is the table's own unread param, mirrored"
        );
        assert_eq!(regen_pair_at(&header, "protection_feat", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn grounded_protection_ignores_on_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "grounded", CURRENT_RULES_EPOCH),
            (5, 5),
            "terrain_within_in is the table's own unread param, mirrored"
        );
        assert_eq!(regen_pair_at(&header, "grounded", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn knightborn_ignores_on_6_and_spells_on_4_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "knightborn", CURRENT_RULES_EPOCH), (6, 4));
        assert_eq!(regen_pair_at(&header, "knightborn", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_gf", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn self_repair_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "self_repair_boost", CURRENT_RULES_EPOCH), (5, 5));
        assert_eq!(regen_pair_at(&header, "self_repair_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn regeneration_buff_reads_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "regen_buff", CURRENT_RULES_EPOCH),
            (5, 5),
            "table-faithful: the alias layer pays the carrier, the buff flow is unmodelled"
        );
        assert_eq!(regen_pair_at(&header, "regen_buff", 0), (0, 0), "epoch 0 replays legacy");
    }

    // ================================================ mutant-killing tests ====

    /// Three profiles for `growth_of`: one plain "Piercing Growth" carrier
    /// (alien_hives: per_round, max_markers 4, ap_per_two 1), one carrying
    /// the same rule TWICE in special_rules (the de-dup case), and one
    /// "Defensive Growth" carrier (human_inquisition) whose params carry NO
    /// ap/hit facet at all.
    const GROWTH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "growth_carrier":{"unit_id":"growth_carrier","name":"Growth Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Piercing Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "growth_dup":{"unit_id":"growth_dup","name":"Growth Dup","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Piercing Growth","Piercing Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "growth_zero":{"unit_id":"growth_zero","name":"Growth Zero","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition",
        "special_rules":["Defensive Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Five gf units chosen so the REGISTRY tells them apart, not a stub.
    /// `alien_hives` fields an `Infiltrate` entry (`min_enemy_dist_in: 3.0`) and
    /// NO `Repel Ambushers`; `eternal_dynasty` is the mirror image (a
    /// `Repel Ambushers` entry at `min_dist_in: 12.0`, no `Infiltrate`).
    const AMBUSH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "inf_registry":{"unit_id":"inf_registry","name":"Infiltrator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Infiltrate"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "inf_unmapped":{"unit_id":"inf_unmapped","name":"Unmapped Infiltrator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Infiltrate"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "plain_ambusher":{"unit_id":"plain_ambusher","name":"Plain Ambusher","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Ambush","Ambush Beacon"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "repel_carrier":{"unit_id":"repel_carrier","name":"Repeller","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Repel Ambushers"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "repel_unmapped":{"unit_id":"repel_unmapped","name":"Unmapped Repeller","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Repel Ambushers"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    fn ambush_static(key: &str) -> UnitStatic {
        let header = read_act_header(AMBUSH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build(&mut reg, header.profiles.get(key).expect(key))
    }

    /// RED — the REGISTRY value wins, and it is measurably not the fallback.
    /// `min_enemy_dist_in: 3.0` is an exact 3.0; the table's own fallback
    /// expression (`INFILTRATE_MIN_ENEMY_DIST_M / INCHES_TO_METERS`,
    /// solo_controller.gd:9620) is `3.0000000000000004`. Stamp the constant
    /// instead of reading the entry and this assertion fails on that ULP.
    #[test]
    fn an_infiltrators_ring_is_the_registrys_value_not_the_constant() {
        let us = ambush_static("inf_registry");
        assert_eq!(us.infiltrate_min_enemy_dist_in, 3.0, "the registry's exact 3.0");
        assert_ne!(
            us.infiltrate_min_enemy_dist_in, INFILTRATE_MIN_ENEMY_DIST_IN,
            "and it is NOT the fallback — they are one ULP apart by design"
        );
    }

    /// The other half: a faction the map fields no `Infiltrate` entry for still
    /// gets a ring, because the table gates this one on the PLAIN rule name
    /// (`has_special_rule`, :9618), not on `unit_rule_active`. Swap the gate to
    /// `unit_rule_active` and this drops to 0.0.
    #[test]
    fn an_unmapped_infiltrator_falls_back_to_the_tables_own_expression() {
        let us = ambush_static("inf_unmapped");
        assert_eq!(us.infiltrate_min_enemy_dist_in, INFILTRATE_MIN_ENEMY_DIST_IN);
        assert_eq!(us.infiltrate_min_enemy_dist_in, 0.0762 / 0.0254);
        assert_ne!(us.infiltrate_min_enemy_dist_in, 3.0, "a bare 3.0 is a different float");
    }

    /// A plain Ambush unit is NOT an infiltrator: 0.0 hands the caller the 9"
    /// `AMBUSH_MIN_ENEMY_DIST_M` path (:9606). "Ambush Beacon" rides along to
    /// pin the prefix lesson (solo_controller.gd:9731-9734) — `has_special_rule`
    /// is exact-or-parametrised, so it must not answer the "Infiltrate" query
    /// and must not answer "Ambush" for the Beacon either.
    #[test]
    fn a_plain_ambusher_is_not_an_infiltrator() {
        let us = ambush_static("plain_ambusher");
        assert_eq!(us.infiltrate_min_enemy_dist_in, 0.0);
        assert_eq!(us.repel_ambushers_dist_in, 0.0);
    }

    /// Repel Ambushers projects the registry's 12"; the gate here IS
    /// `unit_rule_active`, so a faction whose map fields no entry projects
    /// NOTHING even though the unit prints the rule. Copy the Infiltrate gate
    /// onto this field and the second assertion becomes 12.0.
    #[test]
    fn repel_ambushers_is_registry_gated_unlike_infiltrate() {
        assert_eq!(ambush_static("repel_carrier").repel_ambushers_dist_in, 12.0);
        assert_eq!(ambush_static("repel_carrier").repel_ambushers_dist_in, REPEL_AMBUSHERS_DIST_IN);
        assert_eq!(
            ambush_static("repel_unmapped").repel_ambushers_dist_in, 0.0,
            "alien_hives fields no Repel Ambushers entry -> unit_rule_active is false"
        );
    }

    /// `growth_of` REPORTS the registry's Growth Markers entry — a body
    /// emptied into `vec![]` would report nothing at all.
    #[test]
    fn growth_of_reports_a_registry_growth_rule() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "one Growth Markers entry: {out:?}");
        assert_eq!(out[0].name, "Piercing Growth");
    }

    /// ...with the registry's own PARAMS, not a default-constructed stub —
    /// `vec![Default::default()]` carries an empty name, max_markers 0 and
    /// no rates at all.
    #[test]
    fn growth_of_carries_the_registry_params() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out[0].max_markers, 4, "the registry's max_markers");
        assert!(out[0].per_round, "Piercing Growth ticks per round");
        assert_eq!(out[0].ap_per_two, 1);
        assert_eq!(out[0].ap_per_marker, 0);
        assert_eq!(out[0].hit_per_marker, 0);
        assert_eq!(out[0].hit_per_two, 0);
    }

    /// The de-dup: the same rule twice in special_rules reports ONE entry —
    /// the `||` at the skip gate (empty-name OR already-seen) must not
    /// collapse into an `&&` that loses the seen-list half.
    #[test]
    fn a_duplicated_growth_rule_is_reported_once() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_dup").expect("dup");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "the seen-list keeps one copy: {out:?}");
    }

    /// Same de-dup, by NAME: the seen comparison `*s == n` must not become
    /// `!=`, which would re-admit the very rule just recorded.
    #[test]
    fn a_repeated_growth_name_is_deduped_by_name() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_dup").expect("dup");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "one entry per distinct name: {out:?}");
    }

    /// The facet gate: a rule WITH an ap/hit facet is consumed silently; a
    /// rule whose four facets are all zero is REPORTED as unimplemented.
    /// Flipping the `==` to `!=` reports the facet-bearing rule instead and
    /// stays silent about the defense-only one.
    #[test]
    fn a_growth_rule_with_no_attack_facet_is_reported_unimplemented() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1);
        assert!(un.is_empty(), "Piercing Growth has an ap facet: {un:?}");
        let pz = header.profiles.get("growth_zero").expect("zero");
        let outz = growth_of(&mut reg, pz, &mut un);
        assert_eq!(outz.len(), 1);
        assert!(
            un.iter().any(|u| u.rule == "Defensive Growth"),
            "the defense-only facets are reported: {un:?}"
        );
    }

    /// Block C (Versatile Reach) end to end through the REAL registry: the
    /// base rule's `charge_bonus_in` param (`battle_brothers/gf`, identical
    /// 2.0 on every occurrence) stamps `Some(2.0)`; a profile without either
    /// name stamps `None`. RED the moment the rule-NAME literal is misspelled
    /// (the field then falls to `None` on every arm).
    const VR_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "vr_carrier":{"unit_id":"vr_carrier","name":"VR Carrier","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Versatile Reach"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "vr_plain":{"unit_id":"vr_plain","name":"VR Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Fearless"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "vr_aura":{"unit_id":"vr_aura","name":"VR Aura","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Versatile Reach Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    #[test]
    fn the_base_rule_stamps_the_registry_charge_bonus_and_a_non_carrier_stamps_none() {
        let header = read_act_header(VR_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("vr_carrier").expect("vr_carrier");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(
            us.versatile_reach_charge_in, Some(2.0),
            "the registry's charge_bonus_in, read off the rule-NAME literal"
        );
        let plain = header.profiles.get("vr_plain").expect("vr_plain");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(
            us.versatile_reach_charge_in, None,
            "no VR name, no stamp — the +4\" range half is not a field at all"
        );
    }

    /// The AURA arm: "Versatile Reach Aura" is UNMAPPED-registered
    /// (`primitive: null`, so `unit_rule_active` is false for it by
    /// construction) — the raw-name arm is what credits the aura carrier
    /// without depending on the import's `_expand_auras` having run. RED the
    /// moment that arm is dropped: the stamp falls to `None`.
    #[test]
    fn an_aura_only_carrier_stamps_too() {
        let header = read_act_header(VR_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let aura = header.profiles.get("vr_aura").expect("vr_aura");
        let us = UnitStatic::build(&mut reg, aura);
        assert_eq!(
            us.versatile_reach_charge_in, Some(2.0),
            "the raw-name arm makes the core independent of the expander"
        );
    }

    /// Rung C data port (AUDIT_armybook_flanks_2026-09-02.md §"NO REGISTRY
    /// ENTRY"): six names with no registry entry in any system, now aliased
    /// onto an existing primitive through the SAME faction folders the new
    /// `assets/solo/rules_mechanics_gf.json` entries live in. Each carrier
    /// sits next to a plain non-carrier in the identical faction, so the
    /// registry lookup (system, faction, name) is exercised for real, not
    /// synthesised.
    const RUNG_C_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "screened_unit":{"unit_id":"screened_unit","name":"Screened Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"change_disciples","special_rules":["Screened"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_change_disciple":{"unit_id":"plain_change_disciple","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"change_disciples","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "predator_unit":{"unit_id":"predator_unit","name":"Predator Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost","special_rules":["Predator"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_saurian_starhost":{"unit_id":"plain_saurian_starhost","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "brutal_unit":{"unit_id":"brutal_unit","name":"Brutal Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Brutal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_blessed_sisters":{"unit_id":"plain_blessed_sisters","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "precision_hunter_unit":{"unit_id":"precision_hunter_unit","name":"Precision Hunter Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dao_union","special_rules":["Precision Hunter"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_dao_union":{"unit_id":"plain_dao_union","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dao_union","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "nimble_unit":{"unit_id":"nimble_unit","name":"Nimble Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"elven_jesters","special_rules":["Nimble"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_elven_jesters":{"unit_id":"plain_elven_jesters","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"elven_jesters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "courageous_unit":{"unit_id":"courageous_unit","name":"Courageous Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Courageous"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_alien_hives":{"unit_id":"plain_alien_hives","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Screened = the Stealth DATA ALIAS (`stealth_alias_of`): -1 to hit past
    /// 9", same shape as the pre-existing `wormhole_daemons_of_plague` entry.
    /// RED (drop the new `change_disciples` registry entry): the alias
    /// fields fall back to the carrier's plain-Fearless sibling's zero.
    #[test]
    fn screened_carries_the_stealth_alias_a_plain_sibling_does_not() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("screened_unit").expect("screened_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.ctx.stealth_alias_penalty, 1, "Screened's own hit_penalty");
        assert_eq!(us.ctx.stealth_alias_over_in, 9.0, "Screened's own over_in");
        let plain = header.profiles.get("plain_change_disciple").expect("plain_change_disciple");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.ctx.stealth_alias_penalty, 0, "no Screened, no alias");
    }

    /// Predator = the Surge `extra_attack` DATA ALIAS, same shape as the
    /// pre-existing `ratmen_clans` entry — reaches both profiles (ungated).
    /// RED (drop the new `saurian_starhost` registry entry): `surge_attack`
    /// stays false on both.
    #[test]
    fn predator_reaches_both_profiles_via_the_surge_extra_attack_alias() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("predator_unit").expect("predator_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert!(us.shoot[0].surge_attack, "Predator's extra-attack-die facet, ranged");
        assert!(us.melee[0].surge_attack, "and melee — Predator carries no facet gate");
        let plain = header.profiles.get("plain_saurian_starhost").expect("plain_saurian_starhost");
        let us = UnitStatic::build(&mut reg, plain);
        assert!(!us.shoot[0].surge_attack, "no Predator, no extra-attack die");
    }

    /// Lacerate+Counter wave — one melee-weapon carrier per Counter DATA
    /// alias next to a plain sibling. The stamp is the EPOCH-gated one
    /// (`UnitStatic::build`'s `rule_on` gate), so every test reads the rule at
    /// the current epoch, at epoch 0 (every recorded corpus) and without the
    /// rule — the three rows the port must never confuse.
    const COUNTER_ALIASES_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "counter_attack_unit":{"unit_id":"counter_attack_unit","name":"Counter-Attack Bearer","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":["Counter-Attack"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "counter_in_melee_unit":{"unit_id":"counter_in_melee_unit","name":"Counter in Melee Bearer","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":["Counter in Melee"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_unit":{"unit_id":"plain_unit","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// RED (drop the `rule_on` gate or the "Counter-Attack" arm): the carrier
    /// reads `counter` at the wrong epoch or never; GREEN (any ungated stamp):
    /// the epoch-0 row flips and the recorded corpora stop replaying.
    #[test]
    fn counter_attack_strikes_first_only_from_the_current_epoch() {
        let header = read_act_header(COUNTER_ALIASES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("counter_attack_unit").expect("counter_attack_unit");
        let us = UnitStatic::build_for(&mut reg, carrier, CURRENT_RULES_EPOCH);
        assert!(us.melee[0].counter, "the alias strikes first at the current epoch");
        let us = UnitStatic::build_for(&mut reg, carrier, 0);
        assert!(!us.melee[0].counter, "epoch 0 replays the Gen-0 rule set");
        let plain = header.profiles.get("plain_unit").expect("plain_unit");
        let us = UnitStatic::build_for(&mut reg, plain, CURRENT_RULES_EPOCH);
        assert!(!us.melee[0].counter, "no rule, no stamp");
    }

    /// Same three rows for "Counter in Melee" — the AoF-only sibling.
    #[test]
    fn counter_in_melee_strikes_first_only_from_the_current_epoch() {
        let header = read_act_header(COUNTER_ALIASES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("counter_in_melee_unit").expect("counter_in_melee_unit");
        let us = UnitStatic::build_for(&mut reg, carrier, CURRENT_RULES_EPOCH);
        assert!(us.melee[0].counter, "the melee-scoped alias strikes first at the current epoch");
        let us = UnitStatic::build_for(&mut reg, carrier, 0);
        assert!(!us.melee[0].counter, "epoch 0 replays the Gen-0 rule set");
        let plain = header.profiles.get("plain_unit").expect("plain_unit");
        let us = UnitStatic::build_for(&mut reg, plain, CURRENT_RULES_EPOCH);
        assert!(!us.melee[0].counter, "no rule, no stamp");
    }

    /// Brutal = Devout's twin: the PLAIN auto-hit Surge alias (no
    /// `extra_attack`), so it lands on `surge`, never `surge_attack`. RED
    /// (drop the new `blessed_sisters` registry entry): `surge` stays false.
    #[test]
    fn brutal_fires_the_plain_surge_auto_hit_not_the_extra_attack_die() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("brutal_unit").expect("brutal_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert!(us.melee[0].surge, "Brutal's plain auto-hit facet");
        assert!(!us.melee[0].surge_attack, "not the extra-attack-die form");
        let plain = header.profiles.get("plain_blessed_sisters").expect("plain_blessed_sisters");
        let us = UnitStatic::build(&mut reg, plain);
        assert!(!us.melee[0].surge, "no Brutal, no auto-hit");
    }

    /// Surge family wave 2 (rules-wave2-surge2) — one test per ported name,
    /// end to end through the REAL registry (each name's own (system, faction)
    /// entry, the folder its book prints). The six names ride the plain
    /// auto-hit form: the generic alias walk (stamp's block 3, ungated) has
    /// stamped them since the coverage wave, and build_for's named arm (gated
    /// `EPOCH_5_TABLE_RULES`, frozen at 5 — the stamping-gap fix, NOT the
    /// naive 4) states the same facet BY NAME on top. Since the generic walk
    /// already covers these six names, the named arm is a redundant safety
    /// net for THEM specifically: the assertions below stay true at 4
    /// (Gen-2b's stamping-gap window) exactly as they did at 3, unlike
    /// Lacerate/Ambush/Utility Buff, whose gates are the ONLY path to their
    /// effect and so DO flip at the new boundary (see their own tests).
    /// Present at 5 (the named arm) and at 3/4 (the pre-wave generic walk,
    /// byte-exact — the wave must never re-date it), absent WITHOUT the rule
    /// (the RED leg; the effect predates the epoch mechanism, the Brutal
    /// Fighter precedent).
    const SURGE_WAVE2_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Brutal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One rule's truth table through the template: the (shoot, melee) surge
    /// stamp at `epoch`, with `rule` swapped into the carrier's special_rules
    /// and (system, faction) set so the REAL registry entry resolves.
    fn surge_stamp_of(rule: &str, system: &str, faction: &str, epoch: u32) -> (bool, bool) {
        let tpl = SURGE_WAVE2_HEADER
            .replace("\"Brutal\"", &format!("\"{rule}\""))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"blessed_sisters\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.shoot[0].surge, us.melee[0].surge)
    }

    /// "Brutal" (gf/blessed_sisters, aof/halflings|orcs): the plain auto-hit
    /// facet on BOTH profiles from 4, the same at 3 (the pre-wave walk),
    /// nothing without the rule.
    #[test]
    fn brutal_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Brutal", "gf", "blessed_sisters", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Brutal", "gf", "blessed_sisters", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "blessed_sisters", 4), (false, false), "no rule, no surge");
    }

    /// "Great Sergeant" (aof/ogres, aof/plague_disciples): the table's own
    /// stamp loop never reads the entry's printed `surge_low: 5` (it reads
    /// `surge_low` only off `upgrades` carriers), so the port replays the
    /// TABLE — the plain 6s form — not the printed 5-6 text.
    #[test]
    fn great_sergeant_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Great Sergeant", "aof", "ogres", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Great Sergeant", "aof", "ogres", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "ogres", 4), (false, false), "no rule, no surge");
    }

    /// "Devout" (gf/blessed_sisters): Devout-Boost's own base, the plain
    /// auto-hit facet on BOTH profiles, same three rows.
    #[test]
    fn devout_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Devout", "gf", "blessed_sisters", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Devout", "gf", "blessed_sisters", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "blessed_sisters", 4), (false, false), "no rule, no surge");
    }

    /// "Surge when Shooting" (gf/gff common; the book carrier is Dwarf
    /// Guilds): the entry carries NO `shooting_only`, so the table's alias
    /// loop stamps both arrays — the port replays the table, scoping gap and
    /// all (the printed "when shooting" is the table's own gap).
    #[test]
    fn surge_when_shooting_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Surge when Shooting", "gf", "dwarf_guilds", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Surge when Shooting", "gf", "dwarf_guilds", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "dwarf_guilds", 4), (false, false), "no rule, no surge");
    }

    /// "Lucky" (aof/halflings): Lucky-Boost's own base, the plain auto-hit
    /// facet on BOTH profiles, same three rows.
    #[test]
    fn lucky_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Lucky", "aof", "halflings", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Lucky", "aof", "halflings", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "halflings", 4), (false, false), "no rule, no surge");
    }

    /// "Surge Mark" (aof/chivalrous_kingdoms): the table's dice path reads the
    /// Mark as plain always-on Surge through the alias loop — the
    /// once-per-activation pick is a Utility-Buff `vs_target` overlay this
    /// entry does not carry (the Bane Mark precedent), so the port replays the
    /// table's plain reading.
    #[test]
    fn surge_mark_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Surge Mark", "aof", "chivalrous_kingdoms", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Surge Mark", "aof", "chivalrous_kingdoms", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "chivalrous_kingdoms", 4), (false, false), "no rule, no surge");
    }

    /// The Surge family's plain-form gates through the REAL registry: Devout
    /// Boost stamps `surge_low`/`surge_over_in` onto every profile Devout gave
    /// `surge` (ai_ev.gd:250-260) and stops being reported unimplemented;
    /// Point-Blank stamps its `within_in` on BOTH facets (no `shooting_only`
    /// in the entry). RED: drop the stamp arms or the entries — the asserts
    /// fall back to the defaults.
    const SURGE_GATES_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "devout_boost_unit":{"unit_id":"devout_boost_unit","name":"Devout Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Devout","Devout Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plain_blessed":{"unit_id":"plain_blessed","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "point_blank_unit":{"unit_id":"point_blank_unit","name":"Point Blank Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Point-Blank Surge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "brutal_fighter_unit":{"unit_id":"brutal_fighter_unit","name":"Brutal Fighter Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition","special_rules":["Brutal Fighter"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plain_inquisition":{"unit_id":"plain_inquisition","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;
    #[test]
    fn the_surge_gates_stamp_through_the_real_registry() {
        let header = read_act_header(SURGE_GATES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let dev = UnitStatic::build(
            &mut reg, header.profiles.get("devout_boost_unit").expect("devout_boost_unit"),
        );
        assert_eq!(dev.shoot[0].surge_low, 5, "Devout Boost's surge_low");
        assert_eq!(dev.shoot[0].surge_over_in, 9.0, "Devout Boost's over_in");
        assert_eq!(dev.melee[0].surge_low, 5, "the boost rides EVERY profile Devout gave surge");
        assert!(
            dev.unimplemented.iter().all(|u| u.rule != "Devout Boost"),
            "consumed, not stamped as unimplemented: {:?}", dev.unimplemented
        );
        let plain = UnitStatic::build(
            &mut reg, header.profiles.get("plain_blessed").expect("plain_blessed"),
        );
        assert_eq!(plain.shoot[0].surge_low, 6, "no Boost, no 5s (main.gd's default)");
        assert_eq!(plain.shoot[0].surge_over_in, 0.0, "and no over-9\" gate");
        let pb = UnitStatic::build(
            &mut reg, header.profiles.get("point_blank_unit").expect("point_blank_unit"),
        );
        assert_eq!(pb.shoot[0].surge_within_in, 12.0, "Point-Blank's within gate, ranged");
        assert_eq!(pb.melee[0].surge_within_in, 12.0, "and melee — the entry carries no shooting_only");
    }

    /// Brutal Fighter = the `melee_only` Surge alias (gf human_inquisition):
    /// the facet gate keeps it off the ranged profile. Its effect predates the
    /// epoch mechanism (consumed ungated since block B6), so the RED leg here
    /// is the WITHOUT-rule one: the plain sibling stays silent on both.
    #[test]
    fn brutal_fighter_is_melee_only_through_the_real_registry() {
        let header = read_act_header(SURGE_GATES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let bf = UnitStatic::build(
            &mut reg, header.profiles.get("brutal_fighter_unit").expect("brutal_fighter_unit"),
        );
        assert!(bf.melee[0].surge, "Brutal Fighter's melee-only surge facet");
        assert!(!bf.shoot[0].surge, "the ranged profile stays untouched (melee_only)");
        let plain = UnitStatic::build(
            &mut reg, header.profiles.get("plain_inquisition").expect("plain_inquisition"),
        );
        assert!(!plain.melee[0].surge && !plain.shoot[0].surge, "no Brutal Fighter, no facet");
    }

    /// Precision Hunter = Targeting Visor's word-for-word twin, now on the
    /// `stamp_shot_modifier` allow-list: +1 to hit past 9". RED (drop the
    /// list entry, or the new `dao_union` registry entry): `hit_bonus_over9`
    /// stays 0.
    #[test]
    fn precision_hunter_stamps_the_over_nine_hit_bonus() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("precision_hunter_unit").expect("precision_hunter_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.shoot[0].hit_bonus_over9, 1, "Precision Hunter's own hit_bonus");
        assert_eq!(us.shoot[0].hit_bonus, 0, "flat (non-over-9) leg stays untouched");
        let plain = header.profiles.get("plain_dao_union").expect("plain_dao_union");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no Precision Hunter, no bonus");
    }

    /// Nimble = Bounding's word-for-word twin, own D3 (vs Bounding's D3+1) —
    /// `bounding_of`'s named-carrier loop. RED (drop the new
    /// `elven_jesters` registry entry): `bounding` falls back to `None`.
    #[test]
    fn nimble_stamps_its_own_d3_reach_not_boundings_d3_plus_one() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("nimble_unit").expect("nimble_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.bounding, Some(0.0), "Nimble's own place_d3_plus");
        let plain = header.profiles.get("plain_elven_jesters").expect("plain_elven_jesters");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.bounding, None, "no Nimble, no stamp");
    }

    /// Courageous = the Banner DATA ALIAS (`banner_bonus_of`'s generic scan
    /// over every carried rule's own registry entry) — the SAME mechanism
    /// Screened rides for Stealth, so no Rust change was needed here either.
    /// RED (drop the new `alien_hives` registry entry): `morale_bonus` stays 0.
    #[test]
    fn courageous_reaches_capture_reads_via_the_banner_alias() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("courageous_unit").expect("courageous_unit");
        let reads = capture_reads(&mut reg, carrier);
        assert_eq!(reads.morale_bonus, 1, "Courageous's own morale_bonus");
        let plain = header.profiles.get("plain_alien_hives").expect("plain_alien_hives");
        let reads = capture_reads(&mut reg, plain);
        assert_eq!(reads.morale_bonus, 0, "no Courageous, no bonus");
    }

    /// The Quick/Fast move-band family's six carriers, one per real gf faction
    /// block (`assets/solo/rules_mechanics_gf.json`), each next to a plain
    /// sibling in the SAME faction so the (system, faction, name) lookup is
    /// real. Three rows per name: stamped with the rule at
    /// CURRENT_RULES_EPOCH, absent without the rule, absent at epoch 0 —
    /// the same reading the recorded (epoch 0/2) corpora replay with.
    const QUICKFAST_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "agile_unit":{"unit_id":"agile_unit","name":"Agile Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dark_elf_raiders","special_rules":["Agile"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_dark_elf_raiders":{"unit_id":"plain_dark_elf_raiders","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dark_elf_raiders","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "highborn_unit":{"unit_id":"highborn_unit","name":"Highborn Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":["Highborn"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_high_elf_fleets":{"unit_id":"plain_high_elf_fleets","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "quick_unit":{"unit_id":"quick_unit","name":"Quick Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers","special_rules":["Quick"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_goblin_reclaimers":{"unit_id":"plain_goblin_reclaimers","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "scurry_unit":{"unit_id":"scurry_unit","name":"Scurry Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":["Scurry"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_ratmen_clans":{"unit_id":"plain_ratmen_clans","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_unit":{"unit_id":"rapid_charge_unit","name":"Rapid Charge Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"wormhole_daemons_of_war","special_rules":["Rapid Charge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_wormhole_daemons_of_war":{"unit_id":"plain_wormhole_daemons_of_war","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"wormhole_daemons_of_war","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_aura_unit":{"unit_id":"rapid_charge_aura_unit","name":"Rapid Charge Aura Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Rapid Charge Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_expanded_unit":{"unit_id":"rapid_charge_expanded_unit","name":"Rapid Charge Expanded","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Rapid Charge Aura","Rapid Charge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_alien_hives_qf":{"unit_id":"plain_alien_hives_qf","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn quickfast_bands(name: &str, rules_epoch: u32) -> Option<Bands> {
        let header = read_act_header(QUICKFAST_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get(name).expect(name), rules_epoch).move_rule_mods
    }

    /// Agile rides Quick's own params (+1" Advance, +2" Rush/Charge) — the
    /// entry's own `advance_mod`/`rush_mod`, not a constant. RED: drop the
    /// `move_rule_mods_of` arm (or the registry entry) and the carrier falls
    /// to `None`.
    #[test]
    fn agile_stamps_its_own_advance_and_rush_mods() {
        assert_eq!(
            quickfast_bands("agile_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 1.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_dark_elf_raiders", CURRENT_RULES_EPOCH),
            None,
            "no Agile, no stamp"
        );
        assert_eq!(quickfast_bands("agile_unit", 0), None, "epoch 0 reads the pre-port row");
    }

    /// Highborn = the Quick primitive's +2"/+2" alias. RED: drop the loop's
    /// "Highborn" literal (or the entry): `None`.
    #[test]
    fn highborn_stamps_the_quick_primitive_bands() {
        assert_eq!(
            quickfast_bands("highborn_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_high_elf_fleets", CURRENT_RULES_EPOCH),
            None,
            "no Highborn, no stamp"
        );
        assert_eq!(quickfast_bands("highborn_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Quick itself — the name pass's own constant rule (+2"/+2"), stamped
    /// from its own entry's params. RED: drop the "Quick" literal: `None`.
    #[test]
    fn quick_stamps_its_own_entry_params() {
        assert_eq!(
            quickfast_bands("quick_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_goblin_reclaimers", CURRENT_RULES_EPOCH),
            None,
            "no Quick, no stamp"
        );
        assert_eq!(quickfast_bands("quick_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Scurry = the Quick primitive's ratmen alias (+2"/+2"). RED: drop the
    /// "Scurry" literal (or the entry): `None`.
    #[test]
    fn scurry_stamps_its_own_entry_params() {
        assert_eq!(
            quickfast_bands("scurry_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_ratmen_clans", CURRENT_RULES_EPOCH),
            None,
            "no Scurry, no stamp"
        );
        assert_eq!(quickfast_bands("scurry_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Rapid Charge rides Fast's `rush_mod` (+4" Charge; the rush band is the
    /// system's charge_reach), no advance half. RED: drop the "Rapid Charge"
    /// literal (or the entry): `None`.
    #[test]
    fn rapid_charge_stamps_fast_rush_mod_only() {
        assert_eq!(
            quickfast_bands("rapid_charge_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 4.0 })
        );
        assert_eq!(
            quickfast_bands("plain_wormhole_daemons_of_war", CURRENT_RULES_EPOCH),
            None,
            "no Rapid Charge, no stamp"
        );
        assert_eq!(quickfast_bands("rapid_charge_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Rapid Charge Aura — its OWN gf entry carries the same
    /// `rush_mod`/`charge_mod` shape, so the aura name is a carrier in its
    /// own right (the raw-name arm keeps the core independent of the import's
    /// aura expander). The import is ADDITIVE (keeps "X Aura", appends "X"),
    /// so a real aura unit carries BOTH names and the stamp sums to +8
    /// exactly like both band passes' per-name `counted` stacks. RED: drop
    /// the "Rapid Charge Aura" literal: the aura row falls to `None`.
    #[test]
    fn rapid_charge_aura_stamps_own_entry_and_stacks_the_expansion() {
        assert_eq!(
            quickfast_bands("rapid_charge_aura_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 4.0 }),
            "the aura entry's own rush_mod"
        );
        assert_eq!(
            quickfast_bands("plain_alien_hives_qf", CURRENT_RULES_EPOCH),
            None,
            "no aura, no stamp"
        );
        assert_eq!(quickfast_bands("rapid_charge_aura_unit", 0), None, "epoch 0 is pre-port");
    }

    /// The import is ADDITIVE (keeps "X Aura", appends "X"), so a real aura
    /// unit carries BOTH names and the stamp sums to +8 — exactly like both
    /// band passes' per-name `counted` stacks.
    #[test]
    fn rapid_charge_aura_plus_expanded_base_stacks_like_the_loaders() {
        assert_eq!(
            quickfast_bands("rapid_charge_expanded_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 8.0 }),
            "aura + expanded base, the loaders' per-name stack"
        );
        assert_eq!(
            quickfast_bands("rapid_charge_expanded_unit", 0),
            None,
            "epoch 0 is pre-port"
        );
    }
}
