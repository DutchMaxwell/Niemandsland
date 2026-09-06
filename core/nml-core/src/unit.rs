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

use std::borrow::Cow;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::acts::{
    rule_on, EPOCH_3_TABLE_RULES, EPOCH_4_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES,
    EPOCH_7_TABLE_RULES,
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

/// The Shielded-family DATA-alias stamp (wave 3, `acts::EPOCH_6_TABLE_RULES`):
/// the table's Shielded coverage read (`_solo_defense_parts`, main.gd:5506-
/// 5525) takes the literal name first, then the family's own entries — each on
/// all models, its +1 riding the SAME floored rung (`combat::shielded_defense`)
/// and the same "not from spells" clause the spell path's own ladder keeps.
/// `None` = the literal name or no member of the family; the literal keeps its
/// pre-port silent read.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ShieldedAlias {
    #[default]
    None,
    PlusOneToDefense,
    SturdyBoost,
    /// The terrain-conditional kind: its `terrain_within_in` gates the +1 on
    /// the majority-in-cover answer (`_solo_majority_in_cover`), which is
    /// live state — the static stamp leaves `shielded` off and
    /// `sim::ctx_live` folds it beside the granted names.
    GroundedReinforcement,
}

impl ShieldedAlias {
    /// The rules-must-log name, verbatim the rule's own text.
    pub fn name(self) -> &'static str {
        match self {
            Self::None => "",
            Self::PlusOneToDefense => "+1 to Defense",
            Self::SturdyBoost => "Sturdy Boost",
            Self::GroundedReinforcement => "Grounded Reinforcement",
        }
    }
}

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
    /// Wave 4 (`rules-wave4-boostbases`) — "Machine-Fog Boost" is the reason
    /// `evasive` is on: the printed unconditional form of Machine-Fog's own
    /// -1 (the base entry's conditional alias leg stands down so the two
    /// never stack). The dice seams name the RULE in their rules-must-log
    /// lines off this marker; a plain "Evasive" carrier keeps it false and
    /// stays silent, the `indirect_alias` marker precedent. Stamped behind
    /// the FROZEN `EPOCH_6_TABLE_RULES` — pre-epoch corpora replay
    /// byte-exact.
    pub evasive_alias: bool,
    /// Wave 4 (`rules-wave4-boostbases2`) — WHICH Boost is the reason
    /// `evasive_alias` is on, so the dice seams name the RULE that fired
    /// ("Machine-Fog Boost" at epoch 6, "Empyrean Spirit Boost" at epoch 7);
    /// "" = no Boost. A `&'static str`, not a `String`: `Ctx` is `Copy` and
    /// every name here is a literal in `ctx_for`'s own arms.
    pub evasive_alias_name: &'static str,
    /// `Melee Evasion` — the melee twin of Evasive (ai_ev.gd:150).
    pub melee_evasion: bool,
    pub fortified: bool,
    /// WAVE 3 — the Fortified family's DATA-ALIAS stamp (`fortified_alias_of`
    /// below, gated `EPOCH_6_TABLE_RULES`; the stamp IS the dice hook's gate).
    /// `fortified_boost_ap` — the carried Boost entry's reduction (`over_in`
    /// absent, the table's `gate_in <= 0.0` shape): EVERY save batch, every
    /// leg — the table passes `over9=false` to all of them (main.gd:3508,
    /// :6119). `fortified_alias_ap`/`fortified_alias_over_in` — the gated
    /// shape ("Guardian"/"Primeborn"/"Warden"/"Ossified"). 0 = not carried.
    pub fortified_boost_ap: i64,
    pub fortified_alias_ap: i64,
    pub fortified_alias_over_in: f64,
    /// The volley's over-9" GATE (main.gd:3090/6415): only
    /// `resolve_volley_with_tray` sets it, on its local Ctx copy; every other
    /// save path leaves it false.
    pub fortified_alias_over9: bool,
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
    /// Wave 3 — the Shielded-family DATA-alias fold (`acts::EPOCH_6_TABLE_
    /// RULES`): WHICH member of the family is driving the working `shielded`
    /// +1, `None` for the literal "Shielded" (its pre-port silent read) or no
    /// member. The three names are the wave's assignment; the fold itself is
    /// `ctx_for` (static carriers) plus `sim::ctx_live` (granted names and
    /// the terrain clause on the live in_cover answer).
    pub shielded_alias: ShieldedAlias,
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
    /// rules-wave3-growthmark (epoch 6) — the DEFENDER-side sister facets.
    /// ZERO on every `ctx_of` like the attacker half above; only `sim::ctx_live`
    /// folds them, and only behind `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`,
    /// so a rules_epoch 5 record replays byte-exact. Read by the tray's
    /// `save_batch` when THIS ctx is the DEFENDER.
    /// Defensive Frenzy/Growth: +X to every Defense roll the bearer makes
    /// (`defense_per_marker`/`defense_per_two` summed per `sim::growth_defense_of`).
    pub growth_def_mod: i64,
    /// Fortified Growth: the AP delta every unit attacking the bearer rides
    /// with (negative — the `enemy_ap_per_two` ladder), floored at the hard 0
    /// in `dice::save_batch`.
    pub growth_fortify_ap: i64,
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
    // --- Wave 3, the Piercing-Tag family's spend. ZERO on every `ctx_of` /
    // `ctx_live` — stamped ONLY by the volley seam's spend (sim.rs) after the
    // target's marker pool zeroes, so the EV imagination stays blind to it
    // exactly like `growth_ap_mod` (the table spends at resolve time only,
    // main.gd:3123/:9857) and melee never spends at all (the two spend call
    // sites are shooting paths; :6012's melee seam has no tag spend).
    /// +AP(markers) on THIS volley — folded into every shot profile's ap the
    /// same merge dice.rs's volley fold gives Piercing Growth's marker delta
    /// (main.gd:3124-3131 adds `tag_ap` to each `prof["ap"]`).
    pub tag_ap_mod: i64,
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
    // --- Wave 3 — the Shot Modifier family's two RUNTIME-GATED shooting
    // members (main.gd:5761-5779's data-driven loop), stamped BY NAME in
    // `ctx_for` behind the EPOCH_6_TABLE_RULES gate (`shot_modifier_runtime_
    // of`). Consumed in dice.rs's volley and melee folds. ---
    /// Mobile Artillery's +N to hit strictly past its own `over_in`, only
    /// while the shooter has NOT moved this round — the dynamic half is
    /// `moved_this_round` below, the table's `moved_round ==
    /// current_round` stamp gate (main.gd:5773-5775).
    pub mobile_artillery_hit: i64,
    pub mobile_artillery_over_in: f64,
    /// Grounded Precision's +N on every attack (its `all_attacks`), only
    /// while the attacker stands in terrain — the core's own cover read
    /// (`in_cover`) standing in for the table's majority-of-models gate
    /// (`_solo_majority_in_cover`, main.gd:7065-7083; the snapshot's cover
    /// is the unit-centre probe, battle_sim.gd:753).
    pub grounded_precision_hit: i64,
    /// The act-scope `moved` flag, stamped at sim.rs's volley call site over
    /// the template. Default TRUE — a context nobody stamped counts as
    /// moved, so the Mobile Artillery bonus stays OFF (#489's direction:
    /// under-credit, never over-credit).
    pub moved_this_round: bool,
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
    /// Wave 4 (rules-wave4-condap): the `ranged_within` cap — "Point-Blank
    /// Piercing"'s "when shooting enemies within 12\"". 0.0 on every spec the
    /// generic pass stamps (`cond_ap_of` never reads it), so the registry's own
    /// `ranged_within` spelling stays inert there; only `build_for`'s epoch-7
    /// named arm sets it, and combat.rs's arm fires on nothing else.
    pub within_in: f64,
    pub condition: String,
    pub threshold: i64,
    /// The rule NAME, for the rules-must-log line at the dice folds
    /// (`ShootResult.log`). Empty on every spec the generic pass stamps —
    /// pre-wave behaviour logs nothing and old replays stay byte-identical —
    /// only the wave-3 named forms carry it (Piercing Hunter family).
    pub name: String,
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
    /// Wave 4 (`rules-wave4-boostbases`) — the Bane Boost's widened save
    /// re-roll window ("Mischievous Boost"'s own `reroll_save_low`, stamped
    /// by `build_for`'s epoch-6 arm only when the model also carries the
    /// entry's `upgrades` base rule): successful unmodified defense rolls
    /// from this face up re-roll, not just 6s. 0 = the base 6s-only window.
    /// Read by the volley strictly past `bane_over_in`; the melee resolve
    /// never widens — no pre-charge gap (the Shred Boost's own measured
    /// shape).
    pub bane_low: i64,
    /// The Bane Boost's distance gate (the entry's own `over_in`): the
    /// widened window counts only past this centre distance, exactly 9" not
    /// "over" — same strict gate as every other over-9" read in this port.
    pub bane_over_in: f64,
    /// Wave 4 (`rules-wave4-boostbases2`) — WHICH Bane Boost widened this
    /// window, so the volley's rules-must-log line names the RULE that fired
    /// ("Mischievous Boost" at epoch 6, "Bestial Boost" at epoch 7); "" = the
    /// base 6s-only window.
    pub bane_rule: &'static str,
    /// Wave 3 (`rules-wave3-shred3`): the family's per-face wound amount,
    /// read off the carried Shred-primitive entry's own
    /// `extra_wound_per_save_one` (`build_for`'s epoch-6 arm, gated
    /// `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`). 0 = unread — the dice
    /// path falls back to the base +1 the wave-1 alias arm hard-codes, so
    /// every epoch-5 record replays byte-exact.
    pub shred_ones_wound_bonus: i64,
    /// The entry whose `extra_wound_per_save_one` this profile carries (the
    /// plain names: Destroyer/Infected/Warbound) — the rules-must-log
    /// line's rule name (dice.rs `save_batch`'s ShootResult.log push).
    /// "" = none.
    pub shred_ones_rule: String,
    /// The unit carrying that entry (`Profile::name`) — the log line's
    /// unit. "" = none.
    pub shred_ones_owner: String,
    pub indirect: bool,
    /// The unit-level "Indirect when Shooting" stamp (`build_for`'s epoch-6
    /// named walk below) — set ALONGSIDE `indirect` so the volley log
    /// (dice.rs) can name the RULE, not the weapon tag, when its cover skip
    /// lands. The log leg reads this field only; every effect read keeps the
    /// plain flag.
    pub indirect_alias: bool,
    /// The unit-level "Ignores Cover when Shooting" stamp — the same
    /// log-only marker shape as `indirect_alias` for the cover-only name
    /// (whose plain flag block 5 already stamps, ungated).
    pub ignores_cover_alias: bool,
    pub limited: bool,
    pub takedown: bool,
    /// Wave 4 (rules-wave4-renames): the UNIT-level Takedown-primitive NAME
    /// whose facet stamped `takedown` onto this profile ("Takedown when
    /// Shooting", the ranged facet — `stamp_takedown_named`), the
    /// rules-must-log subject at the volley fold. Empty on a weapon's own
    /// Takedown tag and on every record below `EPOCH_7_TABLE_RULES`, so
    /// pre-wave replays log nothing and stay byte-identical.
    pub takedown_rule: String,
    pub rules: Vec<String>,
    // --- stamped facets (ai_ev.gd:203-274) ---
    pub versatile_attack: bool,
    /// The wave-3 Versatile-Attack-family NAME the epoch-6 named arm stated
    /// this profile's buff under ("Watchborn", "Vinci Tech", "Vinci Tech
    /// Boost") — the rules-must-log subject at the volley fold. Empty on
    /// every generic stamp (the primitive walk), so pre-wave behaviour logs
    /// nothing and every earlier epoch's replay stays byte-identical.
    pub versatile_name: String,
    /// The "Vinci Tech Boost" form (`pick_one: false` in the registry): the
    /// bearer gets BOTH arms (AP(+1) AND +1 to hit) instead of
    /// `versatile_best_mode`'s pick. Stamped only when the model also
    /// carries Vinci Tech — the rule's own printed condition.
    pub versatile_both: bool,
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
            && self.indirect_alias == o.indirect_alias
            && self.ignores_cover_alias == o.ignores_cover_alias
            && self.limited == o.limited
            && self.takedown == o.takedown
            && self.takedown_rule == o.takedown_rule
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
    /// WAVE 3 — the Fortified family's own registry names as carried (unit.rs
    /// ::fortified_alias_of, gated `EPOCH_6_TABLE_RULES`), for the
    /// rules-must-log line the volley/melee orchestrators push. "" = none.
    pub fortified_alias_name: String,
    pub fortified_boost_name: String,
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
    /// The Storm Attack family's carried bursts (wave 3, `storm_of`): one
    /// entry per "Storm of X" the unit bears, params off its own registry
    /// entry, empty below `EPOCH_6_TABLE_RULES`.
    pub storm: Vec<StormSpec>,
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
    /// Wave 4 (`rules-wave4-boostbases2`) — "Wave-Step Boost"'s own placement
    /// DICE COUNT (`place_die: "2d3"` -> 2), stamped behind the FROZEN
    /// `EPOCH_7_TABLE_RULES`; 0 = no Boost (the base entry's single die).
    /// Same evidence-only standing as `bounding` above and as the move-band
    /// family's `move_rule_mods`: the placement reaches this core precomputed
    /// through the RECORDED `bounding_d3` faces, so this is the core's own
    /// per-entry read, not a simulation input — see `bounding_boost_dice_of`.
    pub bounding_dice: i64,
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
    /// simulation input. The wave-3 arm (`EPOCH_6_TABLE_RULES`,
    /// rules-wave3-fastband) stamps Highborn Boost/Scurry Boost BY NAME and
    /// reads their `upgrades` base rule — a statics-time condition ("If this
    /// model has Highborn/Scurry"); on every real book carrier the base
    /// rides along, so the stamp and the band passes' flat fold agree.
    /// Speed Feat (`uses_per_game`) and Grounded Speed (`terrain_within_in`,
    /// a per-activation majority-of-models read) stay OUT: no statics-time
    /// answer, and stamping them flat would claim coverage the core does
    /// not have (#489's over-credit shape).
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
    /// The Royal Legion family (wave 3, epoch 6) — the class's two live halves
    /// as the twins ship them: `range_bonus_in` (the
    /// `solo_controller.gd:shooting_range_bonus` /
    /// `list_to_profile.py::_shooting_range_bonus` alias-max) and `charge_mod`
    /// (the move-band pass's flat per-name rush fold — MOVE_PRIMITIVES carries
    /// "Royal Legion"). Census/evidence-only on this core (the accepted
    /// `bounding` shape, PR #653): the charge half reaches the sim precomputed —
    /// the band pass folds these same params into the profile `move_bands`
    /// this core consumes as `state.bands` — so a live re-fold at the move seam
    /// would double-count a recorded band. The Boost entries' `upgrades`
    /// condition is read by nobody on this core — neither twin's band or range
    /// pass reads it either, so the flat fold IS the shipped behaviour (the
    /// `move_rule_mods` precedent). Epoch-gated: `EPOCH_6_TABLE_RULES` — a
    /// record stamped `rules_epoch: 5` (the Gen-3 fleet's own window) predates
    /// wave 3 and reads zeros.
    pub royal_legion_range_in: f64,
    pub royal_legion_charge_in: f64,
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
    /// Wave 4 (`rules-wave4-boostbases`) — the two "Hit & Run" Boost
    /// spellings ("Guerrilla Boost", "Harassing Boost", the entry's own
    /// `move_in: 6`) stamp the carrier's own post-attack band here, behind
    /// the FROZEN `EPOCH_6_TABLE_RULES`; 0.0 = the shared base 3" const.
    /// The fire gate itself still runs on `hit_and_run_active` (the base
    /// family flag), which is what enforces the printed "If most models …
    /// have Guerrilla/Harassing" coupling.
    pub hit_and_run_move_in: f32,
    /// The Boost spelling whose band this is — the rules-must-log line's
    /// rule name (sim.rs's "Hit & Run: …" battle-log twin). "" = the base
    /// const (the `fortified_alias_name` precedent).
    pub hit_and_run_rule: String,
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
    /// Wave 3 — every "Piercing Tag" family entry this unit carries, each at
    /// its OWN literal (`piercing_tags_of`), empty below `rules_epoch` 6. The
    /// live pool and used-flag live on `State.piercing_tag_markers` /
    /// `State.piercing_tag_used`, not here.
    pub piercing_tags: Vec<PiercingTagEntry>,
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

