//! Free solids (organic plan C1, C3): an intact house of a town board as ONE box in board-centred inches instead of its
//! painted cells. `to_plain` emits each box twice - a `sandbox` piece (movement, `type_at`) and a `containers` box
//! (sight) - with the same centre, half extents and yaw; the table draws and collides exactly these boxes.
//!
//! C3: a house turns off the table axes. Each half of the board has one spine angle per quadrant (5-20 deg), each house
//! a deviation of up to 4 deg; the box is the largest one of its lot's proportions that fits its lot at that yaw (all
//! four corners on the lot's sides), so it never leaves its own cells: never on a street, a ladder foot or a tier. A yaw
//! is kept only if every gap to another solid (house, raised mass, solid landmark) is closed (they touch) or at least
//! [`GAP_MIN_IN`] (lead L-O3), and both sides stay at least [`SIDE_MIN_IN`]; else a smaller yaw, at last 0 (the lot).
use serde::{Deserialize, Serialize};
use super::levels::LotKind;
use super::{Layout, Symmetry};

/// The narrowest open gap between two solids: a 50 mm base passes (lead L-O3).
pub const GAP_MIN_IN: f64 = 2.1;
/// Two solids closer than this touch (a closed gap, a party wall).
const TOUCH_IN: f64 = 0.01;
/// A turned house is never thinner than this.
const SIDE_MIN_IN: f64 = 2.0;

/// One free solid: centre and half extents in inches about the board centre, `yaw` in radians as `terrain::Obb`
/// (local +X -> (cos, -sin)), `lot` the lot it stands on.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FreeSolid { pub c_in: [f64; 2], pub he_in: [f64; 2], pub yaw: f64, pub lot: u16 }

impl FreeSolid {
    /// The four corners, board-centred inches.
    pub fn corners(&self) -> [[f64; 2]; 4] {
        let (s, c) = self.yaw.sin_cos();
        let (ax, az) = ([c * self.he_in[0], -s * self.he_in[0]], [s * self.he_in[1], c * self.he_in[1]]);
        [(1.0, 1.0), (1.0, -1.0), (-1.0, -1.0), (-1.0, 1.0)].map(|(i, j)| [self.c_in[0] + i * ax[0] + j * az[0], self.c_in[1] + i * ax[1] + j * az[1]])
    }
}

/// FNV-style mix of the seed and a key into [0, 1): the angles are data of the seed, never of an rng stream.
fn unit(seed: i64, key: u64) -> f64 {
    let mut h = 0xcbf2_9ce4_8422_2325_u64 ^ seed as u64;
    for b in key.to_le_bytes() { h = (h ^ u64::from(b)).wrapping_mul(0x0000_0100_0000_01b3); }
    (h >> 11) as f64 / (1u64 << 53) as f64
}

/// The box of a `w` x `h` inch lot about `c` turned by `yaw`, as large as fits with the lot's proportions; `None` if a side gets too thin.
fn inscribed(c: [f64; 2], w: f64, h: f64, yaw: f64, lot: u16) -> Option<FreeSolid> {
    let (s, k) = (yaw.abs().sin(), yaw.abs().cos());
    let d = k * k - s * s;
    let (a, b) = ((w * k - h * s) / d, (h * k - w * s) / d);
    (a >= SIDE_MIN_IN && b >= SIDE_MIN_IN).then_some(FreeSolid { c_in: c, he_in: [a * 0.5, b * 0.5], yaw, lot })
}

fn seg_point(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    let (d, v) = ([b[0] - a[0], b[1] - a[1]], [p[0] - a[0], p[1] - a[1]]);
    let t = ((v[0] * d[0] + v[1] * d[1]) / (d[0] * d[0] + d[1] * d[1]).max(1e-12)).clamp(0.0, 1.0);
    (p[0] - a[0] - d[0] * t).hypot(p[1] - a[1] - d[1] * t)
}

