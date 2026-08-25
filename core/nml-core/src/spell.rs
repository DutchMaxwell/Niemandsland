//! The damage-spell EV that rides the shooting volley while the cast sub-phase
//! seam is OFF: `BattleSim.spell_ev_of` battle_sim.gd:766-773, `_spell_ev_from`
//! :778-795 and `_spell_damage_ev_of` :802-809, over `AiSpell.spell_facets`
//! (ai_spell.gd:130-167), `effective_ap` (:181-190) and `spell_damage_ev`
//! (:205-235).
//!
//! Scope is the GDScript's own v0 scope, quoted at battle_sim.gd:760-765:
//! DAMAGE spells only, unit-level tokens, no boost, no interference — so the
//! cast chance is always `AiSpell.cast_success_chance(0, 0)` = 0.5.

use crate::combat::{block_chance, deadly_multiplier, success_chance, REGENERATION_TARGET, SIX_P};
use crate::rules::Spell;
use crate::unit::Ctx;

/// `AiSpell.CAST_BASE_TARGET` ai_spell.gd:28.
pub const CAST_BASE_TARGET: i64 = 4;

/// `AiSpell.cast_success_chance(0, 0)` ai_spell.gd:112-113 with no tokens on
/// either side — `cast_target` then reduces to the plain base target.
#[inline]
pub fn cast_success_chance_base() -> f64 {
    success_chance(CAST_BASE_TARGET.clamp(2, 6))
}

/// `AiSpell.spell_facets` ai_spell.gd:130-167 — the knobs a spell's weapon-rule
/// token list grants. Unknown tokens are a conservative no-op.
#[derive(Debug, Clone, Copy, Default)]
pub struct Facets {
    pub ap: i64,
    pub blast: i64,
    pub deadly: i64,
    pub bane: bool,
    pub shred: bool,
    pub surge: bool,
    pub on6_ap: i64,
    pub ignores_regen: bool,
    pub ap_vs_tough3: i64,
    pub ap_vs_tough9: i64,
    pub ap_vs_def3: i64,
}

/// `AiSpell._rating` ai_spell.gd:170-175 — "AP(2)" -> 2, never negative.
fn rating(rule: &str) -> i64 {
    let (Some(open), Some(close)) = (rule.find('('), rule.find(')')) else {
        return 0;
    };
    if close <= open {
        return 0;
    }
    let inner: String = rule[open + 1..close].chars().filter(|c| *c != '+').collect();
    inner.trim().parse::<i64>().unwrap_or(0).max(0)
}

pub fn spell_facets(weapon_rules: &[String]) -> Facets {
    let mut f = Facets::default();
    for r in weapon_rules {
        let s = r.trim();
        let base = s.split('(').next().unwrap_or("").trim();
        match base {
            "AP" => f.ap = f.ap.max(rating(s)),
            "Blast" => f.blast = rating(s),
            "Deadly" => f.deadly = rating(s),
            "Bane" | "Lacerate" => {
                f.bane = true;
                f.ignores_regen = true;
            }
            "Shred" => f.shred = true,
            "Surge" => f.surge = true,
            "Crack" => f.on6_ap = f.on6_ap.max(2),
            // RENDING_AP_BONUS — ai_spell.gd:152-153.
            "Destructive" => f.on6_ap = f.on6_ap.max(4),
            "Hazardous" => f.ap = f.ap.max(4),
            "Disintegrate" => {
                f.ignores_regen = true;
                f.ap_vs_def3 = 2;
            }
            "Shatter" => f.ap_vs_tough3 = 2,
            "Tear" => f.ap_vs_tough9 = 4,
            _ => {}
        }
    }
    f
}

/// `AiSpell.effective_ap` ai_spell.gd:181-190.
fn effective_ap(f: &Facets, def: &Ctx) -> i64 {
    let mut ap = f.ap;
    let tough = def.tough.max(1);
    if f.ap_vs_tough3 > 0 && tough >= 3 {
        ap += f.ap_vs_tough3;
    }
    if f.ap_vs_tough9 > 0 && tough >= 9 {
        ap += f.ap_vs_tough9;
    }
    if f.ap_vs_def3 > 0 && def.defense <= 3 {
        ap += f.ap_vs_def3;
    }
    ap
}

