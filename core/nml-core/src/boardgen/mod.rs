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

use std::collections::BTreeSet;
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
    pub raised: (usize, usize), pub high: (usize, usize), pub lift: (usize, usize), pub tower_pairs: (usize, usize), pub landmark_pieces: (usize, usize),
    pub lot_pool: &'static [LotKind],
    /// Mirrored lot pairs the graph aims for, the lot footprints (w, h in cells) it draws from at random, and the order it fills gaps in.
    pub lot_pairs: usize, pub lot_shapes: &'static [(usize, usize)], pub lot_fill: &'static [(usize, usize)],
    /// Shapes of the first lot pairs, placed before all others and outside the deployment bands (the town's tower site: a 3 x 2 block).
    pub lot_first: &'static [(usize, usize)],
    /// A lot of at most this many cells is a garden plot (`LotKind::Rough`): flat, never raised. 0 = none (Deepworks).
    pub garden_area: usize,
    /// The fewest garden plots a board must have (0 = no demand).
    pub garden_min: usize,
    /// Size (cells across, cells deep; both even; (0, 0) = none) of the market square kept as street cells about the board centre. Deeper than wide: it is the one open place between the staggered arteries.
    pub plaza: (usize, usize),
    /// Whether the board has a city wall (two half-turn twins of a 6 in ridge with a gate, a breach, towers and a buttress each).
    pub wall: bool,
    /// The landmark kinds drawn as mirrored pairs, how many pairs a board gets (inclusive), and whether the fountain (a `TankCluster`) stands alone
    /// at the board centre, on the market square.
    pub landmark_kinds: &'static [LandmarkKind], pub landmark_pairs: (usize, usize), pub centre_piece: bool,
    /// Whether a pool may also be a 2 x 1 / 1 x 2 well yard (a garden plot is one).
    pub small_pools: bool,
    /// Share (percent) of the building lots that are intact, roofed houses (solid, no standing room on the roof) instead of ruined, walkable ones.
    pub intact_percent: usize,
    /// Reject a board with a straight open lane (a full row or column of level-0 cells, no solid piece) from edge to edge: it is a sight corridor.
    pub lane_free: bool,
    /// Sub-seeds tried before the last one is returned as it is (the caller then sees `problems()`).
    pub max_attempts: u8,
    /// Side of a tower in cells (level-3 blocks): 1 = single cells, 2 = 2 x 2 blocks; `tower_pairs` counts mirrored pairs of towers.
    pub tower_side: usize,
    /// A town tower (`tower_side` 2) is a slender 2 x 1 / 1 x 2 block instead of a 2 x 2 one (silhouette round: a 6 x 6 x 9 in cube read as a block from above).
    pub tower_slender: bool,
    /// Houses stand in rows along the streets (party walls, a passage after each row) instead of scattered with an alley ring round each (`Point180` only).
    pub rows: bool,
    /// The most houses one walkable roof run may touch (0 = no cap): rows must not become a roof highway (a plunging-fire platform across the town).
    pub roof_run_max: usize,
    /// Half-turn pairs of small intact houses put on free earth between the bands after the lots (0 = none): more roofs, fewer filler slabs (roofs plan K3).
    pub infill_pairs: usize,
    /// The fewest intact (roofed) houses a board must have (0 = no demand): every town board shows a skyline (roofs plan K4).
    pub intact_min: usize,
    /// Footprint (cells across, cells deep) of the one half-turn pair of tall scenery towers in the outer two columns between the bands; (0, 0) = none (towers plan T2).
    pub tall_towers: (usize, usize),
}

