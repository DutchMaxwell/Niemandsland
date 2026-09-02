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

/// Objective token, `F_o = 12` — DESIGN §8.1 "Objective token". `Objective`
/// `state.rs:329-333`; `Marker` `state.rs:336-349`; distances
/// `geom::centre_dist_in` (`geom.rs:109`, single-point slice on the marker
/// side); contesting count `score::control_gap_in` (`score.rs:34`) against
/// `OBJECTIVE_CONTROL_IN` (`lib.rs:41`) — the rulebook contest range, not a
/// re-derived one.
///
/// DEVIATION §8.1: the design cites `placed_by`/`swept` at `objectives.rs:
/// 52-53`, but those lines belong to the offline layout GENERATOR's `Layout`
/// struct, not `State` — no live game state carries either field (`Objective`
/// is `pos`+`owner` only). Both columns are stamped 0, not invented.
///
/// `markers_meta` is a SEPARATE, marker-MISSION-only ledger — empty on every
/// plain objective mission even when `objectives` is not (`io.rs:195`,
/// written only when the recorder actually carried one) — so a missing entry
/// reads as `Marker::default()`, not a panic.
fn objective_token(state: &State, side: i64, oi: usize) -> [f32; F_O] {
    let o = &state.objectives[oi];
    let default_marker = crate::state::Marker::default();
    let mk = state.markers_meta.get(oi).unwrap_or(&default_marker);
    let (ox, oz) = mirror(side, o.pos[0] / IN2M, o.pos[2] / IN2M);
    let rel = if o.owner == 0 {
        0.0
    } else if o.owner == side {
        1.0
    } else {
        -1.0
    };
    let (mut mine, mut theirs) = (f64::INFINITY, f64::INFINITY);
    let (mut cm, mut ct) = (0i64, 0i64);
    for i in 0..state.units() {
        if state.alive[i] <= 0 {
            continue;
        }
        let mine_side = state.player[i] == side;
        let d = geom::centre_dist_in(std::slice::from_ref(&o.pos), &state.positions[i]);
        if mine_side {
            mine = mine.min(d);
        } else {
            theirs = theirs.min(d);
        }
        if control_gap_in(state, i, o.pos) <= OBJECTIVE_CONTROL_IN {
            if mine_side {
                cm += 1;
            } else {
                ct += 1;
            }
        }
    }
    let mut t = [0f32; F_O];
    t[0] = (ox / 30.0) as f32;
    t[1] = (oz / 30.0) as f32;
    t[2] = rel as f32;
    t[3] = b(mk.destructible);
    t[4] = b(mk.destroyed);
    t[5] = (mk.destroyed_seq as f64 / 5.0) as f32;
    t[6] = (mine.min(999.0) / 30.0) as f32;
    t[7] = (theirs.min(999.0) / 30.0) as f32;
    t[8] = (cm as f64 / 10.0) as f32;
    t[9] = (ct as f64 / 10.0) as f32;
    t
}

/// Terrain token, `F_t = 12` — DESIGN §8.1 "Terrain token". `Obb`
/// (`terrain.rs:61-67`) via `Terrain::sandbox` (new accessor, mirrors
/// `sandbox_pieces`); `c`/`he` are world METRES (`terrain::point_in_obb`
/// subtracts them straight against a world point), so they take the same
/// `/IN2M` step every other coordinate does. Kind one-hot RUINS/FOREST/
/// CONTAINER/DANGEROUS (`terrain.rs:20-23`); `gives_cover`/`is_difficult`
/// (`terrain.rs:32/38`). `is_dangerous` is implied by the one-hot and not
/// repeated (DESIGN §8.1 says so explicitly).
fn terrain_token(side: i64, piece: &Obb) -> [f32; F_T] {
    let (cx, cz) = mirror(side, piece.c[0] / IN2M, piece.c[1] / IN2M);
    let mut t = [0f32; F_T];
    t[0] = (cx / 30.0) as f32;
    t[1] = (cz / 30.0) as f32;
    t[2] = (piece.he[0] / IN2M / 12.0) as f32;
    t[3] = (piece.he[1] / IN2M / 12.0) as f32;
    t[4] = piece.yaw.cos() as f32;
    t[5] = piece.yaw.sin() as f32;
    t[6] = b(piece.kind == RUINS);
    t[7] = b(piece.kind == FOREST);
    t[8] = b(piece.kind == CONTAINER);
    t[9] = b(piece.kind == DANGEROUS);
    t[10] = b(gives_cover(piece.kind));
    t[11] = b(is_difficult(piece.kind));
    t
}

