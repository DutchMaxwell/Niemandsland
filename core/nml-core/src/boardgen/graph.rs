//! Stage 1: the seeded street / lot graph on the 16 x 16 lattice of 3-inch cells (a 48 x 48 in board).
//! Two staggered arteries (2 cells = 6 in wide), one cross street per half, and lots placed in mirrored
//! (`Point180`) or area-matched (`BalancedFree`) pairs. Integer lattice only; `LotKind` is set by the next stage.
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use super::levels::LotKind;
use super::{Budgets, Symmetry, CELL_IN, DEPLOY_DEPTH_CELLS, GRID};

/// The share (percent) of the houses of a row that get a garden plot behind them.
const YARD_PERCENT: i64 = 85;
/// Lots in one row of houses, inclusive.
const RUN_LOTS: (i64, i64) = (2, 4);

/// A main street: a rectangle of cells. `width_in` is its short side in inches.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Artery { pub x: usize, pub z: usize, pub w: usize, pub h: usize, pub width_in: u32 }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Lot { pub id: u16, pub x: usize, pub z: usize, pub w: usize, pub h: usize, pub sector: [usize; 2], pub kind: LotKind }
pub struct SectorGraph {
    pub nx: usize, pub nz: usize, pub symmetry: Symmetry,
    pub arteries: Vec<Artery>, pub is_street: Vec<bool>, pub lots: Vec<Lot>,
    /// Cells reserved for the city wall (two half-turn twins; empty unless the theme has a wall).
    pub wall: Vec<bool>,
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
    if b.rows && sym == Symmetry::Point180 { bend_arteries(&mut street, ax1, cz1, &mut rng); }
    let cz2 = if sym == Symmetry::Point180 { nz - 1 - cz1 } else { rng.randi_range(hz as i64 + 1, (nz as i64 - 2).max(hz as i64 + 1)) as usize };
    for x in 0..nx { street[(if x < hx { cz1 } else { cz2 }) * nx + x] = true; }
    if b.rows && sym == Symmetry::Point180 { second_square(&mut street, cz1, &mut rng); }
    // A market square: a square of street cells about the board centre, on the mid cross street (it always crosses columns 7 and 8).
    for z in hz - b.plaza.1 / 2..hz + b.plaza.1 / 2 { for x in hx - b.plaza.0 / 2..hx + b.plaza.0 / 2 { street[z * nx + x] = true; } }

    // A city wall: two half-turn twins running north-south over the whole board height on a column no artery runs along; where it meets a street that cell
    // stays street (a gate). No usable column = no wall (the validator then rejects the board).
    let mut wall = vec![false; nx * nz];
    let cols: Vec<usize> = if b.wall { (2..=5).filter(|&x| {
        let rows: Vec<usize> = (0..nz).filter(|&z| street[z * nx + x]).collect();
        !rows.is_empty() && rows.windows(2).all(|w| w[1] != w[0] + 1 || w[0] == hz - 1)
    }).collect() } else { Vec::new() };
    if !cols.is_empty() {
        let x = cols[rng.randi_range(0, cols.len() as i64 - 1) as usize];
        // a KINK (rows mode): from row `k` on the wall runs in the next usable column, with both columns walled on row `k` itself (a 1-cell step), the kink clear of every street
        let kink: Option<(usize, usize)> = if b.rows && sym == Symmetry::Point180 {
            let no_artery = |c: usize| { let rows: Vec<usize> = (0..nz).filter(|&z| street[z * nx + c]).collect(); rows.windows(2).all(|w| w[1] != w[0] + 1 || w[0] == hz - 1) };
            let next: Vec<usize> = [x.wrapping_sub(1), x + 1].into_iter().filter(|&c| (2..=5).contains(&c) && no_artery(c)).collect();   // a neighbouring column no artery runs along
            let rows: Vec<usize> = (2..=hz - 2).filter(|&k| next.iter().any(|&c| (k - 1..=k + 1).all(|z| !street[z * nx + x] && !street[z * nx + c]))).collect();
            (!next.is_empty() && !rows.is_empty()).then(|| {
                let k = rows[rng.randi_range(0, rows.len() as i64 - 1) as usize];
                let ok: Vec<usize> = next.iter().copied().filter(|&c| (k - 1..=k + 1).all(|z| !street[z * nx + x] && !street[z * nx + c])).collect();
                (k, ok[rng.randi_range(0, ok.len() as i64 - 1) as usize])
            })
        } else { None };
        for z in 0..nz {
            let zn = z.min(nz - 1 - z);   // the north half decides; the half turn mirrors it
            let cols_here: Vec<usize> = match kink { Some((k, c)) if zn > k => vec![c], Some((k, c)) if zn == k => vec![x, c], _ => vec![x] };
            for col in cols_here { for i in [z * nx + col, (nz - 1 - z) * nx + nx - 1 - col] { wall[i] = !street[i]; } }
        }
    }
    let mut g = SectorGraph { nx, nz, symmetry: sym, arteries, is_street: Vec::new(), lots: Vec::new(), wall: wall.clone() };
    let (mut occ, tpls, target) = (wall, b.lot_shapes, b.lot_pairs);
    let loose = if b.rows && sym == Symmetry::Point180 { b.lot_first.len() } else { target };   // a town grows rows after its forced first pairs; everyone else scatters
    let no_row = vec![false; nx * nz];
    for _ in 0..220 {
        if g.lots.len() / 2 >= loose { break; }
        let first = b.lot_first.get(g.lots.len() / 2).copied();   // the first pairs may have a forced shape and stay out of the bands (a tower site)
        let (w, h) = first.unwrap_or_else(|| tpls[rng.randi_range(0, tpls.len() as i64 - 1) as usize]);
        if w <= nx && h <= hz {
            let z0 = if first.is_some() { DEPLOY_DEPTH_CELLS as i64 } else { 0 };
            let r = (rng.randi_range(0, (nx - w) as i64) as usize, rng.randi_range(z0, (hz - h) as i64) as usize, w, h);
            try_pair(&mut g, &street, &mut occ, &no_row, &mut rng, r);
        }
    }
    if b.rows && sym == Symmetry::Point180 {
        // the forced first pairs (the tower site) are swept over every position if the random tries missed: a crowded centre must not lose its tower
        for (i, &(w, h)) in b.lot_first.iter().enumerate() { for z1 in DEPLOY_DEPTH_CELLS..=hz.saturating_sub(h) { for x1 in 0..=nx.saturating_sub(w) {
            if g.lots.len() / 2 == i { try_pair(&mut g, &street, &mut occ, &no_row, &mut rng, (x1, z1, w, h)); }
        }}}
        grow_rows(&mut g, &street, &mut occ, &mut rng, b);
    }
    else { for &(w, h) in b.lot_fill { for z1 in 0..=hz.saturating_sub(h) { for x1 in 0..=nx.saturating_sub(w) {
        if g.lots.len() / 2 < target { try_pair(&mut g, &street, &mut occ, &no_row, &mut rng, (x1, z1, w, h)); }
    }}}}
    g.is_street = street;
    g
}

