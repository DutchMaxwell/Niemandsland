//! An EXACT memo for `menu::safe_advances`, scoped to one game in one process (a pool worker asks the same question
//! about the same squares over and over).
//!
//! INPUTS THAT FORM THE KEY (every one `safe_advances` reads; none is hashed alone - a hit needs full content equality):
//! the terrain's content identity (`Terrain::uid`), `tuning.{advance_k, cover_bonus_in}`, `state.los_pairs.is_some()`,
//! every objective position, the mover's model positions and `bands.advance`, and for each living enemy (in
//! `enemy_keys` order) its model positions, `bands.{advance, rush}` and `max_range_inches(profile weapons)`.
//! Positions enter through `geom::to_f32` in the function, so their f32 bit patterns are the key; the other floats are
//! keyed by their f64 bit pattern. The mover's own index and unit key only name the returned candidates (rebuilt on a hit).
//!
//! SCOPE. Thread-local, DISARMED by default (tests, Godot and other callers are untouched). `begin_game()` (the Python
//! seam's `Core.set_header`) clears and arms; pool workers inherit the parent's armed memo through fork. Exactness never
//! depends on the clear, the clear only bounds lifetime. Entries and key words are capped; an overflow drops everything.

use std::cell::RefCell;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

use crate::menu::{max_range_inches, Tuning};
use crate::state::State;
use crate::terrain::Terrain;

/// Most stored answers per process.
pub const MAX_ENTRIES: usize = 12_000;
/// Most stored key words (4 bytes each) per process: 3.2 MB.
pub const MAX_WORDS: usize = 800_000;

#[derive(Default)]
struct IdHasher(u64);
impl Hasher for IdHasher {
    fn write(&mut self, _: &[u8]) {}
    fn write_u64(&mut self, i: u64) {
        self.0 = i;
    }
    fn finish(&self) -> u64 {
        self.0
    }
}

struct Entry {
    key: Box<[u32]>,
    dests: Box<[Dest]>,
}
type Dest = [f64; 3];

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Stats {
    pub calls: u64,
    pub hits: u64,
    pub entries: usize,
    pub words: usize,
    pub clears: u64,
}

struct Memo {
    armed: bool,
    max_entries: usize,
    max_words: usize,
    table: HashMap<u64, Vec<Entry>, BuildHasherDefault<IdHasher>>,
    st: Stats,
    scratch: Vec<u32>,
    stats_path: Option<std::path::PathBuf>,
}

thread_local! {
    static MEMO: RefCell<Memo> = RefCell::new(Memo {
        armed: false,
        max_entries: MAX_ENTRIES,
        max_words: MAX_WORDS,
        table: HashMap::default(),
        st: Stats::default(),
        scratch: Vec::new(),
        stats_path: None,
    });
}

#[cfg(test)]
thread_local! {
    /// TEST KNOB: truncates every table hash so that unequal keys collide and only the content check keeps them apart.
    static HASH_MASK: std::cell::Cell<u64> = const { std::cell::Cell::new(u64::MAX) };
}

fn hash_of(key: &[u32]) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325u64;
    for &w in key {
        h = (h.rotate_left(5) ^ u64::from(w)).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
    #[cfg(test)]
    {
        h &= HASH_MASK.with(|m| m.get());
    }
    h
}

fn push64(k: &mut Vec<u32>, v: u64) {
    k.push(v as u32);
    k.push((v >> 32) as u32);
}

fn push_models(k: &mut Vec<u32>, ps: &[[f64; 3]]) {
    k.push(ps.len() as u32);
    for p in ps {
        k.extend(p.iter().map(|c| (*c as f32).to_bits()));
    }
}