/// The "Unregistered Rules" wave (epoch 6): names that are word-for-word
/// twins of an existing ported primitive under another faction's name. Their
/// registry entries ship with THIS wave, so a record below
/// `EPOCH_6_TABLE_RULES` was recorded against a table that had none of them —
/// every by-primitive walk below must skip them until the record's own epoch
/// reaches 6, exactly the stamping-gap rule `EPOCH_5_TABLE_RULES` fixed for
/// wave 2. Reach Hunt is the only one whose port rides a name-literal list
/// (the move bands); the other three ride by-primitive walks and need this
/// name check to stay invisible below the wave.
fn wave3_alias(name: &str) -> bool {
    matches!(
        name,
        "Violent" | "Vicious" | "Warding" | "Reach Hunt"
    )
}

/// Rules-must-log: each wave-3 arm names its rule on stderr when
/// NML_TRACE_RULES=1. Off by default — the fast core stays silent in gates
/// and rollouts. Same shape as `sim.rs`'s own helper (the S10 arms).
fn trace_rule(arm: &str, rule: &str, detail: &str) {
    if std::env::var("NML_TRACE_RULES").as_deref() == Ok("1") {
        eprintln!("[{arm}] {rule} — {detail}");
    }
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

/// The two "Hit & Run" Boost spellings (gf/rebel_guerrillas "Guerrilla Boost",
/// aof|gf dark-elf "Harassing Boost"): the entry's own `move_in` replaces the
/// shared 3" const when the FROZEN `EPOCH_6_TABLE_RULES` gate is on — wave 4
/// (`rules-wave4-boostbases`), read BY NAME, never by iterating the shared
/// primitive (the census's trusted-whole trap, #489). The fire gate itself
/// (`tray_hit_and_run`) still runs on `hit_and_run_active`, which is what
/// enforces the printed base-rule coupling. (0.0, "") = no Boost — the base
/// band.
fn hit_and_run_boost_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> (f32, String) {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return (0.0, String::new());
    }
    for name in ["Guerrilla Boost", "Harassing Boost"] {
        if unit_rule_active(reg, p, name) {
            let mv = unit_param_f(reg, p, name, "move_in", 0.0);
            if mv > 0.0 {
                return (mv as f32, name.to_string());
            }
        }
    }
    (0.0, String::new())
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
    stealth_alias_of_excluding(reg, p, "")
}

/// The same walk with one name stood down — the thin-wrapper shape the
/// signature rule prescribes: "Machine-Fog Boost" (wave 4) REPLACES its base
/// entry's conditional alias leg with an unconditional evasive fold, and the
/// two must never stack. `skip` "" = the plain walk, byte-exact.
fn stealth_alias_of_excluding(reg: &mut Registries, p: &Profile, skip: &str) -> (i64, f64) {
    let mut best_penalty = 0;
    let mut best_over_in = 0.0;
    let map = reg.rules_for(&p.game_system);
    for r in &p.special_rules {
        let name = base_rule_name(r);
        if name.is_empty() || name == "Stealth" || name == skip || !rule_on_all_models(p, &name) {
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

/// The Fortified family's DATA-ALIAS stamp — main.gd:6447-6462's coverage wave
/// (`unit_rules_of_primitive(defender, "Fortified")`, literal name skipped):
/// a Boost entry (`incoming_ap_reduction`, NO `over_in`) is the table's
/// `gate_in <= 0.0` branch — EVERY save batch, every leg; a gated entry
/// ("Guardian"/"Primeborn"/"Warden"/"Ossified") fires only past its own
/// `over_in`, which only the volley can measure. The table applies the FIRST
/// entry whose gate passes and breaks (:6461); every shipped entry carries
/// `incoming_ap_reduction: 1`, so the max here IS that first read — the
/// primal-Boost "uniform printed shape" precedent. Scans own rules AND
/// `item_grants`, each gated by `rule_on_all_models` (TC-023's all-models read).
#[derive(Default)]
struct FortifiedAlias {
    boost_ap: i64,
    boost_name: String,
    alias_ap: i64,
    alias_over_in: f64,
    alias_name: String,
}

fn fortified_alias_of(reg: &mut Registries, p: &Profile) -> FortifiedAlias {
    let mut out = FortifiedAlias::default();
    let map = reg.rules_for(&p.game_system);
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    for raw in raws {
        let name = base_rule_name(raw);
        if name.is_empty() || name == "Fortified" || !rule_on_all_models(p, &name) {
            continue;
        }
        let Some(e) = map.lookup(&p.faction_folder, &name) else {
            continue;
        };
        if e.primitive.as_deref() != Some("Fortified") {
            continue;
        }
        let ap = e.param_i("incoming_ap_reduction", 1);
        let over_in = e.param_f("over_in", 0.0);
        if over_in <= 0.0 {
            if ap > out.boost_ap {
                out.boost_ap = ap;
                out.boost_name = name;
            }
        } else if ap > out.alias_ap {
            out.alias_ap = ap;
            out.alias_over_in = over_in;
            out.alias_name = name;
        }
    }
    out
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
    /// The family's own per-face wound amount (`extra_wound_per_save_one` —
    /// the fixed +1 every Shred entry prints; the shred3 wave makes the core
    /// READ it instead of hard-coding it, `build_for`'s epoch-6 arm). 0 =
    /// the entry carries no such param.
    extra_wound_per_save_one: i64,
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
                    extra_wound_per_save_one: e.param_i("extra_wound_per_save_one", 0),
                });
            }
        }
    }
    let _ = rule_rating("", 0); // keep the import honest: ratings are unread here
    out
}
/// Rules-must-log: the aura fold names its unit and what it granted on stderr
/// when NML_TRACE_RULES=1 — the same gate `sim::trace_rule` uses. Off by
/// default: the fast core stays silent in gates and rollouts.
fn aura_channel_trace_rule(unit: &str, rule: &str, detail: &str) {
    if std::env::var("NML_TRACE_RULES").as_deref() == Ok("1") {
        eprintln!("[aura-channel] {unit} — {rule} — {detail}");
    }
}