/// `AiSpell.spell_damage_ev` ai_spell.gd:205-235 — a spell has no to-hit roll,
/// and its saves ignore BOTH Shielded and Cover (the raw Defense of the ctx).
pub fn spell_damage_ev(hits: i64, def: &Ctx, f: &Facets) -> f64 {
    if hits <= 0 {
        return 0.0;
    }
    let mut h = hits as f64;
    if f.surge {
        h += (hits as f64) * SIX_P;
    }
    let mut six_hits = if f.on6_ap > 0 { (hits as f64) * SIX_P } else { 0.0 };
    if f.blast > 1 {
        h *= f.blast.clamp(1, def.models.max(1)) as f64;
    }
    six_hits = six_hits.min(h);
    let defense = def.defense;
    let bane = f.bane;
    let ap = effective_ap(f, def);
    let mut unsaved = (h - six_hits) * (1.0 - block_chance(defense, ap, bane))
        + six_hits * (1.0 - block_chance(defense, ap + f.on6_ap, bane));
    if f.deadly > 0 {
        unsaved *= deadly_multiplier(f.deadly, def.tough.max(1)) as f64;
    }
    if f.shred {
        unsaved += h * SIX_P;
    }
    if def.regeneration && !(bane || f.ignores_regen) {
        // `def_ctx.get("regen_target", REGENERATION_TARGET)` — ctx_for always
        // writes the key, so the constant is a documented dead fallback here.
        let _ = REGENERATION_TARGET;
        unsaved *= 1.0 - success_chance(def.regen_target);
    }
    unsaved
}

/// `BattleSim._spell_damage_ev_of` battle_sim.gd:802-809.
pub fn spell_damage_ev_of(sp: &Spell, def: &Ctx) -> f64 {
    if sp.effect_kind != "damage" {
        return 0.0;
    }
    let hits = sp.effect_hits * sp.target_count.max(1);
    spell_damage_ev(hits, def, &spell_facets(&sp.weapon_rules))
}

/// `BattleSim._spell_ev_from` battle_sim.gd:778-795 — the best affordable
/// DAMAGE spell in range; returns (ev, cost). Ties keep the FIRST spell
/// (strict `>`), which is why the book order of the list is rule data.
pub fn spell_ev_from(spells: &[Spell], tokens: i64, def: &Ctx, d: f64) -> (f64, i64) {
    let mut best_ev = 0.0f64;
    let mut best_cost = 0i64;
    for e in spells {
        if e.status == "unmodeled" {
            continue;
        }
        if e.effect_kind != "damage" {
            continue;
        }
        if e.threshold > tokens || d > e.range_in + 0.001 {
            continue;
        }
        let ev = cast_success_chance_base() * spell_damage_ev_of(e, def);
        if ev > best_ev {
            best_ev = ev;
            best_cost = e.threshold;
        }
    }
    (best_ev, best_cost)
}

/// `BattleSim.spell_ev_of` battle_sim.gd:766-773 — zeros unless the caster has
/// tokens left AND `GameUnit.is_caster()` (game_unit.gd:374-377).
pub fn spell_ev_of(is_caster: bool, spells: &[Spell], tokens: i64, def: &Ctx, d: f64) -> (f64, i64) {
    if tokens <= 0 || !is_caster {
        return (0.0, 0);
    }
    spell_ev_from(spells, tokens, def, d)
}

/// `AiSpell.official_pick_order` ai_spell.gd:305-312 — the book list rotated by
/// the D3 face plus the caster's rating, then walked in order.
pub fn official_pick_order(list_size: usize, d3: i64, caster_x: i64) -> Vec<usize> {
    if list_size == 0 {
        return Vec::new();
    }
    let start = ((d3.clamp(1, 3) + caster_x.max(0) - 1) as usize) % list_size;
    (0..list_size).map(|i| (start + i) % list_size).collect()
}
