//! LAZARUS M1 step 8b — the 1-inch grid's proposal order: ring shells around the hand cells, then a
//! seeded uniform tail. UNUSED by the planner until the `grid_k` knob (step 9) consumes `propose_order`;
//! adding it changes no existing behaviour. The cell ids are the ones `crate::grid` assigns.

use crate::geom;
use crate::state::State;

/// splitmix64 — the seeded mixer behind `grid_seed` and `propose_order`'s uniform tail.
#[inline]
pub fn splitmix64(mut z: u64) -> u64 {
    z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// A stable seed for `(state, unit, kind)`: the round, the unit index, the kind and the unit centre bits
/// hashed together, so the uniform tail is reproducible from the state alone.
pub fn grid_seed(state: &State, unit: usize, kind: i64) -> u64 {
    let c = geom::centre(&state.positions[unit]);
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for v in [state.round as u64, unit as u64, kind as u64, c[0].to_bits() as u64, c[2].to_bits() as u64] {
        h ^= v;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    splitmix64(h)
}

/// The FULL priority order over `reachable`: ring 1 then ring 2 (Chebyshev shells) around the `hand_cells`
/// in menu order, then the remaining cells in a `seed`-deterministic Fisher-Yates order. `source` is 0 for
/// a ring cell and 1 for the uniform tail. Callers take a prefix (`grid_k`, step 9). The `hand_cells`
/// themselves are never proposed (they are already in the menu).
pub fn propose_order(reachable: &[u16], hand_cells: &[u16], seed: u64, nx: u16) -> Vec<(u16, u8)> {
    let reach_set: std::collections::HashSet<u16> = reachable.iter().copied().collect();
    let hand_set: std::collections::HashSet<u16> = hand_cells.iter().copied().collect();
    let mut out: Vec<(u16, u8)> = Vec::new();
    let mut seen: std::collections::HashSet<u16> = std::collections::HashSet::new();
    for ring in 1..=2i32 {
        for &h in hand_cells {
            let (hx, hy) = ((h % nx) as i32, (h / nx) as i32);
            for dy in -ring..=ring {
                for dx in -ring..=ring {
                    if dx.abs() != ring && dy.abs() != ring {
                        continue;
                    }
                    let (x, y) = (hx + dx, hy + dy);
                    if x < 0 || y < 0 {
                        continue;
                    }
                    let id = (x as u32 + y as u32 * nx as u32) as u16;
                    if !reach_set.contains(&id) || seen.contains(&id) || hand_set.contains(&id) {
                        continue;
                    }
                    seen.insert(id);
                    out.push((id, 0));
                }
            }
        }
    }
    let mut rest: Vec<u16> =
        reachable.iter().copied().filter(|c| !seen.contains(c) && !hand_set.contains(c)).collect();
    let mut s = seed;
    for i in (1..rest.len()).rev() {
        s = splitmix64(s);
        let j = (s % (i as u64 + 1)) as usize;
        rest.swap(i, j);
    }
    out.extend(rest.into_iter().map(|c| (c, 1)));
    out
}

#[cfg(test)]
#[path = "tests/grid_order/mod.rs"]
mod tests;