/// The Aura-Channel family's read (rules-wave3-aura1, epoch 6): every carried
/// rule (own + item-granted + attached heroes') whose registry entry resolves
/// to the "Aura Channel" primitive, with its `grants` base. The family's
/// "<X> Aura" entries ("This model and its unit get X") are expanded at IMPORT
/// (opr_army_manager.gd:_expand_auras / list_to_profile.py:_expand_auras), so a
/// header recorded through either path already carries the granted base on
/// every member and the entry itself rides UNMAPPED-registered — no primitive,
/// no params anyone reads, the census's capped-at-STAMPED shape. This fold
/// makes the entry FIRST-CLASS: the core reads the entry's own `grants` param
/// instead of depending on an import-time rewrite it cannot see, so a header
/// carrying the RAW entries resolves identically. Idempotent with the import
/// expansion BY CONSTRUCTION (the base is appended only when absent), so a
/// corpus recorded with the expansion on replays byte-exact — and the fold's
/// own effect is observable exactly where that rewrite did not run.
fn aura_channel_hits(reg: &mut Registries, p: &Profile) -> Vec<(String, String)> {
    let map = reg.rules_for(&p.game_system);
    let mut out: Vec<(String, String)> = Vec::new();
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    for hr in &p.attached_hero_rules {
        raws.extend(hr.iter());
    }
    let mut seen: Vec<String> = Vec::new();
    for raw in raws {
        let aura = base_rule_name(raw);
        if aura.is_empty() || seen.iter().any(|s| *s == aura) {
            continue;
        }
        seen.push(aura.clone());
        let Some(e) = map.lookup(&p.faction_folder, &aura) else {
            continue;
        };
        if e.primitive.as_deref() != Some("Aura Channel") {
            continue;
        }
        let base = e.param_s("grants").trim().to_string();
        if !base.is_empty() && !out.iter().any(|(_, b)| *b == base) {
            out.push((aura, base));
        }
    }
    out
}

/// The fold's application: each hit's `grants` base joins the unit's own list
/// AND every attached hero's — the import twin's `expand_auras_of` shape (the
/// "all models" quantifier reads the heroes' own lists), each name once.
/// Gated `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` (the FROZEN constant,
/// never the literal or `CURRENT_RULES_EPOCH`): the recording fleet stamps
/// `rules_epoch: 5` and wave 3's registry rows do not exist in that recorder,
/// so a record stamped 5 must keep the import-fold-only reading it played
/// with. Logs one line per aura entry that actually changed a member — the
/// logging rule: a rule that fires silently is not shipped.
fn apply_aura_channel(reg: &mut Registries, p: &mut Profile, rules_epoch: u32) {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return;
    }
    for (aura, base) in aura_channel_hits(reg, p) {
        let mut added = 0;
        if !has_special_rule(&p.special_rules, &base) {
            p.special_rules.push(base.clone());
            added += 1;
        }
        for hr in p.attached_hero_rules.iter_mut() {
            if !has_special_rule(hr, &base) {
                hr.push(base.clone());
                added += 1;
            }
        }
        if added > 0 {
            aura_channel_trace_rule(&p.name, &aura, &format!("granted {base} to {added} member(s)"));
        }
    }
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

/// main.gd:5506-5525's Shielded coverage wave, the STATIC half — the literal
/// name first (the ungated pre-port read), then the wave's three names, each
/// on all models like the base form, its own entry deciding both reads: the
/// +1 is the entry's own `defense_bonus` (0 = no fold) and
/// `terrain_within_in > 0` makes it the majority-in-cover kind, which only
/// the live fold (`sim::ctx_live`, on the recorded/computed `state.in_cover`)
/// can resolve — so a terrain-gated alias returns pending here. Item-granted
/// rules already reach it through the import's fold (`rules_of_primitive`'s
/// own+item walk). EPOCH-GATED (`acts::rule_on`): the walk is wave-3
/// behaviour, so a record below `EPOCH_6_TABLE_RULES` keeps the pre-port
/// reading — the bare literal with nothing beside it.
fn shielded_alias_of(
    reg: &mut Registries,
    p: &Profile,
    rules_epoch: u32,
) -> Option<(ShieldedAlias, bool)> {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) || rule_on_all_models(p, "Shielded") {
        return None;
    }
    const ALIASES: [(&str, ShieldedAlias); 3] = [
        ("+1 to Defense", ShieldedAlias::PlusOneToDefense),
        ("Sturdy Boost", ShieldedAlias::SturdyBoost),
        ("Grounded Reinforcement", ShieldedAlias::GroundedReinforcement),
    ];
    let map = reg.rules_for(&p.game_system);
    for (name, alias) in ALIASES {
        if !rule_on_all_models(p, name) {
            continue;
        }
        let Some(e) = map.lookup(&p.faction_folder, name) else {
            continue;
        };
        if e.primitive.as_deref() != Some("Shielded") || e.param_i("defense_bonus", 0) <= 0 {
            continue;
        }
        return Some((alias, e.param_f("terrain_within_in", 0.0) > 0.0));
    }
    None
}

/// The four reads above for one unit profile.
pub fn capture_reads(reg: &mut Registries, p: &Profile) -> CaptureReads {
    capture_reads_for_epoch(reg, p, 0)
}

/// The epoch-aware capture twin (rules-wave3-aura1): `capture_reads` keeps its
/// signature for its existing callers (never widen a shared function) and
/// stays epoch-blind — the pre-6 reading every recorded capture mirrors. The
/// epoch-aware caller adopts this wrapper, which applies the aura fold before
/// the reads, so the capture-time reads answer a RAW header the way the
/// table's own expansion would have.
pub fn capture_reads_for_epoch(
    reg: &mut Registries,
    p: &Profile,
    rules_epoch: u32,
) -> CaptureReads {
    let mut p = p.clone();
    apply_aura_channel(reg, &mut p, rules_epoch);
    let p = &p;
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
            // Wave 3 (epoch 6): "Warding" is Angelic Blessing/Knightborn's
            // word-for-word twin — its registry entry ships with this wave,
            // so a record below `EPOCH_6_TABLE_RULES` keeps NOT seeing it.
            if wave3_alias(&n) {
                if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
                    continue;
                }
                trace_rule(
                    "regen",
                    &n,
                    &format!("regen alias on {} — wounds ignored on {}+ (spells {}+)", p.name,
                        e.param_i("ignore_target", 0), e.param_i("ignore_target_spell", 0)),
                );
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
    // Wave 4 — "Machine-Fog Boost": the printed unconditional form of
    // Machine-Fog's own -1 (folds into `evasive`, below; the base entry's
    // conditional alias leg stands down so the two never stack).
    let machine_fog_boost = rule_on(rules_epoch, EPOCH_6_TABLE_RULES)
        && rule_on_all_models(p, "Machine-Fog") && rule_on_all_models(p, "Machine-Fog Boost");
    // Wave 4 (rules-wave4-boostbases2) — "Empyrean Spirit Boost" is the
    // aof/ghostly_undead twin of the same shape: the printed unconditional
    // form of Empyrean Spirit's own -1 ("enemies attacking them always get -1
    // to hit"), its OWN Evasive-primitive entry, behind the FROZEN
    // `EPOCH_7_TABLE_RULES`. The base entry's conditional Stealth alias leg
    // stands down so the two never stack.
    let empyrean_spirit_boost = rule_on(rules_epoch, EPOCH_7_TABLE_RULES)
        && rule_on_all_models(p, "Empyrean Spirit")
        && rule_on_all_models(p, "Empyrean Spirit Boost");
    // The Boost that is the reason `evasive` is on, if any — the dice seams'
    // rules-must-log name ("" = none). Epoch 6 before epoch 7: a carrier can
    // only ever hold one of these two (different systems and factions).
    let evasive_boost = if machine_fog_boost {
        "Machine-Fog Boost"
    } else if empyrean_spirit_boost {
        "Empyrean Spirit Boost"
    } else {
        ""
    };
    let (stealth_alias_penalty, stealth_alias_over_in) = if machine_fog_boost {
        stealth_alias_of_excluding(reg, p, "Machine-Fog")
    } else if empyrean_spirit_boost {
        stealth_alias_of_excluding(reg, p, "Empyrean Spirit")
    } else {
        stealth_alias_of(reg, p)
    };
    // WAVE 3 — the family's DATA-ALIAS amounts, gated on the FROZEN
    // `EPOCH_6_TABLE_RULES`: an `rules_epoch: 5` record (the Gen-3 fleet's
    // window) reads zeros and replays byte-exact; the stamp IS the gate.
    let (fortified_boost_ap, fortified_alias_ap, fortified_alias_over_in) =
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            let fa = fortified_alias_of(reg, p);
            (fa.boost_ap, fa.alias_ap, fa.alias_over_in)
        } else {
            (0, 0, 0.0)
        };
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
    // the rest of the primitive (Precision Feat, ...) uncredited — #489's
    // lesson. The two runtime-gated shooters ride `shot_modifier_runtime_of`
    // below; Grounded Precision's `all_attacks` melee half is consumed at the
    // melee seam itself (dice.rs::melee_hit_target).
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
    // Wave 3 — the family's two runtime-gated shooting members (see
    // `shot_modifier_runtime_of`); `moved_this_round` keeps its default true
    // until sim.rs's volley site stamps the act-scope flag over it.
    let (mobile_artillery_hit, mobile_artillery_over_in, grounded_precision_hit) =
        shot_modifier_runtime_of(reg, p, rules_epoch);
    let shielded_alias = shielded_alias_of(reg, p, rules_epoch);
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
        evasive: rule_on_all_models(p, "Evasive") || !evasive_boost.is_empty(),
        evasive_alias: !evasive_boost.is_empty(),
        evasive_alias_name: evasive_boost,
        melee_evasion: rule_on_all_models(p, "Melee Evasion"),
        fortified: rule_on_all_models(p, "Fortified"),
        // WAVE 3 — stamped above, behind `EPOCH_6_TABLE_RULES`.
        fortified_boost_ap,
        fortified_alias_ap,
        fortified_alias_over_in,
        fortified_alias_over9: false,
        // Guarded OR Versatile Defense — ai_ev.gd:157-158.
        guarded: rule_on_all_models(p, "Guarded") || rule_on_all_models(p, "Versatile Defense"),
        ranged_shrouding: ranged_shroud.is_some(),
        ranged_shroud_penalty_in: ranged_shroud.map_or(SHROUD_RANGE_PENALTY_IN, |s| s[0]),
        ranged_shroud_floor_in: ranged_shroud.map_or(SHROUD_FLOOR_IN, |s| s[1]),
        mobile_artillery_hit,
        mobile_artillery_over_in,
        grounded_precision_hit,
        moved_this_round: true,
        shielded: rule_on_all_models(p, "Shielded")
            || shielded_alias.as_ref().is_some_and(|(_, pending)| !*pending),
        shielded_alias: shielded_alias.map_or(ShieldedAlias::None, |(a, _)| a),
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
        growth_def_mod: 0,
        growth_fortify_ap: 0,
        ambush_arrival_ap: 0,
        tag_ap_mod: 0,
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
    rules_epoch: u32,
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
    let mut shred_hits = rules_of_primitive(reg, p, "Shred");
    // Wave 3 (epoch 6): "Violent" is Warbound/Destroyer/Infected's
    // word-for-word twin — its registry entry ships with this wave, so a
    // record below `EPOCH_6_TABLE_RULES` keeps NOT seeing it (the walk below
    // is epoch-blind; the dice-side gate at sim.rs is epoch 3, older than the
    // wave).
    shred_hits.retain(|h| !wave3_alias(&h.name) || rule_on(rules_epoch, EPOCH_6_TABLE_RULES));
    for h in shred_hits.iter().filter(|h| wave3_alias(&h.name)) {
        trace_rule(
            "stamp",
            &h.name,
            &format!("shred alias on {} — blocking rolls of unmodified 1 take +1 wound", p.name),
        );
    }
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
            // Wave 4 (rules-wave4-condap), gated on the FROZEN
            // `EPOCH_7_TABLE_RULES`: "Rending in Melee" leaves the flat
            // prefix read for the facet read below (its own entry's
            // `melee_only`), and a striker's own "… Aura" spelling never
            // fires by itself (main.gd:6540's rule, the Bane branch above) —
            // the Aura-Channel fold has already granted its base. Below
            // epoch 7 the prefix read stays: both arrays rend, byte-exact.
            if rule_on(rules_epoch, EPOCH_7_TABLE_RULES)
                && (rs.ends_with("Aura") || base_rule_name(rs) == "Rending in Melee")
            {
                continue;
            }
            u_rending = true;
        } else if rs.starts_with("Unstoppable") && !rs.contains(" in ") && !rs.contains(" when ") {
            u_unstop = true;
        }
    }
    if table_ladder {
        // The coverage wave (main.gd:6553-6560): Bane-primitive data aliases
        // whose own entry carries `reroll_save_sixes` — no scope qualifier.
        // Wave 3 (epoch 6): "Vicious" is Bestial/Mischievous/Scrapper's
        // word-for-word twin — its registry entry ships with this wave, so a
        // record below `EPOCH_6_TABLE_RULES` keeps NOT seeing it.
        for hit in rules_of_primitive(reg, p, "Bane") {
            if hit.name.starts_with("Bane") || hit.name.ends_with("Aura") {
                continue;
            }
            if wave3_alias(&hit.name) {
                if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
                    continue;
                }
                trace_rule(
                    "strikers",
                    &hit.name,
                    &format!("bane alias on {} — defender re-rolls unmodified 6s", p.name),
                );
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
    // Wave 4 (rules-wave4-condap): "Rending in Melee" ("This model gets
    // Rending in melee") read BY NAME off its own Rending-primitive entry —
    // the facet pair (`melee_only`/`shooting_only`) is the live read, the
    // table's ai_ev.gd:292-303 stamp re-stated; never the primitive whole
    // (#489). Gated on the FROZEN `EPOCH_7_TABLE_RULES`, never the literal.
    let mut melee_rending = false;
    let mut shooting_rending = false;
    if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        for hit in rules_of_primitive(reg, p, "Rending") {
            if hit.name != "Rending in Melee" {
                continue;
            }
            melee_rending |= hit.melee_only;
            shooting_rending |= hit.shooting_only;
            u_rending |= !hit.melee_only && !hit.shooting_only;
        }
    }
    for sp in shoot.iter_mut() {
        sp.bane |= u_bane
            || (melee_bane && sp.range <= 0)
            || (shooting_bane && sp.range > 0);
        sp.rending |= u_rending
            || (melee_rending && sp.range <= 0)
            || (shooting_rending && sp.range > 0);
        sp.unstoppable_ev = sp.unstoppable || u_unstop;
    }
}

