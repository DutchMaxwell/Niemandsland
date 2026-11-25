//! Stage 2: heights. Each lot gets an archetype and raises its cells to level 1 (3 in); the raised share is then
//! fitted to its budget and a part of it is lifted to level 2 (6 in); a few level-2 cells rise once more to level 3
//! (9 in, the towers). Streets stay flat and levels 2 and 3 never enter a deployment band. Every change is a mirrored pair under `Point180` and a one-per-half pair under `BalancedFree`,
//! so both sides keep equal counts.
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use super::graph::{Lot, SectorGraph};
use super::{budget, Budgets, Symmetry, DEPLOY_DEPTH_CELLS, GRID, LEVEL_IN};

/// Lot archetypes (theme-neutral; a kit table picks the look). `Block`: solid mass, walkable roof, blocks sight.
/// `Terrace`: an L-shaped step, the rest of the lot stays ground. `Deck`: open raised platform, sight passes.
/// `Hazard`: flat area hazard, never raised. `Rough`: a flat plot (garden, rubble) that is never raised and gets no piece on it. `Wall`: a cell of the
/// city wall (its 6 in ridge, a 9 in wall tower, a 3 in buttress stair or a level-0 breach), set by the wall stage and never by a lot. `Roofed`: an intact house -
/// level-0 solid ground (nobody stands on a roof, sight stops), the core's `CONTAINER` class; ruined houses are `Block` / `Terrace` / `Deck`. `Tower`: a tall scenery tower (towers plan
/// T1) - level 0 in the layout, solid like a house and `TOWER_IN` high to the core: nobody stands in or on it, no ladder touches it, sight stops at it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LotKind { Street, Block, Terrace, Deck, Hazard, Rough, Wall, Roofed, Tower }

/// One lattice cell. `level` 0/1/2/3 = 0/3/6/9 in; `deploy` 1/2 = the player whose band it is, 0 = neither.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cell { pub x: usize, pub z: usize, pub deploy: u8, pub street: bool, pub lot_id: u16, pub lot_kind: LotKind, pub level: u8 }

pub fn stack(seed: i64, g: &SectorGraph, b: &Budgets) -> (Vec<Lot>, Vec<Cell>) {
    let (nx, nz, sym, mut rng, mut lots) = (g.nx, g.nz, g.symmetry, GodotRng::new(seed), g.lots.clone());
    let mut cells: Vec<Cell> = (0..nx * nz).map(|i| {
        let (x, z) = (i % nx, i / nx);
        let deploy = if z < DEPLOY_DEPTH_CELLS { 1 } else if z >= nz - DEPLOY_DEPTH_CELLS { 2 } else { 0 };
        Cell { x, z, deploy, street: g.is_street[i], lot_id: 0, lot_kind: if g.tower[i] { LotKind::Tower } else { LotKind::Street }, level: 0 }
    }).collect();
    let (mut hazards, pool) = (0, b.lot_pool);
    for p in 0..lots.len() / 2 {
        let in_deploy = [2 * p, 2 * p + 1].iter().any(|&i| lots[i].z < DEPLOY_DEPTH_CELLS || lots[i].z + lots[i].h > nz - DEPLOY_DEPTH_CELLS);
        let garden = lots[2 * p].w * lots[2 * p].h <= b.garden_area;
        let mut kind = match p { _ if garden => LotKind::Rough, 0 => LotKind::Block, 1 => LotKind::Terrace, 2 => LotKind::Deck, _ => pool[rng.randi_range(0, pool.len() as i64 - 1) as usize] };
        // an intact house: a share of the building lots (never the first pair, the tower site) is roofed instead of raised
        if b.intact_percent > 0 && p > 0 && matches!(kind, LotKind::Block | LotKind::Terrace | LotKind::Deck) && rng.randi_range(0, 99) < b.intact_percent as i64 { kind = LotKind::Roofed; }
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
        let grow = |i: usize, cs: &[Cell]| cs[i].level == 0 && !cs[i].street && !matches!(cs[i].lot_kind, LotKind::Hazard | LotKind::Rough | LotKind::Roofed | LotKind::Tower) && neighbours(i).any(|j| cs[j].level >= 1);
        let Some((a, b)) = paired(&cells, sym, &mut rng, grow, |_| 0).into_iter().next() else { break };
        cells[a].level = 1; cells[b].level = 1;
    }
    while raised(&cells) > max_r {
        let shave = |i: usize, cs: &[Cell]| cs[i].level == 1;
        let Some((a, b)) = paired(&cells, sym, &mut rng, shave, |c| u8::from(c.lot_kind == LotKind::Block)).into_iter().next() else { break };
        cells[a].level = 0; cells[b].level = 0;
    }
    if b.tower_side == 2 { raise_towers_2x2(&mut cells, sym, &mut rng, b.tower_pairs, b.tower_slender); }
    if g.wall.iter().any(|&w| w) { raise_wall(&mut cells, &g.wall, &mut rng); }
    // Level 2: raised cells outside the deployment bands. A pair is kept only if the board stays one piece when every
    // step of at most one level counts as a possible way up, so no island of level 2 is ever cut off.
    let (min_h, max_h) = budget(b.lift);
    let (lo, hi) = ((min_h + 1) & !1, max_h & !1);
    let target = lo + 2 * rng.randi_range(0, ((hi - lo) / 2) as i64) as usize;
    let lift = |i: usize, cs: &[Cell]| cs[i].level == 1 && cs[i].deploy == 0 && cs[i].lot_kind != LotKind::Wall;
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
    if b.rows && sym == Symmetry::Point180 { cut_lanes(&mut lots, &mut cells, &mut rng); infill_houses(&mut lots, &mut cells, &mut rng, b.infill_pairs); if b.half_roofs { half_roof_slabs(&mut cells, &mut rng); } }
    (lots, cells)
}