/// May a lot stand at `r`? Its cells are free ground; the ring of cells round it is free too, except cells of the row being built (`row`): neighbours in a row share a party wall.
fn ok(nx: usize, nz: usize, st: &[bool], occ: &[bool], row: &[bool], (x0, z0, w, h): (usize, usize, usize, usize)) -> bool {
    x0 + w <= nx && z0 + h <= nz && (z0.saturating_sub(1)..=(z0 + h).min(nz - 1)).all(|z|
        (x0.saturating_sub(1)..=(x0 + w).min(nx - 1)).all(|x| {
            let (i, inside) = (z * nx + x, x >= x0 && x < x0 + w && z >= z0 && z < z0 + h);
            if inside { !occ[i] && !st[i] } else { !occ[i] || row[i] }
        }))
}
fn apart(a: (usize, usize, usize, usize), b: (usize, usize, usize, usize)) -> bool {
    a.0 + a.2 < b.0 || b.0 + b.2 < a.0 || a.1 + a.3 < b.1 || b.1 + b.3 < a.1
}

fn try_pair(g: &mut SectorGraph, st: &[bool], occ: &mut [bool], row: &[bool], rng: &mut GodotRng, r1: (usize, usize, usize, usize)) -> bool {
    let (nx, nz, hz, (x1, z1, w, h)) = (g.nx, g.nz, g.nz / 2, r1);
    if !ok(nx, nz, st, occ, row, r1) { return false; }
    let r2 = if g.symmetry == Symmetry::Point180 {
        let m = (nx - x1 - w, nz - z1 - h, w, h); (apart(r1, m) && ok(nx, nz, st, occ, row, m)).then_some(m)
    } else {
        let (mut cs, sh) = (Vec::new(), [(w, h), (h, w)]);
        for dz in 1..=2 {
            for &(w2, h2) in &sh[..if w == h { 1 } else { 2 }] { for z2 in hz..=nz.saturating_sub(h2) {
                if (nz - h2 - z2).abs_diff(z1) <= dz { for x2 in 0..=nx.saturating_sub(w2) {
                    let c = (x2, z2, w2, h2); if apart(r1, c) && ok(nx, nz, st, occ, row, c) { cs.push(c); }
                }}
            }}
            if !cs.is_empty() { break; }
        }
        let nm: Vec<_> = cs.iter().copied().filter(|&(x2, _, w2, _)| x1 + x2 + w2 != nx).collect();
        let pool = if nm.is_empty() { &cs } else { &nm };
        (!pool.is_empty()).then(|| pool[rng.randi_range(0, (pool.len() - 1) as i64) as usize])
    };
    let Some(r2) = r2 else { return false };
    for (x, z, rw, rh) in [r1, r2] {
        let id = (g.lots.len() + 1) as u16;
        for dz in 0..rh { for dx in 0..rw { occ[(z + dz) * nx + x + dx] = true; } }
        g.lots.push(Lot { id, x, z, w: rw, h: rh, sector: [(x + rw / 2) / 4, (z + rh / 2) / 4], kind: LotKind::Street });
    }
    true
}

