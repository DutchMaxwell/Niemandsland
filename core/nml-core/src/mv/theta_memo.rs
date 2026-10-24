//! An EXACT, game-scoped memo for the Theta* search (`theta::theta_core`).
//!
//! `theta_core` is a pure function of its arguments (see the input list below) and of compile-time constants; the parent
//! search asks it for the same question over and over inside one game (the same unit, from the same square, to the same
//! slot, with the same no-go discs, every time a position is re-planned). This module answers a repeated question from a
//! stored copy of the answer.
//!
//! INPUTS THAT FORM THE KEY (every one that `theta_core` reads, none is hashed alone - a hit needs full content equality):
//!   * `start`, `goal` (f32 bit patterns)
//!   * `opts.step.zones` (centre f32 bits + radius f64 bits, in order)            -> per entry
//!   * the CONTEXT, interned once and shared by many entries (`Ctx`):
//!     `walls` (f32 bits, in order), `board` (f32 bits), `grid` (cell -> type, as a set of pairs),
//!     `opts.reach_closest`, `opts.step.{ledges, clearance, avoid_cells, avoid_fine, dangerous_debuff, difficult_debuff}`,
//!     `cfg.{fast_planner, fast_planner_guard}`, `bend.{strict_open, diag_swap}`.
//!   * The traced call's pop list is part of the ANSWER (stored and replayed), not of the key. A call whose `trace`
//!     vector is not empty on entry is never memoised (the pop indices are relative to the vector's length).
//!
//! A hash is only an index: an entry is used only when the context is the very same interned `Rc<Ctx>` (content-equal,
//! verified field by field, floats by bit pattern) and start/goal/zones are bit-equal. Float values are never compared
//! with `==` (so -0.0, NaN and 0.0 stay distinct).
//!
//! SCOPE. The memo is thread-local and DISARMED by default. `begin_game()` (called from the Python seam's
//! `Core.set_header`, i.e. whenever a new game header / terrain / knob set is installed) clears every stored entry and arms
//! the memo. Exactness does not depend on that clear (the key holds everything), the clear bounds memory and the lifetime
//! of the data to one game. Entries and stored pops are capped (`MAX_ENTRIES`, `MAX_POPS`, `MAX_CTX`); on overflow the
//! whole memo is dropped (counted in `Stats::clears`) and refilled.

use std::cell::RefCell;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::Write;
use std::rc::Rc;

use super::cost::{CellSet, Grid, Wall, Zone};
use super::geom2::V2;
use super::io::ThetaPop;
use super::theta::{ThetaBend, ThetaCfg, ThetaOpts};

/// Most stored searches per game. The measured peak is about 13k distinct keys per game (96-game tranche).
pub const MAX_ENTRIES: usize = 60_000;
/// Most stored pops (16 bytes each) over all entries.
pub const MAX_POPS: usize = 4_000_000;
/// Most distinct contexts (a context holds a copy of the grid).
pub const MAX_CTX: usize = 512;

#[derive(Default)]
struct IdHasher(u64);
impl Hasher for IdHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(5) ^ u64::from(b)).wrapping_mul(0x517c_c1b7_2722_0a95);
        }
    }
    fn write_u64(&mut self, i: u64) {
        self.0 = i;
    }
    fn finish(&self) -> u64 {
        self.0
    }
}
type IdBuild = BuildHasherDefault<IdHasher>;

/// Counters of the current game (reset by `begin_game`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Stats {
    /// Memoised lookups (calls that got past the early-outs while armed).
    pub calls: u64,
    pub hits: u64,
    pub entries: usize,
    pub pops: usize,
    pub ctxs: usize,
    pub peak_entries: usize,
    pub peak_pops: usize,
    pub peak_ctxs: usize,
    /// Whole-memo drops forced by a cap.
    pub clears: u64,
}

struct Ctx {
    hash: u64,
    blob: Vec<u64>,
    grid: Grid,
    avoid_cells: CellSet,
    avoid_fine: CellSet,
}

