//! NML-1073 M3-6b — DESIGN_gen0_training_2026-09-02.md §8.1/§8.2: the
//! board-seeing export. Four token sets (units/objectives/terrain/candidates)
//! plus a global row, padded to a fixed shape and masked, in the ACTING
//! SIDE'S FRAME (`x,z -> -x,-z` when `side == 2`). No column may encode
//! CAPTURE ORDER — `actor`/`target` are pointers into the unit rows, not
//! features, so a permuted roster permutes the rows and the pointers together
//! (§8.2's hard contract; the permutation tests are step 3b).
//!
//! Every distance a token carries is `/ IN2M` once, here, from the state's own
//! world metres — never re-derived downstream. Field sources are cited per
//! group; every group total is checked against §8.1 in this module's own test.

use std::collections::HashMap;

use crate::geom::{self, BaseShape};
use crate::menu::Candidate;
use crate::rows::{neutral_defender, unit_sev_mev, RowEncoder, FLAG_RULES};
use crate::rules::has_special_rule;
use crate::score::control_gap_in;
use crate::sim::{Unsupported, ADVANCE, CHARGE, HOLD, RUSH};
use crate::state::State;
use crate::terrain::{gives_cover, is_dangerous, is_difficult, Obb, Terrain, CONTAINER, DANGEROUS, FOREST, RUINS};
use crate::unit::{Ctx, UnitStatic};
use crate::{IN2M, OBJECTIVE_CONTROL_IN};

pub const N_UNITS: usize = 24;
pub const N_OBJ: usize = 6;
pub const N_TERR: usize = 18;
pub const N_CAND: usize = 80;
pub const F_U: usize = 72;
pub const F_O: usize = 12;
pub const F_T: usize = 12;
pub const F_G: usize = 16;
pub const F_C: usize = 40;
/// `RowVocab` (rows.rs:107-152) unit(200) + weapon(25) slots + one overflow
/// bucket — the divisor the unit token's rule-bag slot ids are read against.
const VOCAB_N: f32 = 226.0;
/// How many `RowEncoder::rule_pairs` (slot, rating) pairs the bag keeps —
/// F_u's "+16" bucket is `BAG_PAIRS` pairs of 2 numbers, ascending by slot
/// (the same order `rule_pairs` already builds), zero-padded past the end.
const BAG_PAIRS: usize = 8;

/// One position's export — `Core.policy_tokens` (nml-core-py/src/lib.rs).
#[derive(Debug)]
pub struct Tokens {
    pub units: Vec<[f32; F_U]>,
    pub units_mask: Vec<u8>,
    pub objs: Vec<[f32; F_O]>,
    pub objs_mask: Vec<u8>,
    pub terr: Vec<[f32; F_T]>,
    pub terr_mask: Vec<u8>,
    pub glob: [f32; F_G],
    pub cands: Vec<[f32; F_C]>,
    pub cands_mask: Vec<u8>,
    pub actor: Vec<i16>,
    pub target: Vec<i16>,
    pub label: i16,
}

#[inline]
fn mirror(side: i64, x: f64, z: f64) -> (f64, f64) {
    if side == 2 { (-x, -z) } else { (x, z) }
}

#[inline]
fn b(v: bool) -> f32 {
    v as i64 as f32
}

