//! Tray-exact S4 — the table's casualty order over the per-model `kits` (S1a/S1b). Unused until
//! the live steps (S6+, behind `Seams::tray_exact`); pinned to the table by a shared fixture.

use std::collections::HashMap;

use crate::geom::BaseShape;
use crate::state::{Kit, State};
use crate::sim::DEFAULT_BASE_RADIUS_M;
use crate::IN2M;

/// `SoloController.casualty_order` (solo_controller.gd:9151-9204): a unit's living slots in
/// removal order, cheapest first. Per slot the value is 2 per weapon entry and 2 per equipment
/// item, +3 once for a RARE weapon (one carried by at most max(n/2, 1) of the living models'
/// entries: rarity marks the bearer) and +8 for a Tough above the unit's lowest; the rank is
/// value x 1000 - distance to the living models' centroid - wounds already taken x 1e6, so a
/// wounded Tough body always goes first. Ascending; Rust's sort is stable where Godot's
/// `sort_custom` is not, and the shared fixture (tests/fixtures/casualty_order.json) carries no
/// exact ties.
pub fn casualty_order_of(kits: &[Kit], positions: &[[f64; 3]], wounds: &[i64]) -> Vec<usize> {
    let n = kits.len();
    if n <= 1 {
        return (0..n).collect();
    }
    let base = kits.iter().map(|k| k.wounds_max.max(1)).min().unwrap_or(1);
    let (sx, sz) = positions.iter().fold((0.0, 0.0), |(x, z), p| (x + p[0], z + p[2]));
    let (cx, cz) = (sx / n as f64, sz / n as f64);
    let mut freq: HashMap<u16, usize> = HashMap::new();
    for w in kits.iter().flat_map(|k| k.weapons.iter()) {
        *freq.entry(*w).or_insert(0) += 1;
    }
    let cap = (n / 2).max(1);
    let rank = |i: usize| -> f64 {
        let k = &kits[i];
        let mut v = (2 * k.weapons.len() + 2 * k.equipment as usize) as f64;
        if k.weapons.iter().any(|w| freq[w] <= cap) {
            v += 3.0;
        }
        if k.wounds_max > base {
            v += 8.0;
        }
        let taken = (k.wounds_max - wounds.get(i).copied().unwrap_or(k.wounds_max)).max(0) as f64;
        let d = (positions[i][0] - cx).hypot(positions[i][2] - cz);
        v * 1000.0 - d - taken * 1_000_000.0
    };
    let mut order: Vec<usize> = (0..n).collect();
    order.sort_by(|&a, &b| rank(a).total_cmp(&rank(b)));
    order
}

/// Unit `u`'s removal order when it carries kits aligned with its slots; `None` = it carries
/// none, and the caller keeps the core's slot order.
pub fn casualty_order(state: &State, u: usize) -> Option<Vec<usize>> {
    let kits = state.kits.get(u).filter(|k| !k.is_empty() && k.len() == state.positions[u].len())?;
    Some(casualty_order_of(kits, &state.positions[u], &state.wounds[u]))
}

/// `CoherencyChecker._get_edge_distance_in_direction`: a base's edge in metres along (dx, dz),
/// the AXIS-ALIGNED ellipse of the checker (no yaw), from the recorded circumscribing radius.
fn edge_m(shape: BaseShape, r: f64, dx: f64, dz: f64) -> f64 {
    let (a, b) = shape.semis(r);
    if matches!(shape, BaseShape::Round) {
        return r;
    }
    let den = (b * b * dx * dx + a * a * dz * dz).sqrt();
    if den < 0.0001 { (a + b) / 2.0 } else { a * b / den }
}

/// `CoherencyChecker._distance_between_models`: edge-to-edge inches, never below 0; the
/// centre distance in f32 like the checker's Vector2.
fn gap_in(pa: [f64; 3], sa: BaseShape, ra: f64, pb: [f64; 3], sb: BaseShape, rb: f64) -> f64 {
    let (dx, dz) = ((pb[0] - pa[0]) as f32, (pb[2] - pa[2]) as f32);
    let d = dx.hypot(dz) as f64;
    if d < 0.001 {
        return 0.0;
    }
    let (ux, uz) = (dx as f64 / d, dz as f64 / d);
    (d - edge_m(sa, ra, ux, uz) - edge_m(sb, rb, -ux, -uz)).max(0.0) / IN2M
}