/// The key of one call (see the module doc). Every variable-length section is length-prefixed, so equal words mean
/// equal inputs. `false` = not keyable (a terrain without content identity, a malformed state): never memoised.
fn build_key(k: &mut Vec<u32>, state: &State, terrain: &Terrain, i: usize, tuning: Tuning) -> bool {
    if terrain.uid() == 0 {
        return false;
    }
    k.clear();
    push64(k, terrain.uid());
    push64(k, tuning.advance_k as u64);
    push64(k, tuning.cover_bonus_in.to_bits());
    k.push(u32::from(state.los_pairs.is_some()));
    k.push(state.objectives.len() as u32);
    for o in &state.objectives {
        k.extend(o.pos.iter().map(|c| (*c as f32).to_bits()));
    }
    let (Some(own), Some(ps)) = (state.bands.get(i), state.positions.get(i)) else { return false };
    push64(k, own.advance.to_bits());
    push_models(k, ps);
    let enemies = crate::menu::enemy_keys(state, i);
    k.push(enemies.len() as u32);
    for e in enemies {
        let weapons = state.roster.profile.get(e).and_then(|p| state.profiles.list.get(*p)).map(|p| &p.weapons);
        let (Some(w), Some(b), Some(ps)) = (weapons, state.bands.get(e), state.positions.get(e)) else { return false };
        push64(k, max_range_inches(w) as u64);
        push64(k, b.advance.to_bits());
        push64(k, b.rush.to_bits());
        push_models(k, ps);
    }
    true
}

impl Memo {
    fn drop_all(&mut self) {
        self.table = HashMap::default();
        self.st.entries = 0;
        self.st.words = 0;
    }

    fn flush(&self) {
        if let (Some(p), true) = (&self.stats_path, self.st.calls > 0) {
            use std::io::Write;
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
                let s = &self.st;
                let _ = writeln!(
                    f,
                    "{{\"pid\":{},\"calls\":{},\"hits\":{},\"entries\":{},\"words\":{},\"clears\":{}}}",
                    std::process::id(), s.calls, s.hits, s.entries, s.words, s.clears
                );
            }
        }
    }
}

/// Start of a game: drop everything stored, reset the counters, arm the memo (`Core.set_header`).
/// With `NML_SAFE_MEMO_STATS=<file>` set, this thread's previous counters are appended to the file as one JSON line.
pub fn begin_game() {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.flush();
        m.drop_all();
        m.st = Stats::default();
        m.armed = true;
        m.stats_path = std::env::var_os("NML_SAFE_MEMO_STATS").map(std::path::PathBuf::from);
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

/// The counters of the current game on this thread.
pub fn stats() -> Stats {
    MEMO.with(|m| m.borrow().st)
}

/// TEST KNOB: shrink this thread's caps.
#[doc(hidden)]
pub fn set_caps(entries: usize, words: usize) {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.max_entries = entries;
        m.max_words = words;
    });
}

/// TEST KNOB: truncate the table hashes of this thread (`u64::MAX` = off).
#[cfg(test)]
pub(crate) fn set_hash_mask(mask: u64) {
    HASH_MASK.with(|m| m.set(mask));
}