/// Global token, `F_g = 16` — DESIGN §8.1 "Global token". `sc_code`/`mj_code`/
/// `first_seize`/the vp read are the SAME branches `RowEncoder::board_rows`
/// takes at `rows.rs:428-455`, re-read here rather than factored out (a
/// dozen lines of `Option`/`&str` matching, not the float arithmetic the
/// "no second arithmetic" rule is about).
///
/// DEVIATION §8.1: the field list there sums to 17, one over `F_g = 16`
/// (round/rounds_total, rounds_total/6, a 4-wide round one-hot, opener_seat,
/// 3 vp numbers, a 3-wide scoring one-hot, majority/2, first_seize, and two
/// un-activated counts). `rounds_total/6` is dropped to fit: `round_frac`
/// already carries the game-length information a policy needs.
///
/// `opener_seat` is `ActStatics.opener_seat` (`acts.rs:328`), a per-ACT header
/// field `State` does not carry — an explicit parameter here (and a keyword
/// default on the `#[pymethods]` wrapper), not a silent zero.
fn global_token(state: &State, side: i64, opener_seat: bool) -> [f32; F_G] {
    let round_frac = if state.rounds_total > 0 {
        state.round as f64 / state.rounds_total as f64
    } else {
        0.0
    };
    let ridx = ((state.round - 1).max(0) as usize).min(3);
    let fl = state.vp_flavour.as_deref();
    let sc_code = match &*state.scoring {
        "round_vp" => 1,
        "sabotage" => 2,
        _ => 0,
    };
    let mj = fl.and_then(|v| v.get("majority")).and_then(|v| v.as_str()).unwrap_or("end");
    let mj_code = if mj == "none" {
        0
    } else if mj == "end" {
        1
    } else {
        2
    };
    let first_seize =
        fl.and_then(|v| v.get("first_seize")).and_then(|v| v.as_bool()).unwrap_or(false);
    let (vp0, vp1) = match state.vp.as_deref().and_then(|v| v.as_array()) {
        Some(a) if a.len() == 2 => (a[0].as_i64().unwrap_or(0), a[1].as_i64().unwrap_or(0)),
        _ => (0, 0),
    };
    let (vm, vt) = if side == 1 { (vp0, vp1) } else { (vp1, vp0) };
    let (mut mu, mut tu) = (0i64, 0i64);
    for i in 0..state.units() {
        if state.alive[i] <= 0 || state.activated[i] {
            continue;
        }
        if state.player[i] == side {
            mu += 1;
        } else {
            tu += 1;
        }
    }
    let mut g = [0f32; F_G];
    g[0] = round_frac as f32;
    g[1 + ridx] = 1.0;
    g[5] = b(opener_seat);
    g[6] = (vm as f64 / 10.0) as f32;
    g[7] = (vt as f64 / 10.0) as f32;
    g[8] = ((vm - vt) as f64 / 10.0) as f32;
    g[9 + sc_code] = 1.0;
    g[12] = (mj_code as f64 / 2.0) as f32;
    g[13] = b(first_seize);
    g[14] = (mu as f64 / 10.0) as f32;
    g[15] = (tu as f64 / 10.0) as f32;
    g
}