/// Tray-exact S5 — `SoloController.chain_casualty_order` (solo_controller.gd:9222-9258): the
/// value order with the survivors' chain kept. One removal at a time over the host's group (its
/// models, then each attached hero's — `get_alive_models_with_attached`): a wounded Tough lead is
/// always taken; otherwise the first slot whose removal leaves the group coherent
/// (`CoherencyChecker.LinkTable` with MEASURING_SLACK 0.01": one 1" chain, 3" across a height step
/// over 1", every pair within 9" or 6" Skirmish), else the value order's lead. `max_picks`: how
/// many leading picks the caller uses; the tail keeps the value order. `None` = no kits.
pub fn chain_casualty_order(state: &State, u: usize, max_picks: Option<usize>) -> Option<Vec<usize>> {
    let order = casualty_order(state, u)?;
    if order.len() <= 2 {
        return Some(order);
    }
    let host = state.attached_to[u].unwrap_or(u);
    let mut group: Vec<(usize, usize)> = (0..state.positions[host].len()).map(|m| (host, m)).collect();
    for &h in state.attached[host].iter() {
        group.extend((0..state.positions[h].len()).map(|m| (h, m)));
    }
    let n = group.len();
    let max_chain = if matches!(state.profile(host).game_system.as_str(), "gff" | "aofs") { 6.0 } else { 9.0 };
    let (slack, mut gap, mut linked) = (0.01, vec![0.0; n * n], vec![false; n * n]);
    for i in 0..n {
        for j in i + 1..n {
            let ((ui, mi), (uj, mj)) = (group[i], group[j]);
            let (pa, pb) = (state.positions[ui][mi], state.positions[uj][mj]);
            let r = |uu: usize, mm: usize| state.radii[uu].get(mm).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            let d = gap_in(pa, state.base_shape(ui), r(ui, mi), pb, state.base_shape(uj), r(uj, mj));
            let limit = if (pa[1] - pb[1]).abs() > IN2M { 3.0 } else { 1.0 };
            (gap[i * n + j], gap[j * n + i]) = (d, d);
            (linked[i * n + j], linked[j * n + i]) = (d <= limit + slack, d <= limit + slack);
        }
    }
    let coherent_without = |gone: &[bool]| -> bool {
        let alive: Vec<usize> = (0..n).filter(|&i| !gone[i]).collect();
        if alive.len() <= 1 {
            return true;
        }
        let (mut seen, mut queue) = (vec![false; n], vec![alive[0]]);
        seen[alive[0]] = true;
        while let Some(cur) = queue.pop() {
            for &o in &alive {
                if !seen[o] && linked[cur * n + o] {
                    seen[o] = true;
                    queue.push(o);
                }
            }
        }
        alive.iter().all(|&i| seen[i])
            && alive.iter().all(|&a| alive.iter().all(|&b| gap[a * n + b] <= max_chain + slack))
    };
    let slot = |m: usize| group.iter().position(|&g| g == (u, m)).unwrap_or(0);
    let kits = &state.kits[u];
    let picks = max_picks.map_or(order.len(), |k| k.min(order.len()));
    let (mut gone, mut out, mut todo) = (vec![false; n], Vec::new(), order);
    while out.len() < picks && !todo.is_empty() {
        let lead = todo[0];
        let mut at = 0;
        if !(kits[lead].wounds_max > 1 && state.wounds[u][lead] < kits[lead].wounds_max) {
            for (k, &m) in todo.iter().enumerate() {
                gone[slot(m)] = true;
                let keeps = coherent_without(&gone);
                gone[slot(m)] = false;
                if keeps {
                    at = k;
                    break;
                }
            }
        }
        let pick = todo.remove(at);
        gone[slot(pick)] = true;
        out.push(pick);
    }
    out.extend(todo);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The core half of the parity pin: test/casualty_order_parity_test.gd holds the table's
    /// `SoloController.casualty_order` to the same file.
    #[test]
    fn the_cores_casualty_order_matches_the_tables_on_the_shared_fixture() {
        let fx: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/casualty_order.json")).unwrap();
        for u in fx["units"].as_array().unwrap() {
            let mut names: Vec<String> = Vec::new();
            let (mut kits, mut pos, mut wounds) = (Vec::new(), Vec::new(), Vec::new());
            for m in u["models"].as_array().unwrap() {
                let mut weapons = Vec::new();
                for w in m["weapons"].as_array().unwrap() {
                    let w = w.as_str().unwrap().to_string();
                    let i = names.iter().position(|n| *n == w).unwrap_or(names.len());
                    if i == names.len() {
                        names.push(w);
                    }
                    weapons.push(i as u16);
                }
                let (e, x) = (m["equipment"].as_u64().unwrap() as u16, m["wounds_max"].as_i64().unwrap());
                kits.push(Kit { weapons, equipment: e, wounds_max: x });
                let p = m["pos"].as_array().unwrap();
                pos.push([p[0].as_f64().unwrap(), p[1].as_f64().unwrap(), p[2].as_f64().unwrap()]);
                wounds.push(m["wounds"].as_i64().unwrap());
            }
            let want: Vec<usize> =
                u["expected"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
            assert_eq!(casualty_order_of(&kits, &pos, &wounds), want, "{}", u["name"]);
        }
    }
}