/// Houses in ROWS (budget `rows`, north half, every lot mirrored by `try_pair`): pick a street cell, a side of it, and walk along the street laying 2 to 4 lots side by side
/// with their fronts on one line (party walls: neighbours in the row touch), long side along the street. The ring round the row keeps a passage at both ends and a yard behind.
/// A lot whose front touches no street cell ends the row.
fn grow_rows(g: &mut SectorGraph, st: &[bool], occ: &mut [bool], rng: &mut GodotRng, b: &Budgets) {
    let (nx, nz, hz) = (g.nx as i64, g.nz as i64, (g.nz / 2) as i64);
    let fronts: Vec<(i64, i64)> = (0..hz).flat_map(|z| (0..nx).map(move |x| (x, z))).filter(|&(x, z)| st[(z * nx + x) as usize]).collect();
    for _ in 0..1500 {
        if g.lots.len() / 2 >= b.lot_pairs { break; }
        let (sx, sz) = fronts[rng.randi_range(0, fronts.len() as i64 - 1) as usize];
        let (dx, dz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][rng.randi_range(0, 3) as usize];   // the side of the street the houses stand on
        let (fx, fz, along_x) = (sx + dx, sz + dz, dz != 0);
        if fx < 0 || fz < 0 || fx >= nx || fz >= hz || st[(fz * nx + fx) as usize] || occ[(fz * nx + fx) as usize] { continue; }
        // the row walks the way the street goes on (a street that does not continue along the frontage gives a one-house frontage)
        let toward = |d: i64| { let (px, pz) = if along_x { (sx + d, sz) } else { (sx, sz + d) }; px >= 0 && pz >= 0 && px < nx && pz < nz && st[(pz * nx + px) as usize] };
        let dir = match (toward(1), toward(-1)) { (true, true) => if rng.randi_range(0, 1) == 0 { 1 } else { -1 }, (true, false) => 1, (false, true) => -1, _ => continue };
        let (mut row, mut span, mut placed, mark, before, mut depth0) = (vec![false; g.nx * g.nz], (0, 0), 0, g.lots.len(), occ.to_vec(), 0);
        for k in 0..rng.randi_range(RUN_LOTS.0, RUN_LOTS.1) {
            let (a, c) = b.lot_shapes[rng.randi_range(0, b.lot_shapes.len() as i64 - 1) as usize];
            let len = a.max(c) as i64;   // long side along the street; every house of a row is as deep as its first
            if k == 0 { depth0 = if rng.randi_range(0, 9) < 7 { 2 } else { 1 }; }   // mostly 6 in deep houses: a roof or a tower needs a block, not a thin strip
            let depth = depth0;
            let start = if k == 0 { (if along_x { sx } else { sz }) - rng.randi_range(0, len - 1) } else if dir > 0 { span.1 } else { span.0 - len };
            let (x0, z0, w, h) = if along_x { (start, if dz < 0 { fz - depth + 1 } else { fz }, len, depth) } else { (if dx < 0 { fx - depth + 1 } else { fx }, start, depth, len) };
            if x0 < 0 || z0 < 0 || z0 + h > hz { break; }
            let faces_street = (0..len).any(|i| { let (cx, cz) = if along_x { (x0 + i, fz - dz) } else { (fx - dx, z0 + i) }; cx >= 0 && cz >= 0 && cx < nx && cz < nz && st[(cz * nx + cx) as usize] });
            if !faces_street || !try_pair(g, st, occ, &row, rng, (x0 as usize, z0 as usize, w as usize, h as usize)) { break; }
            for l in &g.lots[g.lots.len() - 2..] { for z in l.z..l.z + l.h { for x in l.x..l.x + l.w { row[z * g.nx + x] = true; } } }
            span = if k == 0 { (start, start + len) } else { (span.0.min(start), span.1.max(start + len)) };
            placed += 1;
        }
        if placed < RUN_LOTS.0 { g.lots.truncate(mark); occ.copy_from_slice(&before); }   // a lone house is no row: take it back
        else {   // a backyard: behind most houses of the row a single garden plot, so a block has a back (the pair of the lots just placed is [house, twin, house, twin, ...])
            for k in (mark..g.lots.len()).step_by(2) {
                let (lx, lz, lw, lh) = { let l = &g.lots[k]; (l.x as i64, l.z as i64, l.w as i64, l.h as i64) };
                if rng.randi_range(0, 99) >= YARD_PERCENT { continue; }
                // the cells just behind the house, tried from a random one: the first that takes a plot (ring relaxed along the row) gets it
                let backs: Vec<(i64, i64)> = if along_x { (lx..lx + lw).map(|x| (x, if dz < 0 { lz - 1 } else { lz + lh })).collect() } else { (lz..lz + lh).map(|z| (if dx < 0 { lx - 1 } else { lx + lw }, z)).collect() };
                let start = rng.randi_range(0, backs.len() as i64 - 1) as usize;
                for t in 0..backs.len() {
                    let (bx, bz) = backs[(start + t) % backs.len()];
                    if bx >= 0 && bz >= 0 && bx < nx && bz < nz && try_pair(g, st, occ, &row, rng, (bx as usize, bz as usize, 1, 1)) { break; }
                }
            }
        }
    }
    // Backyard gardens: single plots on bare ground beside a house (a mirrored pair each), until the board has the plots it must have.
    let (mut plots, no_row) = (g.lots.iter().filter(|l| l.w * l.h <= b.garden_area).count() / 2, vec![false; g.nx * g.nz]);
    for _ in 0..300 {
        if plots * 2 >= b.garden_min { break; }
        let (x, z) = (rng.randi_range(0, nx - 1), rng.randi_range(0, hz - 1));
        let near_house = [(1i64, 0i64), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)].iter().any(|&(dx, dz)| { let (px, pz) = (x + 2 * dx, z + 2 * dz); px >= 0 && pz >= 0 && px < nx && pz < nz && occ[(pz * nx + px) as usize] });
        if near_house && try_pair(g, st, occ, &no_row, rng, (x as usize, z as usize, 1, 1)) { plots += 1; }
    }
}