// --- Wave 3 "Aura Channel" family (gated `acts::rule_on(.., EPOCH_6_TABLE_RULES)`). ---
//
// The import expansion (opr_army_manager.gd:_expand_auras :2112-2147 and its
// loader twin list_to_profile.py:_expand_auras :350) is additive and deduped:
// every "<X> Aura" carried by a unit or its attached heroes hands the base
// rule "<X>" to the unit AND to each of those heroes ("this model and its
// unit get X", book text). The AURA ENTRY ITSELF stays in special_rules and
// carries no params any resolver reads — the census caps all twenty of this
// family's names at STAMPED (PR #489's "recognised, read by nobody" shape).
//
// This wave makes the aura entry a FIRST-CLASS core read for the twenty
// names: the same additive, deduped grant, computed by the core off the
// carried "* Aura" entries, gated `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`
// (the frozen wave-3 constant — a recorder stamping `rules_epoch: 5` never
// played wave 3's rules, see acts.rs). Dedup is the loader's own exact-match
// test (`g not in m["special_rules"]`), so a post-import profile — where the
// import already granted the base — expands byte-identical: the known
// corpora (epochs <= 5, gate off) and the epoch-6 replay of an expanded
// profile are both untouched. The import expansion STAYS: it is the
// cross-unit leg (a HERO carried by a host stamps its base onto the host,
// which build_for cannot see) and the fallback for every earlier epoch. What
// the core gains is the leg the loader twin skips — `LEGACY_CORE_SELFPLAY`
// returns from `_expand_auras` before it runs.
pub(crate) const AURA_CHANNEL_NAMES: &[&str] = &[
    "Melee Evasion Aura",
    "Fearless Aura",
    "Bounding Aura",
    "Strider Aura",
    "Rending in Melee Aura",
    "Quick Shot Aura",
    "Piercing Hunter Aura",
    "Teleport Aura",
    "Hit & Run Fighter Aura",
    "Indirect when Shooting Aura",
    "Piercing Fighter Aura",
    "Rapid Advance Aura",
    "Ranged Slayer Aura",
    "Melee Slayer Aura",
    "Speed Feat Aura",
    "Reanimation Aura",
    "Piercing Shooter Aura",
    "Grounded Reinforcement Aura",
    "Grounded Protection Aura",
    "Protected Aura",
];

/// The loader's own base-name cut (`rule[:-len(" Aura")].strip()`), kept only
/// for the twenty entries this wave fields: the carried aura entry's base
/// rule name, `Some("Melee Evasion")` for "Melee Evasion Aura". `None` = not
/// an aura entry of this family — a striker's scoped "* Aura" facet
/// (unit.rs:1405) and every other carried name pass through untouched.
fn aura_channel_base_of(aura: &str) -> Option<&str> {
    let entry = aura.trim();
    if !AURA_CHANNEL_NAMES.contains(&entry) {
        return None;
    }
    entry.strip_suffix(" Aura")
}

/// The wave-3 aura expansion read — the loader's `_aura_granted_rules` +
/// `_expand_auras` member loop over what one profile can see: every carried
/// aura entry of the twenty hands its base to the unit (`special_rules`) and
/// to each attached hero (`attached_hero_rules`, the `rule_on_all_models`
/// members ai_ev.gd:79-83 reads). Additive and deduped, the loader's own
/// exact-match test; the aura entry itself is never removed.
pub(crate) fn expand_aura_channel(p: &Profile, rules_epoch: u32) -> Cow<'_, Profile> {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        // The gate is OFF on every recorded corpus (epochs <= 5): the profile
        // passes through UNCLONED — the expansion read costs nothing there.
        return Cow::Borrowed(p);
    }
    let mut expanded = p.clone();
    // The loader's member loop: the bases of the auras across the unit AND
    // its heroes, collected first, then granted to EVERY member — each
    // target list deduped by its own exact-match test.
    let mut bases: Vec<String> = Vec::new();
    for aura in p.special_rules.iter().chain(p.attached_hero_rules.iter().flatten()) {
        if let Some(base) = aura_channel_base_of(aura) {
            if !bases.iter().any(|b| b == base) {
                bases.push(base.to_string());
            }
        }
    }
    for base in bases.iter() {
        if !expanded.special_rules.iter().any(|r| r == base) {
            expanded.special_rules.push(base.clone());
            // Rules-must-log: the unit, the aura entry that fired, the grant.
            crate::sim::trace_rule(
                "aura",
                &format!("{} (unit {})", aura_name_of(p, base), p.name),
                &format!("grants '{base}'"),
            );
        }
    }
    for hero in expanded.attached_hero_rules.iter_mut() {
        for base in bases.iter() {
            if !hero.iter().any(|r| r == base) {
                hero.push(base.clone());
            }
        }
    }
    Cow::Owned(expanded)
}

/// The carried aura entry a fired base came from — "X Aura", for the log.
fn aura_name_of(p: &Profile, base: &str) -> String {
    p.special_rules
        .iter()
        .chain(p.attached_hero_rules.iter().flatten())
        .find(|r| aura_channel_base_of(r) == Some(base))
        .cloned()
        .unwrap_or_else(|| format!("{base} Aura"))
}

// --- Wave 3 "Boost Aura (tail)" family (gated `acts::rule_on(.., EPOCH_6_TABLE_RULES)`). ---
//
// The import expansion (opr_army_manager.gd:_expand_auras :2112-2147 and its
// loader twin list_to_profile.py:_expand_auras :350) is additive and deduped:
// every "<X> Aura" carried by a unit or its attached heroes hands the base
// rule "<X>" to the unit AND to each of those heroes ("this model and its
// unit get X", book text). The AURA ENTRY ITSELF stays in special_rules and
// carries no params any resolver reads — the census caps this family's names
// at STAMPED / MISSING (PR #489's "recognised, read by nobody" shape).
//
// This wave makes the aura entry a FIRST-CLASS core read for the fifteen
// names: the same additive, deduped grant, computed by the core off the
// carried "* Boost Aura" entries, gated `rule_on(rules_epoch,
// EPOCH_6_TABLE_RULES)` (the frozen wave-3 constant — a recorder stamping
// `rules_epoch: 5` never played wave 3's rules, see acts.rs). Dedup is the
// loader's own exact-match test (`g not in m["special_rules"]`), so a
// post-import profile — where the import already granted the base — expands
// byte-identical: the known corpora (epochs <= 5, gate off) and the epoch-6
// replay of an expanded profile are both untouched. The import expansion
// STAYS: it is the cross-unit leg (a HERO carried by a host stamps its base
// onto the host, which build_for cannot see) and the fallback for every
// earlier epoch. What the core gains is the leg the loader twin skips —
// `LEGACY_CORE_SELFPLAY` returns from `_expand_auras` before it runs.
pub(crate) const BOOST_AURA_CHANNEL_NAMES: &[&str] = &[
    "Hold the Line Boost Aura",
    "Targeting Visor Boost Aura",
    "Warden Boost Aura",
    "Lucky Boost Aura",
    "Buccaneer Boost Aura",
    "Vale Oath Boost Aura",
    "Wave-Step Boost Aura",
    "Royal Warrior Boost Aura",
    "Bestial Boost Aura",
    "Vinci Tech Boost Aura",
    "Ossified Boost Aura",
    "Shadowborn Boost Aura",
    "Destroyer Boost Aura",
    "Empyrean Spirit Boost Aura",
    "Wild Veil Boost Aura",
];

