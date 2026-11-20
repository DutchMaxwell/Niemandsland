//! Stage 4: landmarks. A few multi-cell pieces on the finished heightfield, always placed as mirrored pairs (a half turn
//! under `Point180`, one per half and of the same size under `BalancedFree`) so neither side gets the better one. Data
//! only: [`LandmarkKind::terrain_class`] names the terrain class the core already has for the piece, and this stage never
//! changes a level, a ladder or a cost. `TankCluster` and `Crane` (the base cell; the arm is visual only) are solid
//! ground-level pieces, `Sump` is a flat Dangerous pool (it stays level 0, nothing is sunk below the table) and
//! `PumpHouse` marks an ordinary raised block (walkable roof, the rules see no change).
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use crate::terrain::{CONTAINER, DANGEROUS, NONE};
use super::connect::{component_count, Connector};
use super::levels::{shuffle, Cell, LotKind};
use super::{Symmetry, DEPLOY_DEPTH_CELLS, GRID};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum LandmarkKind { TankCluster, PumpHouse, Sump, Crane }

/// `x`, `z`, `w`, `h`: the footprint in cells. `turn`: quarter turns, read only by a crane's (visual) arm.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Landmark { pub kind: LandmarkKind, pub x: usize, pub z: usize, pub w: usize, pub h: usize, pub turn: u8 }

impl LandmarkKind {
    /// The existing core terrain class of the footprint (terrain.rs): a solid sight blocker nobody may stop in (a tank
    /// cluster, a crane base; the core knows only the 2.5 in container, a solid of real height is not a class yet), the
    /// Dangerous class, or none.
    pub fn terrain_class(self) -> i32 { match self { Self::TankCluster | Self::Crane => CONTAINER, Self::Sump => DANGEROUS, Self::PumpHouse => NONE } }
    pub fn is_solid(self) -> bool { matches!(self, Self::TankCluster | Self::Crane) }
    /// Footprint sizes (w, h) in cells; a pump house also fits a narrow strip of a raised block.
    fn shapes(self) -> &'static [(usize, usize)] {
        match self { Self::Crane => &[(1, 1)], Self::PumpHouse => &[(2, 2), (3, 2), (2, 3), (2, 1), (1, 2)], _ => &[(2, 2), (3, 2), (2, 3)] }
    }
}

impl Landmark {
    /// Cell indices (`z * 16 + x`) of the footprint.
    pub fn cells(&self) -> impl Iterator<Item = usize> + '_ { (0..self.h).flat_map(move |dz| (0..self.w).map(move |dx| (self.z + dz) * GRID + self.x + dx)) }
}

/// The cells no walker may enter: every footprint of a solid kind.
pub fn solid_mask(landmarks: &[Landmark]) -> Vec<bool> {
    let mut solid = vec![false; GRID * GRID];
    for l in landmarks.iter().filter(|l| l.kind.is_solid()) { l.cells().for_each(|i| solid[i] = true); }
    solid
}

/// One or two mirrored pairs of different kinds (fewer if nothing fits, so the board misses its budget and is retried).
/// Pieces stay out of the deployment bands, off ladder feet and a cell apart; a solid piece never cuts the walkable board.
pub fn place(seed: i64, sym: Symmetry, cells: &mut [Cell], conns: &[Connector]) -> Vec<Landmark> {
    let mut rng = GodotRng::new(seed);
    let mut kinds = [LandmarkKind::TankCluster, LandmarkKind::PumpHouse, LandmarkKind::Sump, LandmarkKind::Crane];
    shuffle(&mut kinds, &mut rng);
    let (pairs, mut out, mut taken) = (1 + rng.randi_range(0, 1) as usize, Vec::<Landmark>::new(), vec![false; cells.len()]);
    for kind in kinds {
        if out.len() >= 2 * pairs { break; }
        let (firsts, seconds) = (rects(kind, true, &mut rng), rects(kind, false, &mut rng));
        'pair: for (x, z, w, h) in firsts {
            let a = Landmark { kind, x, z, w, h, turn: rng.randi_range(0, 3) as u8 };
            if !fits(&a, cells, &taken, conns) { continue; }
            let twins: Vec<Landmark> = if sym == Symmetry::Point180 { vec![Landmark { x: GRID - x - w, z: GRID - z - h, turn: (a.turn + 2) % 4, ..a }] }
                else { seconds.iter().filter(|s| s.2 * s.3 == w * h).map(|&(x, z, w, h)| Landmark { x, z, w, h, turn: rng.randi_range(0, 3) as u8, ..a }).collect() };
            for b in twins {
                let apart = b.cells().all(|i| !a.cells().any(|j| i == j));
                let all: Vec<Landmark> = out.iter().copied().chain([a, b]).collect();
                if apart && fits(&b, cells, &taken, conns) && component_count(cells, conns, &solid_mask(&all)) == 1 {
                    for l in [a, b] { claim(&l, cells, &mut taken); }
                    out.extend([a, b]);
                    break 'pair;
                }
            }
        }
    }
    out
}

/// Every footprint of `kind` inside one half of the board and outside the deployment bands, shuffled.
fn rects(kind: LandmarkKind, top: bool, rng: &mut GodotRng) -> Vec<(usize, usize, usize, usize)> {
    let mut v: Vec<_> = kind.shapes().iter().flat_map(|&(w, h)| (DEPLOY_DEPTH_CELLS..=GRID - DEPLOY_DEPTH_CELLS - h)
        .filter(move |&z| (z + h <= GRID / 2) == top).flat_map(move |z| (0..=GRID - w).map(move |x| (x, z, w, h)))).collect();
    shuffle(&mut v, rng);
    v
}

/// Free of earlier pieces, outside the bands, off ladder feet, and the right ground: a pump house needs one raised level
/// (1 or 2) under all of it, every other kind needs open level-0 ground that is no street and no hazard.
fn fits(l: &Landmark, cells: &[Cell], taken: &[bool], conns: &[Connector]) -> bool {
    let level = cells[l.z * GRID + l.x].level;
    l.cells().all(|i| { let c = &cells[i]; !taken[i] && c.deploy == 0 && !conns.iter().any(|k| usize::from(k.low) == i || usize::from(k.high) == i)
        && if l.kind == LandmarkKind::PumpHouse { (1..=2).contains(&level) && c.level == level } else { c.level == 0 && !c.street && c.lot_kind != LotKind::Hazard } })
}

/// Keep later pieces a cell away; a sump turns its ground into hazard ground.
fn claim(l: &Landmark, cells: &mut [Cell], taken: &mut [bool]) {
    for i in l.cells() {
        if l.kind == LandmarkKind::Sump { cells[i].lot_kind = LotKind::Hazard; }
        let (x, z) = (i % GRID, i / GRID);
        for j in (z.saturating_sub(1)..=(z + 1).min(GRID - 1)).flat_map(|zz| (x.saturating_sub(1)..=(x + 1).min(GRID - 1)).map(move |xx| zz * GRID + xx)) { taken[j] = true; }
    }
}
