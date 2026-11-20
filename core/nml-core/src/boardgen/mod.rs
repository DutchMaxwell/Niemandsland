//! Seeded board generator, heightfield stage (Firefight / AoF Skirmish, 4 x 4 ft table = 48 x 48 in).
//! Pure data: nothing calls this module yet and no rule code reads it.
//!
//! The board is a 16 x 16 lattice of 3-inch cells. Every cell carries ONE level (0, 3, 6 or 9 in above the table):
//! a heightfield, so no walkable surface lies above another and `y = f(x, z)` stays true. Stages, each with its own
//! seed stream (`seed ^ SALT`, plus a theme offset; [`Theme::Deepworks`] is the original board, its offset is 0): [`graph`] streets and lots -> [`levels`] heights -> [`connect`] ladders (3 in
//! rise, one level each; no stairs) -> [`landmarks`] a few mirrored multi-cell pieces. A tier edge without a ladder is a cliff. All maths is integer; floats
//! never appear. A board that misses a budget or a reachability check is dropped and the next sub-seed is tried.
pub mod connect;
pub mod graph;
pub mod landmarks;
pub mod levels;
pub mod plain;

use serde::{Deserialize, Serialize};
pub use connect::{Connector, ConnectorKind};
pub use graph::{Artery, Lot, SectorGraph};
pub use landmarks::{Landmark, LandmarkKind};
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
const SALTS: [i64; 4] = [0x5449_4546_0001, 0x5449_4546_0002, 0x5449_4546_0003, 0x5449_4546_0004];
/// Landmark pieces per board, inclusive: one or two mirrored pairs.
pub const LANDMARK_PIECES: (usize, usize) = (2, 4);
/// Seed-stream offset of the town (XORed into every stage salt); the Deepworks offset is 0, so its boards never move.
const TOWN_SALT: i64 = 0x5254_4F57_4E00;

/// Which board the generator builds. Same stages, same validator, different budgets: a theme is data, never a rule.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Theme { #[default] Deepworks, RuinTown }

/// The windows a theme fits (tuning knobs, not rules): cell shares per mille, mirrored tower pairs, landmark pieces,
/// and the lot kinds the free lots draw from.
#[derive(Debug, Clone, Copy)]
pub struct Budgets {
    pub raised: (usize, usize), pub high: (usize, usize), pub tower_pairs: (usize, usize), pub landmark_pieces: (usize, usize),
    pub lot_pool: &'static [LotKind],
    /// Mirrored lot pairs the graph aims for, the lot footprints (w, h in cells) it draws from at random, and the order it fills gaps in.
    pub lot_pairs: usize, pub lot_shapes: &'static [(usize, usize)], pub lot_fill: &'static [(usize, usize)],
    /// Reject a board with a straight open lane (a full row or column of level-0 cells, no solid piece) from edge to edge: it is a sight corridor.
    pub lane_free: bool,
    /// Sub-seeds tried before the last one is returned as it is (the caller then sees `problems()`).
    pub max_attempts: u8,
}