impl Theme {
    pub fn is_default(&self) -> bool { *self == Self::Deepworks }
    pub fn budgets(self) -> Budgets {
        match self {
            Self::Deepworks => Budgets { raised: RAISED_PERMILLE, high: HIGH_PERMILLE, lift: HIGH_PERMILLE, tower_pairs: TOWER_PAIRS, landmark_pieces: LANDMARK_PIECES,
                lot_pool: &[LotKind::Block, LotKind::Terrace, LotKind::Deck, LotKind::Hazard],
                lot_pairs: 9, lot_shapes: &[(3, 2), (2, 3), (2, 2)], lot_fill: &[(2, 2), (3, 2), (2, 3)], lot_first: &[], garden_area: 0, garden_min: 0, plaza: (0, 0), wall: false,
                landmark_kinds: &[LandmarkKind::TankCluster, LandmarkKind::PumpHouse, LandmarkKind::Sump, LandmarkKind::Crane], landmark_pairs: (1, 2), centre_piece: false, small_pools: false, intact_percent: 0, lane_free: false, max_attempts: MAX_ATTEMPTS, tower_side: 1, tower_slender: false, rows: false, roof_run_max: 0, infill_pairs: 0, intact_min: 0, tall_towers: (0, 0) },
            // Town values: one tower pair, more terraces; the raised minimum is 10 % (roofs plan K2: fewer filler slabs grown on free earth; look plan D-R2 = C 25.11.:
            // 90 % of the building lots intact houses, at least 8 per board - more gables, fewer flat blocks). Look plan round 4, D-R16 = b
            // (maintainer 26.11.): the raised minimum 100 -> 40 permille and 3 infill pairs - the filler slabs grown on free earth go (14.25 -> 3.1 per board).
            Self::RuinTown => Budgets { raised: (40, 460), high: (60, 200), lift: (30, 70), tower_pairs: (1, 1), landmark_pieces: (7, 7),
                lot_pool: &[LotKind::Block, LotKind::Terrace, LotKind::Terrace, LotKind::Deck, LotKind::Hazard],
                lot_pairs: 18, lot_shapes: &[(2, 2), (2, 2), (3, 2), (2, 3), (2, 1), (1, 2), (2, 1), (1, 2), (1, 1)], lot_fill: &[(2, 2), (3, 2), (2, 3), (2, 1), (1, 2)], lot_first: &[(2, 2)], garden_area: 1, garden_min: 4, plaza: (4, 6), wall: true,
                landmark_kinds: &[LandmarkKind::PumpHouse, LandmarkKind::Sump, LandmarkKind::Crane], landmark_pairs: (3, 3), centre_piece: true, small_pools: true, intact_percent: 90, lane_free: true, max_attempts: 64, tower_side: 2, tower_slender: true, rows: true, roof_run_max: 2, infill_pairs: 3, intact_min: 8, tall_towers: (2, 2) },
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
    /// One char per cell: `T` tall tower, `3`/`2`/`1` raised, `~` hazard lot, `"` rough plot, `.` street, `,` other ground.
    pub fn to_ascii(&self) -> String {
        self.cells.chunks(self.nx).map(|row| row.iter().map(|c| match (c.level, c.lot_kind, c.street) {
            (_, LotKind::Tower, _) => 'T', (3, _, _) => '3', (2, _, _) => '2', (1, _, _) => '1', (_, LotKind::Hazard, _) => '~', (_, LotKind::Rough, _) => '"', (_, _, true) => '.', _ => ',',
        }).chain(Some('\n')).collect::<String>()).collect()
    }
    pub fn raised(&self) -> usize { self.cells.iter().filter(|c| c.level >= 1).count() }
    pub fn high(&self) -> usize { self.cells.iter().filter(|c| c.level >= 2).count() }
    pub fn towers(&self) -> usize { self.cells.iter().filter(|c| c.level == 3 && c.lot_kind != LotKind::Wall).count() }
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
        let solid = landmarks::solid_cells(&self.cells, &self.landmarks);
        let open = |x: usize, z: usize| self.cell(x, z).level == 0 && !solid[z * self.nx + x];
        (0..GRID).any(|a| (0..GRID).all(|k| open(k, a)) || (0..GRID).all(|k| open(a, k)))
    }
    /// The most houses one walkable roof run touches: a chain of edge-adjacent raised cells of ONE level (no wall, no intact house), counted in the lots they belong to (bare raised ground
    /// adds none). A height step or an intact house breaks the chain.
    pub fn longest_roof_run(&self) -> usize {
        let walk = |i: usize| self.cells[i].level > 0 && !matches!(self.cells[i].lot_kind, LotKind::Wall | LotKind::Roofed);
        let (mut seen, mut best) = (vec![false; self.cells.len()], 0);
        for s in (0..self.cells.len()).filter(|&i| walk(i)) {
            if seen[s] { continue; }
            let (mut stack, mut lots) = (vec![s], BTreeSet::new());
            seen[s] = true;
            while let Some(i) = stack.pop() {
                if self.cells[i].lot_id != 0 { lots.insert(self.cells[i].lot_id); }
                for j in levels::neighbours(i) { if !seen[j] && walk(j) && self.cells[j].level == self.cells[i].level { seen[j] = true; stack.push(j); } }
            }
            best = best.max(lots.len());
        }
        best
    }
    /// What this board still gets wrong; empty = accepted.
    pub fn problems(&self) -> Vec<&'static str> {
        let mut p = Vec::new();
        let b = self.theme.budgets();
        let (r, h) = (budget(b.raised), budget(b.high));
        if !(r.0..=r.1).contains(&self.raised()) { p.push("raised area outside its budget"); }
        if !(h.0..=h.1).contains(&self.high()) { p.push("level-2 area outside its budget"); }
        let per = if b.tower_slender { b.tower_side } else { b.tower_side.pow(2) };
        if !(2 * per * b.tower_pairs.0..=2 * per * b.tower_pairs.1).contains(&self.towers()) { p.push("level-3 area outside its budget"); }
        if !(b.landmark_pieces.0..=b.landmark_pieces.1).contains(&self.landmarks.len()) { p.push("landmark count outside its budget"); }
        if self.landmarks.iter().flat_map(Landmark::cells).any(|i| self.connectors.iter().any(|c| usize::from(c.low) == i || usize::from(c.high) == i)) { p.push("a landmark stands on a ladder foot"); }
        if self.lots.iter().filter(|l| l.kind == LotKind::Rough).count() < b.garden_min { p.push("too few garden plots"); }
        if self.lots.iter().filter(|l| l.kind == LotKind::Roofed).count() < b.intact_min { p.push("too few intact houses"); }
        if b.wall && !self.cells.iter().any(|c| c.lot_kind == LotKind::Wall && c.level == 2) { p.push("no city wall"); }
        if b.roof_run_max > 0 && self.longest_roof_run() > b.roof_run_max { p.push("a walkable roof run touches more houses than the cap"); }
        if b.lane_free && self.has_edge_to_edge_lane() { p.push("a straight open lane runs from edge to edge"); }
        if connect::component_count(&self.cells, &self.connectors, &landmarks::solid_cells(&self.cells, &self.landmarks)) != 1 { p.push("board is not one connected walkable area"); }
        if connect::ascent_shortfall(&self.cells, &self.connectors) > 0 { p.push("an island has fewer ascents than it could have (max 2)"); }
        p
    }
}