/// The rows leave bare interior: while a full row or column is open ground (level 0, no intact house), put a small intact house (2 x 1 / 1 x 2 / 2 x 2, a half-turn pair, solid, no
/// ladders) on free ground, the one that cuts the most open lines first, a street at its door breaking ties. A house that would cut the walkable board in two is skipped.
fn cut_lanes(lots: &mut Vec<Lot>, cells: &mut [Cell], rng: &mut GodotRng) {
    let open = |cs: &[Cell], i: usize| cs[i].level == 0 && !matches!(cs[i].lot_kind, LotKind::Roofed | LotKind::Tower);
    let free = |cs: &[Cell], i: usize| cs[i].level == 0 && !cs[i].street && cs[i].lot_id == 0 && cs[i].lot_kind == LotKind::Street;
    for _ in 0..8 {
        let rows: Vec<bool> = (0..GRID).map(|z| (0..GRID).all(|x| open(cells, z * GRID + x))).collect();
        let cols: Vec<bool> = (0..GRID).map(|x| (0..GRID).all(|z| open(cells, z * GRID + x))).collect();
        if !rows.iter().chain(&cols).any(|&o| o) { return; }
        let mut cands: Vec<(usize, (usize, usize, usize, usize))> = Vec::new();
        for &(w, h) in &[(2usize, 1usize), (1, 2), (2, 2)] { for z0 in 0..=GRID - h { for x0 in 0..=GRID - w {
            let (mx, mz) = (GRID - x0 - w, GRID - z0 - h);
            let cells_of = |x: usize, z: usize| (z..z + h).flat_map(move |zz| (x..x + w).map(move |xx| zz * GRID + xx));
            let apart = x0 + w < mx || mx + w < x0 || z0 + h < mz || mz + h < z0;
            let alone = |i: usize| neighbours(i).all(|j| cells[j].lot_id == 0 || cells[j].lot_kind == LotKind::Rough);   // a lane cutter never joins a row (no party wall): it stands alone
            if !apart || !cells_of(x0, z0).chain(cells_of(mx, mz)).all(|i| free(cells, i) && alone(i)) { continue; }
            let cut = [(x0, z0), (mx, mz)].iter().map(|&(x, z)| (z..z + h).filter(|&zz| rows[zz]).count() + (x..x + w).filter(|&xx| cols[xx]).count()).sum::<usize>();
            let door = cells_of(x0, z0).any(|i| neighbours(i).any(|j| cells[j].street));
            if cut > 0 { cands.push((2 * cut + usize::from(door), (x0, z0, w, h))); }
        }}}
        shuffle(&mut cands, rng);
        cands.sort_by_key(|c| usize::MAX - c.0);
        let mut placed = false;
        for (_, (x0, z0, w, h)) in cands {
            let (mx, mz) = (GRID - x0 - w, GRID - z0 - h);
            let snap = cells.to_vec();
            let id = lots.len() as u16 + 1;
            for (k, (x, z)) in [(x0, z0), (mx, mz)].into_iter().enumerate() {
                for zz in z..z + h { for xx in x..x + w { let c = &mut cells[zz * GRID + xx]; (c.lot_id, c.lot_kind) = (id + k as u16, LotKind::Roofed); } }
            }
            if one_piece_without(cells, LotKind::Roofed) {
                for (k, (x, z)) in [(x0, z0), (mx, mz)].into_iter().enumerate() { lots.push(Lot { id: id + k as u16, x, z, w, h, sector: [(x + w / 2) / 4, (z + h / 2) / 4], kind: LotKind::Roofed }); }
                placed = true;
                break;
            }
            cells.clone_from_slice(&snap);
        }
        if !placed { return; }
    }
}

