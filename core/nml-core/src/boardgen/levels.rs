//! Stage 2: heights. Each lot gets an archetype and raises its cells to level 1 (3 in); the raised share is then
//! fitted to its budget and a part of it is lifted to level 2 (6 in); a few level-2 cells rise once more to level 3
//! (9 in, the towers). Streets stay flat and levels 2 and 3 never enter a deployment band. Every change is a mirrored pair under `Point180` and a one-per-half pair under `BalancedFree`,
//! so both sides keep equal counts.
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use super::graph::{Lot, SectorGraph};
use super::{budget, Budgets, Symmetry, DEPLOY_DEPTH_CELLS, GRID};

/// Lot archetypes (theme-neutral; a kit table picks the look). `Block`: solid mass, walkable roof, blocks sight.
/// `Terrace`: an L-shaped step, the rest of the lot stays ground. `Deck`: open raised platform, sight passes.
/// `Hazard`: flat area hazard, never raised.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LotKind { Street, Block, Terrace, Deck, Hazard }

/// One lattice cell. `level` 0/1/2/3 = 0/3/6/9 in; `deploy` 1/2 = the player whose band it is, 0 = neither.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cell { pub x: usize, pub z: usize, pub deploy: u8, pub street: bool, pub lot_id: u16, pub lot_kind: LotKind, pub level: u8 }

pub fn stack(seed: i64, g: &SectorGraph, b: &Budgets) -> (Vec<Lot>, Vec<Cell>) {
    let (nx, nz, sym, mut rng, mut lots) = (g.nx, g.nz, g.symmetry, GodotRng::new(seed), g.lots.clone());
    let mut cells: Vec<Cell> = (0..nx * nz).map(|i| {
        let (x, z) = (i % nx, i / nx);
        let deploy = if z < DEPLOY_DEPTH_CELLS { 1 } else if z >= nz - DEPLOY_DEPTH_CELLS { 2 } else { 0 };
        Cell { x, z, deploy, street: g.is_street[i], lot_id: 0, lot_kind: LotKind::Street, level: 0 }
    }).collect();
    let (mut hazards, pool) = (0, b.lot_pool);
    for p in 0..lots.len() / 2 {
        let in_deploy = [2 * p, 2 * p + 1].iter().any(|&i| lots[i].z < DEPLOY_DEPTH_CELLS || lots[i].z + lots[i].h > nz - DEPLOY_DEPTH_CELLS);
        let mut kind = match p { 0 => LotKind::Block, 1 => LotKind::Terrace, 2 => LotKind::Deck, _ => pool[rng.randi_range(0, pool.len() as i64 - 1) as usize] };
        if kind == LotKind::Hazard && (in_deploy || hazards >= 1) { kind = LotKind::Deck } else if kind == LotKind::Hazard { hazards += 1 }
        let r1 = rng.randi_range(0, 3) as usize;
        let r2 = if sym == Symmetry::Point180 { (r1 + 2) % 4 } else { (r1 + rng.randi_range(1, 3) as usize) % 4 };
        for (li, rot) in [(2 * p, r1), (2 * p + 1, r2)] {
            lots[li].kind = kind;
            let (lx, lz, lw, lh, id) = { let l = &lots[li]; (l.x, l.z, l.w, l.h, l.id) };
            // Terrace: the L is the row and the column through the corner the rotation picks.
            let (cx, cz) = (if rot == 0 || rot == 3 { 0 } else { lw - 1 }, if rot < 2 { 0 } else { lh - 1 });
            for dz in 0..lh { for dx in 0..lw {
                let c = &mut cells[(lz + dz) * nx + lx + dx];
                (c.lot_id, c.lot_kind) = (id, kind);
                c.level = u8::from(matches!(kind, LotKind::Block | LotKind::Deck) || (kind == LotKind::Terrace && (dx == cx || dz == cz)));
            }}
        }
    }
    let (min_r, max_r) = budget(b.raised);
    let raised = |cs: &[Cell]| cs.iter().filter(|c| c.level >= 1).count();
    // Grow a terrace next to raised ground, or shave non-block cells, until the raised share fits.
    while raised(&cells) < min_r {
        let grow = |i: usize, cs: &[Cell]| cs[i].level == 0 && !cs[i].street && cs[i].lot_kind != LotKind::Hazard && neighbours(i).any(|j| cs[j].level >= 1);
        let Some((a, b)) = paired(&cells, sym, &mut rng, grow, |_| 0).into_iter().next() else { break };
        cells[a].level = 1; cells[b].level = 1;
    }
    while raised(&cells) > max_r {
        let shave = |i: usize, cs: &[Cell]| cs[i].level == 1;
        let Some((a, b)) = paired(&cells, sym, &mut rng, shave, |c| u8::from(c.lot_kind == LotKind::Block)).into_iter().next() else { break };
        cells[a].level = 0; cells[b].level = 0;
    }
    if b.tower_side == 2 { raise_towers_2x2(&mut cells, sym, &mut rng, b.tower_pairs); }
    // Level 2: raised cells outside the deployment bands. A pair is kept only if the board stays one piece when every
    // step of at most one level counts as a possible way up, so no island of level 2 is ever cut off.
    let (min_h, max_h) = budget(b.high);
    let (lo, hi) = ((min_h + 1) & !1, max_h & !1);
    let target = lo + 2 * rng.randi_range(0, ((hi - lo) / 2) as i64) as usize;
    let lift = |i: usize, cs: &[Cell]| cs[i].level == 1 && cs[i].deploy == 0;
    let (mut lifted, order) = (0, paired(&cells, sym, &mut rng, lift, |c| match c.lot_kind { LotKind::Block | LotKind::Terrace => 0, LotKind::Deck => 1, _ => 2 }));
    for (a, b) in order {
        if lifted == target / 2 { break; }
        (cells[a].level, cells[b].level) = (2, 2);
        if one_piece(&cells) { lifted += 1 } else { (cells[a].level, cells[b].level) = (1, 1) }
    }
    // Level 3: a few level-2 cells rise once more, as mirrored pairs, each kept only if the board stays one piece (so a
    // tower is always reachable by a ladder from level 2). A pair next to an existing tower comes first (blocks, not
    // single posts), then the cell with the fewest ground neighbours (the shortest sheer wall).
    for _ in 0..if b.tower_side == 2 { 0 } else { rng.randi_range(b.tower_pairs.0 as i64, b.tower_pairs.1 as i64) } {
        let snap = cells.clone();
        let key = |c: &Cell| { let i = c.z * nx + c.x; if neighbours(i).any(|j| snap[j].level == 3) { 0 } else { 1 + neighbours(i).filter(|&j| snap[j].level == 0).count() as u8 } };
        for (a, b) in paired(&snap, sym, &mut rng, |i, cs| cs[i].level == 2, key) {
            (cells[a].level, cells[b].level) = (3, 3);
            if one_piece(&cells) { break } else { (cells[a].level, cells[b].level) = (2, 2) }
        }
    }
    (lots, cells)
}