/// A stored `ThetaPop` in 16 bytes (parent and open-list size always fit an `i32`; an entry whose pops do not is not stored).
#[derive(Clone, Copy)]
struct PackedPop {
    g: f64,
    parent: i32,
    open: i32,
}

fn pack(pops: &[ThetaPop]) -> Option<Vec<PackedPop>> {
    pops.iter()
        .map(|p| Some(PackedPop { g: p.g, parent: i32::try_from(p.parent).ok()?, open: i32::try_from(p.open).ok()? }))
        .collect()
}

struct Entry {
    ctx: Rc<Ctx>,
    start: [u32; 2],
    goal: [u32; 2],
    zones: Box<[u64]>,
    path: Vec<V2>,
    pops: Vec<PackedPop>,
}

struct Memo {
    armed: bool,
    max_entries: usize,
    max_pops: usize,
    max_ctx: usize,
    ctxs: HashMap<u64, Vec<Rc<Ctx>>, IdBuild>,
    table: HashMap<u64, Vec<Entry>, IdBuild>,
    st: Stats,
    games: u64,
    stats_path: Option<std::path::PathBuf>,
    blob: Vec<u64>,
    zbuf: Vec<u64>,
}

impl Memo {
    fn new() -> Memo {
        Memo {
            armed: false,
            max_entries: MAX_ENTRIES,
            max_pops: MAX_POPS,
            max_ctx: MAX_CTX,
            ctxs: HashMap::default(),
            table: HashMap::default(),
            st: Stats::default(),
            games: 0,
            stats_path: None,
            blob: Vec::new(),
            zbuf: Vec::new(),
        }
    }

    fn drop_all(&mut self) {
        self.ctxs = HashMap::default();
        self.table = HashMap::default();
        self.st.entries = 0;
        self.st.pops = 0;
        self.st.ctxs = 0;
    }

    fn flush(&self) {
        if let Some(p) = &self.stats_path {
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
                let s = &self.st;
                let _ = writeln!(
                    f,
                    "{{\"pid\":{},\"game\":{},\"calls\":{},\"hits\":{},\"entries\":{},\"pops\":{},\"peak_entries\":{},\"peak_pops\":{},\"peak_ctxs\":{},\"clears\":{}}}",
                    std::process::id(), self.games, s.calls, s.hits, s.entries, s.pops, s.peak_entries, s.peak_pops, s.peak_ctxs, s.clears
                );
            }
        }
    }
}

thread_local! {
    static MEMO: RefCell<Memo> = RefCell::new(Memo::new());
}

#[cfg(test)]
thread_local! {
    /// TEST KNOB: truncates every table hash so that unequal keys collide and only the content checks keep the answers apart.
    static HASH_MASK: std::cell::Cell<u64> = const { std::cell::Cell::new(u64::MAX) };
}

#[inline]
fn fin(h: u64) -> u64 {
    #[cfg(test)]
    {
        h & HASH_MASK.with(|m| m.get())
    }
    #[cfg(not(test))]
    {
        h
    }
}

#[inline]
fn mix(h: u64, w: u64) -> u64 {
    (h.rotate_left(5) ^ w).wrapping_mul(0x517c_c1b7_2722_0a95)
}

#[inline]
fn bits2(p: V2) -> u64 {
    u64::from(p[0].to_bits()) | (u64::from(p[1].to_bits()) << 32)
}

fn set_hash(len: usize, acc: u64) -> u64 {
    mix(mix(0x9e37_79b9_7f4a_7c15, len as u64), acc)
}

fn cells_hash(s: &CellSet) -> u64 {
    let mut acc = 0u64;
    for c in s {
        acc = acc.wrapping_add(mix(mix(1, c.0 as u32 as u64), c.1 as u32 as u64));
    }
    set_hash(s.len(), acc)
}