/// Up to `pairs` half-turn pairs of small intact houses (2 x 1 / 1 x 2 / 2 x 2) on free earth between the deployment bands (roofs plan K3: fewer filler slabs, more houses).
/// A candidate needs a street cell at its door and may not make a row (houses joined by party walls) longer than 4; the one that newly stops the fewest
/// opening-turn sight lines comes first. A pair is kept only if the walkable board stays one piece.
fn infill_houses(lots: &mut Vec<Lot>, cells: &mut [Cell], rng: &mut GodotRng, pairs: usize) {
    let free = |cs: &[Cell], i: usize| cs[i].level == 0 && !cs[i].street && cs[i].lot_id == 0 && cs[i].lot_kind == LotKind::Street && cs[i].deploy == 0;
    for _ in 0..pairs {
        let low = open_rays_low(cells);
        let mut cands: Vec<(u32, (usize, usize, usize, usize))> = Vec::new();
        for &(w, h) in &[(2usize, 1usize), (1, 2), (2, 2)] { for z0 in 0..=GRID - h { for x0 in 0..=GRID - w {
            let (mx, mz) = (GRID - x0 - w, GRID - z0 - h);
            let cells_of = |x: usize, z: usize| (z..z + h).flat_map(move |zz| (x..x + w).map(move |xx| zz * GRID + xx));
            let apart = x0 + w < mx || mx + w < x0 || z0 + h < mz || mz + h < z0;
            if !apart || !cells_of(x0, z0).chain(cells_of(mx, mz)).all(|i| free(cells, i)) || !cells_of(x0, z0).any(|i| neighbours(i).any(|j| cells[j].street)) { continue; }
            let hit = cells_of(x0, z0).chain(cells_of(mx, mz)).fold([0u64; 4], |m, i| [m[0] | low[i][0], m[1] | low[i][1], m[2] | low[i][2], m[3] | low[i][3]]);
            cands.push((hit.iter().map(|b| b.count_ones()).sum(), (x0, z0, w, h)));
        }}}
        shuffle(&mut cands, rng);
        cands.sort_by_key(|c| c.0);
        let mut placed = false;
        for (_, (x0, z0, w, h)) in cands {
            let (mx, mz) = (GRID - x0 - w, GRID - z0 - h);
            let (snap, id) = (cells.to_vec(), lots.len() as u16 + 1);
            for (k, (x, z)) in [(x0, z0), (mx, mz)].into_iter().enumerate() {
                for zz in z..z + h { for xx in x..x + w { let c = &mut cells[zz * GRID + xx]; (c.lot_id, c.lot_kind) = (id + k as u16, LotKind::Roofed); } }
            }
            if row_of(cells, id) <= 4 && row_of(cells, id + 1) <= 4 && one_piece_without(cells, LotKind::Roofed) {
                for (k, (x, z)) in [(x0, z0), (mx, mz)].into_iter().enumerate() { lots.push(Lot { id: id + k as u16, x, z, w, h, sector: [(x + w / 2) / 4, (z + h / 2) / 4], kind: LotKind::Roofed }); }
                placed = true;
                break;
            }
            cells.clone_from_slice(&snap);
        }
        if !placed { return; }
    }
}