/// The loader's own base-name cut (`rule[:-len(" Aura")].strip()`), kept only
/// for the fifteen entries this wave fields: the carried aura entry's base
/// rule name, `Some("Lucky Boost")` for "Lucky Boost Aura". `None` = not an
/// aura entry of this family — a striker's scoped "* Aura" facet (unit.rs
/// ::stamp_unit_strikers) and every other carried name pass through untouched.
fn boost_aura_base_of(aura: &str) -> Option<&str> {
    let entry = aura.trim();
    if !BOOST_AURA_CHANNEL_NAMES.contains(&entry) {
        return None;
    }
    entry.strip_suffix(" Aura")
}

/// The wave-3 Boost-aura expansion read — the loader's `_aura_granted_rules`
/// + `_expand_auras` member loop over what one profile can see: every carried
/// aura entry of the fifteen hands its base to the unit (`special_rules`) and
/// to each attached hero (`attached_hero_rules`, the `rule_on_all_models`
/// members ai_ev.gd:79-83 reads). Additive and deduped, the loader's own
/// exact-match test; the aura entry itself is never removed.
pub(crate) fn expand_boost_aura(p: &Profile, rules_epoch: u32) -> Cow<'_, Profile> {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        // The gate is OFF on every recorded corpus (epochs <= 5): the profile
        // passes through UNCLONED — the expansion read costs nothing there.
        return Cow::Borrowed(p);
    }
    let mut expanded = p.clone();
    // The loader's member loop: the bases of the auras across the unit AND
    // its heroes, collected first, then granted to EVERY member — each
    // target list deduped by its own exact-match test.
    let mut bases: Vec<String> = Vec::new();
    for aura in p
        .special_rules
        .iter()
        .chain(p.attached_hero_rules.iter().flatten())
    {
        if let Some(base) = boost_aura_base_of(aura) {
            if !bases.iter().any(|b| b == base) {
                bases.push(base.to_string());
            }
        }
    }
    for base in bases.iter() {
        if !expanded.special_rules.iter().any(|r| r == base) {
            expanded.special_rules.push(base.clone());
            // Rules-must-log: the unit, the aura entry that fired, the grant.
            crate::sim::trace_rule(
                "boost-aura",
                &format!("{} (unit {})", boost_aura_name_of(p, base), p.name),
                &format!("grants '{base}'"),
            );
        }
    }
    for hero in expanded.attached_hero_rules.iter_mut() {
        for base in bases.iter() {
            if !hero.iter().any(|r| r == base) {
                hero.push(base.clone());
            }
        }
    }
    Cow::Owned(expanded)
}

/// The carried aura entry a fired base came from — "X Boost Aura", for the log.
fn boost_aura_name_of(p: &Profile, base: &str) -> String {
    p.special_rules
        .iter()
        .chain(p.attached_hero_rules.iter().flatten())
        .find(|r| boost_aura_base_of(r) == Some(base))
        .cloned()
        .unwrap_or_else(|| format!("{base} Aura"))
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
/// (`requires_stationary`) and Grounded Precision (`terrain_within_in`) —
/// ride `shot_modifier_runtime_of` below (wave 3: their gates ARE the
/// runtime state), while Precision Feat (`uses_per_game`) stays out: a
/// once-per-game PLAYER CHOICE the table never automates, so stamping it
/// flat would be bug #489's over-credit.
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

/// Wave 3 — the Shot Modifier family's two RUNTIME-GATED shooting members,
/// stamped BY NAME (#489's lesson: naming them one by one keeps the rest of
/// the primitive uncredited). `stamp_shot_modifier` above covers the eight
/// flat/over-9" names whose bonuses are unconditional per weapon; these two
/// carry a runtime gate the table's own loop reads per shot
/// (main.gd:5761-5779): Mobile Artillery's `requires_stationary` (the
/// `moved_round == current_round` stamp, main.gd:5773-5775) and Grounded
/// Precision's `terrain_within_in` (`_solo_majority_in_cover`,
/// main.gd:5771). The core answers the first with the act-scope `moved`
/// flag (Ctx::moved_this_round, stamped at sim.rs's volley site) and the
/// second with its own cover read (Ctx::in_cover — the centre-probe
/// stand-in for the table's majority-of-models gate, battle_sim.gd:753).
/// Returns `(mobile_artillery_hit, mobile_artillery_over_in,
/// grounded_precision_hit)`, zeros = nothing carried. Gated on
/// `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` (frozen at 6, never the
/// literal or `CURRENT_RULES_EPOCH`): the Gen-3 recorder stamps
/// `rules_epoch: 5` and keeps today's reading byte-exact.
fn shot_modifier_runtime_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> (i64, f64, i64) {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return (0, 0.0, 0);
    }
    let (mut mobile_hit, mut mobile_over, mut grounded_hit) = (0, 0.0, 0);
    if unit_rule_active(reg, p, "Mobile Artillery") {
        if let Some(e) = reg.rules_for(&p.game_system).lookup(&p.faction_folder, "Mobile Artillery") {
            mobile_hit = e.param_i("hit_bonus", 0);
            mobile_over = e.param_f("over_in", 0.0);
        }
    }
    if unit_rule_active(reg, p, "Grounded Precision") {
        if let Some(e) = reg.rules_for(&p.game_system).lookup(&p.faction_folder, "Grounded Precision") {
            if e.param_f("terrain_within_in", 0.0) > 0.0 {
                grounded_hit = e.param_i("hit_bonus", 0);
            }
        }
    }
    (mobile_hit, mobile_over, grounded_hit)
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


#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StormFacet { Shred, Surge, Bane, Ap1 }

/// One carried "Storm of X" burst (main.gd:17231, the table's automation):
/// once per game, when ACTIVATED, before attacking — roll `dice`, per
/// `trigger`+ one enemy unit within `range_in` takes `hits` hits w/ `facet`.
#[derive(Debug, Clone, PartialEq)]
pub struct StormSpec {
    pub name: String,
    pub dice: i64, pub trigger: i64, pub range_in: f64,
    pub hits: i64, pub facet: StormFacet,
}

/// The Storm Attack family's stamp (wave 3): every carried "Storm Attack"
/// entry, read off its OWN params, gated on the FROZEN `EPOCH_6_TABLE_RULES`
/// — the fleet stamps `rules_epoch: 5` and wave 3's rules do not exist in
/// that recorder, so a record below 6 must never carry them.
fn storm_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> Vec<StormSpec> {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) { return Vec::new(); }
    let map = reg.rules_for(&p.game_system);
    let mut seen = std::collections::HashSet::new();
    p.special_rules.iter().chain(p.item_grants.iter())
        .filter_map(|raw| {
            let n = base_rule_name(raw);
            (!n.is_empty() && seen.insert(n.clone())).then_some(n)
        })
        .filter_map(|n| map.lookup(&p.faction_folder, &n)
            .filter(|e| e.primitive.as_deref() == Some("Storm Attack")).map(|e| (n, e)))
        .map(|(n, e)| StormSpec {
            name: n, dice: e.param_i("dice", 3), trigger: e.param_i("trigger_target", 2),
            range_in: e.param_f("range_in", 12.0), hits: e.param_i("hits", 3),
            facet: match e.param_s("facet") { "shred" => StormFacet::Shred, "surge" => StormFacet::Surge,
                "bane" => StormFacet::Bane, _ => StormFacet::Ap1 }, // the table's own `sp.get("facet", "ap1")` fallback
        })
        .collect()
}

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

/// One "Piercing Tag" registry entry the unit carries — wave 3's marker
/// family (`_solo_apply_piercing_tag` main.gd:16999-17027, the three registry
/// names that ride the "Piercing Tag" primitive). The table's resolver reads
/// exactly these per entry, in `unit_rules_of_primitive`'s own order:
/// `range_in` (its GDScript default 24.0), `needs_los` (default true) and the
/// RAW rule string's parsed rating — `maxi(rule_rating(str(raw)), 1)`
/// (main.gd:17022; the params' `"rating": "X"` placeholder parses as 0, so a
/// bare name places ONE marker). The entry's `place_roll` (Piercing Spotter)
/// and `uses_per_game` are dead data on the TABLE's own resolver — the AI
/// never rolls for the Spotter and the shared `piercing_tag_used` flag IS the
/// once-per-game beat — so the twin reads neither.
///
/// GATED `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` (frozen at 6, never the
/// literal and never `CURRENT_RULES_EPOCH`): a recording fleet is stamping
/// `rules_epoch: 5` today and wave 3's rules do not exist in that recorder —
/// see `acts::EPOCH_6_TABLE_RULES`.
#[derive(Debug, Clone, PartialEq)]
pub struct PiercingTagEntry {
    pub name: String,
    /// The marker count one placement adds: `maxi(rule_rating(raw), 1)`.
    pub markers: i64,
    /// The pick's range gate, centre to centre (`_solo_utility_target`).
    pub range_in: f64,
    /// The pick's sight gate (`bool(sp.get("needs_los", true))`).
    pub needs_los: bool,
}