/// The board for `seed`: the first sub-seed (attempt 0, 1, ...) whose layout has no [`Layout::problems`].
/// Falls back to the last attempt if none passes, so a caller must still check `problems()`.
pub fn generate(seed: i64, symmetry: Symmetry) -> Layout { generate_themed(seed, symmetry, Theme::Deepworks) }

/// [`generate`] for a theme: the same stages on the theme's budgets and its own seed streams.
pub fn generate_themed(seed: i64, symmetry: Symmetry, theme: Theme) -> Layout {
    let (mut last, b) = (None, theme.budgets());
    let steps = tower_steps(&b);
    for attempt in 0..b.max_attempts * steps.len() as u8 {
        let layout = generate_attempt(seed, symmetry, theme, attempt);
        let towered = steps[usize::from(attempt / b.max_attempts)].0 == 0 || layout.cells.iter().any(|c| c.lot_kind == LotKind::Tower);
        if towered && layout.problems().is_empty() { return layout; }
        last = Some(layout);
    }
    last.expect("max_attempts > 0")
}

/// One sub-seed of [`generate_themed`], accepted or not: what `attempt` 0, 1, ... would give (the census asks how often the first one is good).
/// The tall tower footprints a board tries in turn (towers plan T2, lead 22.11.): the theme's pair (2 x 2) for `max_attempts` sub-seeds, then a 1 x 2 pair, then
/// none; a theme without towers has one step. Sub-seed `attempt` belongs to step `attempt / max_attempts`, so (seed, attempt) still rebuilds the board.
fn tower_steps(b: &Budgets) -> Vec<(usize, usize)> { if b.tall_towers.0 > 0 { vec![b.tall_towers, (1, 2), (0, 0)] } else { vec![(0, 0)] } }

pub fn generate_attempt(seed: i64, symmetry: Symmetry, theme: Theme, attempt: u8) -> Layout {
    let (b, salt) = (theme.budgets(), theme.salt());
    let towers = tower_steps(&b)[usize::from(attempt / b.max_attempts).min(tower_steps(&b).len() - 1)];
    let b = Budgets { tall_towers: towers, ..b };
    let s = seed.wrapping_add(i64::from(attempt) * SUBSEED_STEP);
    let g = graph::build(s ^ SALTS[0] ^ salt, symmetry, &b);
    let (lots, mut cells) = levels::stack(s ^ SALTS[1] ^ salt, &g, &b);
    let connectors = connect::wire(s ^ SALTS[2] ^ salt, symmetry, &cells);
    let landmarks = landmarks::place(s ^ SALTS[3] ^ salt, symmetry, &mut cells, &connectors, &b);
    Layout { theme, seed, attempt, symmetry, board_in: BOARD_IN, nx: g.nx, nz: g.nz, cell_in: CELL_IN, deploy_depth_cells: DEPLOY_DEPTH_CELLS, arteries: g.arteries, lots, cells, connectors, landmarks }
}