/// Per cell, the opening-turn sight lines (row 1 against row 14, every column pair, eyes 1.25 in over their floor) that nothing stops yet and that pass
/// that level-0 cell lower than a house (2.5 in): a house there would stop them. Integer hundredths of an inch, 99 samples per line.
fn open_rays_low(cells: &[Cell]) -> Vec<[u64; 4]> {
    let top = |i: usize| { let f = i64::from(LEVEL_IN[usize::from(cells[i].level)]) * 100; match cells[i].lot_kind { LotKind::Roofed => f.max(250), LotKind::Tower => 1200, _ => f } };
    let mut low = vec![[0u64; 4]; cells.len()];
    for r in 0..GRID * GRID {
        let ((xa, za), (xb, zb)) = (((r / GRID) as i64 * 300 + 150, 450), ((r % GRID) as i64 * 300 + 150, 14 * 300 + 150));
        let (ya, yb) = (top(GRID + r / GRID) + 125, top(14 * GRID + r % GRID) + 125);
        let mut hit = Vec::new();
        let stopped = (1..100).any(|k| {
            let (i, y) = (((za + (zb - za) * k / 100) / 300) as usize * GRID + ((xa + (xb - xa) * k / 100) / 300) as usize, ya + (yb - ya) * k / 100);
            if cells[i].level == 0 && !matches!(cells[i].lot_kind, LotKind::Roofed | LotKind::Tower) && y < 250 { hit.push(i); }
            top(i) > y
        });
        if !stopped { for i in hit { low[i][r / 64] |= 1 << (r % 64); } }
    }
    low
}

/// Houses (lots of a house kind) joined to lot `id` by party walls, `id` included: the row it stands in.
fn row_of(cells: &[Cell], id: u16) -> usize {
    let (mut ids, mut stack) = (vec![id], vec![id]);
    while let Some(a) = stack.pop() {
        for i in (0..cells.len()).filter(|&i| cells[i].lot_id == a) { for j in neighbours(i) {
            let c = &cells[j];
            if c.lot_id != 0 && matches!(c.lot_kind, LotKind::Block | LotKind::Terrace | LotKind::Deck | LotKind::Roofed) && !ids.contains(&c.lot_id) { ids.push(c.lot_id); stack.push(c.lot_id); }
        }}
    }
    ids.len()
}

/// Halfroofs plan H1: a filler slab (a connected group of raised cells on free earth, no lot) keeps half its 3 in floor; the first half of its 3 in cells along the
/// group's longer side (which end: rng) and their half-turn twins become a half roof - `Roofed`, level 0, solid like a house. A group that holds its own twin is left
/// alone; a cut that would split the walkable board tries the other end, then nothing.
fn half_roof_slabs(cells: &mut [Cell], rng: &mut GodotRng) {
    let filler = |c: &Cell| c.level >= 1 && c.lot_id == 0 && c.lot_kind == LotKind::Street;
    let mut seen = vec![false; cells.len()];
    for s in 0..cells.len() / 2 {
        if seen[s] || !filler(&cells[s]) { continue; }
        let (mut group, mut stack) = (vec![s], vec![s]);
        seen[s] = true;
        while let Some(i) = stack.pop() { for j in neighbours(i) { if !seen[j] && filler(&cells[j]) { seen[j] = true; group.push(j); stack.push(j); } } }
        for &i in &group { seen[mirror(i)] = true; }
        if group.iter().any(|&i| group.contains(&mirror(i))) { continue; }
        let (xs, zs) = (group.iter().map(|&i| i % GRID), group.iter().map(|&i| i / GRID));
        let along_x = xs.clone().max().unwrap() - xs.min().unwrap() >= zs.clone().max().unwrap() - zs.min().unwrap();
        let mut low: Vec<usize> = group.iter().copied().filter(|&i| cells[i].level == 1).collect();
        if low.len() < 2 { continue; }
        low.sort_by_key(|&i| if along_x { (i % GRID, i / GRID) } else { (i / GRID, i % GRID) });
        let half = low.len() / 2;
        let first = rng.randi_range(0, 1) == 0;
        for end in [first, !first] {
            let cut: Vec<usize> = if end { low[..half].to_vec() } else { low[low.len() - half..].to_vec() };
            let cut: Vec<usize> = cut.iter().copied().filter(|&i| neighbours(i).any(|j| cells[j].level == 1 && group.contains(&j) && !cut.contains(&j))).collect();   // a half roof always leans on 3 in floor it keeps
            let snap = cells.to_vec();
            for &i in &cut { for j in [i, mirror(i)] { (cells[j].lot_kind, cells[j].level) = (LotKind::Roofed, 0); } }
            if one_piece_without(cells, LotKind::Roofed) { break; }
            cells.clone_from_slice(&snap);
        }
    }
}

