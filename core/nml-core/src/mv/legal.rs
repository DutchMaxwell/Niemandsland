//! The legality checker (docs/one_core/PARITY_RULING.md item 4): may the named units' models REST where they stand?
//! One checker for both sides - the door asks it of the core's end state before it lands, the shadow and the sweep ask it
//! of the table's. It only READS the state (no dice, no recorded act), so it needs no rules epoch.

use super::gate::{self, Disc};
use crate::{geom, state::State, terrain::Terrain, IN2M};

/// One broken rule. `kind`: `overlap` (`other` = the base it sits in), `forbidden_rest` (impassable / wall band /
/// solid cell), `off_board`, `coherency` (the first model outside the largest 1" chain, or model 0 when overspread),
/// `enemy_within_1in` (`other` = the nearest enemy base), `distance` (moved beyond the allowance). `by_in` = how far.
#[derive(Clone, Debug, PartialEq)]
pub struct Illegal { pub unit: usize, pub model: usize, pub kind: &'static str, pub other: Option<(usize, usize)>, pub by_in: f64 }

/// `SoloController.OVERLAP_EPS_M`: sub-0.5 mm is noise. Base contact: `SeparationChecker.BASE_CONTACT_EPSILON_INCHES`.
const OVERLAP_EPS_IN: f64 = 0.0005 / IN2M;
const CONTACT_IN: f64 = 0.05;
const ENEMY_EPS_IN: f64 = 0.01;
/// `SoloController.WALL_REST_CLEARANCE_M` + `OVERLAP_EPS_M`: a base inside this of a wall or a block only touches it.
const TOUCH_IN: f64 = 0.0025 / IN2M;
/// A model this far above the table stands on something it climbed.
const RAISED_M: f64 = 0.005;

fn on_table(st: &State, u: usize) -> bool { st.alive[u] > 0 && !st.positions[u].is_empty() }

fn gap_in(st: &State, u: usize, k: usize, v: usize, j: usize) -> f64 {
    let (p, q) = (st.positions[u][k], st.positions[v][j]);
    geom::pair_gap_m([p[0] as f32, p[1] as f32, p[2] as f32], st.radii[u][k], st.base_shape(u),
        [q[0] as f32, q[1] as f32, q[2] as f32], st.radii[v][j], st.base_shape(v)) / IN2M
}

/// Every rule the models of `units` break where they stand. A pair of named units is read once; a unit in base contact
/// with an enemy (melee) skips the 1" enemy test; coherency reads the host with its joined heroes, at the planner's chain.
pub fn rest_illegal(st: &State, t: &Terrain, units: &[usize]) -> Vec<Illegal> {
    let (mut out, mut hosts) = (Vec::new(), Vec::new());
    let named = |v: usize| units.iter().position(|&w| w == v);
    for (ui, &u) in units.iter().enumerate().filter(|&(_, &u)| on_table(st, u)) {
        let mut engaged = false;
        let mut near: Vec<Option<(f64, usize, usize)>> = vec![None; st.positions[u].len()];
        for (k, p) in st.positions[u].iter().enumerate() {
            let r = st.radii[u][k];
            for v in (0..st.units()).filter(|&v| on_table(st, v)) {
                for j in 0..st.positions[v].len() {
                    let g = gap_in(st, u, k, v, j);
                    let read_here = if v == u { j > k } else { named(v).is_none_or(|vi| vi > ui) };
                    if read_here && (v, j) != (u, k) && g < -OVERLAP_EPS_IN {
                        out.push(Illegal { unit: u, model: k, kind: "overlap", other: Some((v, j)), by_in: -g });
                    }
                    if st.player[v] != st.player[u] {
                        engaged |= g <= CONTACT_IN;
                        if near[k].is_none_or(|n| g < n.0) { near[k] = Some((g, v, j)); }
                    }
                }
            }
            if t.is_valid() {
                // `gate::overlaps_block`'s reading (a base that only touches is left), but its roof exemption holds only for
                // a model that stands raised (it climbed); a ground model with its centre over a container is inside it.
                let (c, w) = (t.to_inch([p[0] as f32, 0.0, p[2] as f32]), [p[0] as f32, 0.0, p[2] as f32]);
                let roof = p[1] > RAISED_M && t.type_at(w) == crate::terrain::CONTAINER;
                if t.solid_at(p[0] / t.in2m(), p[2] / t.in2m())
                    || !roof && gate::rest_forbidden([f64::from(c[0]), f64::from(c[1])], r / IN2M - TOUCH_IN, t) {
                    out.push(Illegal { unit: u, model: k, kind: "forbidden_rest", other: None, by_in: 0.0 });
                }
                let over = (p[0].abs() + r - t.board_in()[0] * t.in2m() * 0.5).max(p[2].abs() + r - t.board_in()[1] * t.in2m() * 0.5);
                if over > 1e-6 { out.push(Illegal { unit: u, model: k, kind: "off_board", other: None, by_in: over / IN2M }); }
            }
        }
        for (k, n) in near.iter().enumerate().filter(|_| !engaged) {
            if let Some((g, v, j)) = *n { if g < 1.0 - ENEMY_EPS_IN {
                out.push(Illegal { unit: u, model: k, kind: "enemy_within_1in", other: Some((v, j)), by_in: 1.0 - g });
            } }
        }
        let host = st.attached_to.get(u).copied().flatten().unwrap_or(u);
        if hosts.contains(&host) { continue; }
        hosts.push(host);
        let members: Vec<(usize, usize)> = std::iter::once(host).chain(st.attached.get(host).into_iter().flatten().copied())
            .filter(|&w| on_table(st, w)).flat_map(|w| (0..st.positions[w].len()).map(move |k| (w, k))).collect();
        let cfg: Vec<Disc> = members.iter().map(|&(w, k)| Disc { c: [st.positions[w][k][0] / IN2M, st.positions[w][k][2] / IN2M],
            r: st.radii[w][k] / IN2M, shape: st.base_shape(w) }).collect();
        if !gate::config_coherent(&cfg, super::MAX_CHAIN_IN) {
            let big = gate::largest_component(&cfg);
            let stray = (0..cfg.len()).find(|i| !big.contains(i)).map_or((host, 0), |i| members[i]);
            out.push(Illegal { unit: stray.0, model: stray.1, kind: "coherency", other: None, by_in: 0.0 });
        }
    }
    out
}

/// `distance`: every model of `u` that ended more than `allowance_in` from its spot in `from` (a move "up to X").
pub fn beyond_allowance(st: &State, u: usize, from: &[[f64; 3]], allowance_in: f64) -> Vec<Illegal> {
    st.positions[u].iter().zip(from).enumerate().filter_map(|(k, (p, a))| {
        let d = (p[0] - a[0]).hypot(p[2] - a[2]) / IN2M - allowance_in;
        (d > ENEMY_EPS_IN).then_some(Illegal { unit: u, model: k, kind: "distance", other: None, by_in: d })
    }).collect()
}

/// The door-only `illegal` field of a `done` step: `rest_illegal` over every unit whose surviving models `after` moved
/// against `before` (a casualty alone moves nobody; a returned model counts as moved).
pub fn landing_illegal(before: &State, after: &State, t: &Terrain) -> Vec<Illegal> {
    let moved: Vec<usize> = (0..after.units()).filter(|&u| {
        let mut was = before.positions[u].iter();
        !after.positions[u].iter().all(|p| was.any(|q| q == p))
    }).collect();
    rest_illegal(after, t, &moved)
}

/// The bindings' shape of one list: `[{unit, model, kind, other, other_model, by_in}]`, units by roster key
/// (`other` "" and `other_model` -1 when no other base is involved).
pub fn illegal_json(st: &State, found: &[Illegal]) -> serde_json::Value {
    serde_json::Value::Array(found.iter().map(|i| serde_json::json!({"unit": st.key(i.unit), "model": i.model, "kind": i.kind,
        "other": i.other.map_or("", |o| st.key(o.0)), "other_model": i.other.map_or(-1, |o| o.1 as i64), "by_in": i.by_in})).collect())
}
