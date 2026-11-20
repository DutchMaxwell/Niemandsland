//! Stage 1: the seeded street / lot graph on the 16 x 16 lattice of 3-inch cells (a 48 x 48 in board).
//! Two staggered arteries (2 cells = 6 in wide), one cross street per half, and lots placed in mirrored
//! (`Point180`) or area-matched (`BalancedFree`) pairs. Integer lattice only; `LotKind` is set by the next stage.
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use super::levels::LotKind;
use super::{Budgets, Symmetry, CELL_IN, DEPLOY_DEPTH_CELLS, GRID};

/// A main street: a rectangle of cells. `width_in` is its short side in inches.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Artery { pub x: usize, pub z: usize, pub w: usize, pub h: usize, pub width_in: u32 }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Lot { pub id: u16, pub x: usize, pub z: usize, pub w: usize, pub h: usize, pub sector: [usize; 2], pub kind: LotKind }
pub struct SectorGraph {
    pub nx: usize, pub nz: usize, pub symmetry: Symmetry,
    pub arteries: Vec<Artery>, pub is_street: Vec<bool>, pub lots: Vec<Lot>,
}

pub fn build(seed: i64, sym: Symmetry, b: &Budgets) -> SectorGraph {
    let (nx, nz, mut rng) = (GRID, GRID, GodotRng::new(seed));
    let (hx, hz) = (nx / 2, nz / 2);
    let mut ax1 = rng.randi_range(1, (hx as i64 - 3).max(1)) as usize;
    let mut ax2 = if sym == Symmetry::Point180 { nx - 2 - ax1 } else { rng.randi_range(hx as i64 + 1, (nx as i64 - 3).max(hx as i64 + 1)) as usize };
    if rng.randi_range(0, 1) == 1 { std::mem::swap(&mut ax1, &mut ax2); }
    let arteries = vec![
        Artery { x: ax1, z: 0, w: 2, h: hz, width_in: 2 * CELL_IN },
        Artery { x: ax2, z: hz, w: 2, h: nz - hz, width_in: 2 * CELL_IN },
        Artery { x: ax1.min(ax2), z: hz - 1, w: ax1.max(ax2) + 2 - ax1.min(ax2), h: 2, width_in: 2 * CELL_IN },
    ];
    let mut street = vec![false; nx * nz];
    for a in &arteries { for dz in 0..a.h { for dx in 0..a.w { street[(a.z + dz) * nx + a.x + dx] = true; } } }
    let cz1 = rng.randi_range(1, (hz as i64 - 2).max(1)) as usize;
    let cz2 = if sym == Symmetry::Point180 { nz - 1 - cz1 } else { rng.randi_range(hz as i64 + 1, (nz as i64 - 2).max(hz as i64 + 1)) as usize };
    for x in 0..nx { street[(if x < hx { cz1 } else { cz2 }) * nx + x] = true; }

    let mut g = SectorGraph { nx, nz, symmetry: sym, arteries, is_street: Vec::new(), lots: Vec::new() };
    let (mut occ, tpls, target) = (vec![false; nx * nz], b.lot_shapes, b.lot_pairs);
    for _ in 0..220 {
        if g.lots.len() / 2 >= target { break; }
        let first = b.lot_first.get(g.lots.len() / 2).copied();   // the first pairs may have a forced shape and stay out of the bands (a tower site)
        let (w, h) = first.unwrap_or_else(|| tpls[rng.randi_range(0, tpls.len() as i64 - 1) as usize]);
        if w <= nx && h <= hz {
            let z0 = if first.is_some() { DEPLOY_DEPTH_CELLS as i64 } else { 0 };
            let r = (rng.randi_range(0, (nx - w) as i64) as usize, rng.randi_range(z0, (hz - h) as i64) as usize, w, h);
            try_pair(&mut g, &street, &mut occ, &mut rng, r);
        }
    }
    for &(w, h) in b.lot_fill { for z1 in 0..=hz.saturating_sub(h) { for x1 in 0..=nx.saturating_sub(w) {
        if g.lots.len() / 2 < target { try_pair(&mut g, &street, &mut occ, &mut rng, (x1, z1, w, h)); }
    }}}
    g.is_street = street;
    g
}

fn ok(nx: usize, nz: usize, st: &[bool], occ: &[bool], (x0, z0, w, h): (usize, usize, usize, usize)) -> bool {
    x0 + w <= nx && z0 + h <= nz && (z0.saturating_sub(1)..=(z0 + h).min(nz - 1)).all(|z|
        (x0.saturating_sub(1)..=(x0 + w).min(nx - 1)).all(|x| !occ[z * nx + x] && !(x >= x0 && x < x0 + w && z >= z0 && z < z0 + h && st[z * nx + x])))
}
fn apart(a: (usize, usize, usize, usize), b: (usize, usize, usize, usize)) -> bool {
    a.0 + a.2 < b.0 || b.0 + b.2 < a.0 || a.1 + a.3 < b.1 || b.1 + b.3 < a.1
}

fn try_pair(g: &mut SectorGraph, st: &[bool], occ: &mut [bool], rng: &mut GodotRng, r1: (usize, usize, usize, usize)) {
    let (nx, nz, hz, (x1, z1, w, h)) = (g.nx, g.nz, g.nz / 2, r1);
    if !ok(nx, nz, st, occ, r1) { return; }
    let r2 = if g.symmetry == Symmetry::Point180 {
        let m = (nx - x1 - w, nz - z1 - h, w, h); (apart(r1, m) && ok(nx, nz, st, occ, m)).then_some(m)
    } else {
        let (mut cs, sh) = (Vec::new(), [(w, h), (h, w)]);
        for dz in 1..=2 {
            for &(w2, h2) in &sh[..if w == h { 1 } else { 2 }] { for z2 in hz..=nz.saturating_sub(h2) {
                if (nz - h2 - z2).abs_diff(z1) <= dz { for x2 in 0..=nx.saturating_sub(w2) {
                    let c = (x2, z2, w2, h2); if apart(r1, c) && ok(nx, nz, st, occ, c) { cs.push(c); }
                }}
            }}
            if !cs.is_empty() { break; }
        }
        let nm: Vec<_> = cs.iter().copied().filter(|&(x2, _, w2, _)| x1 + x2 + w2 != nx).collect();
        let pool = if nm.is_empty() { &cs } else { &nm };
        (!pool.is_empty()).then(|| pool[rng.randi_range(0, (pool.len() - 1) as i64) as usize])
    };
    if let Some(r2) = r2 {
        for (x, z, rw, rh) in [r1, r2] {
            let id = (g.lots.len() + 1) as u16;
            for dz in 0..rh { for dx in 0..rw { occ[(z + dz) * nx + x + dx] = true; } }
            g.lots.push(Lot { id, x, z, w: rw, h: rh, sector: [(x + rw / 2) / 4, (z + rh / 2) / 4], kind: LotKind::Street });
        }
    }
}