/// `fresh` (the real search, returns the destinations in order) run through the memo.
pub fn run(
    state: &State,
    terrain: &Terrain,
    i: usize,
    tuning: Tuning,
    fresh: impl FnOnce() -> Vec<Dest>,
) -> Vec<Dest> {
    let taken = MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.armed.then(|| std::mem::take(&mut m.scratch))
    });
    let Some(mut k) = taken else { return fresh() };
    let give_back = |k: Vec<u32>| MEMO.with(|m| m.borrow_mut().scratch = k);
    if !build_key(&mut k, state, terrain, i, tuning) {
        give_back(k);
        return fresh();
    }
    let h = hash_of(&k);
    let hit = MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.st.calls += 1;
        if m.st.calls & 4095 == 0 {
            m.flush(); // workers die without a clean exit
        }
        let found = m.table.get(&h).and_then(|v| v.iter().find(|e| *e.key == *k)).map(|e| e.dests.to_vec());
        if found.is_some() {
            m.st.hits += 1;
        }
        found
    });
    if let Some(d) = hit {
        give_back(k);
        return d;
    }
    let out = fresh();
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        if m.st.entries + 1 > m.max_entries || m.st.words + k.len() > m.max_words {
            m.drop_all();
            m.st.clears += 1;
        }
        if k.len() <= m.max_words {
            let e = Entry { key: k.as_slice().into(), dests: out.as_slice().into() };
            m.table.entry(h).or_default().push(e);
            m.st.entries += 1;
            m.st.words += k.len();
        }
        m.scratch = k;
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom;
    use crate::menu::{safe_advances, safe_advances_fresh, Candidate};
    use crate::state::Profiles;
    use crate::terrain::{CellParams, PlainTerrain, Terrain, FOREST, RUINS};
    use std::rc::Rc;

    const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
    const FIELDS: usize = 23;

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }
        fn below(&mut self, n: usize) -> usize {
            (self.next() % n as u64) as usize
        }
        fn f(&mut self, lo: f64, hi: f64) -> f64 {
            lo + (hi - lo) * ((self.next() >> 11) as f64 / (1u64 << 53) as f64)
        }
    }

    /// Everything a candidate list says, floats by bit pattern.
    fn sig(v: &[Candidate]) -> String {
        v.iter()
            .map(|c| {
                format!("{}|{}|{:?}|{:?}|{:?}|{}|{:?}", c.unit, c.kind, c.dest.map(|d| d.map(f64::to_bits)), c.shoot, c.charge, c.patient, c.wave)
            })
            .collect::<Vec<_>>()
            .join(";")
    }

    fn board_with(cells: Vec<[f64; 3]>) -> Terrain {
        Terrain::build(&PlainTerrain {
            cells,
            sandbox: Vec::new(),
            pieces: Vec::new(),
            walls: Vec::new(),
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 6.0,
                inches_to_meters: 0.0254,
            },
        })
    }

    /// A board whose cover varies across the table, so `cover_bonus_in` can matter.
    fn forest_board() -> Terrain {
        let mut cells = Vec::new();
        for cx in -2..14 {
            for cz in -2..14 {
                if (cx + cz) % 2 == 0 {
                    cells.push([cx as f64, cz as f64, FOREST as f64]);
                } else if cx % 4 == 1 {
                    cells.push([cx as f64, cz as f64, RUINS as f64]);
                }
            }
        }
        board_with(cells)
    }

    /// (state, unit, terrain) bases: every living unit of every recorded act.
    fn bases() -> (Vec<(State, usize)>, Terrain) {
        let c = crate::load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"));
        let mut out = Vec::new();
        for act in &c.acts {
            for i in 0..act.state.units() {
                if act.state.alive[i] > 0 && !crate::menu::enemy_keys(&act.state, i).is_empty() {
                    out.push((act.state.clone(), i));
                }
            }
        }
        (out, c.terrain)
    }

    /// A base in which one enemy's cluster is placed right where its threat edge cuts the mover's frontier, so that
    /// changing any input that the threat depends on changes the answer. Returns the state and that enemy.
    fn contest(st: &State, i: usize, r: &mut Rng) -> (State, usize) {
        let mut s = st.clone();
        let es = crate::menu::enemy_keys(&s, i);
        let e = es[r.below(es.len())];
        let me = geom::centre(&s.positions[i]);
        let near = s.objectives.iter().map(|o| geom::to_f32(o.pos)).min_by(|a, b| {
            geom::length(geom::sub(*a, me)).partial_cmp(&geom::length(geom::sub(*b, me))).unwrap_or(std::cmp::Ordering::Equal)
        });
        if let Some(goal) = near.filter(|g| geom::length(geom::sub(*g, me)) > 0.5) {
            let dir = geom::normalized(geom::sub(goal, me));
            let reach = (crate::menu::max_range_inches(&s.profile(e).weapons) as f64 + s.bands[e].advance) * crate::IN2M;
            let d = reach + r.f(-0.05, 0.2);
            for (k, m) in s.positions[e].iter_mut().enumerate() {
                *m = [me[0] as f64 + dir[0] as f64 * d + 0.01 * k as f64, me[1] as f64, me[2] as f64 + dir[2] as f64 * d];
            }
        }
        (s, e)
    }

    /// One-field perturbation `f` of a base. Returns the changed (state, terrain, tuning).
    fn perturb(st: &State, tr: &Terrain, forest: &Terrain, i: usize, e: usize, f: usize, r: &mut Rng) -> (State, Terrain, Tuning) {
        let mut s = st.clone();
        let mut t = tr.clone();
        let mut tu = Tuning::default();
        let me = geom::centre(&s.positions[i]);
        match f {
            0 => s.positions[i][0][0] += r.f(0.5, 2.0),
            1 => s.positions[i][0][2] -= r.f(0.5, 2.0),
            2 => s.positions[i][0][1] += 0.25,
            3 => s.positions[e][0] = [me[0] as f64 + r.f(0.2, 1.2), 0.0, me[2] as f64 + r.f(-1.0, 1.0)], // one model leaves
            4 => {
                let q = s.positions[e][0];
                s.positions[e].push([q[0] + r.f(-0.1, 0.1), q[1], q[2] + r.f(-0.1, 0.1)]);
            }
            5 => s.positions[e][0][0] += r.f(0.05, 0.3),
            6 => s.bands[e].advance += r.f(2.0, 9.0),
            7 => s.bands[e].rush += r.f(2.0, 9.0),
            8 => {
                let p = &s.profiles;
                let mut list = p.list.clone();
                let k = s.roster.profile[e];
                for w in &mut list[k].weapons {
                    w.range += r.f(6.0, 30.0);
                }
                s.profiles = Rc::new(Profiles { list, index: p.index.clone() });
            }
            9 => s.bands[i].advance += r.f(1.0, 6.0),
            10 => s.objectives[0].pos[0] += r.f(-3.0, 3.0),
            11 => {
                let mut o = s.objectives[0];
                o.pos[2] += r.f(-4.0, 4.0);
                s.objectives.push(o);
            }
            12 => {
                if s.objectives.len() > 1 {
                    s.objectives.remove(0);
                } else {
                    s.objectives[0].pos[1] += 0.01;
                }
            }
            13 => s.los_pairs = if s.los_pairs.is_some() { None } else { Some(Rc::new(vec![true])) },
            14 => tu.advance_k = 3,
            15 => {
                t = forest.clone();
                tu.cover_bonus_in = r.f(0.0, 3.0); // below the frontier span, or every cover point wins anyway
            }
            16 => t = Terrain::absent(),
            17 | 22 => t = forest.clone(),
            18 => s.alive[e] = 0,
            19 => s.player[e] = s.player[i],
            20 => s.positions[i].push([me[0] as f64 + 0.3, 0.0, me[2] as f64]),
            _ => {} // 21: unchanged - must be a hit after the first pass
        }
        (s, t, tu)
    }

    /// Memo vs fresh over every base x every perturbation, two passes (the second answers from the memo). Returns, per field,
    /// how many perturbations changed the fresh answer (non-vacuity).
    fn differential(seed: u64, bases_n: usize) -> Vec<usize> {
        let (all, tr) = bases();
        let forest = forest_board(); // ONE board object: clones share its identity, so a key that ignores the bonus is caught
        let mut r = Rng(seed);
        let mut changed = vec![0usize; FIELDS];
        begin_game();
        for _ in 0..bases_n {
            let (b, i) = &all[r.below(all.len())];
            let (cst, e) = contest(b, *i, &mut r);
            let st = &cst;
            let base_sig = sig(&safe_advances_fresh(st, &tr, *i, Tuning::default()));
            let mut order: Vec<usize> = (0..FIELDS).collect();
            for k in (1..order.len()).rev() {
                order.swap(k, r.below(k + 1));
            }
            let cases: Vec<_> = order.iter().map(|&f| (f, perturb(st, &tr, &forest, *i, e, f, &mut r))).collect();
            // the cover bonus only shows on a board with cover: compare it with the same board at the default bonus
            let forest_sig = sig(&safe_advances_fresh(st, &cases.iter().find(|c| c.0 == 22).unwrap().1 .1, *i, Tuning::default()));
            for pass in 0..2 {
                for (f, (s, t, tu)) in &cases {
                    let want = sig(&safe_advances_fresh(s, t, *i, *tu));
                    let got = sig(&safe_advances(s, t, *i, *tu));
                    assert_eq!(got, want, "field {f} pass {pass}");
                    if pass == 0 && want != *if *f == 15 { &forest_sig } else { &base_sig } {
                        changed[*f] += 1;
                    }
                }
                let got = sig(&safe_advances(st, &tr, *i, Tuning::default()));
                assert_eq!(got, base_sig, "base pass {pass}");
            }
        }
        disarm();
        changed
    }

    fn assert_nonvacuous(changed: &[usize]) {
        eprintln!("answer-changing perturbations per field: {changed:?}");
        let weak: Vec<_> = changed.iter().enumerate().filter(|(f, n)| *f != 21 && **n < 5).collect();
        assert!(weak.is_empty(), "fields (index, count) that rarely change the answer - the test would not notice a key ignoring them: {weak:?}");
    }

    #[test]
    fn a_memoised_answer_equals_a_fresh_one_for_every_key_field() {
        let changed = differential(0x5afe_ad0a, 3000);
        assert_nonvacuous(&changed);
        let s = stats();
        let _ = s; // disarm() cleared the entries; the hit counters are checked in the scope test
    }

    #[test]
    fn colliding_hashes_never_mix_up_two_different_questions() {
        set_hash_mask(0b11);
        let changed = differential(0xc011_1de5, 1000);
        set_hash_mask(u64::MAX);
        assert_nonvacuous(&changed);
    }

    #[test]
    fn a_new_game_starts_empty_and_a_disarmed_thread_stores_nothing() {
        let (all, tr) = bases();
        let (st, i) = &all[0];
        disarm();
        let _ = safe_advances(st, &tr, *i, Tuning::default());
        assert_eq!(stats(), Stats::default(), "a disarmed thread must not store or count");
        begin_game();
        let a = sig(&safe_advances(st, &tr, *i, Tuning::default()));
        let b = sig(&safe_advances(st, &tr, *i, Tuning::default()));
        assert_eq!(a, b);
        let s = stats();
        assert_eq!((s.calls, s.hits, s.entries), (2, 1, 1));
        begin_game();
        assert_eq!(stats(), Stats::default(), "begin_game must drop every entry and counter");
        let _ = safe_advances(st, &tr, *i, Tuning::default());
        assert_eq!(stats().hits, 0, "the first question of a new game is never a hit");
        disarm();
    }

    #[test]
    fn the_caps_bound_the_memo_and_never_change_an_answer() {
        let (all, tr) = bases();
        for (entries, words) in [(5usize, 1_000_000usize), (1_000_000, 3000), (1, 1)] {
            begin_game();
            set_caps(entries, words);
            for (st, i) in all.iter().take(300) {
                let want = sig(&safe_advances_fresh(st, &tr, *i, Tuning::default()));
                assert_eq!(sig(&safe_advances(st, &tr, *i, Tuning::default())), want);
                let s = stats();
                assert!(s.entries <= entries && s.words <= words, "caps exceeded: {s:?}");
            }
            assert!(stats().clears > 0 || entries == 1 && words == 1 || all.len() < 6, "cap {entries}/{words} never reached");
            set_caps(MAX_ENTRIES, MAX_WORDS);
        }
        disarm();
    }

    #[test]
    fn a_terrain_without_content_identity_is_never_memoised() {
        let (all, _) = bases();
        let (st, i) = &all[0];
        begin_game();
        let t = Terrain::default();
        assert_eq!(t.uid(), 0);
        let _ = safe_advances(st, &t, *i, Tuning::default());
        assert_eq!(stats().calls, 0);
        disarm();
    }

    #[test]
    fn every_content_change_of_a_terrain_mints_a_new_identity() {
        let a = board_with(Vec::new());
        let b = board_with(Vec::new());
        assert!(a.uid() != 0 && a.uid() != b.uid(), "two builds share an identity");
        assert_eq!(a.clone().uid(), a.uid(), "a clone is the same content");
        assert!(Terrain::absent().uid() != 0 && Terrain::absent().uid() != Terrain::absent().uid());
        let mut c = a.clone();
        c.set_bank_props(&[], &[[10.0, 10.0, 2.0]], &[]);
        assert!(c.uid() != a.uid(), "set_bank_props kept the identity");
        let mut d = a.clone();
        d.set_walls_world_m(&[[[0.0, 0.0], [1.0, 1.0]]]);
        assert!(d.uid() != a.uid() && d.uid() != c.uid(), "set_walls_world_m kept the identity");
    }

    #[test]
    fn the_model_sections_of_a_key_cannot_be_shifted_into_each_other() {
        let (a, b, c) = ([1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]);
        let (mut k1, mut k2) = (Vec::new(), Vec::new());
        push_models(&mut k1, &[a]);
        push_models(&mut k1, &[b, c]);
        push_models(&mut k2, &[a, b]);
        push_models(&mut k2, &[c]);
        assert_ne!(k1, k2, "one model moved from the second section to the first must change the key");
    }
}
