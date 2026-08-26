//! NML-1073 M4-2 — `MovementPlanner.theta_star` / `_theta_star_b` /
//! `_theta_reconstruct` / `_cell_before` (movement_planner.gd:1325-1452), a
//! LITERAL transcription.
//!
//! Everything the GDScript does load-bearingly is kept, deliberately, including
//! the parts a textbook would call wrong:
//!
//!   * THE OPEN LIST IS A PLAIN `Vec`, LINEARLY SCANNED for min-f
//!     (movement_planner.gd:1377-1384). A `BinaryHeap` cannot reproduce it: the
//!     scan's acceptance rule is `f < best_f - EPS` OR (`|f - best_f| <= EPS`
//!     AND `_cell_before(c, open[best_i])`), i.e. near-ties are broken by the
//!     WORLD-FRAME CELL ORDER against the current best, not by insertion order
//!     and not by a total order over f alone. Change it and the paths move.
//!   * `THETA_DIAG`'s ORDER (movement_planner.gd:72-73) decides which of two
//!     equal-cost parents a node keeps, because the relaxation only replaces an
//!     existing `g` when the new one is cheaper BY MORE THAN EPS
//!     (movement_planner.gd:1416) — first neighbour wins every near-tie.
//!   * `guard = min(nx*ny*4, fast_planner_guard)` (:1370-1372). The shipped
//!     arena value is 320, so recorded searches are TRUNCATED and come back
//!     through `reach_closest`. That truncation is part of the contract; raising
//!     the guard is a behaviour change, not a port (see the M4 recon, §F).
//!
//! PRECISION. `g`, every cost and every `f` are GDScript `float` = f64;
//! positions are `Vector2` = f32. `distance_to` therefore computes in f32 and
//! promotes on the way out, exactly as `geom2` documents.

use std::collections::{HashMap, HashSet};

use super::cost::{cspace_blocked, segment_cost, step_blocked, terrain_cost_at, Grid, StepOpts, Wall};
use super::geom2::{distance_to, to_f32, V2};
use super::{cell_of, EPS, FAST_PLANNER_GUARD, PLAN_CELL_IN, THETA_DIAG};

/// A `Vector2i` grid cell.
pub type Cell = (i32, i32);

/// `MovementPlanner.board_extents` — movement_planner.gd:471. `board_y_in` is
/// `opts["board_y_in"]`; 0 or absent means "square, same as X" (#215).
#[inline]
pub fn board_extents(board_in: f64, board_y_in: f64) -> V2 {
    to_f32([board_in, if board_y_in > EPS { board_y_in } else { board_in }])
}

/// `MovementPlanner._cell_before` — movement_planner.gd:1321. The world-frame
/// canonical cell order (smaller x, then y) that breaks every open-list near-tie.
#[inline]
pub fn cell_before(a: Cell, b: Cell) -> bool {
    a.0 < b.0 || (a.0 == b.0 && a.1 < b.1)
}

/// `MovementPlanner._cell_center_fine` — movement_planner.gd:1252. The
/// arithmetic runs in f64 (`float(cell.x) + 0.5`, times the `float` constant)
/// and narrows only when the `Vector2` is constructed.
#[inline]
pub fn cell_center_fine(cell: Cell) -> V2 {
    to_f32([
        (cell.0 as f64 + 0.5) * PLAN_CELL_IN,
        (cell.1 as f64 + 0.5) * PLAN_CELL_IN,
    ])
}

/// The two `MovementPlanner` STATIC vars the search reads —
/// `fast_planner` (movement_planner.gd:60) and `fast_planner_guard` (:62).
/// They are statics in GDScript; here they travel as an argument so a test can
/// set them without a global.
#[derive(Clone, Copy, Debug)]
pub struct ThetaCfg {
    /// `MovementPlanner.fast_planner` — true in the arena/self-play driver, and
    /// in the interactive game (main.gd:2269-2275). It caps the guard AND turns
    /// `reach_closest` on for every search.
    pub fast_planner: bool,
    /// `MovementPlanner.fast_planner_guard` — the shipped arena value is 320.
    pub fast_planner_guard: i64,
}

impl Default for ThetaCfg {
    fn default() -> Self {
        ThetaCfg { fast_planner: false, fast_planner_guard: FAST_PLANNER_GUARD }
    }
}