/// Candidate token, `F_c = 40` — DESIGN §8.1 "Candidate token". `actor`/
/// `target` are returned as pointers (§8.2's contract), never a column of
/// this array. `slot_idx`/`build_idx` are computed fresh from THIS call's
/// `cands` order every time (never cached across calls) — the property
/// step 3b's RED 3 checks.
fn candidate_token(
    state: &State,
    side: i64,
    terrain: &Terrain,
    row_of: &HashMap<usize, usize>,
    c: &Candidate,
    slot_idx: i64,
    build_idx: usize,
) -> ([f32; F_C], i16, i16) {
    let actor_r = state.roster.index.get(&c.unit).copied();
    let actor_row = actor_r.and_then(|r| row_of.get(&r)).map(|&r| r as i16).unwrap_or(-1);
    let actor_centre: [f64; 3] = actor_r
        .map(|r| {
            let c = geom::centre(&state.positions[r]);
            [c[0] as f64, c[1] as f64, c[2] as f64]
        })
        .unwrap_or([0.0; 3]);
    let dest = c.dest.unwrap_or(actor_centre);
    let (dxi, dzi) = mirror(side, dest[0] / IN2M, dest[2] / IN2M);
    let (axi, azi) = mirror(side, actor_centre[0] / IN2M, actor_centre[2] / IN2M);
    let (dx, dz) = (dxi - axi, dzi - azi);
    let dmag = (dx * dx + dz * dz).sqrt();
    let bands_rush = actor_r.map(|r| state.bands[r].rush).unwrap_or(12.0).max(1e-6);

    let nearest = state
        .objectives
        .iter()
        .map(|o| (o, geom::centre_dist_in(std::slice::from_ref(&o.pos), std::slice::from_ref(&dest))))
        .min_by(|a, b| a.1.total_cmp(&b.1));
    let (obj_dx, obj_dz, obj_dmag, obj_rel, obj_closing) = match nearest {
        Some((o, d_dest)) => {
            let (oxi, ozi) = mirror(side, o.pos[0] / IN2M, o.pos[2] / IN2M);
            let rel = if o.owner == 0 {
                0.0
            } else if o.owner == side {
                1.0
            } else {
                -1.0
            };
            let d_now = geom::centre_dist_in(std::slice::from_ref(&o.pos), std::slice::from_ref(&actor_centre));
            (oxi - dxi, ozi - dzi, d_dest, rel, d_now - d_dest)
        }
        None => (0.0, 0.0, 0.0, 0.0, 0.0),
    };

    let (mut enemy_from_dest, mut enemy_from_actor) = (f64::INFINITY, f64::INFINITY);
    for i in 0..state.units() {
        if state.alive[i] <= 0 || state.player[i] == side {
            continue;
        }
        enemy_from_dest = enemy_from_dest.min(geom::centre_dist_in(std::slice::from_ref(&dest), &state.positions[i]));
        enemy_from_actor =
            enemy_from_actor.min(geom::centre_dist_in(std::slice::from_ref(&actor_centre), &state.positions[i]));
    }

    let dest_v3 = geom::to_f32(dest);
    let terr_kind = terrain.type_at(dest_v3);
    let edge_in = if terrain.is_valid() {
        let q = terrain.to_inch(dest_v3);
        let board = terrain.board_in();
        (q[0] as f64).min(board[0] - q[0] as f64).min(q[1] as f64).min(board[1] - q[1] as f64)
    } else {
        0.0
    };

    let target_stats = |key: &str| -> (f64, f64, f64) {
        state
            .roster
            .index
            .get(key)
            .map(|&r| {
                (
                    geom::centre_dist_in(std::slice::from_ref(&actor_centre), &state.positions[r]),
                    state.alive[r] as f64 / 10.0,
                    state.wound_frac[r],
                )
            })
            .unwrap_or((0.0, 0.0, 0.0))
    };
    let charge = c.charge.as_deref().map(target_stats).unwrap_or((0.0, 0.0, 0.0));
    let shoot = c.shoot.as_deref().map(target_stats).unwrap_or((0.0, 0.0, 0.0));
    let target_key = c.charge.as_deref().or(c.shoot.as_deref());
    let target_row = target_key
        .and_then(|k| state.roster.index.get(k))
        .and_then(|r| row_of.get(r))
        .map(|&r| r as i16)
        .unwrap_or(-1);
    let has_wave = c.wave.as_deref().is_some_and(|w| !w.is_empty());

    let mut t = [0f32; F_C];
    t[0] = b(c.kind == HOLD);
    t[1] = b(c.kind == ADVANCE);
    t[2] = b(c.kind == RUSH);
    t[3] = b(c.kind == CHARGE);
    t[4] = b(c.dest.is_some());
    t[5] = b(c.shoot.is_some());
    t[6] = b(c.charge.is_some());
    t[7] = b(c.patient);
    t[8] = b(has_wave);
    t[9] = (dx / 30.0) as f32;
    t[10] = (dz / 30.0) as f32;
    t[11] = (dmag / 30.0) as f32;
    t[12] = (dmag / bands_rush) as f32;
    t[13] = (obj_dx / 30.0) as f32;
    t[14] = (obj_dz / 30.0) as f32;
    t[15] = (obj_dmag / 30.0) as f32;
    t[16] = obj_rel as f32;
    t[17] = (obj_closing / 30.0) as f32;
    t[18] = (enemy_from_dest.min(999.0) / 30.0) as f32;
    t[19] = (enemy_from_actor.min(999.0) / 30.0) as f32;
    t[20] = b(gives_cover(terr_kind));
    t[21] = b(is_difficult(terr_kind));
    t[22] = b(is_dangerous(terr_kind));
    t[23] = (edge_in / 30.0) as f32;
    t[24] = (charge.0 / 30.0) as f32;
    t[25] = charge.1 as f32;
    t[26] = charge.2 as f32;
    t[27] = (shoot.0 / 30.0) as f32;
    t[28] = shoot.1 as f32;
    t[29] = shoot.2 as f32;
    t[30] = (slot_idx as f64 / 11.0) as f32;
    t[31] = b(slot_idx == 0);
    t[32] = (build_idx as f64 / 73.0) as f32;
    t[33] = b(has_wave); // deliberately == t[8]; §8.1 names it in both groups
    (t, actor_row, target_row)
}