fn grid_hash(g: &Grid) -> u64 {
    let mut acc = 0u64;
    for (c, v) in g {
        acc = acc.wrapping_add(mix(mix(mix(1, c.0 as u32 as u64), c.1 as u32 as u64), *v as u64));
    }
    set_hash(g.len(), acc)
}

/// Everything of the CONTEXT except the three cell collections, as a flat word list (length-prefixed sections).
fn fill_blob(out: &mut Vec<u64>, walls: &[Wall], board: V2, opts: &ThetaOpts, cfg: ThetaCfg, bend: ThetaBend) {
    out.clear();
    let so = &opts.step;
    out.push(u64::from(bend.strict_open));
    match bend.diag_swap {
        None => out.push(0),
        Some((i, j)) => {
            out.push(1);
            out.push(i as u64);
            out.push(j as u64);
        }
    }
    out.push(u64::from(cfg.fast_planner));
    out.push(cfg.fast_planner_guard as u64);
    out.push(u64::from(opts.reach_closest));
    out.push(u64::from(so.dangerous_debuff));
    out.push(u64::from(so.difficult_debuff));
    out.push(so.clearance.to_bits());
    out.push(bits2(board));
    out.push(walls.len() as u64);
    for w in walls {
        out.push(bits2(w[0]));
        out.push(bits2(w[1]));
    }
    out.push(so.ledges.len() as u64);
    for l in so.ledges {
        out.push(bits2(l.a));
        out.push(bits2(l.b));
        out.push(l.dy_in.to_bits());
    }
}

enum Probe {
    Hit(Vec<V2>, Vec<PackedPop>),
    Miss { ctx: Rc<Ctx>, hash: u64 },
}