impl ThetaCfg {
    /// The recorded configuration of a corpus header.
    pub fn of(fast_planner: bool, fast_planner_guard: i64) -> Self {
        ThetaCfg { fast_planner, fast_planner_guard }
    }
}

/// The `opts` dictionary `_theta_star_b` reads: the step/cost subset plus the
/// one key that is the search's own — `opts["reach_closest"]`
/// (movement_planner.gd:1374), set by the flow's charge branch (:1114).
#[derive(Clone, Copy, Debug)]
pub struct ThetaOpts<'a> {
    pub step: StepOpts<'a>,
    pub reach_closest: bool,
}

impl<'a> ThetaOpts<'a> {
    pub fn new(step: StepOpts<'a>) -> Self {
        ThetaOpts { step, reach_closest: false }
    }
}

/// DELIBERATE DAMAGE, for the red proofs — every field off is the shipped
/// search, byte for byte. Same convention as `arbitration::ArbBend`.
#[derive(Clone, Copy, Debug, Default)]
pub struct ThetaBend {
    /// RED (a): replace the open list's EPS rule + `_cell_before` tie-break with
    /// a strict `f < best_f` (movement_planner.gd:1382).
    pub strict_open: bool,
    /// RED (b): swap two entries of `THETA_DIAG` (movement_planner.gd:72-73).
    pub diag_swap: Option<(usize, usize)>,
}

impl ThetaBend {
    fn diag(&self) -> [(i32, i32); 8] {
        let mut d = THETA_DIAG;
        if let Some((i, j)) = self.diag_swap {
            d.swap(i, j);
        }
        d
    }
}

/// `MovementPlanner.theta_star` — movement_planner.gd:1331. Resolves the board
/// extents and defers to `theta_star_b`.
pub fn theta_star(
    start: V2,
    goal: V2,
    walls: &[Wall],
    grid: &Grid,
    board_in: f64,
    board_y_in: f64,
    opts: &ThetaOpts,
    cfg: ThetaCfg,
) -> Vec<V2> {
    theta_star_b(start, goal, walls, grid, board_extents(board_in, board_y_in), opts, cfg)
}

/// `MovementPlanner._theta_star_b` — movement_planner.gd:1341. The per-axis
/// core: the extents travel as an argument because the flow rebuilds its option
/// dictionaries per model and a board carried in `opts` would be dropped there.
pub fn theta_star_b(
    start: V2,
    goal: V2,
    walls: &[Wall],
    grid: &Grid,
    board: V2,
    opts: &ThetaOpts,
    cfg: ThetaCfg,
) -> Vec<V2> {
    theta_star_bent(start, goal, walls, grid, board, opts, cfg, ThetaBend::default())
}