/// Streets that grew (budget `rows`, north half, every change mirrored by the half turn): the north artery is not one ruler line. From a row `j` on it shifts one column toward the board
/// centre (a 1-cell JOG; the street stays connected through the shared column and still meets the mid cross street), and two rows somewhere else lose their outer column: a 2-cell PINCH
/// where the street is 3 in wide (every base passes).
fn bend_arteries(street: &mut [bool], ax: usize, cz: usize, rng: &mut GodotRng) {
    let (nx, nz, hz) = (GRID, GRID, GRID / 2);
    let toward: i64 = if ax + 1 < nx / 2 { 1 } else { -1 };
    let mut set = |x: i64, z: usize, v: bool| { let i = z * nx + x as usize; street[i] = v; street[nz * nx - 1 - i] = v; };
    let js: Vec<usize> = (2..=hz - 4).filter(|&j| j != cz && j - 1 != cz).collect();   // the jog is not on the cross street's row
    let j = js[rng.randi_range(0, js.len() as i64 - 1) as usize];
    for z in j..hz - 1 {
        if toward > 0 { set(ax as i64, z, false); set(ax as i64 + 2, z, true); } else { set(ax as i64 + 1, z, false); set(ax as i64 - 1, z, true); }
    }
    let rows: Vec<usize> = (0..hz - 2).filter(|&p| (p + 1 < j || p > j) && p != cz && p + 1 != cz).collect();   // two rows on one side of the jog, short of the mid street, clear of the cross street
    let p = rows[rng.randi_range(0, rows.len() as i64 - 1) as usize];
    for z in p..p + 2 {
        let outer = if z < j { if toward > 0 { ax as i64 } else { ax as i64 + 1 } } else if toward > 0 { ax as i64 + 2 } else { ax as i64 - 1 };
        set(outer, z, false);
    }
}

/// A second, small square: where the cross street of the north half meets the artery, the cross street is two cells wide for two cells beside the crossing (a 2 x 2 block of street, and its
/// half-turn twin).
fn second_square(street: &mut [bool], cz: usize, rng: &mut GodotRng) {
    let (nx, nz) = (GRID, GRID);
    let crossings: Vec<usize> = (1..nx / 2 - 2).filter(|&x| cz + 2 < nz / 2 - 1 && street[cz * nx + x] && street[(cz + 1) * nx + x] && !street[(cz + 1) * nx + x + 1]).collect();   // the artery's east edge on the cross street
    if crossings.is_empty() { return; }
    let x = crossings[rng.randi_range(0, crossings.len() as i64 - 1) as usize];
    for dx in [1, 2] {
        let i = (cz + 1) * nx + x + dx;
        street[i] = true;
        street[nz * nx - 1 - i] = true;
    }
}