/// Town towers, raised before the level-2 lift: a 2 x 2 block of level-1 cells outside the bands rises to level 3, with one level-1 cell beside it
/// lifted to level 2 (the ladder up), as mirrored pairs; the board must stay one piece. The block with the most lower neighbours goes first (the
/// tallest sheer faces). The level-2 lift then runs on what is left.
fn raise_towers_2x2(cells: &mut [Cell], sym: Symmetry, rng: &mut GodotRng, pairs: (usize, usize)) {
    let block = |o: usize| [o, o + 1, o + GRID, o + GRID + 1];
    for _ in 0..rng.randi_range(pairs.0 as i64, pairs.1 as i64) {
        let snap = cells.to_vec();
        let around = |o: usize| block(o).into_iter().flat_map(neighbours).filter(move |j| !block(o).contains(j)).collect::<Vec<_>>();
        let step = |o: usize| around(o).into_iter().find(|&j| snap[j].level == 1 && snap[j].deploy == 0);   // the cell that becomes the 6 in step
        let ok = |o: usize| o % GRID + 1 < GRID && o / GRID + 1 < GRID && block(o).iter().all(|&i| snap[i].level == 1 && snap[i].deploy == 0) && step(o).is_some();
        let lower = |o: usize| around(o).iter().filter(|&&j| snap[j].level == 0).count();
        let mut cand: Vec<(usize, usize)> = if sym == Symmetry::Point180 {
            // the half-turn image of the block at `o` has its origin at 238 - o
            (0..GRID * GRID - GRID - 1).filter_map(|o| { let t = GRID * GRID - GRID - 2 - o; (o < t && ok(o) && ok(t) && !block(o).iter().any(|i| block(t).contains(i))).then_some((o, t)) }).collect()
        } else {
            let (mut a, mut c): (Vec<_>, Vec<_>) = ((0..GRID * GRID).filter(|&o| o / GRID + 1 < GRID / 2 && ok(o)).collect(), (0..GRID * GRID).filter(|&o| o / GRID >= GRID / 2 && ok(o)).collect());
            shuffle(&mut a, rng); shuffle(&mut c, rng); a.into_iter().zip(c).collect()
        };
        shuffle(&mut cand, rng);
        cand.sort_by_key(|&(o, t)| usize::MAX - lower(o) - lower(t));
        for (o, t) in cand {
            let s1 = step(o).expect("ok() found a step");
            let steps = [s1, if sym == Symmetry::Point180 { mirror(s1) } else { step(t).expect("ok() found a step") }];   // a half-turn twin has the half-turn step
            if steps.iter().any(|j| block(o).contains(j) || block(t).contains(j)) { continue; }
            for i in block(o).into_iter().chain(block(t)) { cells[i].level = 3; }
            for &j in &steps { cells[j].level = 2; }
            if one_piece(cells) { break } else { for i in block(o).into_iter().chain(block(t)).chain(steps) { cells[i].level = snap[i].level; } }
        }
    }
}