/// [`one_piece`] over the cells that are not `skip` (solid houses are no ground).
fn one_piece_without(cells: &[Cell], skip: LotKind) -> bool {
    let Some(start) = (0..cells.len()).find(|&i| cells[i].lot_kind != skip) else { return true };
    let (mut seen, mut stack) = (vec![false; cells.len()], vec![start]);
    seen[start] = true;
    while let Some(i) = stack.pop() {
        for j in neighbours(i) { if !seen[j] && cells[j].lot_kind != skip && cells[i].level.abs_diff(cells[j].level) <= 1 { seen[j] = true; stack.push(j); } }
    }
    (0..cells.len()).all(|i| seen[i] || cells[i].lot_kind == skip)
}

/// The city wall. The reserved cells rise to level 2 (lot kind `Wall`); the first and last cell of each run of two or more become level-3 wall
/// towers; one inner cell is a breach (level 0, kind `Wall`: rubble); and a level-1 buttress stands beside every run (the way up for the ladders), all done
/// for the west twin and mirrored, so the board stays a half turn. If the result is not one piece the wall is dropped (the validator rejects the board).
fn raise_wall(cells: &mut [Cell], wall: &[bool], rng: &mut GodotRng) {
    let snap = cells.to_vec();
    let col: Vec<usize> = (0..GRID * GRID).filter(|&i| wall[i] && i % GRID < GRID / 2).collect();   // the west twin, top to bottom
    let set = |cells: &mut [Cell], i: usize, level: u8, kind: LotKind| for j in [i, mirror(i)] { cells[j].level = level; cells[j].lot_kind = kind; };
    // inside a deployment band the wall is a ruined low wall (3 in, cover, no towers): nobody gets plunging fire into a deployment zone from it
    for &i in &col { set(cells, i, if cells[i].deploy == 0 { 2 } else { 1 }, LotKind::Wall); }
    let inner: Vec<usize> = col.iter().copied().filter(|&i| cells[i].deploy == 0 && i >= GRID && col.contains(&(i - GRID)) && col.contains(&(i + GRID))).collect();
    if !inner.is_empty() { set(cells, inner[rng.randi_range(0, inner.len() as i64 - 1) as usize], 0, LotKind::Wall); }
    // runs of wall cells (the walkway); a run of two has a wall tower at one end, a run of three or more at both, and every run gets one buttress on free ground beside a
    // level-2 cell, nearest the run's middle first (a tower is 9 in: a 3 in buttress cannot reach it)
    let mut runs: Vec<Vec<usize>> = Vec::new();
    let mut by_column = col.clone();
    by_column.sort_by_key(|&i| (i % GRID, i / GRID));   // column by column: a kinked wall's two columns are separate runs (row order interleaved them and cut runs short)
    for &i in &by_column { if cells[i].lot_kind == LotKind::Wall && cells[i].level == 2 { if runs.last().is_some_and(|r| r.last().is_some_and(|&l| l + GRID == i)) { runs.last_mut().expect("a run").push(i); } else { runs.push(vec![i]); } } }
    for run in runs {
        // one wall tower per run (silhouette round: a tower at both ends of every run made the wall a row of keeps), at the end nearer the board's middle row
        let mid = |i: usize| (2 * (i / GRID)).abs_diff(GRID - 1);
        let towers = match run.len() { 0 | 1 => Vec::new(), n => vec![if mid(run[n - 1]) < mid(run[0]) { run[n - 1] } else { run[0] }] };
        for &i in &towers { set(cells, i, 3, LotKind::Wall); }
        let mut by_middle: Vec<usize> = run.iter().copied().filter(|i| !towers.contains(i)).collect();
        by_middle.sort_by_key(|&i| i.abs_diff(run[run.len() / 2]));
        let free = |cells: &[Cell], j: usize| cells[j].level == 0 && !cells[j].street && cells[j].lot_kind == LotKind::Street && !wall[j] && cells[j].deploy == 0;
        if let Some(j) = by_middle.iter().flat_map(|&i| [i + 1, i - 1]).find(|&j| free(cells, j) && free(cells, mirror(j))) { set(cells, j, 1, LotKind::Wall); }
    }
    if !one_piece(cells) { cells.clone_from_slice(&snap); }
}