impl Theme {
    pub fn is_default(&self) -> bool { *self == Self::Deepworks }
    pub fn budgets(self) -> Budgets {
        match self {
            Self::Deepworks => Budgets { raised: RAISED_PERMILLE, high: HIGH_PERMILLE, tower_pairs: TOWER_PAIRS, landmark_pieces: LANDMARK_PIECES,
                lot_pool: &[LotKind::Block, LotKind::Terrace, LotKind::Deck, LotKind::Hazard],
                lot_pairs: 9, lot_shapes: &[(3, 2), (2, 3), (2, 2)], lot_fill: &[(2, 2), (3, 2), (2, 3)], lane_free: false, max_attempts: MAX_ATTEMPTS },
            // First town values (step 6 of the ruin-town plan re-fits them): more raised ground, one tower pair, more terraces.
            Self::RuinTown => Budgets { raised: (300, 400), high: (60, 110), tower_pairs: (1, 1), landmark_pieces: LANDMARK_PIECES,
                lot_pool: &[LotKind::Block, LotKind::Terrace, LotKind::Terrace, LotKind::Deck, LotKind::Hazard],
                lot_pairs: 14, lot_shapes: &[(3, 2), (2, 3), (2, 2), (2, 2), (2, 1), (1, 2)], lot_fill: &[(2, 2), (3, 2), (2, 3), (2, 1), (1, 2)], lane_free: true, max_attempts: 32 },
        }
    }
    fn salt(self) -> i64 { if self.is_default() { 0 } else { TOWN_SALT } }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Symmetry { Point180, BalancedFree }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Layout {
    /// Absent from the JSON for the default theme, so a Deepworks layout serialises exactly as before the field existed.
    #[serde(default, skip_serializing_if = "Theme::is_default")]
    pub theme: Theme,
    pub seed: i64, pub attempt: u8, pub symmetry: Symmetry, pub board_in: [u32; 2], pub nx: usize, pub nz: usize,
    pub cell_in: u32, pub deploy_depth_cells: usize,
    pub arteries: Vec<Artery>, pub lots: Vec<Lot>, pub cells: Vec<Cell>, pub connectors: Vec<Connector>, pub landmarks: Vec<Landmark>,
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
    /// True if a full row or column is open ground (level 0, no solid landmark): a straight lane from edge to edge.
    pub fn has_edge_to_edge_lane(&self) -> bool {
        let solid = landmarks::solid_mask(&self.landmarks);
        let open = |x: usize, z: usize| self.cell(x, z).level == 0 && !solid[z * self.nx + x];
        (0..GRID).any(|a| (0..GRID).all(|k| open(k, a)) || (0..GRID).all(|k| open(a, k)))
    }
    /// What this board still gets wrong; empty = accepted.
    pub fn problems(&self) -> Vec<&'static str> {
        let mut p = Vec::new();
        let b = self.theme.budgets();
        let (r, h) = (budget(b.raised), budget(b.high));
        if !(r.0..=r.1).contains(&self.raised()) { p.push("raised area outside its budget"); }
        if !(h.0..=h.1).contains(&self.high()) { p.push("level-2 area outside its budget"); }
        if !(2 * b.tower_pairs.0..=2 * b.tower_pairs.1).contains(&self.towers()) { p.push("level-3 area outside its budget"); }
        if !(b.landmark_pieces.0..=b.landmark_pieces.1).contains(&self.landmarks.len()) { p.push("landmark count outside its budget"); }
        if self.landmarks.iter().flat_map(Landmark::cells).any(|i| self.connectors.iter().any(|c| usize::from(c.low) == i || usize::from(c.high) == i)) { p.push("a landmark stands on a ladder foot"); }
        if b.lane_free && self.has_edge_to_edge_lane() { p.push("a straight open lane runs from edge to edge"); }
        if connect::component_count(&self.cells, &self.connectors, &landmarks::solid_mask(&self.landmarks)) != 1 { p.push("board is not one connected walkable area"); }
        if connect::ascent_shortfall(&self.cells, &self.connectors) > 0 { p.push("an island has fewer ascents than it could have (max 2)"); }
        p
    }
}

/// The board for `seed`: the first sub-seed (attempt 0, 1, ...) whose layout has no [`Layout::problems`].
/// Falls back to the last attempt if none passes, so a caller must still check `problems()`.
pub fn generate(seed: i64, symmetry: Symmetry) -> Layout { generate_themed(seed, symmetry, Theme::Deepworks) }

/// [`generate`] for a theme: the same stages on the theme's budgets and its own seed streams.
pub fn generate_themed(seed: i64, symmetry: Symmetry, theme: Theme) -> Layout {
    let (b, salt) = (theme.budgets(), theme.salt());
    let mut last = None;
    for attempt in 0..b.max_attempts {
        let s = seed.wrapping_add(i64::from(attempt) * SUBSEED_STEP);
        let g = graph::build(s ^ SALTS[0] ^ salt, symmetry, &b);
        let (lots, mut cells) = levels::stack(s ^ SALTS[1] ^ salt, &g, &b);
        let connectors = connect::wire(s ^ SALTS[2] ^ salt, symmetry, &cells);
        let landmarks = landmarks::place(s ^ SALTS[3] ^ salt, symmetry, &mut cells, &connectors);
        let layout = Layout { theme, seed, attempt, symmetry, board_in: BOARD_IN, nx: g.nx, nz: g.nz, cell_in: CELL_IN,
            deploy_depth_cells: DEPLOY_DEPTH_CELLS, arteries: g.arteries, lots, cells, connectors, landmarks };
        if layout.problems().is_empty() { return layout; }
        last = Some(layout);
    }
    last.expect("max_attempts > 0")
}