impl Memo {
    /// Finds (or interns) the context of a call, then looks the call up. `zbuf` and `blob` are scratch.
    #[allow(clippy::too_many_arguments)]
    fn probe(
        &mut self,
        start: V2,
        goal: V2,
        walls: &[Wall],
        grid: &Grid,
        board: V2,
        opts: &ThetaOpts,
        cfg: ThetaCfg,
        bend: ThetaBend,
    ) -> Probe {
        let so = &opts.step;
        let mut blob = std::mem::take(&mut self.blob);
        fill_blob(&mut blob, walls, board, opts, cfg, bend);
        let mut h = 0xcbf2_9ce4_8422_2325u64;
        for &w in &blob {
            h = mix(h, w);
        }
        h = mix(h, grid_hash(grid));
        h = mix(h, cells_hash(so.avoid_cells));
        h = mix(h, cells_hash(so.avoid_fine));
        let h = fin(h);
        let found = self.ctxs.get(&h).and_then(|v| {
            v.iter()
                .find(|c| {
                    c.blob == blob && c.grid == *grid && c.avoid_cells == *so.avoid_cells && c.avoid_fine == *so.avoid_fine
                })
                .cloned()
        });
        let ctx = match found {
            Some(c) => c,
            None => {
                if self.st.ctxs >= self.max_ctx {
                    self.drop_all();
                    self.st.clears += 1;
                }
                let c = Rc::new(Ctx {
                    hash: h,
                    blob: blob.clone(),
                    grid: grid.clone(),
                    avoid_cells: so.avoid_cells.clone(),
                    avoid_fine: so.avoid_fine.clone(),
                });
                self.ctxs.entry(h).or_default().push(Rc::clone(&c));
                self.st.ctxs += 1;
                self.st.peak_ctxs = self.st.peak_ctxs.max(self.st.ctxs);
                c
            }
        };
        self.blob = blob;
        let mut z = std::mem::take(&mut self.zbuf);
        z.clear();
        for zone in so.zones {
            z.push(bits2(zone.c));
            z.push(zone.r.to_bits());
        }
        let (s, g) = ([start[0].to_bits(), start[1].to_bits()], [goal[0].to_bits(), goal[1].to_bits()]);
        let mut eh = mix(ctx.hash, bits2(start));
        eh = mix(eh, bits2(goal));
        eh = mix(eh, z.len() as u64);
        for &w in &z {
            eh = mix(eh, w);
        }
        let eh = fin(eh);
        let hit = self.table.get(&eh).and_then(|v| {
            v.iter()
                .find(|e| Rc::ptr_eq(&e.ctx, &ctx) && e.start == s && e.goal == g && *e.zones == *z)
                .map(|e| (e.path.clone(), e.pops.clone()))
        });
        self.zbuf = z;
        match hit {
            Some((p, t)) => Probe::Hit(p, t),
            None => Probe::Miss { ctx, hash: eh },
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn insert(&mut self, ctx: Rc<Ctx>, hash: u64, start: V2, goal: V2, zones: &[Zone], path: &[V2], pops: &[ThetaPop]) {
        if pops.len() > self.max_pops {
            return; // one search larger than the whole budget is not worth keeping
        }
        let Some(packed) = pack(pops) else { return };
        // A cap overflow drops everything (contexts included, they own the grids) and starts over; the context of
        // this call is interned again so the new entry is still found next time.
        if self.st.entries + 1 > self.max_entries || self.st.pops + pops.len() > self.max_pops {
            self.drop_all();
            self.st.clears += 1;
            self.ctxs.entry(ctx.hash).or_default().push(Rc::clone(&ctx));
            self.st.ctxs = 1;
        }
        let mut zw: Vec<u64> = Vec::with_capacity(zones.len() * 2);
        for z in zones {
            zw.push(bits2(z.c));
            zw.push(z.r.to_bits());
        }
        let e = Entry {
            ctx,
            start: [start[0].to_bits(), start[1].to_bits()],
            goal: [goal[0].to_bits(), goal[1].to_bits()],
            zones: zw.into_boxed_slice(),
            path: path.to_vec(),
            pops: packed,
        };
        self.table.entry(hash).or_default().push(e);
        self.st.entries += 1;
        self.st.pops += pops.len();
        self.st.peak_entries = self.st.peak_entries.max(self.st.entries);
        self.st.peak_pops = self.st.peak_pops.max(self.st.pops);
    }
}

/// Start of a game: drop everything stored, reset the counters, arm the memo. Called by the Python seam's `set_header`.
/// With `NML_THETA_MEMO_STATS=<file>` set, the previous game's counters are appended to the file as one JSON line.
pub fn begin_game() {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        if m.st.calls > 0 {
            m.flush();
        }
        let games = m.games + 1;
        let (me, mp, mc) = (m.max_entries, m.max_pops, m.max_ctx);
        *m = Memo::new();
        m.armed = true;
        m.games = games;
        (m.max_entries, m.max_pops, m.max_ctx) = (me, mp, mc);
        m.stats_path = std::env::var_os("NML_THETA_MEMO_STATS").map(std::path::PathBuf::from);
    });
}

/// Stop memoising and drop everything (the default state of a thread).
pub fn disarm() {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.drop_all();
        m.armed = false;
    });
}

/// The counters of the current game.
pub fn stats() -> Stats {
    MEMO.with(|m| m.borrow().st)
}

/// TEST KNOB: shrink the caps of this thread's memo (restored to the defaults by `set_caps(MAX_ENTRIES, MAX_POPS, MAX_CTX)`).
#[doc(hidden)]
pub fn set_caps(entries: usize, pops: usize, ctxs: usize) {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.max_entries = entries;
        m.max_pops = pops;
        m.max_ctx = ctxs;
    });
}