/// Every "Piercing Tag" family entry the unit carries, in
/// `unit_rules_of_primitive`'s own order (own rules then item grants, each
/// base name once — rules_registry.gd:155-176) — but each at its OWN literal,
/// never a bare primitive loop, the #489 trusted-whole trap (a name this arm
/// does not list stays unwired and the census keeps it MISSING/STAMPED).
/// Empty below `rules_epoch` 6 — see the struct's gate note.
fn piercing_tags_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> Vec<PiercingTagEntry> {
    let mut out = Vec::new();
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return out;
    }
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
        if !matches!(n.as_str(), "Piercing Tag" | "Piercing Spotter" | "Piercing Target") {
            continue;
        }
        let Some(e) =
            map.lookup(&p.faction_folder, &n).filter(|e| e.primitive.as_deref() == Some("Piercing Tag"))
        else {
            continue;
        };
        out.push(PiercingTagEntry {
            name: n,
            markers: rule_rating(raw, 0).max(1),
            range_in: e.param_f("range_in", 24.0),
            needs_los: e.param_b_or("needs_los", true),
        });
    }
    out
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
    /// rules-wave3-growthmark (epoch 6) — Regenerative Strength's own trigger:
    /// +1 marker each time this unit IGNORES a wound.
    pub on_ignore_wound: bool,
    pub max_markers: i64,
    pub ap_per_marker: i64,
    pub ap_per_two: i64,
    pub hit_per_marker: i64,
    pub hit_per_two: i64,
    /// Defensive Frenzy/Growth: +X to this unit's Defense rolls per marker /
    /// per two markers (`sim::growth_defense_of`, epoch 6).
    pub defense_per_marker: i64,
    pub defense_per_two: i64,
    /// Fortified Growth: every unit attacking THIS one gets AP(X) per two
    /// markers (defender-side, negative), epoch 6.
    pub enemy_ap_per_two: i64,
    /// Regenerative Strength: +X attacks with one melee weapon, X = markers,
    /// epoch 6 (`sim::melee_parts`).
    pub attacks_per_marker: i64,
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
            on_ignore_wound: e.param_b("on_ignore_wound"),
            max_markers: e.param_i("max_markers", 4),
            ap_per_marker: e.param_i("ap_per_marker", 0),
            ap_per_two: e.param_i("ap_per_two", 0),
            hit_per_marker: e.param_i("hit_per_marker", 0),
            hit_per_two: e.param_i("hit_per_two", 0),
            defense_per_marker: e.param_i("defense_per_marker", 0),
            defense_per_two: e.param_i("defense_per_two", 0),
            enemy_ap_per_two: e.param_i("enemy_ap_per_two", 0),
            attacks_per_marker: e.param_i("attacks_per_marker", 0),
        };
        if (g.ap_per_marker, g.ap_per_two, g.hit_per_marker, g.hit_per_two,
            g.defense_per_marker, g.defense_per_two, g.enemy_ap_per_two,
            g.attacks_per_marker, g.on_ignore_wound) == (0, 0, 0, 0, 0, 0, 0, 0, false) {
            un.push(Unimplemented { rule: g.name.clone(), why:
                "Growth Markers params carry no facet this port consumes — the attack facets (main.gd:4287/:5675-5680) and the epoch-6 wave (defense_per_marker/defense_per_two, enemy_ap_per_two, on_ignore_wound, attacks_per_marker) are read; min_ap/all_models/scope are not".into() });
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
            ..Default::default()
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

/// Wave 4 (rules-wave4-condap) — the conditional-AP family's three remaining
/// printed shapes, read off the registry BY NAME (the census's own-token
/// evidence; never the primitive whole, #489). Called by `build_for` behind
/// the FROZEN `EPOCH_7_TABLE_RULES` only, AFTER the generic pass:
///   * "Piercing Fighter" ("This model gets AP(+1) in melee"): the entry's
///     `in_melee` spelling is inert on the shared match — the generic pass
///     has stamped it unnamed at every epoch, so the match must keep
///     answering 0 — and the named arm states the always leg on the MELEE
///     array alone (the Havocbound Boost mechanism, facet-scoped);
///   * "Point-Blank Piercing" ("AP(+1) when shooting enemies within 12\""):
///     the entry's own `within_in` cap on the SHOOT array — combat.rs's
///     `ranged_within` arm reads it, and the generic pass stamps 0.0;
///   * "Melee Slayer" ("When this model charges, its weapons get AP(+2) if
///     most models in the target have Tough(3) or higher") is live at every
///     epoch off the generic pass (`cond_ap_of`'s charge_only + vs_tough_ge,
///     fired by dice.rs's melee fold with the real `charging`) — no
///     arithmetic delta; the arm NAMES that stamped spec so the strike logs
///     it (rules-must-log). Naming, never a second spec: two would double.
///   * "Piercing Warrior" (wave 4, rules-wave4-renames — gf/havoc_brothers,
///     aof/havoc_dwarves, aof/havoc_warriors): Havocbound's text word for
///     word ("When this model shoots at enemies over 9\" away, or when it
///     charges, its weapons get AP(+1)"), and the same entry shape
///     (`condition: ranged_over_or_charge`, inert on the shared match) —
///     so the same two printed legs, on_charge plus ranged_over at the
///     entry's own over_in, on both arrays (the epoch-6 Havocbound arm's
///     mechanism, born at 7 for this spelling). No Boost couples to it:
///     "Havocbound Boost" `upgrades` the name "Havocbound" exactly.
/// The dice folds log the named forms; the unnamed generic specs stay
/// silent, so every earlier epoch's replay is byte-identical.
fn stamp_conditional_ap_named(
    reg: &mut Registries,
    p: &Profile,
    shoot: &mut [ShootProfile],
    melee: &mut [ShootProfile],
) {
    let map = reg.rules_for(&p.game_system);
    let mut seen: Vec<String> = Vec::new();
    for raw in &p.special_rules {
        let n = base_rule_name(raw);
        if n.is_empty() || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        let Some(e) = map.lookup(&p.faction_folder, &n) else {
            continue;
        };
        let ap = e.param_i("ap_bonus", 0);
        if ap <= 0 {
            continue;
        }
        match n.as_str() {
            "Piercing Fighter" => {
                for sp in melee.iter_mut() {
                    sp.cond_ap.push(CondAp {
                        ap_bonus: ap,
                        condition: "always".into(),
                        name: n.clone(),
                        ..Default::default()
                    });
                }
            }
            "Point-Blank Piercing" => {
                let within_in = e.param_f("within_in", 0.0);
                if within_in <= 0.0 {
                    continue;
                }
                for sp in shoot.iter_mut() {
                    sp.cond_ap.push(CondAp {
                        ap_bonus: ap,
                        condition: "ranged_within".into(),
                        within_in,
                        name: n.clone(),
                        ..Default::default()
                    });
                }
            }
            "Melee Slayer" => {
                let threshold = e.param_i("threshold", 0);
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    for c in sp.cond_ap.iter_mut() {
                        if c.name.is_empty()
                            && c.charge_only
                            && c.gate.is_empty()
                            && c.condition == "vs_tough_ge"
                            && c.ap_bonus == ap
                            && c.threshold == threshold
                        {
                            c.name = n.clone();
                        }
                    }
                }
            }
            "Piercing Warrior" => {
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    sp.cond_ap.push(CondAp {
                        ap_bonus: ap,
                        condition: "on_charge".into(),
                        name: n.clone(),
                        ..Default::default()
                    });
                    sp.cond_ap.push(CondAp {
                        ap_bonus: ap,
                        condition: "ranged_over".into(),
                        over_in: e.param_f("over_in", LONG_RANGE_IN),
                        name: n.clone(),
                        ..Default::default()
                    });
                }
            }
            _ => {}
        }
    }
}

/// Wave 4 (rules-wave4-renames) — the UNIT-level "Takedown when Shooting"
/// (aof/saurians: "This model gets Takedown when shooting"), the table's
/// `AiEv.takedown_rule_for_profile` ai_ev.gd:210-235: a carried Takedown-
/// primitive entry WITHOUT an `extra_attack_q` (the once-per-game "Takedown
/// Shot"/"Takedown Strike" bonus groups are a different mechanism — dice.rs's
/// own NOT-PORTED note) flags every profile its facet reaches, so
/// `shooting_only` keeps the melee array plain. Read BY NAME, never the
/// primitive whole (#489), off the unit's own rules plus its item grants —
/// the table's `unit_rules_of_primitive` universe. The flag routes to the
/// EXISTING Takedown consumers (the resolve-first sort and the `unported`
/// mark for the unit-of-[1] pick this port does not reproduce, dice.rs), and
/// the name lands in `takedown_rule` so the volley fold logs it
/// (rules-must-log). Called by `build_for` behind the FROZEN
/// `EPOCH_7_TABLE_RULES` only — a record below 7 keeps the flag off and
/// replays byte-exact.
fn stamp_takedown_named(
    reg: &mut Registries,
    p: &Profile,
    shoot: &mut [ShootProfile],
    melee: &mut [ShootProfile],
    name: &str,
) {
    if !has_exact_rule(&p.special_rules, name) && !has_exact_rule(&p.item_grants, name) {
        return;
    }
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map.lookup(&p.faction_folder, name) else {
        return;
    };
    if e.primitive.as_deref() != Some("Takedown") || e.param_i("extra_attack_q", 0) > 0 {
        return;
    }
    let (melee_only, shooting_only) = (e.param_b("melee_only"), e.param_b("shooting_only"));
    for sp in shoot.iter_mut().chain(melee.iter_mut()) {
        if facet_applies(melee_only, shooting_only, sp.range) {
            sp.takedown = true;
            sp.takedown_rule = name.to_string();
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

/// The Bane family's WIDENED save re-roll window, stamped off ONE named Boost
/// entry: the entry's own `reroll_save_low` + `over_in`, and only when the
/// model also carries the entry's `upgrades` base rule. Read BY NAME, never by
/// iterating the shared primitive (the census's trusted-whole trap, #489) —
/// the carry gate IS the port: a faction lookup alone would stamp every bane
/// carrier in the faction, carried Boost or not. Stamped on the SHOOT array
/// only: the volley consumes the window strictly past the entry's own
/// `over_in` (dice.rs `save_batch`); the melee resolve never widens — no
/// pre-charge gap (the shred2 precedent). Wave 3 calls it for "Mischievous
/// Boost" (gf+aof goblins) behind `EPOCH_6_TABLE_RULES`, wave 4 for "Bestial
/// Boost" (aof/beastmen) behind `EPOCH_7_TABLE_RULES`; each name states its
/// own epoch at the call site, so neither can back-date the other.
fn stamp_bane_boost(
    reg: &mut Registries,
    p: &Profile,
    shoot: &mut [ShootProfile],
    name: &'static str,
) {
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map
        .lookup(&p.faction_folder, name)
        .filter(|_| has_exact_rule(&p.special_rules, name))
    else {
        return;
    };
    let base = e.param_s("upgrades");
    let low = e.param_i("reroll_save_low", 0);
    if e.primitive.as_deref() != Some("Bane") || low <= 1 || !has_exact_rule(&p.special_rules, base)
    {
        return;
    }
    let over = e.param_f("over_in", 9.0);
    for sp in shoot.iter_mut().filter(|sp| sp.bane) {
        sp.bane_low = low;
        sp.bane_over_in = over;
        sp.bane_rule = name;
    }
}

/// `SoloController.bounding_dice_count` (solo_controller.gd:1386-1396) — how
/// many dice a Bounding placement rolls: an explicit `dice_count`, else the
/// head of an "NdM" `place_die` ("2d3" -> 2), else one.
fn bounding_dice_count(e: &crate::rules::Entry) -> i64 {
    let explicit = e.param_i("dice_count", 0);
    if explicit > 0 {
        return explicit.max(1);
    }
    let pd = e.param_s("place_die").to_lowercase();
    match pd.split_once('d') {
        Some((head, _)) => head.trim().parse::<i64>().unwrap_or(1).max(1),
        None => 1,
    }
}

/// Wave 4 (rules-wave4-boostbases2) — "Wave-Step Boost"'s own placement dice
/// count (aof/deep_sea_elves, `place_die: "2d3"` behind its own `upgrades`
/// coupling, "If this model has Wave-Step"): 2d3 instead of the base entry's
/// single D3. Read BY NAME behind the FROZEN `EPOCH_7_TABLE_RULES`; 0 = no
/// Boost, the single-die base, so every earlier record reads zero.
///
/// EVIDENCE-ONLY, the accepted `bounding` shape (PR #653, see
/// `UnitStatic::bounding`): the placement itself reaches this core
/// PRECOMPUTED — the table draws one die per head and records every face
/// (`AiActRecorder.traced("bounding_d3", faces, plus)`,
/// solo_controller.gd:1685-1703), and `sim::bounding_bonus_in` sums whatever
/// was recorded, so a 2d3 draw already replays exactly. Re-drawing the die
/// here would desync from the table; this stamp is the core's own per-entry
/// read, never a simulation input.
fn bounding_boost_dice_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> i64 {
    if !rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        return 0;
    }
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map
        .lookup(&p.faction_folder, "Wave-Step Boost")
        .filter(|_| has_exact_rule(&p.special_rules, "Wave-Step Boost"))
    else {
        return 0;
    };
    if e.primitive.as_deref() != Some("Bounding")
        || !has_exact_rule(&p.special_rules, e.param_s("upgrades"))
    {
        return 0;
    }
    bounding_dice_count(e)
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
    for name in [
        "Agile",
        "Highborn",
        "Quick",
        "Scurry",
        "Rapid Charge",
        "Rapid Charge Aura",
        // Wave 3 (epoch 6): "Reach Hunt" is Royal Legion/Lustbound's
        // word-for-word twin (+4" range when shooting — the loader-side
        // `shooting_range_bonus` half, unmodelled on this core exactly like
        // the twins' — and +2" on Charge actions, this arm). Its registry
        // entry ships with this wave, so a record below
        // `EPOCH_6_TABLE_RULES` keeps NOT seeing it.
        "Reach Hunt",
    ] {
        if !unit_rule_active(reg, p, name) {
            continue;
        }
        if wave3_alias(name) && !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            continue;
        }
        let map = reg.rules_for(&p.game_system);
        if let Some(e) = map.lookup(&p.faction_folder, name) {
            acc.advance += e.param_f("advance_mod", 0.0);
            acc.rush += e.param_f("rush_mod", e.param_f("charge_mod", 0.0));
            hit = true;
            if wave3_alias(name) {
                trace_rule(
                    "move_bands",
                    name,
                    &format!(
                        "move-band alias on {} — charge actions +{:.0}\"",
                        p.name,
                        e.param_f("rush_mod", e.param_f("charge_mod", 0.0))
                    ),
                );
            }
        }
    }
    // WAVE 3 Fast family (rules-wave3-fastband), gated on
    // `EPOCH_6_TABLE_RULES` (frozen at 6, never the literal or
    // `CURRENT_RULES_EPOCH`): the two move-band Boost upgrades stamp BY NAME
    // (the census's own-token evidence), each firing only with the base rule
    // its entry's `upgrades` param names ("If this model has
    // Highborn/Scurry") and contributing its own advance_mod/rush_mod — the
    // same per-name stack both band passes fold (Highborn 2/2 + Highborn
    // Boost 4/4 = 6/6). Grounded Speed stays OUT: its `terrain_within_in`
    // gate is a per-activation majority read no statics-time stamp can
    // answer, so a flat stamp would be #489's over-credit, not a port.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        for name in ["Highborn Boost", "Scurry Boost"] {
            if !unit_rule_active(reg, p, name) {
                continue;
            }
            // The registry read is scoped: `map`/`e` borrow `reg` mutably,
            // and the `upgrades` prereq check below needs that borrow free.
            let (base, adv, rsh) = {
                let map = reg.rules_for(&p.game_system);
                let Some(e) = map.lookup(&p.faction_folder, name) else {
                    continue;
                };
                (
                    e.param_s("upgrades").to_string(),
                    e.param_f("advance_mod", 0.0),
                    e.param_f("rush_mod", e.param_f("charge_mod", 0.0)),
                )
            };
            if base.is_empty() || !unit_rule_active(reg, p, &base) {
                continue;
            }
            acc.advance += adv;
            acc.rush += rsh;
            hit = true;
            // Rules-must-log: one stderr line when NML_TRACE_RULES=1, same
            // shape as sim.rs's S10 arms / rollout.rs's round-start leg.
            crate::sim::trace_rule(
                "move-bands",
                name,
                &format!(
                    "{}: +{adv}\" advance, +{rsh}\" rush/charge from {base}",
                    p.name
                ),
            );
        }
    }
    if hit { Some(acc) } else { None }
}