/// Least distance between two convex quads (0 when they overlap or touch).
pub fn quad_gap(p: &[[f64; 2]; 4], q: &[[f64; 2]; 4]) -> f64 {
    let inside = |x: [f64; 2], r: &[[f64; 2]; 4]| {
        let side = |i: usize| { let (a, b) = (r[i], r[(i + 1) % 4]); (b[0] - a[0]) * (x[1] - a[1]) - (b[1] - a[1]) * (x[0] - a[0]) };
        (0..4).all(|i| side(i) >= -1e-9) || (0..4).all(|i| side(i) <= 1e-9)
    };
    if p.iter().any(|&x| inside(x, q)) || q.iter().any(|&x| inside(x, p)) { return 0.0; }
    let one = |r: &[[f64; 2]; 4], s: &[[f64; 2]; 4]| r.iter().flat_map(|&x| (0..4).map(move |i| seg_point(x, s[i], s[(i + 1) % 4]))).fold(f64::MAX, f64::min);
    one(p, q).min(one(q, p))
}

/// Every solid of `l` that is not a free house, as quads in board-centred inches: one per raised cell (any level, the wall
/// included) and per solid landmark cell. A free house's gap to a raised MASS is its least gap to any of the mass's cells.
fn fixed_solids(l: &Layout) -> Vec<[[f64; 2]; 4]> {
    let cell = f64::from(l.cell_in);
    let o = [f64::from(l.board_in[0]) * 0.5, f64::from(l.board_in[1]) * 0.5];
    let solid_lm = super::landmarks::solid_mask(&l.landmarks);
    l.cells.iter().enumerate().filter(|(i, c)| c.level > 0 || solid_lm[*i]).map(|(_, c)| {
        let (x0, z0) = (c.x as f64 * cell - o[0], c.z as f64 * cell - o[1]);
        [[x0, z0], [x0 + cell, z0], [x0 + cell, z0 + cell], [x0, z0 + cell]]
    }).collect()
}

/// Gaps that break the rule: open (> touch) and narrower than [`GAP_MIN_IN`], between a house and anything solid (another house, a raised cell, a solid landmark).
pub fn trap_gaps(l: &Layout, solids: &[FreeSolid]) -> usize {
    let fixed = fixed_solids(l);
    let bad = |g: f64| g > TOUCH_IN && g < GAP_MIN_IN;
    let quads: Vec<_> = solids.iter().map(FreeSolid::corners).collect();
    let mut n = 0;
    for (i, q) in quads.iter().enumerate() {
        n += usize::from(bad(fixed.iter().map(|f| quad_gap(q, f)).fold(f64::MAX, f64::min)));
        n += quads[i + 1..].iter().filter(|r| bad(quad_gap(q, r))).count();
    }
    n
}

