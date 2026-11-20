//! Seeded board generator, heightfield stage (Firefight / AoF Skirmish, 4 x 4 ft table = 48 x 48 in).
//! Pure data: nothing calls this module yet and no rule code reads it.
//!
//! The board is a 16 x 16 lattice of 3-inch cells. Every cell carries ONE level (0, 3, 6 or 9 in above the table):
//! a heightfield, so no walkable surface lies above another and `y = f(x, z)` stays true. Stages, each with its own
//! seed stream (`seed ^ SALT`): [`graph`] streets and lots -> [`levels`] heights -> [`connect`] ladders (3 in
//! rise, one level each; no stairs). A tier edge without a ladder is a cliff. All maths is integer; floats
//! never appear. A board that misses a budget or a reachability check is dropped and the next sub-seed is tried.
pub mod connect;
pub mod graph;
pub mod levels;

use serde::{Deserialize, Serialize};
pub use connect::{Connector, ConnectorKind};
pub use graph::{Artery, Lot, SectorGraph};
pub use levels::{Cell, LotKind};

pub const BOARD_IN: [u32; 2] = [48, 48];
pub const CELL_IN: u32 = 3;
pub const GRID: usize = 16;
/// Deployment bands: 12 in deep at each end, so the zones are 24 in apart.
pub const DEPLOY_DEPTH_CELLS: usize = 4;
pub const LEVEL_IN: [u32; 4] = [0, 3, 6, 9];
/// Share of cells at level >= 1 (per mille, inclusive) and at level >= 2. Tuning knobs, not rules.
pub const RAISED_PERMILLE: (usize, usize) = (280, 360);
pub const HIGH_PERMILLE: (usize, usize) = (80, 150);
/// Mirrored pairs of level-3 cells (9 in towers) per board, inclusive: 2 to 6 cells.
pub const TOWER_PAIRS: (usize, usize) = (1, 3);
pub const MAX_ATTEMPTS: u8 = 16;
const SUBSEED_STEP: i64 = 0x9E37_79B9;
const SALTS: [i64; 3] = [0x5449_4546_0001, 0x5449_4546_0002, 0x5449_4546_0003];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Symmetry { Point180, BalancedFree }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Layout {
    pub seed: i64, pub attempt: u8, pub symmetry: Symmetry, pub board_in: [u32; 2], pub nx: usize, pub nz: usize,
    pub cell_in: u32, pub deploy_depth_cells: usize,
    pub arteries: Vec<Artery>, pub lots: Vec<Lot>, pub cells: Vec<Cell>, pub connectors: Vec<Connector>,
}

/// Inclusive cell-count window for a per-mille range on the 256-cell board (min rounded up, max down).
pub fn budget(permille: (usize, usize)) -> (usize, usize) {
    let total = GRID * GRID;
    ((total * permille.0).div_ceil(1000), total * permille.1 / 1000)
}

impl Layout {
    pub fn cell(&self, x: usize, z: usize) -> &Cell { &self.cells[z * self.nx + x] }
    pub fn to_json(&self) -> String { serde_json::to_string(self).expect("layout JSON") }
    /// One char per cell: `3`/`2`/`1` raised, `~` hazard lot, `.` street, `,` other ground.
    pub fn to_ascii(&self) -> String {
        self.cells.chunks(self.nx).map(|row| row.iter().map(|c| match (c.level, c.lot_kind, c.street) {
            (3, _, _) => '3', (2, _, _) => '2', (1, _, _) => '1', (_, LotKind::Hazard, _) => '~', (_, _, true) => '.', _ => ',',
        }).chain(Some('\n')).collect::<String>()).collect()
    }
    pub fn raised(&self) -> usize { self.cells.iter().filter(|c| c.level >= 1).count() }
    pub fn high(&self) -> usize { self.cells.iter().filter(|c| c.level >= 2).count() }
    pub fn towers(&self) -> usize { self.cells.iter().filter(|c| c.level == 3).count() }
    /// Largest height step between two neighbouring cells, in inches.
    pub fn max_drop_in(&self) -> u32 {
        let lv = |x: usize, z: usize| LEVEL_IN[usize::from(self.cell(x, z).level)];
        let mut m = 0;
        for z in 0..self.nz { for x in 0..self.nx {
            if x + 1 < self.nx { m = m.max(lv(x, z).abs_diff(lv(x + 1, z))); }
            if z + 1 < self.nz { m = m.max(lv(x, z).abs_diff(lv(x, z + 1))); }
        }}
        m
    }
    /// What this board still gets wrong; empty = accepted.
    pub fn problems(&self) -> Vec<&'static str> {
        let mut p = Vec::new();
        let (r, h) = (budget(RAISED_PERMILLE), budget(HIGH_PERMILLE));
        if !(r.0..=r.1).contains(&self.raised()) { p.push("raised area outside its budget"); }
        if !(h.0..=h.1).contains(&self.high()) { p.push("level-2 area outside its budget"); }
        if !(2 * TOWER_PAIRS.0..=2 * TOWER_PAIRS.1).contains(&self.towers()) { p.push("level-3 area outside its budget"); }
        if connect::component_count(&self.cells, &self.connectors) != 1 { p.push("board is not one connected walkable area"); }
        if connect::ascent_shortfall(&self.cells, &self.connectors) > 0 { p.push("an island has fewer ascents than it could have (max 2)"); }
        p
    }
}

/// The board for `seed`: the first sub-seed (attempt 0, 1, ...) whose layout has no [`Layout::problems`].
/// Falls back to the last attempt if none passes, so a caller must still check `problems()`.
pub fn generate(seed: i64, symmetry: Symmetry) -> Layout {
    let mut last = None;
    for attempt in 0..MAX_ATTEMPTS {
        let s = seed.wrapping_add(i64::from(attempt) * SUBSEED_STEP);
        let g = graph::build(s ^ SALTS[0], symmetry);
        let (lots, cells) = levels::stack(s ^ SALTS[1], &g);
        let connectors = connect::wire(s ^ SALTS[2], symmetry, &cells);
        let layout = Layout { seed, attempt, symmetry, board_in: BOARD_IN, nx: g.nx, nz: g.nz, cell_in: CELL_IN,
            deploy_depth_cells: DEPLOY_DEPTH_CELLS, arteries: g.arteries, lots, cells, connectors };
        if layout.problems().is_empty() { return layout; }
        last = Some(layout);
    }
    last.expect("MAX_ATTEMPTS > 0")
}