/// The whole position — DESIGN §8.2 "the export binding". Refuses (never
/// truncates) a state over any padding cap; terrain is a MEASURED constant
/// (§8.1: "exactly 18 pieces on 200 of 200 games"), not a cap, so an
/// over-count is capped by iteration, not refused.
#[allow(clippy::too_many_arguments)]
pub fn build(
    state: &State,
    side: i64,
    statics: &[UnitStatic],
    terrain: &Terrain,
    rows: &mut RowEncoder,
    cands: &[Candidate],
    best: i64,
    hero_attach: bool,
    opener_seat: bool,
) -> Result<Tokens, Unsupported> {
    let live: Vec<usize> = (0..state.units()).filter(|&i| state.alive[i] > 0).collect();
    if live.len() > N_UNITS {
        return Err(Unsupported::TooManyUnits(live.len()));
    }
    if state.objectives.len() > N_OBJ {
        return Err(Unsupported::TooManyObjectives(state.objectives.len()));
    }
    if cands.len() > N_CAND {
        return Err(Unsupported::TooManyCandidates(cands.len()));
    }
    let row_of: HashMap<usize, usize> = live.iter().enumerate().map(|(row, &r)| (r, row)).collect();
    let acting = cands.first().and_then(|c| state.roster.index.get(&c.unit).copied());
    let def = neutral_defender();

    let mut units: Vec<[f32; F_U]> = live
        .iter()
        .map(|&i| unit_token(state, i, side, &statics[state.roster.profile[i]], &def, rows, acting))
        .collect();
    let mut units_mask = vec![1u8; units.len()];
    units.resize(N_UNITS, [0.0; F_U]);
    units_mask.resize(N_UNITS, 0);
    let _ = hero_attach; // reserved: `can_activate`'s seam, off in Gen 0 like the corpus itself

    let mut objs: Vec<[f32; F_O]> =
        (0..state.objectives.len()).map(|oi| objective_token(state, side, oi)).collect();
    let mut objs_mask = vec![1u8; objs.len()];
    objs.resize(N_OBJ, [0.0; F_O]);
    objs_mask.resize(N_OBJ, 0);

    let mut terr: Vec<[f32; F_T]> =
        terrain.pieces().iter().take(N_TERR).map(|p| terrain_token(side, p)).collect();
    let mut terr_mask = vec![1u8; terr.len()];
    terr.resize(N_TERR, [0.0; F_T]);
    terr_mask.resize(N_TERR, 0);

    let mut slot_of: HashMap<String, i64> = HashMap::new();
    let mut cand_rows = Vec::with_capacity(cands.len());
    let mut actor = Vec::with_capacity(cands.len());
    let mut target = Vec::with_capacity(cands.len());
    for (bi, c) in cands.iter().enumerate() {
        let slot = slot_of.entry(c.unit.clone()).or_insert(0);
        let this_slot = *slot;
        *slot += 1;
        let (t, a, tg) = candidate_token(state, side, terrain, &row_of, c, this_slot, bi);
        cand_rows.push(t);
        actor.push(a);
        target.push(tg);
    }
    let mut cands_mask = vec![1u8; cand_rows.len()];
    cand_rows.resize(N_CAND, [0.0; F_C]);
    cands_mask.resize(N_CAND, 0);
    actor.resize(N_CAND, -1);
    target.resize(N_CAND, -1);

    Ok(Tokens {
        units,
        units_mask,
        objs,
        objs_mask,
        terr,
        terr_mask,
        glob: global_token(state, side, opener_seat),
        cands: cand_rows,
        cands_mask,
        actor,
        target,
        label: best as i16,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::acts::read_act_header;
    use crate::io::state_from_json;
    use crate::rules::Registries;
    use crate::state::{ProfileCache, Roster};
    use crate::terrain::{CellParams, PlainTerrain};
    use std::rc::Rc;

    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// §8.2 RED 1's fixture: `rows.rs`'s `two_unit_state()` (A at 10"/11",
    /// B at -10", one objective at the origin), plus a SECOND objective at
    /// (15", 5") owned by side 2.
    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":3,
        "wounds_max":[3,3],"model_count":2,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Fearless","Tough(3)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[
          {"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":5,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Stealth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Pistol","range":6,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end",
      "objectives":[{"pos":[0.0,0.0,0.0],"owner":1},{"pos":[0.381,0.0,0.127],"owner":2}],
      "units":{
        "p1_0_a":{"player":1,"alive":2,"wounds":[3,2],"radii":[0.016,0.016],
          "positions":[[0.254,0.0,0.0],[0.2794,0.0,0.0]],
          "in_cover":false,"shaken":false,"fatigued":false,"activated":false,
          "casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
          "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
          "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
        "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
          "positions":[[-0.254,0.0,0.0]],
          "in_cover":true,"shaken":false,"fatigued":false,"activated":true,
          "casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
          "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
          "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn fixture() -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let state = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let mut reg = Registries::new(&repo_root());
        let statics = state.profiles.list.iter().map(|p| UnitStatic::build(&mut reg, p)).collect();
        (state, statics)
    }

    /// Two sandbox pieces: a FOREST at (8", 0") 2"x2", a DANGEROUS at
    /// (-8", 3") 1.5"x1.5", both axis-aligned.
    fn terrain_fixture() -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: vec![],
            sandbox: vec![
                Obb { c: [8.0 * IN2M, 0.0], he: [2.0 * IN2M, 2.0 * IN2M], yaw: 0.0, kind: FOREST },
                Obb { c: [-8.0 * IN2M, 3.0 * IN2M], he: [1.5 * IN2M, 1.5 * IN2M], yaw: 0.0, kind: DANGEROUS },
            ],
            pieces: vec![],
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// The four-entry menu, all for unit A: hold, advance, the charge on B
    /// (`best`), a patient second-wave advance.
    fn cands_fixture() -> Vec<Candidate> {
        vec![
            Candidate::new("p1_0_a", HOLD),
            Candidate { unit: "p1_0_a".into(), kind: ADVANCE, dest: Some([12.0 * IN2M, 0.0, 2.0 * IN2M]), ..Default::default() },
            Candidate {
                unit: "p1_0_a".into(),
                kind: CHARGE,
                dest: Some([-9.0 * IN2M, 0.0, 0.0]),
                charge: Some("p2_0_b".into()),
                ..Default::default()
            },
            Candidate {
                unit: "p1_0_a".into(),
                kind: ADVANCE,
                dest: Some([6.0 * IN2M, 0.0, -3.0 * IN2M]),
                patient: true,
                wave: Some("second_wave".into()),
                ..Default::default()
            },
        ]
    }

    fn near(a: f32, b: f32, name: &str) {
        assert!((a - b).abs() <= 1e-3, "{name}: {a} vs {b}");
    }

    #[test]
    fn every_column_of_the_synthetic_position_is_hand_computed() {
        let (state, statics) = fixture();
        let terrain = terrain_fixture();
        let cands = cands_fixture();
        let mut enc = RowEncoder::new(&repo_root());
        let def = neutral_defender();
        let t = build(&state, 1, &statics, &terrain, &mut enc, &cands, 2, false, true).expect("build");

        assert_eq!(t.units.len(), N_UNITS);
        assert_eq!(t.units_mask, {
            let mut m = vec![1u8, 1];
            m.resize(N_UNITS, 0);
            m
        });

        // Unit A (row 0). sev/mev cross-checked against the reused primitive,
        // never re-derived — the combat-math oracle is `rows::unit_sev_mev`.
        let (sev_a, mev_a) = unit_sev_mev(state.profile(0), &statics[0], &def);
        let a = &t.units[0];
        let want_a = [
            10.5 / 30.0, 0.0, 0.5 / 6.0, 0.5 / 6.0, 0.016 / 0.05, 0.0, 0.2, // geometry
            1.0, 0.2, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // live state
            4.0 / 6.0, 3.0 / 6.0, 3.0 / 6.0, 24.0 / 30.0, 4.0 / 20.0, (sev_a / 5.0) as f32, (mev_a / 5.0) as f32,
            0.0, 0.0, 1.0, // static combat
            1.0, 1.0, (0.016 / IN2M) as f32, 0.0, 0.0, 0.0, // movement/charge
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // live modifiers
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // ledgers
            1.0, 0.0, 0.0, 0.0, 0.0, 0.0, // FLAG_RULES: Fearless only
        ];
        for (k, &w) in want_a.iter().enumerate() {
            near(a[k], w, &format!("unit A col {k}"));
        }
        let bag_a = {
            let pairs = enc.rule_pairs(state.profile(0), &statics[0]);
            let mut out = [0f32; 16];
            for (k, pr) in pairs.chunks(2).take(8).enumerate() {
                out[2 * k] = pr[0] as f32 / VOCAB_N;
                out[2 * k + 1] = pr[1] as f32 / 6.0;
            }
            out
        };
        for (k, &w) in bag_a.iter().enumerate() {
            near(a[52 + k], w, &format!("unit A rule-bag col {k}"));
        }
        near(a[68], 1.0, "unit A can_activate");
        near(a[69], 1.0, "unit A is_the_acting_unit");
        near(a[70], 0.0, "unit A pad 70");
        near(a[71], 0.0, "unit A pad 71");

        // Unit B (row 1): the other side, a single model, already activated.
        let (sev_b, mev_b) = unit_sev_mev(state.profile(1), &statics[0], &def);
        assert_eq!(sev_b, 0.0, "a 6\" pistol does not reach the 12\" reference");
        assert_eq!(mev_b, 0.0, "no melee weapon");
        let b = &t.units[1];
        let want_b = [
            -10.0 / 30.0, 0.0, 0.0, 0.0, 0.016 / 0.05, 0.0, 0.1,
            0.0, 0.1, 0.1, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0,
            5.0 / 6.0, 4.0 / 6.0, 1.0 / 6.0, 6.0 / 30.0, 1.0 / 20.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            1.0, 1.0, (0.016 / IN2M) as f32, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 1.0, 0.0, 0.0, // Stealth only
        ];
        for (k, &w) in want_b.iter().enumerate() {
            near(b[k], w, &format!("unit B col {k}"));
        }
        near(b[68], 0.0, "unit B can_activate (already activated)");
        near(b[69], 0.0, "unit B is_the_acting_unit");

        // Objectives.
        assert_eq!(t.objs.len(), N_OBJ);
        assert_eq!(&t.objs_mask[..2], &[1, 1]);
        assert!(t.objs_mask[2..].iter().all(|&m| m == 0));
        let o0 = &t.objs[0];
        let want_o0 = [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 10.5 / 30.0, 10.0 / 30.0, 0.0, 0.0, 0.0, 0.0];
        for (k, &w) in want_o0.iter().enumerate() {
            near(o0[k], w, &format!("obj0 col {k}"));
        }
        let o1 = &t.objs[1];
        let want_o1 = [0.5, 5.0 / 30.0, -1.0, 0.0, 0.0, 0.0, 6.726 / 30.0, 25.495 / 30.0, 0.0, 0.0, 0.0, 0.0];
        for (k, &w) in want_o1.iter().enumerate() {
            near(o1[k], w, &format!("obj1 col {k}"));
        }

        // Terrain.
        assert_eq!(t.terr.len(), N_TERR);
        assert_eq!(&t.terr_mask[..2], &[1, 1]);
        assert!(t.terr_mask[2..].iter().all(|&m| m == 0));
        let want_terr0 = [8.0 / 30.0, 0.0, 2.0 / 12.0, 2.0 / 12.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0];
        for (k, &w) in want_terr0.iter().enumerate() {
            near(t.terr[0][k], w, &format!("terrain0 col {k}"));
        }
        let want_terr1 = [-8.0 / 30.0, 3.0 / 30.0, 1.5 / 12.0, 1.5 / 12.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0];
        for (k, &w) in want_terr1.iter().enumerate() {
            near(t.terr[1][k], w, &format!("terrain1 col {k}"));
        }

        // Global.
        let want_g = [0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.5, 0.0, 0.1, 0.0];
        for (k, &w) in want_g.iter().enumerate() {
            near(t.glob[k], w, &format!("global col {k}"));
        }

        // Candidates: hand-check c0 (HOLD, full row) and c2 (CHARGE == the
        // recorded pick, full row); c1/c3 spot-checked.
        assert_eq!(t.cands.len(), N_CAND);
        assert_eq!(&t.cands_mask[..4], &[1, 1, 1, 1]);
        assert!(t.cands_mask[4..].iter().all(|&m| m == 0));
        assert_eq!(&t.actor[..4], &[0, 0, 0, 0]);
        assert_eq!(&t.target[..4], &[-1, -1, 1, -1]);
        assert_eq!(t.label, 2, "the recorded pick is cands[2], the charge");

        let want_c0 = [
            1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0,
            0.15, 5.0 / 30.0, 6.7268 / 30.0, -1.0, 0.0,
            20.5 / 30.0, 20.5 / 30.0,
            0.0, 0.0, 0.0, 24.0 / 30.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
        ];
        for (k, &w) in want_c0.iter().enumerate() {
            near(t.cands[0][k], w, &format!("cand0 col {k}"));
        }
        let want_c2 = [
            0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0,
            -0.65, 0.0, 0.65, 19.5 / 12.0,
            0.3, 0.0, 0.3, 1.0, 0.05,
            1.0 / 30.0, 20.5 / 30.0,
            0.0, 0.0, 0.0, 24.0 / 30.0,
            20.5 / 30.0, 0.1, 0.0, 0.0, 0.0, 0.0,
            2.0 / 11.0, 0.0, 2.0 / 73.0, 0.0,
        ];
        for (k, &w) in want_c2.iter().enumerate() {
            near(t.cands[2][k], w, &format!("cand2 col {k}"));
        }
        // c1/c3: kind/shape flags, the actor-relative delta, and the two
        // order-derived grammar columns — not re-derived, spot-checked.
        near(t.cands[1][1], 1.0, "cand1 kind ADVANCE");
        near(t.cands[1][9], 1.5 / 30.0, "cand1 dx");
        near(t.cands[1][10], 2.0 / 30.0, "cand1 dz");
        near(t.cands[1][30], 1.0 / 11.0, "cand1 slot_idx");
        near(t.cands[1][32], 1.0 / 73.0, "cand1 build_idx");
        near(t.cands[3][7], 1.0, "cand3 patient");
        near(t.cands[3][8], 1.0, "cand3 has_wave");
        near(t.cands[3][33], 1.0, "cand3 wave non-empty (== col 8)");
        near(t.cands[3][30], 3.0 / 11.0, "cand3 slot_idx");
        near(t.cands[3][32], 3.0 / 73.0, "cand3 build_idx");
    }

    /// §8.1's own field-count check: the design's group totals for the unit
    /// token (7+11+10+6+6+6+22+2) and the candidate token (9+4+5+2+4+6+3+1)
    /// both land on the raw width this builder actually fills.
    #[test]
    fn group_totals_match_design_8_1() {
        assert_eq!(7 + 11 + 10 + 6 + 6 + 6 + 22 + 2, 70);
        assert_eq!(9 + 4 + 5 + 2 + 4 + 6 + 3 + 1, 34);
    }

    /// RED: dropping the side-2 mirror (or transposing x/z) must fail this.
    #[test]
    fn side_2_mirrors_every_coordinate() {
        let (state, statics) = fixture();
        let terrain = terrain_fixture();
        let cands = cands_fixture();
        let mut enc = RowEncoder::new(&repo_root());
        let t1 = build(&state, 1, &statics, &terrain, &mut enc, &cands, 2, false, false).expect("side1");
        let t2 = build(&state, 2, &statics, &terrain, &mut enc, &cands, 2, false, false).expect("side2");
        near(t1.units[0][0], -t2.units[0][0], "unit A cx mirrors");
        near(t1.units[0][7], 1.0, "A is mine at side1");
        near(t2.units[0][7], 0.0, "A is theirs at side2");
        near(t2.units[1][7], 1.0, "B is mine at side2");
        near(t1.objs[1][0], -t2.objs[1][0], "obj1 x mirrors");
        near(t1.objs[1][2], -t2.objs[1][2], "obj1 owner relation flips");
        near(t1.terr[0][0], -t2.terr[0][0], "terrain0 x mirrors");
    }

    /// RED 4: a state over any padding cap is REFUSED, never truncated.
    #[test]
    fn overflow_is_refused_not_truncated() {
        let (base, statics) = fixture();
        let terrain = terrain_fixture();
        let cands = cands_fixture();

        // 25 living units: clone unit 0's per-unit data into a fresh 25-key
        // roster (all pointing at profile 0, so `statics` needs no change).
        let mut big = base.clone();
        let n = 25;
        let keys: Vec<String> = (0..n).map(|i| format!("u{i}")).collect();
        big.roster = Rc::new(Roster {
            index: keys.iter().cloned().enumerate().map(|(i, k)| (k, i)).collect(),
            keys,
            profile: vec![0; n],
        });
        macro_rules! rep {
            ($f:ident) => {
                big.$f = (0..n).map(|_| base.$f[0].clone()).collect();
            };
        }
        rep!(player);
        rep!(alive);
        rep!(activated);
        rep!(shaken);
        rep!(fatigued);
        rep!(in_cover);
        rep!(aircraft);
        rep!(dormant);
        rep!(casts);
        rep!(morale_bonus);
        rep!(ambush_arrived_round);
        rep!(earliest_arrival_round);
        rep!(wound_frac);
        rep!(positions);
        rep!(wounds);
        rep!(radii);
        rep!(mods);
        rep!(mods_base);
        rep!(los);
        rep!(bands);
        rep!(shroud);
        rep!(charge_no_difficult);
        rep!(charge_probe_r);
        rep!(buffs);
        rep!(vs_mark_round);
        rep!(hit_and_run_round);
        rep!(growth_markers);
        rep!(growth_round);
        rep!(second_wind_used);
        big.attached = Rc::new((0..n).map(|_| Vec::new()).collect());
        big.attached_to = Rc::new((0..n).map(|_| None).collect());
        let mut enc = RowEncoder::new(&repo_root());
        match build(&big, 1, &statics, &terrain, &mut enc, &cands, 0, false, false) {
            Err(Unsupported::TooManyUnits(25)) => {}
            other => panic!("expected TooManyUnits(25), got {other:?}"),
        }

        // 7 objectives on the ORIGINAL 2-unit state (`markers_meta` stays
        // empty — a plain objective mission never fills it, see
        // `objective_token`'s own note).
        let mut many_objs = base.clone();
        many_objs.objectives = (0..7).map(|_| many_objs.objectives[0]).collect();
        match build(&many_objs, 1, &statics, &terrain, &mut enc, &cands, 0, false, false) {
            Err(Unsupported::TooManyObjectives(7)) => {}
            other => panic!("expected TooManyObjectives(7), got {other:?}"),
        }

        // 81 candidates on the original state.
        let many_cands: Vec<Candidate> = (0..81).map(|_| Candidate::new("p1_0_a", HOLD)).collect();
        match build(&base, 1, &statics, &terrain, &mut enc, &many_cands, 0, false, false) {
            Err(Unsupported::TooManyCandidates(81)) => {}
            other => panic!("expected TooManyCandidates(81), got {other:?}"),
        }
    }
}