/// The unit token, `F_u = 72` — DESIGN §8.1 "Unit token". 70 fields, zero
/// padded to 72. Field groups, source cited once per group:
/// * geometry (7) — centroid `geom::centre` (`geom.rs:73`) over
///   `state.positions[i]` (`state.rs:384`); `base_radius` `state.rs:59`;
///   `is_oval` `state.rs:196-202`; `model_count` `state.rs:52`.
/// * live state (11) — `state.rs:371-379` (`player`..`casts`), `wound_frac`
///   `state.rs:383`, `wounds` sum `state.rs:385`.
/// * static combat (10) — `quality`/`defense`/`tough` `state.rs:43-47`;
///   `range_max`/`attacks` over `Profile.weapons` `state.rs:53`, same sums as
///   `rows.rs:374-378`; `sev`/`mev` `rows::unit_sev_mev` (no second
///   arithmetic); `caster_value` `state.rs:57`; `is_hero` `unit.rs:340`;
///   `fearless` `unit.rs:37-45` (`Ctx.fearless`).
/// * movement/charge (6) — `Bands` `state.rs:126-131` via `state.rs:410`;
///   `charge_probe_r` `state.rs:422`; `shroud` `state.rs:415`;
///   `charge_no_difficult` `state.rs:418`.
/// * live modifiers (6) — `Mods` `state.rs:311-326`.
/// * per-game ledgers (6) — `state.rs:433-449` (`vs_mark_round` ..
///   `second_wind_used`), `is_attached`/`n_attached` `state.rs:398-399`.
/// * rules (6+16) — `FLAG_RULES` `rows.rs:51-52` verbatim, plus the rule-bag
///   (see `rule_bag`).
/// * role (2) — `can_activate` `state.rs:475`; `is_the_acting_unit` is
///   `cands[0].unit` (every candidate of one position shares its actor).
#[allow(clippy::too_many_arguments)]
fn unit_token(
    state: &State,
    i: usize,
    side: i64,
    us: &UnitStatic,
    def: &Ctx,
    rows: &mut RowEncoder,
    acting_roster_idx: Option<usize>,
) -> [f32; F_U] {
    let p = state.profile(i);
    let c = geom::centre(&state.positions[i]);
    let (cx, cz) = mirror(side, c[0] as f64 / IN2M, c[2] as f64 / IN2M);
    let n = state.positions[i].len().max(1) as f64;
    let (mut sumsq, mut maxd) = (0.0f64, 0.0f32);
    for m in &state.positions[i] {
        let d = geom::length(geom::sub(geom::to_f32(*m), c));
        sumsq += (d as f64) * (d as f64);
        maxd = maxd.max(d);
    }
    let spread_rms_in = (sumsq / n).sqrt() / IN2M;
    let spread_max_in = maxd as f64 / IN2M;
    let is_oval = matches!(state.base_shape(i), BaseShape::Oval { .. });
    let wl: i64 = state.wounds[i].iter().sum();
    let (sev, mev) = unit_sev_mev(p, us, def);
    let (mut rmax, mut atk) = (0i64, 0i64);
    for w in &p.weapons {
        rmax = rmax.max(w.range as i64);
        atk += w.attacks * w.count.max(1);
    }
    let bands = &state.bands[i];
    let sh = state.shroud[i].unwrap_or([0.0, 0.0]);
    let mo = state.mods[i];

    let mut t = [0f32; F_U];
    t[0] = (cx / 30.0) as f32;
    t[1] = (cz / 30.0) as f32;
    t[2] = (spread_rms_in / 6.0) as f32;
    t[3] = (spread_max_in / 6.0) as f32;
    t[4] = (p.base_radius / 0.05) as f32;
    t[5] = b(is_oval);
    t[6] = (p.model_count as f64 / 10.0) as f32;
    t[7] = b(state.player[i] == side);
    t[8] = (state.alive[i] as f64 / 10.0) as f32;
    t[9] = (wl as f64 / 10.0) as f32;
    t[10] = state.wound_frac[i] as f32;
    t[11] = b(state.shaken[i]);
    t[12] = b(state.fatigued[i]);
    t[13] = b(state.in_cover[i]);
    t[14] = b(state.aircraft[i]);
    t[15] = b(state.dormant[i]);
    t[16] = b(state.activated[i]);
    t[17] = (state.casts[i] as f64 / 3.0) as f32;
    t[18] = (p.quality as f64 / 6.0) as f32;
    t[19] = (p.defense as f64 / 6.0) as f32;
    t[20] = (p.tough as f64 / 6.0) as f32;
    t[21] = (rmax as f64 / 30.0) as f32;
    t[22] = (atk as f64 / 20.0) as f32;
    t[23] = (sev / 5.0) as f32;
    t[24] = (mev / 5.0) as f32;
    t[25] = (p.caster_value as f64 / 3.0) as f32;
    t[26] = b(us.is_hero);
    t[27] = b(us.ctx.fearless);
    t[28] = (bands.advance / 6.0) as f32;
    t[29] = (bands.rush / 12.0) as f32;
    t[30] = (state.charge_probe_r[i] / IN2M) as f32;
    t[31] = sh[0] as f32;
    t[32] = sh[1] as f32;
    t[33] = b(state.charge_no_difficult[i]);
    t[34] = mo.hit as f32;
    t[35] = mo.def as f32;
    t[36] = mo.morale as f32;
    t[37] = (mo.range_in / 6.0) as f32;
    t[38] = (mo.advance / 6.0) as f32;
    t[39] = (mo.rush / 12.0) as f32;
    t[40] = b(state.vs_mark_round[i] >= 0);
    t[41] = b(state.hit_and_run_round[i] == state.round);
    t[42] = (state.growth_markers[i] as f64 / 5.0) as f32;
    t[43] = b(state.second_wind_used[i]);
    t[44] = b(state.attached_to[i].is_some());
    t[45] = (state.attached[i].len() as f64 / 3.0) as f32;
    for (k, r) in FLAG_RULES.iter().enumerate() {
        t[46 + k] = b(has_special_rule(&p.special_rules, r));
    }
    t[52..68].copy_from_slice(&rule_bag(rows, p, us));
    t[68] = b(state.can_activate(i, state.player[i], false));
    t[69] = b(acting_roster_idx == Some(i));
    t
}

/// The "+16" of the rules bucket: up to `BAG_PAIRS` (slot, rating) pairs off
/// `RowEncoder::rule_pairs` (rows.rs:290-321, the same `RowVocab` the row
/// encoder builds — no second vocabulary), ascending by slot, as
/// `(slot / VOCAB_N, rating / 6)`. A trained `nn.Embedding(226, 16)` reads
/// these pairs at train time (DESIGN §8.1); the export cannot bake trained
/// weights, so it hands the model the sparse indices instead of a vector.
fn rule_bag(rows: &mut RowEncoder, p: &crate::state::Profile, us: &UnitStatic) -> [f32; 16] {
    let pairs = rows.rule_pairs(p, us);
    let mut out = [0f32; 16];
    for (k, pair) in pairs.chunks(2).take(BAG_PAIRS).enumerate() {
        out[2 * k] = pair[0] as f32 / VOCAB_N;
        out[2 * k + 1] = pair[1] as f32 / 6.0;
    }
    out
}
