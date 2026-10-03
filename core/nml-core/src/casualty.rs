//! Tray-exact S4 — the table's casualty order over the per-model `kits` (S1a/S1b). Unused until
//! the live steps (S6+, behind `Seams::tray_exact`); pinned to the table by a shared fixture.

use std::collections::HashMap;

use crate::state::{Kit, State};

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