/// `_theta_star_b` with the red-proof knobs. `ThetaBend::default()` is the
/// shipped search.
pub fn theta_star_bent(
    start: V2,
    goal: V2,
    walls: &[Wall],
    grid: &Grid,
    board: V2,
    opts: &ThetaOpts,
    cfg: ThetaCfg,
    bend: ThetaBend,
) -> Vec<V2> {
    let so = &opts.step;
    // :1347-1352 — early-out ONLY when the straight shot is hard-clear AND
    // carries no soft-cost surcharge; a merely-Dangerous line must still be
    // compared against a detour.
    if !cspace_blocked(start, goal, walls, grid, so)
        && segment_cost(start, goal, grid, so) <= distance_to(start, goal) + EPS
    {
        return vec![start, goal];
    }
    let start_c = cell_of(start, PLAN_CELL_IN);
    let goal_c = cell_of(goal, PLAN_CELL_IN);
    if start_c == goal_c {
        return vec![start, goal];
    }
    // :1360-1361 — the fine planning grid, PER AXIS (#215).
    let nx = ((board[0] as f64 / PLAN_CELL_IN).ceil() as i64).max(1) as i32;
    let ny = ((board[1] as f64 / PLAN_CELL_IN).ceil() as i64).max(1) as i32;

    let mut g: HashMap<Cell, f64> = HashMap::new();
    g.insert(start_c, 0.0);
    let mut parent: HashMap<Cell, Cell> = HashMap::new();
    parent.insert(start_c, start_c);
    let mut pos: HashMap<Cell, V2> = HashMap::new();
    pos.insert(start_c, start);
    let mut open: Vec<Cell> = vec![start_c];
    let mut open_set: HashSet<Cell> = HashSet::new();
    open_set.insert(start_c);
    let mut closed: HashSet<Cell> = HashSet::new();

    let mut guard: i64 = nx as i64 * ny as i64 * 4;
    if cfg.fast_planner {
        guard = guard.min(cfg.fast_planner_guard);
    }
    // :1374 — a bounded search always ends through reach_closest.
    let reach_closest = opts.reach_closest || cfg.fast_planner;
    let mut best_reach: Cell = start_c;
    let mut best_reach_d: f64 = distance_to(start, goal);

    let diag = bend.diag();

    while !open.is_empty() && guard > 0 {
        guard -= 1;
        // :1377-1384 — LINEAR SCAN for min-f. See the module note.
        let mut best_i = 0usize;
        let mut best_f = f64::INFINITY;
        for k in 0..open.len() {
            let c = open[k];
            let f = g[&c] + distance_to(pos[&c], goal);
            let take = if bend.strict_open {
                f < best_f
            } else {
                f < best_f - EPS
                    || ((f - best_f).abs() <= EPS && cell_before(c, open[best_i]))
            };
            if take {
                best_f = f;
                best_i = k;
            }
        }
        let cur = open[best_i];
        if cur == goal_c {
            return theta_reconstruct(&parent, &pos, cur);
        }
        open.remove(best_i);
        open_set.remove(&cur);
        closed.insert(cur);
        let cur_pt = pos[&cur];
        for d in diag {
            let nb: Cell = (cur.0 + d.0, cur.1 + d.1);
            if nb.0 < 0 || nb.0 >= nx || nb.1 < 0 || nb.1 >= ny || closed.contains(&nb) {
                continue;
            }
            let nb_pt = if nb == goal_c { goal } else { cell_center_fine(nb) };
            if nb != goal_c && terrain_cost_at(nb_pt, grid, so).is_infinite() {
                continue;
            }
            if step_blocked(cur_pt, nb_pt, walls, so) {
                continue;
            }
            // :1405-1415 — price BOTH the grid step and the taut parent
            // shortcut with the path integral and take the cheaper, PARENT ON
            // TIES (`via_par <= tentative + EPS`).
            let par = parent[&cur];
            let par_pt = pos[&par];
            let mut from_node = cur;
            let mut tentative = g[&cur] + segment_cost(cur_pt, nb_pt, grid, so);
            if !cspace_blocked(par_pt, nb_pt, walls, grid, so) {
                let via_par = g[&par] + segment_cost(par_pt, nb_pt, grid, so);
                if via_par <= tentative + EPS {
                    from_node = par;
                    tentative = via_par;
                }
            }
            if !g.contains_key(&nb) || tentative < g[&nb] - EPS {
                g.insert(nb, tentative);
                parent.insert(nb, from_node);
                pos.insert(nb, nb_pt);
                if reach_closest {
                    let rd = distance_to(nb_pt, goal);
                    if rd < best_reach_d - EPS {
                        best_reach_d = rd;
                        best_reach = nb;
                    }
                }
                if !open_set.contains(&nb) {
                    open.push(nb);
                    open_set.insert(nb);
                }
            }
        }
    }
    // :1432-1441 — a guard-exhausted search returns its closest-reached stub,
    // unless the straight line is hard-legal AND no dearer than stub+remainder.
    if reach_closest && best_reach != start_c {
        if !cspace_blocked(start, goal, walls, grid, so) {
            let via_stub = g[&best_reach] + segment_cost(pos[&best_reach], goal, grid, so);
            if segment_cost(start, goal, grid, so) <= via_stub + EPS {
                return vec![start, goal];
            }
        }
        return theta_reconstruct(&parent, &pos, best_reach);
    }
    vec![start, goal]
}

/// `MovementPlanner._theta_reconstruct` — movement_planner.gd:1446. Walks the
/// parent chain back to the start (the start is its OWN parent, which ends the
/// walk) and maps every cell to the point the search stored for it.
pub fn theta_reconstruct(
    parent: &HashMap<Cell, Cell>,
    pos: &HashMap<Cell, V2>,
    goal_cell: Cell,
) -> Vec<V2> {
    let mut nodes: Vec<Cell> = vec![goal_cell];
    let mut cur = goal_cell;
    while let Some(&p) = parent.get(&cur) {
        if p == cur {
            break;
        }
        cur = p;
        nodes.push(cur);
    }
    nodes.reverse();
    nodes.iter().map(|n| pos[n]).collect()
}