/// The Royal Legion family (wave 3, epoch 6) — every carried Royal
/// Legion-primitive entry's two live halves, folded the way the twins ship
/// them: `range_bonus_in` takes the alias-MAX (`_shooting_range_bonus`'s
/// `best`), `charge_mod` flat-folds per name (the move-band pass's per-name
/// stack — MOVE_PRIMITIVES carries "Royal Legion"). The Boost entries'
/// `upgrades` condition is read by nobody on this core — neither twin's band
/// or range pass reads it either (the `move_rule_mods` precedent), so the
/// flat fold IS the shipped behaviour. The primitive-NULL "Lustbound Boost
/// Aura" (no params anyone reads) rides the import's aura expansion through
/// its own raw-name arm — the `versatile_reach_charge_in` shape; an aura
/// whose own entry IS primitive-bearing (aof's Royal Legion Boost Aura,
/// every Increased Shooting Range Aura) was already folded under its own
/// name and is skipped here. Rules-must-log: one `trace_rule` line per
/// stamped unit. Epoch-gated: `EPOCH_6_TABLE_RULES` — a record stamped
/// `rules_epoch: 5` (the Gen-3 fleet's own window) predates wave 3.
fn royal_legion_family_of(reg: &mut Registries, p: &Profile, rules_epoch: u32) -> (f64, f64) {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return (0.0, 0.0);
    }
    let hits = rules_of_primitive(reg, p, "Royal Legion");
    let map = reg.rules_for(&p.game_system);
    let (mut range, mut charge) = (0.0_f64, 0.0_f64);
    let mut folded: Vec<String> = Vec::new();
    for hit in hits {
        let Some(e) = map.lookup(&p.faction_folder, &hit.name) else { continue };
        range = range.max(e.param_f("range_bonus_in", 0.0));
        charge += e.param_f("charge_mod", 0.0);
        folded.push(hit.name);
    }
    for (aura, base) in [("Lustbound Boost Aura", "Lustbound Boost")] {
        if !has_special_rule(&p.special_rules, aura) || folded.iter().any(|n| n == base) {
            continue;
        }
        if let Some(e) = map.lookup(&p.faction_folder, aura) {
            if e.primitive.as_deref() == Some("Royal Legion") {
                continue;
            }
        }
        let Some(e) = map.lookup(&p.faction_folder, base) else { continue };
        range = range.max(e.param_f("range_bonus_in", 0.0));
        charge += e.param_f("charge_mod", 0.0);
        folded.push(base.to_string());
    }
    if !folded.is_empty() {
        crate::sim::trace_rule(
            "W3-royal-legion",
            &folded.join(", "),
            &format!("{}: +{:.0}\" shooting range, +{:.0}\" charge", p.name, range, charge),
        );
    }
    (range, charge)
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
        // Wave 3 aura expansion reads (`EPOCH_6_TABLE_RULES`, frozen): the
        // core's own additive leg of the import expansion — post-import
        // profiles expand byte-identical (the loader's dedup), a
        // `LEGACY_CORE_SELFPLAY` feed gains the leg its loader twin skips,
        // and a Borrowed cow keeps every earlier-epoch replay clone-free.
        // Chained: Aura Channel first, then Boost Aura sees its output — both
        // are additive/dedup-checked against their OWN disjoint name lists,
        // so the order between the two independent families is inert.
        let aura_leg = expand_aura_channel(p, rules_epoch);
        let p: &Profile = &aura_leg;
        let boost_leg = expand_boost_aura(p, rules_epoch);
        let p: &Profile = &boost_leg;
        let mut unimplemented: Vec<Unimplemented> = Vec::new();
        // The Aura-Channel fold (rules-wave3-aura1, epoch 6) runs BEFORE any
        // read: the granted bases join a CLONE of the profile's own rule lists
        // (each name once), so every stamp/ctx read below sees them exactly as
        // the import expansion's fold delivered them on recorded corpora.
        // Shadowing `p` keeps every existing read site untouched.
        let mut p = p.clone();
        apply_aura_channel(reg, &mut p, rules_epoch);
        let p = &p;
        let mut shoot = profiles_in_range(&p.weapons, 0.0);
        stamp(reg, p, &mut shoot, &mut unimplemented, rules_epoch);
        stamp_conditional_ap(reg, p, &mut shoot);
        stamp_unit_strikers(reg, p, &mut shoot, rules_epoch);
        stamp_shot_modifier(reg, p, &mut shoot);

        let mut melee = melee_profiles(&p.weapons);
        // The same stamping runs on the melee array (`_profiles_of(su, true)`
        // battle_sim.gd:719-720 takes the identical path); a rule the port
        // cannot model is reported ONCE, not once per array.
        let mut melee_unimpl: Vec<Unimplemented> = Vec::new();
        stamp(reg, p, &mut melee, &mut melee_unimpl, rules_epoch);
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
        // Piercing Hunter family wave 3 (rules-wave3-piercehunt), gated on
        // `EPOCH_6_TABLE_RULES` (the FROZEN wave-3 constant — never the
        // literal 6, never CURRENT_RULES_EPOCH) so every record stamped 5 or
        // below (the Gen-3 recording fleet included) replays byte-exact. The
        // family's own spellings, read off the registry BY NAME — the
        // census's own-token evidence:
        //   * "Piercing Hunter" is live at every epoch off the generic
        //     pass's ranged_over spec (NML-1103) — no delta, name only;
        //   * "Havocbound"'s entry spelling (condition:
        //     "ranged_over_or_charge") is INERT on the shared match — its
        //     two printed legs are stated instead: on_charge (the charge
        //     leg) plus ranged_over at the entry's own over_in (the shoot
        //     leg);
        //   * "Piercing Shooter" ("gets AP(+1) when shooting") is the
        //     ranged_over spelling at its degenerate bound (over_in -1: any
        //     MEASURED distance fires; the unknown-distance sentinel stays
        //     shut, the table's own conservative reading, main.gd:6382).
        // The named forms log at the dice folds (rules-must-log); the
        // generic pass's unnamed specs keep every earlier epoch's replay
        // byte-identical. Wave 4 (rules-wave4-boostbases) ports "Havocbound
        // Boost" onto the same mechanism (the always leg + the `upgrades`
        // coupling, above); Point-Blank Piercing (a `within_in` cap) is
        // wave 4's condap arm below (epoch 7), not this block.
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            let mut live: Vec<CondAp> = Vec::new();
            let map = reg.rules_for(&p.game_system);
            let mut seen: Vec<String> = Vec::new();
            // Wave 4 (rules-wave4-boostbases): "Havocbound Boost" REPLACES its
            // base's two conditional legs when carried — the printed "always
            // … (instead of only when …)" — so the walk knows before it
            // reaches either name.
            let havoc_boosted = p.special_rules.iter().any(|r| base_rule_name(r) == "Havocbound Boost");
            for raw in &p.special_rules {
                let n = base_rule_name(raw);
                if n.is_empty() || seen.iter().any(|s| *s == n) {
                    continue;
                }
                seen.push(n.clone());
                let Some(e) = map.lookup(&p.faction_folder, &n) else {
                    continue;
                };
                if e.primitive.as_deref() != Some("Piercing Hunter") {
                    continue;
                }
                let ap = e.param_i("ap_bonus", 0);
                if ap <= 0 {
                    continue;
                }
                match n.as_str() {
                    "Piercing Hunter" => {} // live off the generic pass at every epoch — no delta
                    "Havocbound" if !havoc_boosted => {
                        live.push(CondAp {
                            ap_bonus: ap,
                            condition: "on_charge".into(),
                            name: n.clone(),
                            ..Default::default()
                        });
                        live.push(CondAp {
                            ap_bonus: ap,
                            condition: "ranged_over".into(),
                            over_in: e.param_f("over_in", LONG_RANGE_IN),
                            name: n.clone(),
                            ..Default::default()
                        });
                    }
                    "Piercing Shooter" => {
                        live.push(CondAp {
                            ap_bonus: ap,
                            condition: "ranged_over".into(),
                            over_in: -1.0,
                            name: n.clone(),
                            ..Default::default()
                        });
                    }
                    "Havocbound Boost" => {
                        // Wave 4 — the always leg, the entry's own `upgrades`
                        // coupling ("If this model has Havocbound"); the
                        // volley's and the strike's named cond_ap lines log.
                        if has_exact_rule(&p.special_rules, e.param_s("upgrades")) {
                            live.push(CondAp {
                                ap_bonus: ap, condition: "always".into(), name: n.clone(),
                                ..Default::default()
                            });
                        }
                    }
                    _ => {}
                }
            }
            if !live.is_empty() {
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    sp.cond_ap.extend(live.iter().cloned());
                }
            }
        }
        // Wave 4 (rules-wave4-condap), gated on the FROZEN
        // `EPOCH_7_TABLE_RULES` (never the literal 7, never
        // CURRENT_RULES_EPOCH): the conditional-AP family's three remaining
        // printed shapes, read off the registry BY NAME — see
        // `stamp_conditional_ap_named`. A record below epoch 7 runs none of
        // it and replays byte-exact.
        if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
            stamp_conditional_ap_named(reg, p, &mut shoot, &mut melee);
        }
        // Wave 4 (rules-wave4-renames), gated on the FROZEN
        // `EPOCH_7_TABLE_RULES`: "Takedown when Shooting" is Takedown's
        // ranged facet under a unit-level name — see `stamp_takedown_named`.
        // A record below epoch 7 keeps every profile's flag as the weapon
        // tag alone set it and replays byte-exact.
        if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
            stamp_takedown_named(reg, p, &mut shoot, &mut melee, "Takedown when Shooting");
        }
        // Boostbases wave (rules-wave4-boostbases), gated on the FROZEN
        // `EPOCH_6_TABLE_RULES`: "Mischievous Boost" is the Bane family's
        // widened save re-roll window — the entry's own `reroll_save_low` +
        // `over_in`, firing only when the model also carries the entry's
        // `upgrades` base rule, the shred2 arm 6b's own shape. Stamped on
        // the SHOOT array only: the volley consumes the window strictly past
        // the entry's own over_in distance (dice.rs `save_batch`); melee
        // never widens — no pre-charge gap (the shred2 precedent). Read BY
        // NAME, never by iterating the shared primitive (#489).
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            stamp_bane_boost(reg, p, &mut shoot, "Mischievous Boost");
        }
        // Wave 4 (rules-wave4-boostbases2), gated on the FROZEN
        // `EPOCH_7_TABLE_RULES`: "Bestial Boost" is the aof/beastmen twin of
        // the arm above — the same Bane-primitive entry shape
        // (`reroll_save_low: 5` + `over_in: 9` behind its own `upgrades`
        // coupling, "If this model has Bestial"), so it rides the same seam
        // instead of a second mechanism. An epoch-6 record reads the base
        // 6s-only window and replays byte-exact.
        if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
            stamp_bane_boost(reg, p, &mut shoot, "Bestial Boost");
        }
        // Shred wave 3 (rules-wave3-shred3): the family's per-face wound
        // amount is now READ off the carried Shred-primitive entry
        // (`extra_wound_per_save_one`) instead of hard-coded — the wave-1
        // alias arm's fixed +1 stays every pre-epoch-6 reading's value, so
        // Warbound/Infected/Destroyer flip STAMPED -> PORTED only when the
        // core actually consumes the param. Gated on `EPOCH_6_TABLE_RULES`
        // (frozen, never the literal or CURRENT_RULES_EPOCH): the alias leg
        // already shreds at epoch >= 3 and every epoch-5 record replays
        // byte-exact. Read by dice.rs::save_batch, which names the firing
        // in ShootResult.log (rules-must-log).
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            for hit in rules_of_primitive(reg, p, "Shred") {
                let amt = hit.extra_wound_per_save_one;
                if amt <= 0 {
                    continue;
                }
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    if sp.shred_alias
                        && facet_applies(hit.melee_only, hit.shooting_only, sp.range)
                        && amt > sp.shred_ones_wound_bonus
                    {
                        sp.shred_ones_wound_bonus = amt;
                        sp.shred_ones_rule = hit.name.clone();
                        sp.shred_ones_owner = p.name.clone();
                    }
                }
            }
        }
        // Versatile Attack family wave 3 (rules-wave3-versatile), gated on
        // `EPOCH_6_TABLE_RULES` (the FROZEN wave-3 constant — never the
        // literal 6, never CURRENT_RULES_EPOCH) so every record stamped 5 or
        // below (the Gen-3 recording fleet included) replays byte-exact.
        // The family's own spellings, read off the registry BY NAME — the
        // census's own-token evidence:
        //   * "Watchborn" and "Vinci Tech" are live at every epoch off the
        //     generic pass (`stamp`'s rules_of_primitive walk, ungated since
        //     the first core stage) — no delta, name only (the surge2
        //     shape);
        //   * "Vinci Tech Boost" (`pick_one: false`) is the BOTH-arms form:
        //     AP(+1) AND +1 to hit instead of the pick — but only when the
        //     model also carries Vinci Tech, the rule's own printed
        //     condition; the volley fold consumes it (dice.rs) and the EV
        //     imagination reads the same stamped flag (combat.rs).
        // The named forms log at the volley fold (rules-must-log); the
        // generic stamps keep every earlier epoch's replay byte-identical.
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            let map = reg.rules_for(&p.game_system);
            let mut seen: Vec<String> = Vec::new();
            let mut name: Option<String> = None;
            let (mut boost, mut has_vinci, mut both) = (false, false, false);
            for raw in &p.special_rules {
                let n = base_rule_name(raw);
                if n.is_empty() || seen.iter().any(|s| *s == n) {
                    continue;
                }
                seen.push(n.clone());
                if n == "Vinci Tech" {
                    has_vinci = true;
                }
                let Some(e) = map.lookup(&p.faction_folder, &n) else {
                    continue;
                };
                if e.primitive.as_deref() != Some("Versatile Attack") {
                    continue;
                }
                match n.as_str() {
                    "Watchborn" | "Vinci Tech" => name = Some(n.clone()),
                    "Vinci Tech Boost" => boost = true,
                    _ => {}
                }
            }
            if boost && has_vinci {
                name = Some("Vinci Tech Boost".to_string());
                both = true;
            }
            if let Some(vn) = name {
                for sp in shoot.iter_mut().chain(melee.iter_mut()) {
                    sp.versatile_name = vn.clone();
                    sp.versatile_both = both;
                }
            }
        }
        for u in melee_unimpl {
            if !unimplemented.contains(&u) {
                unimplemented.push(u);
            }
        }

        // Indirect family (rules-wave3-indirect), gated `EPOCH_6_TABLE_RULES`
        // (frozen at 6 — the recorder fleet stamps `rules_epoch: 5`, and its
        // records carry no wave-3 rules): the two unit-level names state
        // their facets BY NAME off the same primitive walk block 5 rides.
        // "Indirect when Shooting" stamps the plain `indirect` flag the save
        // gate, the EV imagination and the sight waiver all read; "Ignores
        // Cover when Shooting" stamps plain `ignores_cover` like block 5's
        // ungated arm (whose effect predates this gate) — each alongside its
        // `*_alias` marker, which only the volley log reads. A record below
        // `rules_epoch` 6 replays untouched.
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            for hit in rules_of_primitive(reg, p, "Indirect") {
                match hit.name.as_str() {
                    "Indirect when Shooting" => {
                        for sp in shoot.iter_mut() {
                            if sp.range > 0 {
                                sp.indirect = true;
                                sp.indirect_alias = true;
                            }
                        }
                    }
                    "Ignores Cover when Shooting" => {
                        for sp in shoot.iter_mut() {
                            if sp.range > 0 {
                                sp.ignores_cover = true;
                                sp.ignores_cover_alias = true;
                            }
                        }
                    }
                    _ => {}
                }
            }
        }

        let is_caster = has_special_rule(&p.special_rules, "Caster")
            || has_special_rule(&p.special_rules, "Caster Group");
        let spells = if is_caster {
            reg.spells_for(&p.game_system, &p.faction_folder).to_vec()
        } else {
            Vec::new()
        };
        let royal_legion = royal_legion_family_of(reg, p, rules_epoch);

        // WAVE 3 — the family's own registry names for the rules-must-log
        // line, stamped behind the same frozen `EPOCH_6_TABLE_RULES` gate.
    let fa = rule_on(rules_epoch, EPOCH_6_TABLE_RULES)
        .then(|| fortified_alias_of(reg, p))
        .unwrap_or_default();
    // Wave 4 (`rules-wave4-boostbases`) — the Hit & Run Boost band, stamped
    // behind the same FROZEN `EPOCH_6_TABLE_RULES` gate (the sim fold reads
    // the field, the rules-must-log line reads the name).
    let (hnr_move_in, hnr_rule) = hit_and_run_boost_of(reg, p, rules_epoch);
        UnitStatic {
            ctx: ctx_for(reg, p, rules_epoch),
            name: p.name.clone(),
            fortified_alias_name: fa.alias_name,
            fortified_boost_name: fa.boost_name,
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
            bounding_dice: bounding_boost_dice_of(reg, p, rules_epoch),
            move_rule_mods: move_rule_mods_of(reg, p, rules_epoch),
            royal_legion_range_in: royal_legion.0,
            royal_legion_charge_in: royal_legion.1,
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
            // Wave 4 — the Boost band (0.0 = the base 3" const) and the
            // firing name for the battle-log twin.
            hit_and_run_move_in: hnr_move_in,
            hit_and_run_rule: hnr_rule,
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
            storm: storm_of(reg, p, rules_epoch),
            growth: growth_of(reg, p, &mut unimplemented),
            piercing_tags: piercing_tags_of(reg, p, rules_epoch),
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
#[path = "tests/unit/mod.rs"]
mod tests;