/// Town towers, raised before the level-2 lift: a 2 x 2 block (or, `slender`, a 2 x 1 / 1 x 2 one) of level-1 cells outside the bands rises to level 3, with one level-1 cell beside
/// it lifted to level 2 (the ladder up), as mirrored pairs; the board must stay one piece. The block with the most lower neighbours goes first (the tallest sheer faces). The level-2
/// lift then runs on what is left.
fn raise_towers_2x2(cells: &mut [Cell], sym: Symmetry, rng: &mut GodotRng, pairs: (usize, usize), slender: bool) {
    let shapes: &[(usize, usize)] = if slender { &[(2, 1), (1, 2)] } else { &[(2, 2)] };
    let block = |o: usize, (w, h): (usize, usize)| (0..h).flat_map(move |dz| (0..w).map(move |dx| o + dz * GRID + dx)).collect::<Vec<_>>();
    for _ in 0..rng.randi_range(pairs.0 as i64, pairs.1 as i64) {
        let snap = cells.to_vec();
        let around = |b: &[usize]| b.iter().flat_map(|&i| neighbours(i)).filter(|j| !b.contains(j)).collect::<Vec<_>>();
        let step = |b: &[usize]| around(b).into_iter().find(|&j| snap[j].level == 1 && snap[j].deploy == 0);   // the cell that becomes the 6 in step
        let fits = |o: usize, (w, h): (usize, usize)| o % GRID + w <= GRID && o / GRID + h <= GRID;
        let ok = |b: &[usize]| b.iter().all(|&i| snap[i].level == 1 && snap[i].deploy == 0) && step(b).is_some();
        let lower = |b: &[usize]| around(b).iter().filter(|&&j| snap[j].level == 0).count();
        let mut cand: Vec<(Vec<usize>, Vec<usize>)> = Vec::new();
        for &shape in shapes {
            if sym == Symmetry::Point180 {
                // the half-turn image of a block is the block of the mirrored cells
                for o in (0..GRID * GRID).filter(|&o| fits(o, shape)) {
                    let a = block(o, shape);
                    let t: Vec<usize> = a.iter().map(|&i| mirror(i)).collect();
                    if a[0] < t[0] && ok(&a) && ok(&t) && !a.iter().any(|i| t.contains(i)) { cand.push((a, t)); }
                }
            } else {
                let (mut a, mut c): (Vec<_>, Vec<_>) = ((0..GRID * GRID).filter(|&o| fits(o, shape) && o / GRID + shape.1 < GRID / 2 + 1 && ok(&block(o, shape))).collect(), (0..GRID * GRID).filter(|&o| fits(o, shape) && o / GRID >= GRID / 2 && ok(&block(o, shape))).collect());
                shuffle(&mut a, rng); shuffle(&mut c, rng);
                cand.extend(a.into_iter().zip(c).map(|(x, y)| (block(x, shape), block(y, shape))));
            }
        }
        shuffle(&mut cand, rng);
        cand.sort_by_key(|(a, t)| usize::MAX - lower(a) - lower(t));
        for (a, t) in cand {
            let s1 = step(&a).expect("ok() found a step");
            let steps = [s1, if sym == Symmetry::Point180 { mirror(s1) } else { step(&t).expect("ok() found a step") }];   // a half-turn twin has the half-turn step
            if steps.iter().any(|j| a.contains(j) || t.contains(j)) { continue; }
            for &i in a.iter().chain(&t) { cells[i].level = 3; }
            for &j in &steps { cells[j].level = 2; }
            if one_piece(cells) { break } else { for &i in a.iter().chain(&t).chain(&steps) { cells[i].level = snap[i].level; } }
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