/// `search` run through the memo. `search` is called at most once, always with a trace vector (it records the pops that
/// the memo stores); the caller's own `trace` receives the pops either way.
#[allow(clippy::too_many_arguments)]
pub fn run(
    start: V2,
    goal: V2,
    walls: &[Wall],
    grid: &Grid,
    board: V2,
    opts: &ThetaOpts,
    cfg: ThetaCfg,
    bend: ThetaBend,
    trace: Option<&mut Vec<ThetaPop>>,
    search: impl FnOnce(Option<&mut Vec<ThetaPop>>) -> Vec<V2>,
) -> Vec<V2> {
    let armed = MEMO.with(|m| m.borrow().armed);
    // A non-empty caller vector shifts the recorded pop indices: not memoisable.
    if !armed || trace.as_ref().is_some_and(|t| !t.is_empty()) {
        return search(trace);
    }
    let probe = MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.st.calls += 1;
        if m.stats_path.is_some() && m.st.calls % 4096 == 0 {
            m.flush();
        }
        let p = m.probe(start, goal, walls, grid, board, opts, cfg, bend);
        if matches!(p, Probe::Hit(..)) {
            m.st.hits += 1;
        }
        p
    });
    match probe {
        Probe::Hit(path, pops) => {
            if let Some(t) = trace {
                t.extend(pops.iter().map(|p| ThetaPop { g: p.g, parent: i64::from(p.parent), open: i64::from(p.open) }));
            }
            path
        }
        Probe::Miss { ctx, hash } => {
            let mut local: Vec<ThetaPop> = Vec::new();
            let path = search(Some(&mut local));
            MEMO.with(|m| {
                let mut m = m.borrow_mut();
                m.insert(ctx, hash, start, goal, opts.step.zones, &path, &local);
            });
            if let Some(t) = trace {
                t.extend_from_slice(&local);
            }
            path
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mv::cost::{Ledge, StepOpts, Zone};
    use crate::mv::theta::{theta_core, theta_star_traced_bent};
    use crate::mv::{T_CONTAINER, T_DANGEROUS, T_FOREST, T_RUINS};

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            z ^ (z >> 31)
        }
        fn f(&mut self, lo: f32, hi: f32) -> f32 {
            lo + (hi - lo) * ((self.next() >> 40) as f32 / (1u64 << 24) as f32)
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    #[derive(Clone)]
    struct Sc {
        start: V2,
        goal: V2,
        walls: Vec<Wall>,
        grid: Grid,
        board: V2,
        reach: bool,
        clearance: f64,
        ledges: Vec<super::super::cost::Ledge>,
        zones: Vec<Zone>,
        avoid_cells: CellSet,
        avoid_fine: CellSet,
        dd: bool,
        df: bool,
        cfg: ThetaCfg,
        bend: ThetaBend,
    }

    type Out = (Vec<[u32; 2]>, Vec<(u64, i64, i64)>);

    fn solve(sc: &Sc) -> Out {
        let step = StepOpts {
            ledges: &sc.ledges,
            clearance: sc.clearance,
            zones: &sc.zones,
            avoid_cells: &sc.avoid_cells,
            avoid_fine: &sc.avoid_fine,
            dangerous_debuff: sc.dd,
            difficult_debuff: sc.df,
        };
        let o = ThetaOpts { step, reach_closest: sc.reach };
        let (p, t) = theta_star_traced_bent(sc.start, sc.goal, &sc.walls, &sc.grid, sc.board, &o, sc.cfg, sc.bend);
        (
            p.iter().map(|v| [v[0].to_bits(), v[1].to_bits()]).collect(),
            t.iter().map(|x| (x.g.to_bits(), x.parent, x.open)).collect(),
        )
    }

    fn random_sc(r: &mut Rng) -> Sc {
        let board = [48.0f32, 32.0];
        let start = [r.f(2.0, 12.0), r.f(2.0, 30.0)];
        let goal = [r.f(34.0, 46.0), r.f(2.0, 30.0)];
        let mid = [(start[0] + goal[0]) / 2.0, (start[1] + goal[1]) / 2.0];
        let mut walls: Vec<Wall> = Vec::new();
        for _ in 0..r.below(14) {
            let a = [r.f(4.0, 44.0), r.f(2.0, 30.0)];
            walls.push([a, [a[0] + r.f(-6.0, 6.0), a[1] + r.f(-6.0, 6.0)]]);
        }
        if r.below(10) < 8 {
            walls.push([[mid[0] + r.f(-2.0, 2.0), mid[1] - 7.0], [mid[0] + r.f(-2.0, 2.0), mid[1] + 7.0]]);
        }
        let mut grid = Grid::default();
        let mut avoid_cells = CellSet::default();
        for cx in 0..16 {
            for cy in 0..11 {
                if r.below(4) == 0 {
                    let ty = [T_RUINS, T_FOREST, T_CONTAINER, T_DANGEROUS][r.below(4) as usize];
                    grid.insert((cx, cy), ty);
                    if (ty == T_FOREST || ty == T_DANGEROUS) && r.below(3) == 0 {
                        avoid_cells.insert((cx, cy));
                    }
                }
            }
        }
        let mut zones = Vec::new();
        for _ in 0..1 + r.below(3) {
            zones.push(Zone { c: [mid[0] + r.f(-6.0, 6.0), mid[1] + r.f(-6.0, 6.0)], r: f64::from(r.f(1.5, 3.0)) });
        }
        let mut ledges = Vec::new();
        if r.below(3) == 0 {
            let a = [mid[0] + r.f(-3.0, 3.0), mid[1] - 6.0];
            ledges.push(Ledge { a, b: [a[0] + r.f(-2.0, 2.0), a[1] + 12.0], dy_in: f64::from(r.f(0.5, 2.0)) });
        }
        Sc {
            start,
            goal,
            walls,
            grid,
            board,
            reach: r.below(2) == 0,
            clearance: f64::from(r.f(0.6, 1.2)),
            ledges,
            zones,
            avoid_cells,
            avoid_fine: CellSet::default(),
            dd: false,
            df: false,
            cfg: ThetaCfg::of(r.below(2) == 0, 320),
            bend: ThetaBend::default(),
        }
    }

    /// One big perturbation per key field. Index = field.
    const FIELDS: [&str; 21] = [
        "start", "goal", "walls", "grid", "board", "reach_closest", "clearance", "ledges", "zone_added", "zone_radius",
        "avoid_cells", "avoid_fine", "dangerous_debuff", "difficult_debuff", "fast_planner", "guard", "strict_open",
        "diag_swap", "wall_endpoint", "reach_closest_pair", "ledge_dy_twin",
    ];

    /// The goal walled in: the search cannot finish and ends through `reach_closest` (the only place the flag shows).
    fn enclose_goal(s: &mut Sc, reach: bool) {
        let (g, h) = (s.goal, 2.5f32);
        s.cfg.fast_planner = false;
        s.reach = reach;
        s.walls.push([[g[0] - h, g[1] - h], [g[0] + h, g[1] - h]]);
        s.walls.push([[g[0] + h, g[1] - h], [g[0] + h, g[1] + h]]);
        s.walls.push([[g[0] + h, g[1] + h], [g[0] - h, g[1] + h]]);
        s.walls.push([[g[0] - h, g[1] + h], [g[0] - h, g[1] - h]]);
    }

    fn perturb(sc: &Sc, f: usize, r: &mut Rng) -> Sc {
        let mut s = sc.clone();
        let mid = [(s.start[0] + s.goal[0]) / 2.0, (s.start[1] + s.goal[1]) / 2.0];
        match f {
            0 => s.start = [s.start[0] + r.f(1.0, 3.0), s.start[1] + r.f(-3.0, 3.0)],
            1 => s.goal = [s.goal[0] - r.f(1.0, 3.0), s.goal[1] + r.f(-3.0, 3.0)],
            2 => s.walls.push([[mid[0] + 1.0, mid[1] - 9.0], [mid[0] + 1.0, mid[1] + 9.0]]),
            3 => {
                for k in 0..16 {
                    let c = ((mid[0] / 3.0) as i32 - 3 + k / 3, (mid[1] / 3.0) as i32 - 1 + k % 3);
                    s.grid.insert(c, T_DANGEROUS);
                }
            }
            4 => s.board = [s.goal[0] + 1.5, s.goal[1] + 1.5],
            5 => enclose_goal(&mut s, true),
            6 => s.clearance += 1.0,
            7 => s.ledges.push(Ledge { a: [mid[0], mid[1] - 8.0], b: [mid[0] + 1.0, mid[1] + 8.0], dy_in: 3.0 }),
            8 => s.zones.push(Zone { c: mid, r: 3.5 }),
            9 => {
                let k = r.below(s.zones.len() as u64) as usize;
                s.zones[k] = Zone { c: mid, r: s.zones[k].r + 2.0 };
            }
            10 => {
                for k in 0..12 {
                    s.avoid_cells.insert(((mid[0] / 3.0) as i32 - 2 + k / 3, (mid[1] / 3.0) as i32 - 1 + k % 3));
                }
            }
            11 => {
                for k in 0..30 {
                    s.avoid_fine.insert((mid[0] as i32 - 3 + k / 5, mid[1] as i32 - 2 + k % 5));
                }
            }
            12 => s.dd = !s.dd,
            13 => s.df = !s.df,
            14 => s.cfg.fast_planner = !s.cfg.fast_planner,
            15 => s.cfg.fast_planner_guard = 12,
            16 => s.bend.strict_open = true,
            17 => {
                let i = r.below(8) as usize;
                s.bend.diag_swap = Some((i, (i + 1 + r.below(7) as usize) % 8));
            }
            19 => enclose_goal(&mut s, false),
            20 => s.ledges.push(Ledge { a: [mid[0], mid[1] - 8.0], b: [mid[0] + 1.0, mid[1] + 8.0], dy_in: 0.2 }),
            _ => {
                if s.walls.is_empty() {
                    s.walls.push([[mid[0], mid[1] - 9.0], [mid[0], mid[1] + 9.0]]);
                }
                let k = r.below(s.walls.len() as u64) as usize;
                s.walls[k][1][1] += 7.0;
            }
        }
        s
    }

    /// Replays a shuffled mix of scenarios and one-field perturbations of them, twice, through the armed memo and
    /// demands bit-identical answers (path and pop record) against the unmemoised search. Returns, per field, in how
    /// many scenarios the perturbation really changed the answer (the non-vacuity count).
    fn differential(seed: u64, n: usize, mask: u64) -> Vec<usize> {
        let mut r = Rng(seed);
        let mut all: Vec<Sc> = Vec::new();
        let mut changed = vec![0usize; FIELDS.len()];
        let mut refs: Vec<Out> = Vec::new();
        disarm();
        for _ in 0..n {
            let base = random_sc(&mut r);
            let rb = solve(&base);
            let mut outs: Vec<Out> = Vec::new();
            for f in 0..FIELDS.len() {
                let p = perturb(&base, f, &mut r);
                outs.push(solve(&p));
                all.push(p);
            }
            for f in 0..FIELDS.len() {
                // `reach_closest` shows only against its twin (same walled-in goal, flag flipped).
                let other = match f {
                    5 => &outs[19],
                    7 => &outs[20],
                    _ => &rb,
                };
                if f != 19 && f != 20 && outs[f] != *other {
                    changed[f] += 1;
                }
            }
            refs.extend(outs);
            refs.push(rb);
            all.push(base);
        }
        HASH_MASK.with(|m| m.set(mask));
        begin_game();
        set_caps(1_000_000, 100_000_000, 1_000_000);
        let mut order: Vec<usize> = (0..all.len()).collect();
        for pass in 0..2 {
            for i in (1..order.len()).rev() {
                let j = r.below(i as u64 + 1) as usize;
                order.swap(i, j);
            }
            for &i in &order {
                assert!(solve(&all[i]) == refs[i], "memo answer differs from the plain search (pass {pass}, scenario {i})");
            }
        }
        let st = stats();
        assert!(st.hits as usize >= all.len() / 2, "second pass must be served from the memo: {st:?}");
        HASH_MASK.with(|m| m.set(u64::MAX));
        disarm();
        changed
    }

    /// `bend.diag_swap` is in the key but NOT in the non-vacuity list: 0 of 2,240 random (scenario, swap) pairs changed
    /// the answer (the open-list scan breaks every tie by `cell_before`, so the neighbour order cannot reach the output).
    #[test]
    fn a_memoised_search_answers_exactly_like_a_fresh_one_for_every_key_field() {
        let changed = differential(0x5eed, 60, u64::MAX);
        for (f, c) in changed.iter().enumerate().filter(|(f, _)| *f != 19 && *f != 20 && *f != 17) {
            assert!(*c >= 3, "perturbation of `{}` changed the answer in only {c} scenarios: the test cannot see this field", FIELDS[f]);
        }
    }

    /// Same replay with the table hashes cut to 2 bits: nearly every key collides, so every answer rests on the content
    /// checks alone (the hash is only an index).
    #[test]
    fn colliding_hashes_never_mix_up_two_different_searches() {
        differential(0xc0111de, 40, 0x3);
    }

    #[test]
    fn a_new_game_starts_with_an_empty_memo_and_a_disarmed_thread_stores_nothing() {
        let mut r = Rng(7);
        let sc = random_sc(&mut r);
        disarm();
        let _ = solve(&sc);
        assert_eq!(stats().calls, 0);
        assert_eq!(stats().entries, 0);
        begin_game();
        let a = solve(&sc);
        let _ = solve(&sc);
        let st = stats();
        assert!(st.entries >= 1 && st.hits >= 1, "{st:?}");
        begin_game();
        let st = stats();
        assert_eq!((st.entries, st.pops, st.ctxs, st.calls, st.hits), (0, 0, 0, 0, 0), "{st:?}");
        let b = solve(&sc);
        assert!(a == b);
        assert_eq!(stats().hits, 0, "the first call of a new game must be a miss");
        disarm();
    }

    #[test]
    fn the_caps_bound_the_memo_and_never_change_an_answer() {
        let mut r = Rng(99);
        disarm();
        let scs: Vec<Sc> = (0..80).map(|_| random_sc(&mut r)).collect();
        let refs: Vec<Out> = scs.iter().map(solve).collect();
        begin_game();
        set_caps(6, 400, 3);
        for _ in 0..3 {
            for (sc, rf) in scs.iter().zip(&refs) {
                assert!(solve(sc) == *rf);
                let st = stats();
                assert!(st.entries <= 6 && st.pops <= 400 && st.ctxs <= 3, "{st:?}");
            }
        }
        let st = stats();
        assert!(st.clears > 0, "the caps must have fired: {st:?}");
        assert!(st.peak_entries <= 6 && st.peak_pops <= 400 && st.peak_ctxs <= 3, "{st:?}");
        disarm();
    }

    #[test]
    fn a_trace_vector_that_is_not_empty_is_never_memoised() {
        let mut r = Rng(5);
        let sc = random_sc(&mut r);
        let step = StepOpts {
            ledges: &sc.ledges,
            clearance: sc.clearance,
            zones: &sc.zones,
            avoid_cells: &sc.avoid_cells,
            avoid_fine: &sc.avoid_fine,
            dangerous_debuff: sc.dd,
            difficult_debuff: sc.df,
        };
        let o = ThetaOpts { step, reach_closest: sc.reach };
        let seed = ThetaPop { g: 1.0, parent: -1, open: 1 };
        let run = |armed: bool| {
            if armed {
                begin_game();
            } else {
                disarm();
            }
            let mut pops = vec![seed];
            let p = theta_core(sc.start, sc.goal, &sc.walls, &sc.grid, sc.board, &o, sc.cfg, sc.bend, Some(&mut pops));
            (p, pops.iter().map(|x| (x.g.to_bits(), x.parent, x.open)).collect::<Vec<_>>())
        };
        let plain = run(false);
        let armed = run(true);
        assert!(plain == armed);
        assert_eq!(stats().calls, 0, "a call with a pre-filled trace must bypass the memo");
        disarm();
    }
}