/// True if the cells that touch and differ by at most one level form a single area.
fn one_piece(cells: &[Cell]) -> bool {
    let (mut seen, mut stack) = (vec![false; cells.len()], vec![0]);
    seen[0] = true;
    while let Some(i) = stack.pop() {
        for j in neighbours(i) { if !seen[j] && cells[i].level.abs_diff(cells[j].level) <= 1 { seen[j] = true; stack.push(j); } }
    }
    seen.iter().all(|&s| s)
}

/// Index of the cell rotated 180 degrees about the board centre.
#[inline] pub(crate) fn mirror(i: usize) -> usize { GRID * GRID - 1 - i }

/// The (up to four) orthogonal neighbours of cell `i` on the square lattice.
pub(crate) fn neighbours(i: usize) -> impl Iterator<Item = usize> {
    let (x, z) = (i % GRID, i / GRID);
    [(x > 0).then(|| i - 1), (x + 1 < GRID).then(|| i + 1), (z > 0).then(|| i - GRID), (z + 1 < GRID).then(|| i + GRID)].into_iter().flatten()
}

pub(crate) fn shuffle<T>(v: &mut [T], rng: &mut GodotRng) { for i in (1..v.len()).rev() { let j = rng.randi_range(0, i as i64) as usize; v.swap(i, j); } }

/// Candidate cell pairs, shuffled, then stably ordered by `key` (low first). `Point180`: a cell and its mirror, both
/// passing `pred`. `BalancedFree`: one cell from each half, paired in order.
fn paired(cells: &[Cell], sym: Symmetry, rng: &mut GodotRng, pred: impl Fn(usize, &[Cell]) -> bool, key: impl Fn(&Cell) -> u8) -> Vec<(usize, usize)> {
    let (n, half) = (cells.len(), cells.len() / 2);
    if sym == Symmetry::Point180 {
        let mut v: Vec<_> = (0..half).filter_map(|i| (pred(i, cells) && pred(mirror(i), cells)).then_some((i, mirror(i)))).collect();
        shuffle(&mut v, rng); v.sort_by_key(|&(i, _)| key(&cells[i])); v
    } else {
        let (mut a, mut b): (Vec<_>, Vec<_>) = ((0..half).filter(|&i| pred(i, cells)).collect(), (half..n).filter(|&i| pred(i, cells)).collect());
        shuffle(&mut a, rng); shuffle(&mut b, rng); a.sort_by_key(|&i| key(&cells[i])); b.sort_by_key(|&i| key(&cells[i])); a.into_iter().zip(b).collect()
    }
}