/// The intact houses of `l` as free boxes (empty unless the theme has `free_solids`). A house whose cells are not one
/// rectangle (never seen; kept as a guard) gives one unturned box per cell.
pub fn free_solids(l: &Layout) -> Vec<FreeSolid> {
    if !l.theme.budgets().free_solids { return Vec::new(); }
    let cell = f64::from(l.cell_in);
    let o = [f64::from(l.board_in[0]) * 0.5, f64::from(l.board_in[1]) * 0.5];
    let rect = |x0: usize, z0: usize, w: usize, h: usize| ([(x0 as f64 + w as f64 * 0.5) * cell - o[0], (z0 as f64 + h as f64 * 0.5) * cell - o[1]], w as f64 * cell, h as f64 * cell);
    let mut lots: Vec<u16> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).map(|c| c.lot_id).collect();
    lots.sort_unstable();
    lots.dedup();
    let mut houses = Vec::new();   // (centre, w, h, lot, turnable)
    for id in lots {
        let cs: Vec<_> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed && c.lot_id == id).collect();
        let (x0, z0) = (cs.iter().map(|c| c.x).min().unwrap_or(0), cs.iter().map(|c| c.z).min().unwrap_or(0));
        let (x1, z1) = (cs.iter().map(|c| c.x).max().unwrap_or(0), cs.iter().map(|c| c.z).max().unwrap_or(0));
        if cs.len() == (x1 - x0 + 1) * (z1 - z0 + 1) {
            let (c, w, h) = rect(x0, z0, x1 - x0 + 1, z1 - z0 + 1);
            houses.push((c, w, h, id, true));
        } else {
            houses.extend(cs.iter().map(|c| { let (cc, w, h) = rect(c.x, c.z, 1, 1); (cc, w, h, id, false) }));
        }
    }
    let half_turn = l.symmetry == Symmetry::Point180;
    // a house and its half-turn twin are placed together, the one in the north half (or west on the middle line) leads
    let leads = |c: [f64; 2]| !half_turn || c[1] < 0.0 || (c[1] == 0.0 && c[0] < 0.0);
    let fixed = fixed_solids(l);
    let mut out: Vec<FreeSolid> = Vec::new();
    for &(c, w, h, id, turnable) in houses.iter().filter(|hs| leads(hs.0)) {
        let twin = houses.iter().find(|t| half_turn && t.0 == [-c[0], -c[1]] && t.1 == w && t.2 == h).map(|t| t.3);
        // the spine: one angle per quadrant of the board (sign by the side of the centre line), the house deviates from it
        let quadrant = u64::from(c[0] < 0.0) * 2 + u64::from(c[1] < 0.0);
        let spine = (5.0 + 15.0 * unit(l.seed, 100 + quadrant)) * if quadrant % 3 == 0 { 1.0 } else { -1.0 };
        let want = (spine + 8.0 * unit(l.seed, 200 + u64::from(id)) - 4.0).to_radians();
        let mut pick = None;
        for f in [1.0, 0.75, 0.5, 0.25] {
            let Some(b) = inscribed(c, w, h, want * f, id).filter(|_| turnable) else { continue };
            let pair: Vec<FreeSolid> = std::iter::once(b.clone()).chain(twin.map(|t| FreeSolid { c_in: [-c[0], -c[1]], lot: t, ..b.clone() })).collect();
            let quads: Vec<_> = pair.iter().map(FreeSolid::corners).collect();
            let gap_ok = |g: f64| g <= TOUCH_IN || g >= GAP_MIN_IN;
            // against the fixed solids, the houses already placed, and every house still to come as its whole lot (so a later
            // house that stays unturned can never open a narrow gap to this one)
            let later = houses.iter().filter(|o| o.3 != id && Some(o.3) != twin && !out.iter().any(|p| p.lot == o.3))
                .map(|o| FreeSolid { c_in: o.0, he_in: [o.1 * 0.5, o.2 * 0.5], yaw: 0.0, lot: o.3 }.corners()).collect::<Vec<_>>();
            let ok = quads.iter().all(|q| gap_ok(fixed.iter().map(|f| quad_gap(q, f)).fold(f64::MAX, f64::min))
                && out.iter().all(|o| gap_ok(quad_gap(q, &o.corners()))) && later.iter().all(|r| gap_ok(quad_gap(q, r))))
                && (quads.len() < 2 || gap_ok(quad_gap(&quads[0], &quads[1])));
            if ok { pick = Some(pair); break; }
        }
        out.extend(pick.unwrap_or_else(|| {
            let flat = FreeSolid { c_in: c, he_in: [w * 0.5, h * 0.5], yaw: 0.0, lot: id };
            std::iter::once(flat.clone()).chain(twin.map(|t| FreeSolid { c_in: [-c[0], -c[1]], lot: t, ..flat })).collect()
        }));
    }
    // a house without a leading twin (only off a half-turn board) stays its lot
    for &(c, w, h, id, _) in &houses {
        if !out.iter().any(|o| o.lot == id && o.c_in == c) { out.push(FreeSolid { c_in: c, he_in: [w * 0.5, h * 0.5], yaw: 0.0, lot: id }); }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::boardgen::{generate_themed, Theme};

    fn town(seed: i64) -> Layout { generate_themed(seed, Symmetry::Point180, Theme::RuinTown) }

    #[test]
    fn a_town_has_rotated_houses() {
        // The plan's bar (>= 3 turned houses on 90 % of the boards) cannot hold on a town of ~4 intact houses (organic plan risk 1,
        // measured 84 of 200): the bar here is what the gap rule lets turn - most houses, and some house on most boards (measured 570 of 830, 168 of 200).
        let (mut any, mut turned, mut houses, n) = (0usize, 0usize, 0usize, 200usize);
        for seed in 1..=n as i64 {
            let s = free_solids(&town(seed));
            let t = s.iter().filter(|b| b.yaw.abs() >= 5f64.to_radians()).count();
            any += usize::from(t > 0);
            (turned, houses) = (turned + t, houses + s.len());
        }
        eprintln!("turned houses: {turned} of {houses}; boards with a turned house: {any} of {n}");
        assert!(turned * 10 >= houses * 6, "only {turned} of {houses} houses turned by 5 deg or more");
        assert!(any * 10 >= n * 8, "only {any} of {n} boards have a turned house");
    }

    #[test]
    fn no_gap_between_solids_is_narrower_than_a_base() {
        for seed in 1..=200 {
            let l = town(seed);
            let s = free_solids(&l);
            assert_eq!(trap_gaps(&l, &s), 0, "seed {seed}: a gap between solids is open and narrower than a base");
            assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
            // planted: a 1 x 1 in post 1.0 in off the first house's +x face
            let Some(h) = s.first() else { continue };
            let far = h.corners().iter().map(|c| c[0]).fold(f64::MIN, f64::max);
            let post = FreeSolid { c_in: [far + 1.5, h.c_in[1]], he_in: [0.5, 0.5], yaw: 0.0, lot: 0 };
            assert!(trap_gaps(&l, &[s.clone(), vec![post]].concat()) > 0, "seed {seed}: a planted 1.0 in gap went unnoticed");
        }
    }

    /// Components of the level-0 ground a 50 mm base centre may stand on (1 in samples, 1.05 in clear of every solid).
    fn base_components(l: &Layout, s: &[FreeSolid]) -> usize {
        let mut quads: Vec<[[f64; 2]; 4]> = fixed_solids(l);
        quads.extend(s.iter().map(FreeSolid::corners));
        let free = |x: usize, z: usize| {
            let p = [x as f64 + 0.5 - 24.0, z as f64 + 0.5 - 24.0];
            let dot = [p, p, p, p];
            l.cell(x / 3, z / 3).level == 0 && quads.iter().all(|q| quad_gap(&dot, q) >= 1.05)
        };
        let ok: Vec<bool> = (0..48 * 48).map(|i| free(i % 48, i / 48)).collect();
        let (mut seen, mut n) = (vec![false; 48 * 48], 0);
        for s0 in 0..48 * 48 {
            if !ok[s0] || seen[s0] { continue; }
            n += 1;
            let mut stack = vec![s0];
            seen[s0] = true;
            while let Some(i) = stack.pop() {
                let (x, z) = (i % 48, i / 48);
                for (dx, dz) in [(1i64, 0i64), (-1, 0), (0, 1), (0, -1)] {
                    let (nx, nz) = (x as i64 + dx, z as i64 + dz);
                    if !(0..48).contains(&nx) || !(0..48).contains(&nz) { continue; }
                    let j = nz as usize * 48 + nx as usize;
                    if ok[j] && !seen[j] { seen[j] = true; stack.push(j); }
                }
            }
        }
        n
    }

    #[test]
    fn turning_the_houses_opens_no_new_pocket_of_ground() {
        for seed in 1..=40 {
            let l = town(seed);
            let s = free_solids(&l);
            let flat: Vec<FreeSolid> = s.iter().map(|b| {
                let lot = l.lots.iter().find(|o| o.id == b.lot).expect("lot");
                let c = [(lot.x as f64 + lot.w as f64 * 0.5) * 3.0 - 24.0, (lot.z as f64 + lot.h as f64 * 0.5) * 3.0 - 24.0];
                FreeSolid { c_in: c, he_in: [lot.w as f64 * 1.5, lot.h as f64 * 1.5], yaw: 0.0, lot: b.lot }
            }).collect();
            let (a, b) = (base_components(&l, &s), base_components(&l, &flat));
            assert!(a <= b, "seed {seed}: turning the houses split the ground into {a} pockets (was {b})");
        }
    }
}
