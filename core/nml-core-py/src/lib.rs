//! NML-1073 M3-1 — the Python seam.
//!
//! Wraps the pure-Rust search (`nml-core`) as the extension module `nml_core`,
//! so the milestone-3 harness can play whole self-play games with the Rust
//! brain on both sides and no Godot in the loop. Nothing here re-implements a
//! rule: the crate below owns the port, this file owns the marshalling.
//!
//! CONTRACT
//! - `load(repo_root)` builds a `Core`; `Core.set_header(header)` feeds it the
//!   ACT-corpus header line (profiles + terrain + knobs) and builds the
//!   per-unit static closure through the SAME `acts::read_act_header` the JSONL
//!   loader uses.
//! - `Core.state_of(plain)` reads one plain state (`BattleSim.state_to_plain`
//!   plus the M2-0c/M2-0d gate reads) into an opaque `State`; `State.plain()`
//!   writes it back.
//! - Every call that the port cannot answer raises `nml_core.Unsupported` with
//!   the reason's own name. `plan_with_rollout` is the exception: a decline is
//!   a VALUE there (`{"used": false, "unsupported": ...}`), because the
//!   GDScript answers `{"used": false}` too and a harness has to route on it.
//!
//! PER-ACTIVATION PROFILES (NML-1073 M2-5b). Every act line carries the
//! profile fields a live game rewrites under the unit key `prof`, and the state
//! is replayed on the table THAT says, not on the header's deployment reading.
//! `Core` therefore keeps the same two caches `acts.rs` keeps — a `ProfileCache`
//! for the tables and a `StaticsCache` for the derived closures, keyed on
//! `Rc::ptr_eq` — and every call reads the closure that belongs to the state it
//! was handed. A module that built one closure from the header would answer
//! with a fallen hero's rules from the activation where he fell.
//!
//! MARSHALLING. Every dict crosses the seam as JSON TEXT: `json.dumps` on the
//! way in (a Python dict keeps insertion order, and `units` carries CAPTURE
//! ORDER in its key order — `serde_json::Value`'s `BTreeMap` would sort it
//! away), `json.loads` on the way out. Both directions print floats with the
//! shortest round-trip form, so no f64 is rounded in transit.
//!
//! SEEDS. `resolve_stochastic(state, action, seed)` seeds a fresh `GodotRng`
//! with the number the CALLER passes and advances it for that one call. The
//! game's own log-local formula lives in the caller too — `tools/
//! core_selfplay.gd:262-268` writes `game_seed * 100000 + row_index` for the
//! chosen action and `+ 50000` for the runner-up. This module never invents a
//! seed: a guessed dice stream is a silent lie.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use pyo3::create_exception;
use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList};

use serde_json::{Map, Value};

use nmlcore::acts::{ActHeader, ActStatics, Knobs, MeleeReach, PolicyMode, Sighting};
use nmlcore::arbitration::Arbitration;
use nmlcore::deployment::{self, Placement, Rect, SettleUnit, SideDeploy, UnitSpec};
use nmlcore::menu::{candidates_tuned, Candidate, Tuning};
use nmlcore::objectives;
use nmlcore::plan::{LeafValue, Pick, Search};
use nmlcore::playout::Policy;
use nmlcore::policy::{Policy as PolicyHarness, PolicyNet};
use nmlcore::rollout::Rollout;
use nmlcore::sight;
use nmlcore::sim::Scratch;
use nmlcore::state::{Marker, ProfileCache, Roster};
use nmlcore::rows::{Cell, RowEncoder};
use nmlcore::unit::{StaticsCache, UnitStatic};
use nmlcore::{
    geom, io, mission, reply_threat, resolve_on_board, resolve_stochastic_on_board,
    resolve_stochastic_tray_on_board, score_with, Action, Fitted, GodotRng, PlainTerrain,
    Registries, Seams, State as CoreState, Terrain, Tray, Unsupported as CoreUnsupported,
};

create_exception!(nml_core, Unsupported, PyRuntimeError);

// ------------------------------------------------------------ marshalling ---

/// One Python object as JSON text, in INSERTION order (see the module header).
fn json_text(obj: &Bound<'_, PyAny>) -> PyResult<String> {
    let json = obj.py().import("json")?;
    json.call_method1("dumps", (obj,))?.extract()
}

/// One Python object as a `serde_json::Value`. Only for objects whose key order
/// carries no meaning — never for a plain state.
fn value_of(obj: &Bound<'_, PyAny>) -> PyResult<Value> {
    serde_json::from_str(&json_text(obj)?).map_err(|e| Unsupported::new_err(e.to_string()))
}

/// One `serde_json::Value` as a Python object.
fn to_py(py: Python<'_>, v: &Value) -> PyResult<Py<PyAny>> {
    let text = serde_json::to_string(v).map_err(|e| Unsupported::new_err(e.to_string()))?;
    let json = py.import("json")?;
    Ok(json.call_method1("loads", (text,))?.unbind())
}

/// The two-slot VP ledger `BattleSim` passes around as a Godot `Array`.
fn pair(v: &[i64]) -> PyResult<[i64; 2]> {
    if v.len() != 2 {
        return Err(Unsupported::new_err(format!("vp must hold exactly 2 entries, got {}", v.len())));
    }
    Ok([v[0], v[1]])
}

fn declined(u: CoreUnsupported) -> PyErr {
    Unsupported::new_err(format!("{u:?}"))
}

/// `AiPlanner._plain_candidates` ai_planner.gd:108-116 — `patient` and `wave`
/// are stamped only on the candidate that carries them, which is what a
/// comparison against `trace.menus` reads.
fn cand_plain(c: &Candidate) -> Value {
    let mut m = Map::new();
    m.insert("unit".into(), Value::String(c.unit.clone()));
    m.insert("kind".into(), c.kind.into());
    if let Some(d) = c.dest {
        m.insert("dest".into(), Value::Array(vec![d[0].into(), d[1].into(), d[2].into()]));
    }
    if let Some(s) = &c.shoot {
        m.insert("shoot".into(), Value::String(s.clone()));
    }
    if let Some(s) = &c.charge {
        m.insert("charge".into(), Value::String(s.clone()));
    }
    if c.patient {
        m.insert("patient".into(), true.into());
    }
    if let Some(w) = &c.wave {
        if !w.is_empty() {
            m.insert("wave".into(), Value::String(w.clone()));
        }
    }
    Value::Object(m)
}

/// One `tokens::Tokens` row set as a Python list of lists — `board_rows`'s own
/// `PyList` idiom, generic over the row width so `units`/`objs`/`terr`/`cands`
/// share it.
fn rows2d<const N: usize>(py: Python<'_>, rows: &[[f32; N]]) -> PyResult<Py<PyAny>> {
    let out = PyList::empty(py);
    for r in rows {
        out.append(PyList::new(py, r.iter().copied())?)?;
    }
    Ok(out.into_any().unbind())
}

/// One position's `Tokens` as the dict `Core.policy_tokens` answers with. The
/// R4 leaf batch below hands out a LIST of exactly these, so both doors of the
/// token export are one shape and one place to keep in step.
fn tokens_dict(py: Python<'_>, t: nmlcore::tokens::Tokens) -> PyResult<Bound<'_, PyDict>> {
    let dict = PyDict::new(py);
    dict.set_item("units", rows2d(py, &t.units)?)?;
    dict.set_item("units_mask", t.units_mask)?;
    dict.set_item("objs", rows2d(py, &t.objs)?)?;
    dict.set_item("objs_mask", t.objs_mask)?;
    dict.set_item("terr", rows2d(py, &t.terr)?)?;
    dict.set_item("terr_mask", t.terr_mask)?;
    dict.set_item("glob", t.glob.to_vec())?;
    dict.set_item("cands", rows2d(py, &t.cands)?)?;
    dict.set_item("cands_mask", t.cands_mask)?;
    dict.set_item("actor", t.actor)?;
    dict.set_item("target", t.target)?;
    dict.set_item("label", t.label)?;
    Ok(dict)
}

/// NML-1165 R4 (DESIGN_value_net §7) — `plan::LeafValue` backed by a Python
/// callable: `fn(leaves, side) -> list[float]`, ONE call per activation.
///
/// `leaves` is a list of `policy_tokens` dicts, one per leaf state the search
/// is about to price with the hand eval, in pool order then boundary order.
/// The export is STATE-ONLY (`cands=[]`, `best=-1`), so `t[69]
/// is_the_acting_unit` reads 0 — the same zero the trainer masks (DESIGN §2) —
/// and the terrain block is the board's own since #608.
///
/// A Python exception is PARKED, not swallowed: `LeafValue::value` may answer
/// only with an `Unsupported`, so the error is stashed here and re-raised by
/// `plan_with_rollout`. A hook that silently declined would measure the hand
/// player against itself, the tripwire DESIGN §6 names.
struct PyLeafValue<'a> {
    fun: &'a Bound<'a, PyAny>,
    statics: &'a [UnitStatic],
    terrain: &'a Terrain,
    rows: RefCell<&'a mut RowEncoder>,
    hero_attach: bool,
    opener_seat: bool,
    err: RefCell<Option<PyErr>>,
}

impl LeafValue for PyLeafValue<'_> {
    fn value(&self, leaves: &[&CoreState], side: i64) -> Result<Vec<f64>, CoreUnsupported> {
        let (py, mut rows) = (self.fun.py(), self.rows.borrow_mut());
        let batch = PyList::empty(py);
        let park = |e: PyErr| {
            *self.err.borrow_mut() = Some(e);
            CoreUnsupported::LeafValue(0, leaves.len())
        };
        for st in leaves {
            let t = nmlcore::tokens::build(st, side, self.statics, self.terrain, &mut rows,
                &[], -1, self.hero_attach, self.opener_seat)?;
            to_py(py, &t.to_json()).and_then(|d| batch.append(d)).map_err(&park)?;
        }
        self.fun.call1((batch, side)).and_then(|o| o.extract::<Vec<f64>>()).map_err(&park)
    }
}

fn arb_plain(a: &Arbitration) -> Value {
    let mut m = Map::new();
    m.insert("n".into(), a.n.into());
    m.insert("sum_b".into(), a.sum_b.into());
    m.insert("sum_r".into(), a.sum_r.into());
    m.insert("swapped".into(), a.swapped.into());
    Value::Object(m)
}

/// The pick in the shape the recorder wrote it (`AiActRecorder.finish`
/// act_recorder.gd:80-82): the dictionary `plan_with_rollout` returned, plus
/// `trace` and the winning rollout's leaf state in plain form. `cands` is the
/// expert-iteration opt-in (step 1): true appends `trace.cands`, the CONTENT
/// of every built candidate in build index order — `scored[i].idx` joins —
/// and leaves every other key exactly where it was.
fn pick_plain(p: &Pick, cands: bool) -> Value {
    let mut out = Map::new();
    out.insert("used".into(), true.into());
    // NML-1158c: TRUE only when the exploration knob's coin fired on THIS
    // pick — see `Pick::explored`'s own doc for what the flag does and does
    // not say about the answer it left. The key rides ONLY an explored pick:
    // a default game writes the same pick object it always did (the
    // NML-1147a stamp law).
    if p.explored {
        out.insert("explored".into(), true.into());
    }
    out.insert("unit_key".into(), Value::String(p.unit_key.clone()));
    out.insert("action".into(), cand_plain(&p.action));
    let mut exp = Map::new();
    exp.insert("before".into(), p.expectation_before.into());
    exp.insert("after".into(), p.expectation_after.into());
    out.insert("expectation".into(), Value::Object(exp));
    let runner = match &p.runner_up {
        None => Value::Object(Map::new()),
        Some((uk, a, s)) => {
            let mut m = Map::new();
            m.insert("unit_key".into(), Value::String(uk.clone()));
            m.insert("action".into(), cand_plain(a));
            m.insert("score".into(), (*s).into());
            Value::Object(m)
        }
    };
    out.insert("runner_up".into(), runner);
    out.insert("waits".into(), p.waits.into());
    out.insert(
        "rolled_units".into(),
        Value::Array(p.rolled_units.iter().map(|k| Value::String(k.clone())).collect()),
    );
    let mut trace = Map::new();
    trace.insert(
        "scored".into(),
        Value::Array(
            p.scored
                .iter()
                .map(|(idx, unit, kind, s)| {
                    let mut m = Map::new();
                    m.insert("idx".into(), (*idx).into());
                    m.insert("unit".into(), Value::String(unit.clone()));
                    m.insert("kind".into(), (*kind).into());
                    m.insert("score".into(), (*s).into());
                    Value::Object(m)
                })
                .collect(),
        ),
    );
    trace.insert(
        "pool_idx".into(),
        Value::Array(p.pool_idx.iter().map(|&i| (i as i64).into()).collect()),
    );
    trace.insert(
        "rs".into(),
        Value::Array(
            p.rs.iter()
                .map(|(idx, v)| {
                    let mut m = Map::new();
                    m.insert("idx".into(), (*idx).into());
                    m.insert("rs".into(), (*v).into());
                    Value::Object(m)
                })
                .collect(),
        ),
    );
    if cands {
        trace.insert(
            "cands".into(),
            Value::Array(p.cands.iter().map(cand_plain).collect()),
        );
    }
    trace.insert("best_idx".into(), p.best_idx.into());
    trace.insert("runner_idx".into(), p.runner_idx.into());
    trace.insert(
        "arbitration".into(),
        p.arbitration.as_ref().map(arb_plain).unwrap_or(Value::Null),
    );
    out.insert("trace".into(), Value::Object(trace));
    out.insert(
        "leaf_state".into(),
        p.last_leaf.as_ref().map(io::plain_of).unwrap_or(Value::Null),
    );
    Value::Object(out)
}

// ------------------------------------------------------------------ State ---

/// One battle state. Opaque on purpose: the struct-of-arrays below is the whole
/// point of the port, and handing it out as a dict per call would spend more
/// time marshalling than searching. `plain()` is the escape hatch.
#[pyclass(unsendable, module = "nml_core", name = "State")]
pub struct PyState {
    inner: CoreState,
    /// The M2-5b `prof` block each unit came in with, in ROSTER order, kept
    /// verbatim — the same trick the Godot seam's `Captured` plays with its key
    /// mask. `io::plain_of` cannot write these back: two of the seven fields are
    /// deliberately unmodelled (`ProfileDyn`), so the reader keeps what it read.
    /// `None` on a state this port DERIVED (`resolve`, a rollout leaf): a
    /// derived state has no recorded read, and inventing one would be a lie.
    prof: Option<Vec<Option<Py<PyAny>>>>,
}

impl PyState {
    fn derived(inner: CoreState) -> PyState {
        PyState { inner, prof: None }
    }
}

#[pymethods]
impl PyState {
    /// The plain form `BattleSim.state_to_plain(state, false)` would have
    /// written — `io::plain_of`, the inverse of `Core.state_of`.
    fn plain(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let out = to_py(py, &io::plain_of(&self.inner))?;
        let Some(prof) = &self.prof else { return Ok(out) };
        let bound = out.bind(py);
        let units = bound.get_item("units")?;
        for (i, block) in prof.iter().enumerate() {
            let Some(block) = block else { continue };
            units.get_item(self.inner.key(i))?.set_item("prof", block.bind(py))?;
        }
        Ok(out)
    }

    /// A deep copy — `BattleSim.clone_state` battle_sim.gd:463-505.
    fn copy(&self, py: Python<'_>) -> PyState {
        PyState {
            inner: self.inner.clone(),
            prof: self
                .prof
                .as_ref()
                .map(|v| v.iter().map(|b| b.as_ref().map(|b| b.clone_ref(py))).collect()),
        }
    }

    /// The per-round reset a FORK PLAYOUT does (`tools/core_selfplay.gd:
    /// _fork_playout` :382-386): the round number, and `activated`/`fatigued`
    /// cleared on every unit of both sides.
    ///
    /// Deliberately NOT the game's own round start (`_play_one` :190-206), which
    /// also expires the spell modifiers and refills the Caster(X) tokens — an
    /// imagined round inherits the last one's modifiers, exactly as the shipped
    /// playouts do.
    fn refresh_round(&self, py: Python<'_>, round_no: i64) -> PyState {
        let mut out = self.copy(py);
        out.inner.round = round_no;
        for i in 0..out.inner.units() {
            out.inner.activated[i] = false;
            out.inner.fatigued[i] = false;
        }
        out
    }

    /// `su["casts"]` of every unit, in CAPTURE order — the spell-token ledger
    /// `_magic_tally` reads either side of the played apply (core_selfplay.gd
    /// :63-69) and `_magic_eligibility_tally` reads pre-apply (:109-114).
    fn casts(&self) -> Vec<i64> {
        self.inner.casts.clone()
    }

    /// `_magic_eligibility_tally`'s in-range test (core_selfplay.gd:124-131):
    /// does `actor` have a LIVING enemy whose nearest model sits within
    /// `range_in`? The 0.001" slack is the GDScript's own, and `BattleSim
    /// .dist_in` is `geom::dist_in` — the same f32 lengths.
    fn enemy_within(&self, actor: usize, range_in: f64) -> bool {
        let st = &self.inner;
        if actor >= st.units() {
            return false;
        }
        (0..st.units()).any(|i| {
            st.player[i] != st.player[actor]
                && st.alive[i] > 0
                && nmlcore::geom::dist_in(&st.positions[actor], &st.positions[i])
                    <= range_in + 0.001
        })
    }

    /// The `kind` stamp of every entry in `state["cast_events"]`, in order —
    /// what `_spells_by_kind_tally` (core_selfplay.gd:74-81) counts from its
    /// pre-apply mark. Empty while the cast sub-phase is off.
    fn cast_event_kinds(&self) -> Vec<String> {
        self.inner
            .cast_events
            .iter()
            .map(|e| e.get("kind").and_then(|k| k.as_str()).unwrap_or("").to_string())
            .collect()
    }

    /// The unit keys in CAPTURE order; every per-unit list this module returns
    /// is indexed by it.
    fn keys(&self) -> Vec<String> {
        self.inner.roster.keys.clone()
    }

    /// `SoloController.sim_move_bands(unit)` off THIS state's own per-unit
    /// table — `(advance, rush)` inches, the same field `mv::step::charge_move`
    /// reads internally as `state.bands[si].rush`. `plain_move` takes `band_in`
    /// from its CALLER instead: unlike a charge, a non-charge move's band
    /// depends on the act's own kind (ADVANCE vs RUSH), so `move_call_gate.py`
    /// reads this first. `None` for an unknown unit key.
    fn move_bands(&self, unit: &str) -> Option<(f64, f64)> {
        let st = &self.inner;
        st.roster.index.get(unit).map(|&i| (st.bands[i].advance, st.bands[i].rush))
    }

    #[getter]
    fn round(&self) -> i64 {
        self.inner.round
    }

    #[getter]
    fn rounds_total(&self) -> i64 {
        self.inner.rounds_total
    }

    #[getter]
    fn scoring(&self) -> String {
        self.inner.scoring.to_string()
    }

    #[getter]
    fn units(&self) -> usize {
        self.inner.units()
    }

    /// Own living, un-activated units of `player`, in capture order — what the
    /// harness loops over to know whether a side still has an activation.
    ///
    /// `hero_attach` is `Seams::hero_attach` (io.rs), the FOLD: under it a
    /// JOINED HERO is never an activation of its own
    /// (`SoloController.can_activate` solo_controller.gd:411) — it fires and
    /// moves inside its host's (D1-B4b). It defaults to `true`, which is what
    /// every caller written before NML-1127 got.
    ///
    /// NML-1127: it may not stay UNCONDITIONAL. The old comment here argued
    /// that folding always was harmless because "under `hero_attach="off"` no
    /// unit has a host anyway" — true until NML-1105, and false since:
    /// `tools/core_selfplay.gd` now builds its units through the table's
    /// import path, so its states carry an attachment graph while its pool
    /// (:431-436) still uses the planner's own filter and never folds. A
    /// harness that folds regardless is one activation short per joined hero
    /// and plays a different game from the oracle it is gated against.
    #[pyo3(signature = (player, hero_attach = true))]
    fn pool(&self, player: i64, hero_attach: bool) -> Vec<String> {
        let st = &self.inner;
        (0..st.units())
            .filter(|&i| st.can_activate(i, player, hero_attach))
            .map(|i| st.key(i).to_string())
            .collect()
    }

    /// Surviving models per side, `[p1, p2]` — `mission_winner`'s last two
    /// arguments, counted where the state is.
    fn alive_models(&self) -> Vec<i64> {
        let st = &self.inner;
        let mut out = vec![0i64; 2];
        for i in 0..st.units() {
            let side = st.player[i];
            if side == 1 || side == 2 {
                out[(side - 1) as usize] += st.alive[i].max(0);
            }
        }
        out
    }

    fn __repr__(&self) -> String {
        format!(
            "<nml_core.State round {}/{} units {}>",
            self.inner.round,
            self.inner.rounds_total,
            self.inner.units()
        )
    }
}

// -------------------------------------------------------------------- Rng ---

/// Godot's `RandomNumberGenerator`, bit-exact (`nmlcore::GodotRng`).
///
/// The harness owns the DICE, not this module: `tools/core_selfplay.gd:_play_one`
/// seeds ONE generator per game and keeps drawing from it — deployment, the
/// opener roll-off and every played `resolve_stochastic` share that stream, so a
/// per-call seed would be a different game. This is that generator, handed over
/// so a Python loop can hold it across activations.
#[pyclass(unsendable, module = "nml_core", name = "Rng")]
pub struct PyRng {
    inner: GodotRng,
}

#[pymethods]
impl PyRng {
    /// `var rng := RandomNumberGenerator.new(); rng.seed = seed`.
    #[new]
    fn new(seed: i64) -> PyRng {
        PyRng { inner: GodotRng::new(seed) }
    }

    /// `rng.seed = seed` on a live generator.
    fn seed(&mut self, seed: i64) {
        self.inner.seed(seed);
    }

    /// `rng.state`, readable and writable exactly as GDScript reads it.
    #[getter]
    fn state(&self) -> i64 {
        self.inner.state_i64()
    }

    #[setter]
    fn set_state(&mut self, state: i64) {
        self.inner.state = state as u64;
    }

    /// `rng.randf()` — the f32 draw, widened the way a Variant float is.
    fn randf(&mut self) -> f64 {
        self.inner.randf()
    }

    /// `rng.randf_range(from, to)` — single-precision, one rounding per op.
    fn randf_range(&mut self, from: f64, to: f64) -> f64 {
        self.inner.randf_range(from, to)
    }

    /// `rng.randi_range(from, to)` — the biased modulo, one draw.
    fn randi_range(&mut self, from: i64, to: i64) -> i64 {
        self.inner.randi_range(from, to)
    }

    /// One raw PCG32 draw — the unit the other three are counted in.
    fn rand_u32(&mut self) -> u32 {
        self.inner.rand_u32()
    }

    fn __repr__(&self) -> String {
        format!("<nml_core.Rng state {}>", self.inner.state_i64())
    }
}

// ------------------------------------------------------------------- Tray ---

/// The table's DICE TRAY (`nmlcore::Tray`) — NML-1073 M5 D1-B3.
///
/// A SECOND stream, deliberately: `Rng` above is the game's own generator
/// (deployment, opener roll-off, played activations), while the tray is the
/// one `main.seed_tray_rng(_dice_seed)` seeds after deployment
/// (arena_match.gd:478, main.gd:7120-7121). Sharing one generator between the
/// two could never reproduce the table, however correct the roll order got.
///
/// `roll(count)` is `main.gd:7152-7159` including its `maxi(1, count)`: a
/// zero-die roll returns ONE face and burns ONE draw.
#[pyclass(unsendable, module = "nml_core", name = "Tray")]
pub struct PyTray {
    inner: Tray,
}

#[pymethods]
impl PyTray {
    /// `main.seed_tray_rng(seed)`.
    #[new]
    fn new(seed: i64) -> PyTray {
        PyTray { inner: Tray::seeded(seed) }
    }

    /// Re-seeds in place, as a second `seed_tray_rng` call would.
    fn seed(&mut self, seed: i64) {
        self.inner.seed(seed);
    }

    /// `_solo_tray_roll(count, ..)` in batch mode: the faces, in draw order.
    /// Widened to `i64` on the way out so Python sees a `list[int]` (a
    /// `Vec<u8>` would marshal as `bytes`).
    fn roll(&mut self, count: usize) -> Vec<i64> {
        self.inner.roll(count).into_iter().map(i64::from).collect()
    }

    /// `rng.state` of the tray's own generator — the replay checkpoint.
    #[getter]
    fn state(&self) -> i64 {
        self.inner.state_i64()
    }

    fn __repr__(&self) -> String {
        format!("<nml_core.Tray state {}>", self.inner.state_i64())
    }
}

// ------------------------------------------------------------------- Core ---

/// The per-game closure: the profile table, the board, the search knobs and the
/// derived per-unit statics. Built once from the act-corpus header and shared by
/// every state, exactly the way `read_acts` interns them across a whole corpus.
#[pyclass(unsendable, module = "nml_core")]
pub struct Core {
    repo_root: String,
    /// `None` until `set_header`. Carries the header table and interns the
    /// per-activation ones (NML-1073 M2-5b).
    profiles: Option<ProfileCache>,
    reg: Option<Registries>,
    statics: StaticsCache,
    terrain: Terrain,
    knobs: Knobs,
    roster: Option<Rc<Roster>>,
    /// The encoder row vocabulary + its loud unknown-rule collector, read once
    /// from `repo_root/data/encoder_rule_vocab_v1.json` (NML-1073 M3-6a).
    rows: RowEncoder,
    /// NML-1142 — the trained eval, `None` until `load_net`. Its presence IS
    /// this core's `AiMissionEval.fit_mode`: every search it runs takes the
    /// blended fitted leaf, and one that does not want it must not load a net.
    net: Option<Fitted>,
    /// NML-1158b step 7 — the ORDER-mode policy net, `None` until
    /// `load_policy_net`. Presence alone does not arm it: `plan_with_rollout`
    /// wires it in only when the CALLED act's `statics.policy_mode` asks for
    /// `Order`, the same contract `net`/`fit_mode` already keep.
    policy_net: Option<PolicyHarness>,
}

impl Core {
    fn no_header() -> PyErr {
        Unsupported::new_err("no header — call Core.set_header(header) first")
    }

    /// The `UnitStatic` closure that belongs to THIS state's profile table —
    /// `lib.rs::act_statics`, one activation at a time. Built once per distinct
    /// table; a state whose table never moved shares the header's closure.
    fn statics_for(&mut self, state: &CoreState) -> PyResult<Rc<Vec<UnitStatic>>> {
        let reg = self.reg.as_mut().ok_or_else(Core::no_header)?;
        Ok(self.statics.get(reg, &state.profiles))
    }

    fn seams(&self) -> Seams {
        Seams {
            spacing: self.knobs.seam_spacing,
            cast: self.knobs.seam_cast,
            hero_last: self.knobs.hero_last,
            cast_fold: self.knobs.cast_fold,
            path: self.knobs.seam_path,
            hero_attach: self.knobs.hero_attach,
            charge_landing: self.knobs.charge_landing,
            // NML-1073 M5 D6a-B4 — `sighting="model"` in the header turns the
            // per-model, per-weapon die count on for the TRAY resolver only.
            sighting: self.knobs.sighting == Sighting::Model,
            movement: self.knobs.movement,
            move_rigid: self.knobs.move_rigid,
            // NML-1073 M5 D1-B8 — the header's RED switch, inverted: `dangerous`
            // defaults true, so the p.12 test runs unless a gate turns it off.
            no_dangerous: !self.knobs.dangerous,
            // NML-1073 M5 D5-4 — the header's RED switch, inverted: `hero_fold`
            // defaults true, so the engage test folds unless a gate says no.
            no_engage_fold: !self.knobs.engage_fold,
            // NML-1160 — with `los_model` the state's sight seams are the
            // table's per-model answer, so a clone inherits them untouched.
            los_model: self.knobs.los_model,
            // W2 S0 — `melee_reach="table"` in the header scales a strike
            // phase's attacks by the models within 2" of an enemy model.
            melee_reach: self.knobs.melee_reach == MeleeReach::Table,
            // W1 — `menu_wide` owns both halves: the menu offers ADVANCE+shoot
            // and the resolve stops declining it. See `Seams::moved_shoot`.
            moved_shoot: self.knobs.menu_wide || self.knobs.moved_shoot,
            // DEFECT_LEDGER #12 — passed straight through, not inverted: a
            // NEW rule, so an absent key (every corpus recorded before it)
            // stays OFF.
            dangerous_end_morale: self.knobs.dangerous_end_morale,
            // GF v3.5.1 p.9 — `consolidate="table"` in the header.
            consolidate: self.knobs.consolidate,
            // Rung I (DEFECT_LEDGER row 31) — `cond_ap_dice` in the header.
            cond_ap_dice: self.knobs.cond_ap_dice,
            // PR #582's charge-distance bonus — `versatile_reach` in the
            // header (INVESTIGATION_gen0_replay_drift_2026-09-03.md).
            versatile_reach: self.knobs.versatile_reach,
            // The CLASS FIX (external review 03.09. item 3 / F9) —
            // `rules_epoch` in the header, `acts::CURRENT_RULES_EPOCH` for a
            // fresh one.
            rules_epoch: self.knobs.rules_epoch,
        }
    }

    /// The menu tuning this header resolved to — `plan::tuning_of`, the SAME
    /// derivation `plan_with_rollout` uses inside the crate, so the seam and the
    /// crate's own entry points cannot drift on a menu knob.
    fn tuning(&self) -> Tuning {
        nmlcore::tuning_of(&self.knobs)
    }
}

#[pymethods]
impl Core {
    /// The act-corpus header line, verbatim: `{"profiles": {...}, "terrain":
    /// {cells, cell_params, sandbox} | null, "knobs": {...}}`. Parsed through
    /// `acts::read_act_header`, so the Python seam and the JSONL loader cannot
    /// drift apart, and the per-unit `UnitStatic` closure is built from the
    /// mechanics assets under `repo_root`.
    fn set_header(&mut self, header: &Bound<'_, PyAny>) -> PyResult<()> {
        let text = json_text(header)?;
        let ActHeader { profiles, terrain, knobs } = nmlcore::read_act_header(&text)
            .map_err(|e| Unsupported::new_err(e))?;
        self.profiles = Some(ProfileCache::new(profiles));
        self.reg = Some(Registries::new(&self.repo_root));
        // The statics closures are built under THIS record's rule set —
        // `Knobs::rules_epoch` gates the epoch-gated rule ports inside
        // `UnitStatic::build_for` (epoch 0/2 corpora replay byte-exact).
        // The header's own `rules_epoch` — `acts::rule_on`'s build-time leg:
        // the statics this corpus stamps read the epoch its header carries.
        self.statics = StaticsCache::with_epoch(knobs.rules_epoch);
        self.terrain = terrain;
        self.knobs = knobs;
        self.roster = None;
        // NML-1134: the board rows are slotted with the vocabulary THIS corpus
        // was recorded under — `knobs.rule_vocab_version`, absent meaning the
        // pre-stamp version 2. A version the committed file cannot serve is an
        // error HERE, not a silently different row later.
        self.rows.set_vocab_version(&self.repo_root, self.knobs.rule_vocab_version);
        if !self.rows.vocab.loaded {
            return Err(Unsupported::new_err(
                self.rows.vocab.error.clone().unwrap_or_else(|| "rule vocab unreadable".into()),
            ));
        }
        Ok(())
    }

    /// The resolved search knobs, as they came out of the header.
    fn knobs(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let mut m = Map::new();
        m.insert("top_k".into(), self.knobs.top_k.into());
        m.insert("horizon".into(), self.knobs.horizon.into());
        m.insert("tail_cap_p1".into(), self.knobs.tail_cap_p1.into());
        m.insert("tail_cap_p2".into(), self.knobs.tail_cap_p2.into());
        m.insert("imagined_round_end".into(), self.knobs.imagined_round_end.into());
        m.insert("depth_discount".into(), self.knobs.depth_discount.into());
        m.insert("seat_mode".into(), self.knobs.seat_mode.into());
        m.insert("playout_margin".into(), self.knobs.playout_margin.into());
        m.insert("playout_rich".into(), self.knobs.playout_rich.into());
        m.insert("seam_cast".into(), self.knobs.seam_cast.into());
        m.insert("seam_spacing".into(), self.knobs.seam_spacing.into());
        m.insert("seam_path".into(), self.knobs.seam_path.into());
        m.insert("hero_last".into(), self.knobs.hero_last.into());
        m.insert("cast_fold".into(), self.knobs.cast_fold.into());
        m.insert("charge_gate".into(), self.knobs.charge_gate.into());
        m.insert("menu_targets".into(), self.knobs.menu_targets.into());
        m.insert("hero_attach".into(), self.knobs.hero_attach.into());
        m.insert("charge_landing".into(), self.knobs.charge_landing.into());
        m.insert(
            "sighting".into(),
            Value::String(
                match self.knobs.sighting {
                    Sighting::Unit => "unit",
                    Sighting::Model => "model",
                }
                .into(),
            ),
        );
        m.insert("movement".into(), self.knobs.movement.into());
        m.insert("move_rigid".into(), self.knobs.move_rigid.into());
        m.insert("dangerous".into(), self.knobs.dangerous.into());
        m.insert("engage_fold".into(), self.knobs.engage_fold.into());
        m.insert("rule_vocab_version".into(), self.knobs.rule_vocab_version.into());
        m.insert("eval_variant".into(), self.knobs.eval_variant.into());
        m.insert(
            "melee_reach".into(),
            Value::String(
                match self.knobs.melee_reach {
                    MeleeReach::All => "all",
                    MeleeReach::Table => "table",
                }
                .into(),
            ),
        );
        m.insert("consolidate".into(), self.knobs.consolidate.into());
        to_py(py, &Value::Object(m))
    }

    /// NML-1073 M5 D5-2 — the header's `walls` as the PORT converted them, in
    /// the movement planner's 0-origin INCH frame (`[[ax, ay], [bx, by]]` per
    /// segment). The act header writes `get_wall_segments_world()` in WORLD
    /// METRES while `moves_calls.jsonl` writes board-local INCHES; this is the
    /// instrument that proves the one conversion between them, because a gate
    /// can hold it against the recorded inch list segment by segment.
    fn walls_in(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let v: Vec<Value> = self
            .terrain
            .walls_in()
            .iter()
            .map(|w| {
                Value::Array(
                    w.iter()
                        .map(|p| {
                            Value::Array(
                                p.iter().map(|c| Value::from(*c as f64)).collect::<Vec<_>>(),
                            )
                        })
                        .collect::<Vec<_>>(),
                )
            })
            .collect();
        to_py(py, &Value::Array(v))
    }

    /// The charge-legality STAMP this caller wires — `AiActRecorder.
    /// _charge_illegal_matrix` (act_recorder.gd:204-222) read off the pure
    /// contract instead of off a live `Callable`.
    ///
    /// On the table `SoloController` stamps `state["charge_illegal"]` with
    /// `charge_candidate_illegal` (solo_controller.gd:1450, wired at
    /// :3002/:3358/:3475/:3704) and the recorder samples it for every ordered
    /// pair of ALIVE opposite-side units at that pair's ROOT gap
    /// (`dist_in - CONTACT_IN`, floored at 0 — not the edge gap `_best_charge`
    /// uses). `gate::charge_illegal` is that same body as a pure function of
    /// the capture (NML-1073 M2-0c), so this method answers what the table
    /// stamped.
    ///
    /// The `charge_gate` knob IS the GDScript's `cb.is_valid()`: a caller that
    /// wires no gate stamps NOTHING, so this returns `{}` — the same empty dict
    /// the recorder writes for `tools/core_selfplay.gd`. That is what makes the
    /// gate-off arm a real red proof rather than a second green.
    fn charge_illegal_matrix(&self, py: Python<'_>, state: PyRef<'_, PyState>) -> PyResult<Py<PyAny>> {
        let mut m = Map::new();
        if !self.knobs.charge_gate {
            return to_py(py, &Value::Object(m));
        }
        let st = &state.inner;
        for a in 0..st.units() {
            if st.alive[a] <= 0 {
                continue;
            }
            for v in 0..st.units() {
                if v == a || st.alive[v] <= 0 || st.player[v] == st.player[a] {
                    continue;
                }
                let gap = (geom::dist_in(&st.positions[a], &st.positions[v])
                    - nmlcore::CONTACT_IN)
                    .max(0.0);
                let bad =
                    nmlcore::charge_illegal(st, &self.terrain, a, v, gap, None, None);
                m.insert(format!("{}|{}", st.key(a), st.key(v)), bad.into());
            }
        }
        to_py(py, &Value::Object(m))
    }

    /// NML-1073 M5 D5-2 — the TABLE's charge MOVE for one (charger, target)
    /// pair, exactly as `Seams::movement` runs it, without resolving a melee.
    ///
    /// This is the sharp instrument for the rung: `end` can be held against the
    /// per-model endpoints `moves_calls.jsonl` recorded for the same activation,
    /// and `call` is the `plan_unit_step` input the port BUILT, so a landing
    /// that misses can be traced to the field of the call that differs rather
    /// than guessed at. `None` when the port declines (no board, no models).
    fn charge_move(
        &self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        unit: &str,
        target: &str,
    ) -> PyResult<Py<PyAny>> {
        let st = &state.inner;
        let (Some(&si), Some(&ci)) =
            (st.roster.index.get(unit), st.roster.index.get(target))
        else {
            return to_py(py, &Value::Null);
        };
        let land = (nmlcore::mv::step::MoveRules { rules_epoch: self.knobs.rules_epoch }).charge_move(
            st,
            &self.terrain,
            si,
            ci,
            st.bands[si].rush,
            self.knobs.hero_attach,
            true,
            nmlcore::mv::FAST_PLANNER_GUARD,
        );
        let Some(mut l) = land else { return to_py(py, &Value::Null) };
        let snap = l.snap_charge(st, ci, self.knobs.rules_epoch);
        let mut m = Map::new();
        m.insert("snap_in".into(), snap.map(Value::from).unwrap_or(Value::Null));
        m.insert(
            "movers".into(),
            Value::Array(
                l.movers
                    .iter()
                    .map(|mv| Value::Array(vec![(mv.unit as i64).into(), (mv.model as i64).into()]))
                    .collect(),
            ),
        );
        m.insert(
            "end".into(),
            Value::Array(
                l.end
                    .iter()
                    .map(|p| Value::Array(p.iter().map(|c| Value::from(*c as f64)).collect()))
                    .collect(),
            ),
        );
        m.insert("budget_in".into(), Value::from(l.budget_in));
        m.insert("arc_in".into(), Value::from(l.arc_in));
        m.insert("remaining_in".into(), Value::from(l.remaining_in()));
        if let Some(c) = &l.call {
            let text = nmlcore::mv::entry::canonical_input(c);
            m.insert("call".into(), serde_json::from_str(&text).unwrap_or(Value::Null));
        }
        to_py(py, &Value::Object(m))
    }

    /// NML-1073 M5 S4 — the table's NON-CHARGE move (ADVANCE/RUSH/the post-melee
    /// consolidation step) for one unit aimed at `dest` (a world `[x, y, z]`
    /// point, e.g. the AI act's own recorded `dest`), granted `band_in`.
    ///
    /// Same return shape as `charge_move`, so `move_call_gate.py` scores it with
    /// the identical END/CALL/BUDGET bars. `band_in` is the CALLER's to pick
    /// (the advance or rush band off the act's own kind) because a plain move,
    /// unlike a charge, is not always the rush band. `None` when the port
    /// declines (no board, no models).
    fn plain_move(
        &self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        unit: &str,
        dest: &Bound<'_, PyAny>,
        band_in: f64,
    ) -> PyResult<Py<PyAny>> {
        let st = &state.inner;
        let Some(&si) = st.roster.index.get(unit) else {
            return to_py(py, &Value::Null);
        };
        let land = (nmlcore::mv::step::MoveRules { rules_epoch: self.knobs.rules_epoch }).plain_move(
            st,
            &self.terrain,
            si,
            v3_of(dest)?,
            band_in,
            self.knobs.hero_attach,
            true,
            nmlcore::mv::FAST_PLANNER_GUARD,
        );
        let Some(l) = land else { return to_py(py, &Value::Null) };
        let mut m = Map::new();
        m.insert(
            "movers".into(),
            Value::Array(
                l.movers
                    .iter()
                    .map(|mv| Value::Array(vec![(mv.unit as i64).into(), (mv.model as i64).into()]))
                    .collect(),
            ),
        );
        m.insert(
            "end".into(),
            Value::Array(
                l.end
                    .iter()
                    .map(|p| Value::Array(p.iter().map(|c| Value::from(*c as f64)).collect()))
                    .collect(),
            ),
        );
        m.insert("shorten_covered".into(), Value::Bool(l.shorten_covered));
        m.insert("budget_in".into(), Value::from(l.budget_in));
        m.insert("arc_in".into(), Value::from(l.arc_in));
        m.insert("remaining_in".into(), Value::from(l.remaining_in()));
        if let Some(c) = &l.call {
            let text = nmlcore::mv::entry::canonical_input(c);
            m.insert("call".into(), serde_json::from_str(&text).unwrap_or(Value::Null));
        }
        to_py(py, &Value::Object(m))
    }

    /// The capture-time registry reads for every unit of the header's profile
    /// table — `{key: {morale_bonus, aircraft, charge_no_difficult, shroud}}`.
    ///
    /// `BattleSim.capture` and `AiActRecorder._stamp_gate_reads` take these off
    /// the LIVE `GameUnit` through `RulesRegistry`; a Godot-free capture has to
    /// answer them from the SAME mechanics maps this module already loaded, or
    /// the harness would carry a second registry reader that can drift.
    /// `shroud` is `None` when no rule of the Shrouding family fires.
    fn capture_reads(&mut self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let profiles = self.profiles.as_ref().ok_or_else(Core::no_header)?;
        let reg = self.reg.as_mut().ok_or_else(Core::no_header)?;
        let base = profiles.base();
        let mut out = Map::new();
        for p in &base.list {
            let r = nmlcore::capture_reads(reg, p);
            let mut m = Map::new();
            m.insert("morale_bonus".into(), r.morale_bonus.into());
            m.insert("aircraft".into(), r.aircraft.into());
            m.insert("charge_no_difficult".into(), r.charge_no_difficult.into());
            m.insert(
                "shroud".into(),
                match r.shroud {
                    Some(s) => Value::Array(vec![s[0].into(), s[1].into()]),
                    None => Value::Null,
                },
            );
            out.insert(p.unit_id.clone(), Value::Object(m));
        }
        to_py(py, &Value::Object(out))
    }

    /// The ARRIVAL-time reads for every unit of the header's profile table —
    /// what `_try_place_reserve_unit` asks the live `GameUnit` and the registry
    /// for, answered here so the trainer never grows a second reader that can
    /// drift (the `capture_reads` precedent above).
    ///
    /// * `ring_m` — `_reserve_min_enemy_dist_m` (solo_controller.gd:9617-9621):
    ///   the infiltrator's registry-scoped ring, else the plain 9" Ambush one.
    /// * `repel_m` — `repel_ambush_dist_m` (:9724-9727), `0.0` without the rule.
    /// * `beacon` — an "Ambush Beacon" carrier's models project the 6" waiver
    ///   circle (:9781+); own rule line or item grant, like `unit_carries_rule`.
    /// * `earliest` — `ambush_earliest_round` (:9832-9835): 1 with Rapid
    ///   Ambush, else 2 (GF/AoF v3.5.1 p.13, "any round after the first").
    /// * `flying` — the p.13 difficult-terrain exemption the arrival branches
    ///   on (:10047), a plain rule-name read.
    /// * `radius` / `footprint` / `base_r` / `models` — the already-ported
    ///   deploy geometry (deployment.rs:495/:510), reused unchanged.
    fn arrival_reads(&mut self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let profiles = self.profiles.as_ref().ok_or_else(Core::no_header)?;
        let reg = self.reg.as_mut().ok_or_else(Core::no_header)?;
        let base = profiles.base();
        let mut out = Map::new();
        for p in &base.list {
            let us = UnitStatic::build_for(reg, p, self.knobs.rules_epoch);
            let n = p.model_count.max(1) as usize;
            let carries = |r: &str| {
                nmlcore::rules::has_special_rule(&p.special_rules, r)
                    || nmlcore::rules::has_special_rule(&p.item_grants, r)
            };
            let mut m = Map::new();
            m.insert(
                "ring_m".into(),
                if us.infiltrate_min_enemy_dist_in > 0.0 {
                    (us.infiltrate_min_enemy_dist_in * nmlcore::IN2M).into()
                } else {
                    deployment::AMBUSH_MIN_ENEMY_DIST_M.into()
                },
            );
            m.insert("repel_m".into(), (us.repel_ambushers_dist_in * nmlcore::IN2M).into());
            m.insert("beacon".into(), carries("Ambush Beacon").into());
            // Ambush family (rules-wave2-ambush): the registry's own values at
            // `rules_epoch` 4 — `beacon_in` off the "Ambush Beacon" entry, the
            // table's 6" constant below it (:9766); `arrive_from_round` off
            // "Rapid Ambush", the name-literal 1/2 ladder below it (:9832-9835).
            m.insert(
                "beacon_r_m".into(),
                if us.ambush_family.beacon_radius_in > 0.0 {
                    us.ambush_family.beacon_radius_in * nmlcore::IN2M
                } else {
                    deployment::AMBUSH_BEACON_RADIUS_IN * nmlcore::IN2M
                }
                .into(),
            );
            m.insert(
                "earliest".into(),
                if us.ambush_family.arrive_from_round > 0 {
                    us.ambush_family.arrive_from_round
                } else if carries("Rapid Ambush") {
                    1
                } else {
                    2
                }
                .into(),
            );
            m.insert("flying".into(), (carries("Strider") || carries("Flying")).into());
            m.insert("radius".into(), deployment::deploy_footprint_radius(n, p.base_radius).into());
            m.insert("base_r".into(), p.base_radius.into());
            m.insert("models".into(), (n as i64).into());
            m.insert(
                "footprint".into(),
                Value::Array(
                    deployment::deploy_footprint_offsets(n, p.base_radius, false)
                        .iter()
                        .map(|o| Value::Array(vec![o.0.into(), o.1.into()]))
                        .collect(),
                ),
            );
            out.insert(p.unit_id.clone(), Value::Object(m));
        }
        to_py(py, &Value::Object(out))
    }

    /// `SpellsRegistry.spells_for_unit` spells_registry.gd:62-63 — every
    /// header unit's spell BOOK, by unit id, as the `range_in` of each entry in
    /// book order. The registry keys on (system, faction) alone, so this is NOT
    /// gated on Caster(X), exactly like the GDScript: `_magic_init` asks a
    /// token-bearing unit whether its book resolved, and
    /// `_magic_eligibility_tally` asks for its longest range.
    fn spell_ranges(&mut self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let profiles = self.profiles.as_ref().ok_or_else(Core::no_header)?;
        let reg = self.reg.as_mut().ok_or_else(Core::no_header)?;
        let base = profiles.base();
        let mut out = Map::new();
        for p in &base.list {
            let book: Vec<Value> = reg
                .spells_for(&p.game_system, &p.faction_folder)
                .iter()
                .map(|sp| sp.range_in.into())
                .collect();
            out.insert(p.unit_id.clone(), Value::Array(book));
        }
        to_py(py, &Value::Object(out))
    }

    /// True when the header carried a board — a `Terrain::absent()` is the
    /// `terrain_at.is_valid() == false` case, and `resolve` then leaves the
    /// mover's cover flag exactly as the parent state had it.
    fn has_terrain(&self) -> bool {
        self.terrain.is_valid()
    }

    /// One plain state (the object the act corpus carries under `"state"`).
    fn state_of(&mut self, plain: &Bound<'_, PyAny>) -> PyResult<PyState> {
        let text = json_text(plain)?;
        let profiles = self.profiles.as_mut().ok_or_else(Core::no_header)?;
        let mut cache = self.roster.take();
        let st = io::state_from_json(&text, profiles, &mut cache)
            .map_err(|e| Unsupported::new_err(e))?;
        self.roster = cache;
        // The `prof` blocks are kept as they came, not re-derived — see the
        // note on `PyState::prof`.
        let units = plain.get_item("units")?;
        let mut prof = Vec::with_capacity(st.units());
        let mut any = false;
        for i in 0..st.units() {
            let block = units.get_item(st.key(i))?.cast::<PyDict>()?.get_item("prof")?;
            any |= block.is_some();
            prof.push(block.map(|b| b.unbind()));
        }
        Ok(PyState { inner: st, prof: if any { Some(prof) } else { None } })
    }

    /// NML-1160 — re-stamp both sight seams of one state with the TABLE's
    /// per-model answer: every unit's `los` row and the `los_pairs` matrix, all
    /// from `sight::sight_matrix` over this header's board.
    ///
    /// `BattleSim.capture` runs that sweep before EVERY activation
    /// (battle_sim.gd:1563-1576, `los_of` = `SoloController._has_los`); the
    /// search underneath then inherits the answer, because `clone_state` copies
    /// `su["los"]` and never recomputes it. This is the trainer's way of doing
    /// the same, and it is the caller's job to ask for it at the same cadence:
    /// `selfplay._play_round` calls it once per played activation.
    ///
    /// Both seams are written, because the port reads two: the menu asks
    /// `BattleSim.sees` (the `los` row) and the resolve ANDs it with
    /// `_los_clear` (the matrix). Filling only one leaves the other's answer
    /// standing, which is exactly the split this knob exists to close.
    fn restamp_los(&self, py: Python<'_>, state: &PyState) -> PyState {
        let mut out = state.copy(py);
        let n = out.inner.units();
        let m = sight::sight_matrix(&out.inner, &self.terrain);
        let rows: Vec<Option<Rc<HashMap<String, bool>>>> = (0..n)
            .map(|i| {
                Some(Rc::new(
                    (0..n)
                        .filter(|&j| out.inner.player[j] != out.inner.player[i])
                        .map(|j| (out.inner.key(j).to_string(), m[i * n + j]))
                        .collect(),
                ))
            })
            .collect();
        out.inner.los = rows;
        out.inner.los_pairs = Some(Rc::new(m));
        out
    }

    /// `AiPlanner.plan_with_rollout` ai_planner.gd:118-275 — the whole search.
    ///
    /// `statics` is the per-activation class-static snapshot the recorder writes
    /// (`opener_seat`, `playout_search`, `fit_mode`, `playout_net`); `sig` is
    /// `AiPlanner._playout_sig` at record time and is an INPUT — without it a
    /// close top-2 declines rather than inventing a dice stream.
    ///
    /// Returns the pick plus `trace` and `leaf_state`, or `{"used": false,
    /// "unsupported": <reason>}` when the port declines.
    ///
    /// `eps` / `explore_seed` are the EXPLORATION KNOB (NML-1158c): `eps` is
    /// the trainer's `--explore` (0..1, 0 = never), and `explore_seed` seeds a
    /// FRESH `GodotRng` for this one call — its own dedicated stream, exactly
    /// as `resolve_stochastic` seeds a fresh one per call (module docstring's
    /// SEEDS section). The caller derives `explore_seed` from the game seed
    /// and the activation sequence, never from the game's own dice generator,
    /// so the coin/index draws below never touch it. `eps <= 0.0` (every call
    /// before this knob existed) takes zero draws in `Search::run` and is
    /// byte-identical to `None`.
    ///
    /// `cands` is the EXPERT-ITERATION opt-in (step 1): when true, `trace`
    /// gains `cands` — every built candidate's full content, in build index
    /// order, each the same `cand_plain` shape `action` uses, joined by
    /// `trace.scored`'s `idx`. False (every call before this knob existed)
    /// writes a trace byte-identical to what it always wrote.
    ///
    /// `cand_logits` / `policy_mode` are the R4 SEAM (DESIGN_policy_player §6):
    /// one f32 per built candidate, in the menu's own order, and the knob that
    /// arms them. `policy_mode="order"` visits the menu in DESCENDING logit
    /// order and keeps the top-K by logit; `None`/`"off"` (every call written
    /// before this seam) leaves both the statics and the order exactly as they
    /// were. A logit vector whose length is not the built menu's DECLINES —
    /// see `Unsupported::CandLogits`.
    ///
    /// `leaf_value_fn` / `leaf_value_w` are the R4 SEAM of DESIGN_value_net
    /// §7: `fn(leaves, side) -> list[float]`, called ONCE per activation with
    /// EVERY leaf state the search would price with the hand eval — the round
    /// boundaries of every pooled candidate's rollout, pool order then
    /// boundary order, each exported as a `policy_tokens` dict. The answer is
    /// blended in AT THE LEAF (`hand + w * value`) before the rollout backs
    /// up, so the net moves the number the pick is made on. `None` / `0.0`
    /// (every call written before this seam) never builds a batch and is
    /// byte-identical to the recorded behaviour; a weight armed with NO hook
    /// declines (`Unsupported::LeafValueMissing`) rather than quietly playing
    /// the hand leaf, and an answer of the wrong length declines too
    /// (`Unsupported::LeafValue`).
    #[pyo3(signature = (state, player, statics, sig = None, eps = 0.0, explore_seed = 0, cands = false, cand_logits = None, policy_mode = None, leaf_value_fn = None, leaf_value_w = 0.0))]
    #[allow(clippy::too_many_arguments)]
    fn plan_with_rollout(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        player: i64,
        statics: &Bound<'_, PyAny>,
        sig: Option<i64>,
        eps: f64,
        explore_seed: i64,
        cands: bool,
        cand_logits: Option<Vec<f32>>,
        policy_mode: Option<&str>,
        leaf_value_fn: Option<&Bound<'_, PyAny>>,
        leaf_value_w: f64,
    ) -> PyResult<Py<PyAny>> {
        let mut act: ActStatics = serde_json::from_value(value_of(statics)?)
            .map_err(|e| Unsupported::new_err(format!("statics: {e}")))?;
        match policy_mode {
            None => {}
            Some("off") => act.policy_mode = PolicyMode::Off,
            Some("order") => act.policy_mode = PolicyMode::Order,
            Some(m) => return Err(Unsupported::new_err(format!("policy_mode: {m}"))),
        }
        let statics = self.statics_for(&state.inner)?;
        let seams = self.seams();
        let tuning = self.tuning();
        let mut policy = Policy::new(&statics, &self.terrain, seams);
        policy.tuning = tuning;
        // The net is this core's `AiMissionEval.fit_mode`, but WHETHER it is
        // switched on is the activation's own static. An act recorded with the
        // hand eval must replay on the hand eval even on a core that carries a
        // net — and one recorded with the fitted eval on a core that does not
        // is declined by `admissible`, not silently answered.
        policy.fit = self.net.as_ref().filter(|_| act.fit_mode);
        // NML-1158b step 7 — same contract, ORDER mode: an act that asks for
        // it and reaches a core with no policy net loaded is declined by
        // `admissible` (`Unsupported::PolicyOrder`), not silently answered.
        policy.policy_net =
            self.policy_net.as_ref().filter(|_| act.policy_mode == PolicyMode::Order);
        let roll = Rollout::new(policy, self.knobs);
        let mut search = Search::new(roll, &act);
        search.sig = sig;
        search.cand_logits = cand_logits.as_deref();
        // NML-1165 R4 — the leaf value seam. The WEIGHT rides even with no
        // hook so `admissible` can decline it; the hook itself borrows this
        // core's own row encoder, which is what makes the leaf export the same
        // `policy_tokens` a live token player already reads.
        let rows = RefCell::new(&mut self.rows);
        let hook = leaf_value_fn.map(|f| PyLeafValue {
            fun: f, statics: &statics, terrain: &self.terrain, rows,
            hero_attach: seams.hero_attach, opener_seat: act.opener_seat,
            err: RefCell::new(None),
        });
        search.leaf_value = hook.as_ref().map(|h| h as &dyn LeafValue);
        search.leaf_value_w = leaf_value_w;
        let mut sc = Scratch::default();
        let mut xr = GodotRng::new(explore_seed);
        match search.run(&state.inner, player, &mut sc, Some((eps, &mut xr))) {
            Ok(pick) => to_py(py, &pick_plain(&pick, cands)),
            Err(u) => {
                // A PARKED Python error is the hook's own, and it is re-raised
                // rather than flattened into a decline: a value-net game that
                // silently fell back to the hand leaf would measure the hand
                // player against itself (DESIGN §6's fallback tripwire).
                if let Some(e) = hook.as_ref().and_then(|h| h.err.borrow_mut().take()) {
                    return Err(e);
                }
                let mut m = Map::new();
                m.insert("used".into(), false.into());
                m.insert("unsupported".into(), Value::String(format!("{u:?}")));
                to_py(py, &Value::Object(m))
            }
        }
    }

    /// `AiPlanner._policy_candidates`'s parent — the FULL menu of one unit
    /// (`menu::candidates_in`), for the harness's diagnostics.
    fn candidates(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        unit_key: &str,
    ) -> PyResult<Py<PyAny>> {
        let st = &state.inner;
        let Some(&i) = st.roster.index.get(unit_key) else {
            return Err(Unsupported::new_err(format!("UnknownUnit({unit_key})")));
        };
        let statics = self.statics_for(st)?;
        let mut sc = Scratch::default();
        let menu = candidates_tuned(st, &self.terrain, &statics, i, &mut sc, self.tuning());
        to_py(py, &Value::Array(menu.iter().map(cand_plain).collect()))
    }

    /// `BattleSim.resolve` battle_sim.gd:631 — one activation resolved IN
    /// EXPECTATION against the header's board.
    fn resolve(
        &mut self,
        state: PyRef<'_, PyState>,
        action: &Bound<'_, PyAny>,
    ) -> PyResult<PyState> {
        let act: Action = serde_json::from_value(value_of(action)?)
            .map_err(|e| Unsupported::new_err(format!("action: {e}")))?;
        let statics = self.statics_for(&state.inner)?;
        resolve_on_board(&statics, &state.inner, &act, &self.terrain, self.seams())
            .map(PyState::derived)
            .map_err(declined)
    }

    /// `BattleSim.resolve_stochastic` battle_sim.gd:473 — the same activation
    /// with every wound-rounding remainder decided by a coin flip.
    ///
    /// The CALLER owns the seed. `tools/core_selfplay.gd:262-268` builds the
    /// log-local one as `game_seed * 100000 + row_index` (`+ 50000` for the
    /// runner-up branch); this module reproduces no formula of its own.
    fn resolve_stochastic(
        &mut self,
        state: PyRef<'_, PyState>,
        action: &Bound<'_, PyAny>,
        seed: i64,
    ) -> PyResult<PyState> {
        let act: Action = serde_json::from_value(value_of(action)?)
            .map_err(|e| Unsupported::new_err(format!("action: {e}")))?;
        let statics = self.statics_for(&state.inner)?;
        let mut rng = GodotRng::new(seed);
        resolve_stochastic_on_board(
            &statics,
            &state.inner,
            &act,
            &self.terrain,
            self.seams(),
            &mut rng,
        )
        .map(PyState::derived)
        .map_err(declined)
    }

    /// The same activation against a LIVE generator — the game's own dice
    /// stream, advanced by this call and kept by the caller (`tools/
    /// core_selfplay.gd:_play_round` passes the game `rng` to every played
    /// resolve). `resolve_stochastic` above seeds a fresh one per call, which is
    /// what the log-local pair/fork branches want and what a whole game does not.
    fn resolve_stochastic_rng(
        &mut self,
        state: PyRef<'_, PyState>,
        action: &Bound<'_, PyAny>,
        rng: &mut PyRng,
    ) -> PyResult<PyState> {
        let act: Action = serde_json::from_value(value_of(action)?)
            .map_err(|e| Unsupported::new_err(format!("action: {e}")))?;
        let statics = self.statics_for(&state.inner)?;
        resolve_stochastic_on_board(
            &statics,
            &state.inner,
            &act,
            &self.terrain,
            self.seams(),
            &mut rng.inner,
        )
        .map(PyState::derived)
        .map_err(declined)
    }

    /// NML-1073 M5 D1-B4 — the same played activation with `dice="table"`:
    /// the SHOOTING sub-phase draws from `tray` in the table's own draw order
    /// (`nmlcore::dice::resolve_shooting_with_tray`) instead of filling an
    /// expected-value pool. `rng` still runs everything else, so the two
    /// streams stay split the way the table's are.
    ///
    /// Returns `(state, report)` with `report = {"rolls": [{"kind", "count",
    /// "target", "faces"}], "unported": [name, ...], "log": [line, ...]}` —
    /// `rolls` in draw order
    /// (what `dice.jsonl` records), `unported` the table branches THIS
    /// activation hit that the port does not reproduce. A caller that ignores
    /// `unported` is choosing to ignore a known divergence, not being told
    /// nothing.
    fn resolve_with_tray(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        action: &Bound<'_, PyAny>,
        rng: &mut PyRng,
        tray: &mut PyTray,
    ) -> PyResult<(PyState, Py<PyAny>)> {
        let act: Action = serde_json::from_value(value_of(action)?)
            .map_err(|e| Unsupported::new_err(format!("action: {e}")))?;
        let statics = self.statics_for(&state.inner)?;
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics,
            &state.inner,
            &act,
            &self.terrain,
            self.seams(),
            &mut rng.inner,
            &mut tray.inner,
        )
        .map_err(declined)?;
        let rolls: Vec<Value> = shot
            .rolls
            .iter()
            .map(|r| {
                serde_json::json!({
                    "kind": r.kind,
                    "count": r.count,
                    "target": r.target,
                    "faces": r.faces.iter().map(|&f| f as i64).collect::<Vec<i64>>(),
                    // D1-B4b: WHO rolled it — `dice.jsonl` wraps this in
                    // `"AI (%s)"` (main.gd:7039-7040).
                    "owner": r.owner,
                })
            })
            .collect();
        let report = serde_json::json!({
            "rolls": Value::Array(rolls),
            "unported": shot.unported.iter().map(|s| Value::String((*s).into())).collect::<Vec<Value>>(),
            // Block B13 — the rules-must-log lines, in order (dice.rs's
            // `ShootResult.log`): the twin's ledger beside the dice stream.
            "log": shot.log.iter().map(|s| Value::String(s.clone())).collect::<Vec<Value>>(),
        });
        Ok((PyState::derived(next), to_py(py, &report)?))
    }

    /// `AiMissionEval.score` with the reply threat — the RICH leaf
    /// (`AiPlanner._policy_step` ai_planner.gd:508-510).
    fn score(&mut self, state: PyRef<'_, PyState>, player: i64) -> PyResult<f64> {
        let statics = self.statics_for(&state.inner)?;
        let incoming = reply_threat(&statics, &state.inner, player);
        Ok(score_with(&state.inner, &statics, player, &incoming, self.net.as_ref()))
    }

    /// The same score WITHOUT the reply threat — the cheap leaf.
    fn score_cheap(&mut self, state: PyRef<'_, PyState>, player: i64) -> PyResult<f64> {
        let statics = self.statics_for(&state.inner)?;
        Ok(score_with(
            &state.inner,
            &statics,
            player,
            nmlcore::NO_INCOMING,
            self.net.as_ref(),
        ))
    }

    /// NML-1142 — load a `netlab/fork_train.py` ENCODER net and play with it.
    /// The loader GATE is the GDScript's own (`_encoder_selftest_ok`): a net
    /// without a `selftest` block, or one whose forward here misses that block's
    /// answer by more than 1e-4, RAISES instead of quietly scoring games.
    ///
    /// `scale` is the RED-PROOF seam and 1.0 in every real call: the net's own
    /// answer times this, before the blend.
    ///
    /// `mode` (NML-1158a) is "blend" (the E4.2 mix, the default) or "residual"
    /// (the net's sigmoid read as a DELTA on the hand scale —
    /// `nmlcore::score::combine_residual` owns the one scale definition).
    /// Anything else is a clean error, never a silently reinterpreted net.
    ///
    /// Returns the net's shape, so a caller can log WHICH brain it just armed.
    #[pyo3(signature = (path, scale = 1.0, blend = None, mode = "blend"))]
    fn load_net(
        &mut self,
        py: Python<'_>,
        path: &str,
        scale: f64,
        blend: Option<f64>,
        mode: &str,
    ) -> PyResult<Py<PyAny>> {
        let fit_mode = match mode {
            "blend" => nmlcore::fitted::FitMode::Blend,
            "residual" => nmlcore::fitted::FitMode::Residual,
            other => {
                return Err(Unsupported::new_err(format!(
                    "unknown fit mode {other:?} — expected \"blend\" or \"residual\""
                )))
            }
        };
        let net = nmlcore::Net::load(path).map_err(Unsupported::new_err)?;
        let shape = serde_json::json!({
            "slots": net.slots.len(),
            "keys": net.keys.len(),
            "hidden": net.unit_b1.len(),
            "mode": mode,
        });
        let mut fit =
            Fitted::new(net, &self.repo_root).map_err(Unsupported::new_err)?;
        fit.set_source_qd(self.rows.source_qd);
        fit.scale = scale;
        fit.mode = fit_mode;
        if let Some(b) = blend {
            fit.blend = b;
        }
        self.net = Some(fit);
        to_py(py, &shape)
    }

    /// True when a net is armed — the trainer reads it as `fit_mode`.
    fn has_net(&self) -> bool {
        self.net.is_some()
    }

    /// NML-1158b step 7 — loads the ORDER-mode net (schema `policy_net/1`,
    /// `policy::PolicyNet::load`'s own selftest gate). `scale` mirrors
    /// `load_net`'s red-proof lever, but multiplies the LOGIT, not a leaf
    /// score: an ORDER gate compares a PERMUTATION, so `scale < 0` is the
    /// red proof (fitted_gate.py's positive-scale magnitude lever does not
    /// apply here — see `policy::Policy::scale`'s own doc).
    #[pyo3(signature = (path, scale = 1.0))]
    fn load_policy_net(&mut self, path: &str, scale: f64) -> PyResult<()> {
        let net = PolicyNet::load(path).map_err(Unsupported::new_err)?;
        let mut harness = PolicyHarness::new(net, &self.repo_root).map_err(Unsupported::new_err)?;
        harness.scale = scale;
        // Legacy replay only — see `Policy::set_source_qd`'s own doc: a state
        // rebuilt from a plain corpus reads the stand-in `source_data` 4/4.
        harness.set_source_qd(self.rows.source_qd);
        self.policy_net = Some(harness);
        Ok(())
    }

    /// True when a policy net is armed — mirrors `has_net`.
    fn has_policy_net(&self) -> bool {
        self.policy_net.is_some()
    }

    /// `BattleSim.reply_threat` battle_sim.gd:1099 — expected reply wounds per
    /// unit, indexed by CAPTURE order (`State.keys()`), not by key.
    fn reply_threat(&mut self, state: PyRef<'_, PyState>, player: i64) -> PyResult<Vec<f64>> {
        let statics = self.statics_for(&state.inner)?;
        Ok(reply_threat(&statics, &state.inner, player))
    }

    /// `AiPlanner._policy_step` ai_planner.gd:602-624 with the RICH leaf — the
    /// cheap greedy brain `tools/core_selfplay.gd:_fork_pick` (:422-430) plays
    /// every fork continuation with. Returns the action dict, or `None` when the
    /// side has no living un-activated unit with a candidate.
    #[pyo3(signature = (state, player, rich = true))]
    fn policy_step(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        player: i64,
        rich: bool,
    ) -> PyResult<Option<Py<PyAny>>> {
        let statics = self.statics_for(&state.inner)?;
        let mut policy = Policy::new(&statics, &self.terrain, self.seams());
        policy.tuning = self.tuning();
        policy.fit = self.net.as_ref();
        let mut sc = Scratch::default();
        match policy.policy_step(&state.inner, player, rich, &mut sc) {
            Ok(None) => Ok(None),
            Ok(Some(c)) => Ok(Some(to_py(py, &cand_plain(&c))?)),
            Err(u) => Err(declined(u)),
        }
    }

    // -------------------------------------------------- encoder rows / eval ---

    /// NML-1073 M5 D6a-B3 — the port's PER-MODEL sighted count for one shot,
    /// so `tools/sight_gate.py` can hold `sight.rs` against the table's own
    /// recorded `sighted` (`shots.jsonl`, scripts/solo/shot_recorder.gd) instead
    /// of against another guess.
    ///
    /// `member` is the firing unit key (the host, or one of its attached
    /// heroes); `target` the unit it fires at; `reach_in` the weapon's reach in
    /// inches BEFORE the base-edge slack, which `sight::sighted_count` adds the
    /// way `main._solo_sighted_count` (:4141-4145) adds it. `slack_in` comes
    /// back so the caller can check that half against the recorded
    /// `reach_in` rather than trust it: the recording stamps
    /// `int(reach) + slack`, so `recorded - slack_in` must land on an integer.
    #[pyo3(signature = (state, member, target, reach_in, indirect = false))]
    fn sighted(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        member: &str,
        target: &str,
        reach_in: f64,
        indirect: bool,
    ) -> PyResult<Py<PyAny>> {
        let st = &state.inner;
        let idx = |k: &str| {
            st.roster.index.get(k).copied().ok_or_else(|| Unsupported::new_err(format!("no unit {k}")))
        };
        let (mi, ti) = (idx(member)?, idx(target)?);
        let zones = nmlcore::sight::zones_of(&self.terrain);
        let blockers = nmlcore::sight::blockers_of(st, mi, ti);
        let n = nmlcore::sight::sighted_count(st, &zones, &blockers, mi, ti, reach_in, indirect);
        let slack = nmlcore::sight::unit_radius_m(st, mi) + nmlcore::sight::unit_radius_m(st, ti);
        to_py(
            py,
            &serde_json::json!({
                "sighted": n,
                "alive": st.alive[mi],
                "slack_in": slack / nmlcore::sight::IN2M,
                "blockers": blockers.len(),
                "zones": zones.len(),
                // NON-ZERO is a seam, not a detail — see `Terrain::sandbox_pieces`.
                "sandbox": self.terrain.sandbox_pieces(),
            }),
        )
    }

    /// NML-1132 — the weapon set the EXPECTED-VALUE half of `resolve` really fires
    /// with: `sim::member_profiles_of` for one unit at one state, ranged or melee,
    /// under THIS header's seams. `hero_ev_gate.py`'s instrument — it asks the twin
    /// what its imagination believes the unit carries instead of restating the rule
    /// in Python, so the gate measures the code and not a paraphrase of it.
    ///
    /// `d` is the reach the range filter uses (ranged only; melee has no gate) —
    /// pass `fold_dist_in`'s answer by handing `target` instead, which measures it
    /// the way `resolve` does. Comes back as `{"names": [...], "attacks": [...],
    /// "d_in": float, "folded": bool}`: `names`/`attacks` are the profiles that
    /// PASSED the filter, in the order the EV reads them.
    #[pyo3(signature = (state, unit, melee = false, target = None, d_in = 0.0))]
    fn imagined_profiles(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        unit: &str,
        melee: bool,
        target: Option<&str>,
        d_in: f64,
    ) -> PyResult<Py<PyAny>> {
        let st = &state.inner;
        let idx = |k: &str| {
            st.roster.index.get(k).copied().ok_or_else(|| Unsupported::new_err(format!("no unit {k}")))
        };
        let si = idx(unit)?;
        let seams = self.seams();
        let d = match target {
            Some(t) => nmlcore::sim::fold_dist_in(st, si, idx(t)?, seams),
            None => d_in,
        };
        let statics = self.statics_for(st)?;
        let mut sc = nmlcore::sim::Scratch::default();
        nmlcore::member_profiles_of(&statics, st, si, melee, d, seams, &mut sc);
        let us = &statics[st.roster.profile[si]];
        let own = if melee { &us.melee } else { &us.shoot };
        let all = nmlcore::folded_slice(own, &sc);
        // MELEE has no `keep` (every profile strikes); SHOOTING indexes through it.
        let keep: Vec<usize> = if melee { (0..all.len()).collect() } else { sc.keep.clone() };
        to_py(
            py,
            &serde_json::json!({
                "names": keep.iter().map(|&i| all[i].name.clone()).collect::<Vec<_>>(),
                "attacks": sc.attacks,
                "d_in": d,
                "folded": !sc.fold.is_empty(),
            }),
        )
    }

    /// `BattleSim.board_rows` battle_sim.gd:176 — the v5 encoder input: one row
    /// per LIVING unit in capture order, then one per objective (type 3), then
    /// the single game-state row (type 4). Ints come back as Python ints and
    /// floats as Python floats, the way `JSON.stringify` writes them.
    fn board_rows(&mut self, py: Python<'_>, state: PyRef<'_, PyState>) -> PyResult<Py<PyAny>> {
        if !self.rows.vocab.loaded {
            return Err(Unsupported::new_err(self.rows.vocab.error.clone().unwrap_or_else(
                || format!("rule vocab unreadable at {}/{}", self.repo_root, nmlcore::rows::RULE_VOCAB_PATH),
            )));
        }
        let statics = self.statics_for(&state.inner)?;
        let rows = self.rows.board_rows(&state.inner, &statics);
        let out = PyList::empty(py);
        for row in rows {
            let r = PyList::empty(py);
            for c in row {
                match c {
                    Cell::I(v) => r.append(v)?,
                    Cell::F(v) => r.append(v)?,
                }
            }
            out.append(r)?;
        }
        Ok(out.into_any().unbind())
    }

    /// DESIGN_gen0_training_2026-09-02.md §8.2 — `policy_vecs`'s replacement:
    /// the board-seeing token export. `cands` is the recorded `cands.list` as
    /// plain dicts (the same shape `cand_plain` above writes); `best` is the
    /// recorded pick's build index, returned unchanged as `label`. `hero_attach`
    /// mirrors the unit token's own `can_activate` seam; `opener_seat` is
    /// `ActStatics.opener_seat` (acts.rs:328), a per-act header field `State`
    /// does not carry, so the caller reads it off `act["statics"]` and passes
    /// it — the two DEVIATIONs from the design's literal 4-argument table are
    /// both keyword, both default to the corpus's own common case, and both are
    /// spelled out in `nmlcore::tokens`'s own module doc.
    #[pyo3(signature = (state, side, cands, best, hero_attach = false, opener_seat = false))]
    fn policy_tokens(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        side: i64,
        cands: &Bound<'_, PyAny>,
        best: i64,
        hero_attach: bool,
        opener_seat: bool,
    ) -> PyResult<Py<PyAny>> {
        let statics = self.statics_for(&state.inner)?;
        let cand_list: Vec<Candidate> =
            serde_json::from_value(value_of(cands)?).map_err(|e| Unsupported::new_err(e.to_string()))?;
        let t = nmlcore::tokens::build(
            &state.inner,
            side,
            &statics,
            &self.terrain,
            &mut self.rows,
            &cand_list,
            best,
            hero_attach,
            opener_seat,
        )
        .map_err(declined)?;
        Ok(tokens_dict(py, t)?.into_any().unbind())
    }

    /// `BattleSim.board_row_indices` battle_sim.gd:166 — the capture index of
    /// every unit row, in row order.
    fn board_row_indices(&self, state: PyRef<'_, PyState>) -> Vec<i64> {
        nmlcore::board_row_indices(&state.inner)
    }

    /// LEGACY REPLAY ONLY — board columns 10 and 11 (`quality`, `defense`).
    /// The shipped encoder reads them off the unit's live profile, which is what
    /// `tools/core_selfplay.gd` writes since the `source_data` fill (#392) and
    /// what this module does by default. A corpus recorded BEFORE that fix reads
    /// the blank `OPRApiClient.OPRUnit` defaults (4/4) in every row; set this to
    /// `(4, 4)` to reproduce such a corpus, and to nothing else.
    fn set_encoder_source_qd(&mut self, quality: i64, defense: i64) {
        self.rows.source_qd = Some((quality, defense));
        // The fitted eval encodes its own rows; a reading set here that did not
        // reach it would leave the two halves of one core disagreeing.
        if let Some(f) = self.net.as_ref() {
            f.set_source_qd(Some((quality, defense)));
        }
    }

    /// Drop the legacy column-10/11 override — back to the profile's own
    /// quality/defense, the default and the only setting a fresh corpus may use.
    fn clear_encoder_source_qd(&mut self) {
        self.rows.source_qd = None;
        if let Some(f) = self.net.as_ref() {
            f.set_source_qd(None);
        }
    }

    /// Rule/spell names the committed vocabulary does not carry, collected
    /// across every `board_rows` call — `BattleSim.unknown_rules` (:82), which
    /// the GDScript also stamps into its result rather than slotting silently.
    fn unknown_rules(&self) -> Vec<String> {
        // BOTH collectors (NML-1142): the fitted eval encodes its own rows, and
        // in a `--no-sidecars` net game it is the only encoder that ran.
        let mut out: std::collections::BTreeSet<String> = self.rows.unknown.iter().cloned().collect();
        if let Some(f) = self.net.as_ref() {
            out.extend(f.unknown());
        }
        out.into_iter().collect()
    }

    /// `AiMissionEval.features` ai_mission_eval.gd:480 — the eval's raw feature
    /// vector for `player`, as a name -> float dict.
    ///
    /// `incoming` defaults to `BattleSim.reply_threat(state, player)` (what both
    /// logging sites pass); hand `[]` for the `{}` default. `rich` is the
    /// feature-wave gate — the trainer logs with it ON. `reserves` is
    /// `(mine, theirs)`, 0/0 on every state that is not one of the two in-game
    /// logging sites (nothing else carries the key).
    #[pyo3(signature = (state, player, incoming = None, rich = false, reserves = (0.0, 0.0)))]
    fn features(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        player: i64,
        incoming: Option<Vec<f64>>,
        rich: bool,
        reserves: (f64, f64),
    ) -> PyResult<Py<PyAny>> {
        let statics = self.statics_for(&state.inner)?;
        let inc = match incoming {
            Some(v) => v,
            None => reply_threat(&statics, &state.inner, player),
        };
        let vals =
            nmlcore::features(&state.inner, &statics, player, &inc, rich, reserves);
        let d = PyDict::new(py);
        for (k, v) in nmlcore::FEATURE_KEYS.iter().zip(vals) {
            d.set_item(*k, v)?;
        }
        Ok(d.into_any().unbind())
    }

    // ------------------------------------------------------------ mission ---

    /// `BattleSim.playout_seize` battle_sim.gd:268 — the 3" ring, applied to
    /// both the owners array and the state's objectives. Returns the NEW state
    /// and the new owners, because the GDScript mutates both in place.
    fn playout_seize(
        &self,
        state: PyRef<'_, PyState>,
        owners: Vec<i64>,
    ) -> (PyState, Vec<i64>) {
        let mut st = state.inner.clone();
        let mut own = owners;
        mission::playout_seize(&mut st, &mut own);
        (PyState::derived(st), own)
    }

    /// `BattleSim.vp_round_add` battle_sim.gd:332 — 1 VP per controlled marker.
    fn vp_round_add(&self, owners: Vec<i64>, vp: Vec<i64>) -> PyResult<Vec<i64>> {
        let mut out = pair(&vp)?;
        mission::vp_round_add(&owners, &mut out);
        Ok(out.to_vec())
    }

    /// `BattleSim.vp_end_bonus` battle_sim.gd:340 — +1 VP for holding MORE.
    fn vp_end_bonus(&self, owners: Vec<i64>, vp: Vec<i64>) -> PyResult<Vec<i64>> {
        let mut out = pair(&vp)?;
        mission::vp_end_bonus(&owners, &mut out);
        Ok(out.to_vec())
    }

    /// `BattleSim.vp_score_round` battle_sim.gd:361 — every `round_vp` flavour.
    /// Returns `(vp, memo)`: the GDScript writes into both.
    #[pyo3(signature = (owners, vp, flavour, memo, markers))]
    fn vp_score_round(
        &self,
        py: Python<'_>,
        owners: Vec<i64>,
        vp: Vec<i64>,
        flavour: &Bound<'_, PyAny>,
        memo: &Bound<'_, PyAny>,
        markers: &Bound<'_, PyAny>,
    ) -> PyResult<(Vec<i64>, Py<PyAny>)> {
        let flavour = value_of(flavour)?;
        let mut memo_map = match value_of(memo)? {
            Value::Object(m) => m,
            _ => Map::new(),
        };
        let markers: Vec<Marker> = serde_json::from_value(value_of(markers)?)
            .map_err(|e| Unsupported::new_err(format!("markers: {e}")))?;
        let mut out = pair(&vp)?;
        mission::vp_score_round(&owners, &mut out, &flavour, &mut memo_map, &markers);
        Ok((out.to_vec(), to_py(py, &Value::Object(memo_map))?))
    }

    /// `BattleSim.vp_score_end` battle_sim.gd:397 — the game-end majority bonus,
    /// paid only when the flavour defers it to the END.
    fn vp_score_end(
        &self,
        owners: Vec<i64>,
        vp: Vec<i64>,
        flavour: &Bound<'_, PyAny>,
    ) -> PyResult<Vec<i64>> {
        let flavour = value_of(flavour)?;
        let mut out = pair(&vp)?;
        mission::vp_score_end(&owners, &mut out, &flavour);
        Ok(out.to_vec())
    }

    /// `BattleSim.apply_destroy_step` battle_sim.gd:408 — an owned destructible
    /// marker the ENEMY alone holds at a round end falls. Returns the new
    /// `(markers, owners, seq)`, the three arrays the GDScript mutates.
    fn apply_destroy_step(
        &self,
        py: Python<'_>,
        markers: &Bound<'_, PyAny>,
        owners: Vec<i64>,
        seq: Vec<i64>,
    ) -> PyResult<(Py<PyAny>, Vec<i64>, Vec<i64>)> {
        let mut m: Vec<Marker> = serde_json::from_value(value_of(markers)?)
            .map_err(|e| Unsupported::new_err(format!("markers: {e}")))?;
        let mut own = owners;
        let mut s = seq;
        mission::apply_destroy_step(&mut m, &mut own, &mut s);
        let back = serde_json::to_value(&m).map_err(|e| Unsupported::new_err(e.to_string()))?;
        Ok((to_py(py, &back)?, own, s))
    }

    /// `BattleSim.mission_winner` battle_sim.gd:450 — the end-of-game referee.
    /// `"p1"`, `"p2"` or `"draw"`.
    fn mission_winner(
        &self,
        scoring: &str,
        owners: Vec<i64>,
        vp: Vec<i64>,
        markers: &Bound<'_, PyAny>,
        alive1: i64,
        alive2: i64,
    ) -> PyResult<String> {
        let m: Vec<Marker> = serde_json::from_value(value_of(markers)?)
            .map_err(|e| Unsupported::new_err(format!("markers: {e}")))?;
        Ok(mission::mission_winner(scoring, &owners, pair(&vp)?, &m, alive1, alive2).to_string())
    }

    fn __repr__(&self) -> String {
        format!(
            "<nml_core.Core repo {} profiles {} terrain {}>",
            self.repo_root,
            self.profiles.as_ref().map(|p| p.base().list.len()).unwrap_or(0),
            self.terrain.is_valid()
        )
    }
}

/// Builds a `Core` that reads its mechanics assets (`assets/solo/
/// rules_mechanics_<system>.json`, `spells_mechanics_<system>.json`) from
/// `repo_root`. Feed it a header next.
#[pyfunction]
fn load(repo_root: &str) -> Core {
    Core {
        repo_root: repo_root.to_string(),
        profiles: None,
        reg: None,
        statics: StaticsCache::new(),
        terrain: Terrain::absent(),
        knobs: Knobs::default(),
        roster: None,
        rows: RowEncoder::new(repo_root),
        net: None,
        policy_net: None,
    }
}

/// LEGACY REPLAY ONLY — restore the pre-NML-1112 PREFIX reading of rule names
/// for every `Core` in this process. `False` (the default, and the only setting
/// a fresh corpus may use) is the shipped rule: exact name or parametrised form.
///
/// The frozen corpora were recorded by `tools/core_selfplay.gd`, which runs no
/// aura expansion, so a "Furious Aura" carrier answered the "Furious" query only
/// through the old prefix match — baked into board column 18 (the flag) and
/// column 13 (melee EV, via the attack context). NEITHER reading is game-true: a
/// real aura grants unit-wide, the prefix gave it to the carrier alone. The
/// corpora pin the SEARCH LOOP, not the rule; the loader gap is NML-1105.
#[pyfunction]
fn set_legacy_prefix_rules(on: bool) {
    nmlcore::rules::LEGACY_PREFIX_RULES.store(on, std::sync::atomic::Ordering::Relaxed);
}

/// LEGACY REPLAY ONLY — skip the NML-1103 conditional-AP stamp for every `Core`
/// in this process, so the EV prices Shatter / Tear / Disintegrate / Melee
/// Slayer / Piercing Assault / Piercing Hunter at their PRINTED AP the way the
/// pre-NML-1103 `BattleSim` did. `False` (the default, and the only setting a
/// fresh corpus may use) is the shipped rule.
///
/// `AiEv.stamp_conditional_ap` was never called in the sim path, so the frozen
/// corpora under `~/selfplay_out` recorded a search that valued those weapons at
/// AP(0) while the TABLE resolved them with the bonus. Replaying one of those
/// games against the fixed EV measures the fix, not the search loop the corpus
/// pins. Neither reading is game-true forever: re-record after NML-1105 and this
/// flag retires with the corpora.
#[pyfunction]
fn set_legacy_no_cond_ap(on: bool) {
    nmlcore::unit::LEGACY_NO_COND_AP.store(on, std::sync::atomic::Ordering::Relaxed);
}

/// NML-1134 — the rule-vocabulary version one act header asks to be replayed
/// under. THE ONE RULE, and the only implementation of it: the header's
/// `knobs.rule_vocab_version` when it carries one, else 2, because every corpus
/// recorded before the stamp existed was recorded under version 2. The Python
/// fixtures and gates call this; the Rust tests call
/// `nmlcore::vocab_version_of_header` — the same function.
#[pyfunction]
fn vocab_version_of_header(header: &Bound<'_, PyAny>) -> PyResult<i64> {
    Ok(nmlcore::vocab_version_of_header(&json_text(header)?))
}

/// NML-1134 — the vocabulary version THIS build reads, i.e. the one a FRESH
/// game (and a freshly recorded corpus) is slotted with.
#[pyfunction]
fn rule_vocab_version() -> i64 {
    nmlcore::RULE_VOCAB_VERSION
}

// ------------------------------------------------------------------ Board ---

/// The header's `"terrain"` object, read once. Every lookup below is a pure
/// function of these cells, so a caller that asks more than one question builds
/// the board once instead of re-reading the dict per call — a 30x30 lattice over
/// 200 banked boards is 180 000 questions.
#[pyclass(unsendable, module = "nml_core")]
pub struct Board {
    inner: Terrain,
}

/// One `[x, y, z]` list as a Godot `Vector3` — the positions the corpus carries
/// are f64 text of f32 values, so the narrowing is lossless.
fn v3_of(p: &Bound<'_, PyAny>) -> PyResult<[f32; 3]> {
    let v: Vec<f64> = p.extract()?;
    if v.len() != 3 {
        return Err(Unsupported::new_err(format!("a point is [x, y, z], got {} entries", v.len())));
    }
    Ok(geom::to_f32([v[0], v[1], v[2]]))
}

#[pymethods]
impl Board {
    /// `SchoolTerrain.generate`'s `world["n"]` — the grid is `n` x `n` cells,
    /// derived from `cell_params` the way `map_layout._calculate_grid_dimensions`
    /// derives it from the table.
    fn n(&self) -> i64 {
        self.inner.n()
    }

    /// True when the header carried a board at all.
    fn is_valid(&self) -> bool {
        self.inner.is_valid()
    }

    /// `TerrainOverlay.get_terrain_at_world_position` — the cell grid first, the
    /// freely placed sandbox shapes second. `SchoolTerrain.type_at`
    /// (school_terrain.gd:58-60) reads the SAME cells through its own two
    /// constants; the terrain-bank gate proves the two readings agree.
    fn type_at(&self, p: &Bound<'_, PyAny>) -> PyResult<i32> {
        Ok(self.inner.type_at(v3_of(p)?))
    }

    /// `SchoolTerrain.los_blocked` school_terrain.gd:65-83 — the seam
    /// `tools/core_selfplay.gd:675` stamps on every state it searches.
    fn los_blocked(&self, a: &Bound<'_, PyAny>, b: &Bound<'_, PyAny>) -> PyResult<bool> {
        Ok(self.inner.los_blocked(v3_of(a)?, v3_of(b)?))
    }

    /// `BattleSim.state_to_plain`'s `"los_pairs"` block, battle_sim.gd:1492-1506
    /// — hand it a plain state's `"units"` dict (only `"positions"` is read) and
    /// it answers the same rows the recorder wrote, key-sorted (NML-1073 M3-0b).
    fn los_pairs(&self, units: &Bound<'_, PyAny>) -> PyResult<Vec<String>> {
        let read: Map<String, Value> = match value_of(units)? {
            Value::Object(m) => m,
            _ => return Err(Unsupported::new_err("units must be a dict of unit key -> unit")),
        };
        let mut list = Vec::with_capacity(read.len());
        for (k, v) in read {
            // Only `"positions"` is read: `_centre_of` is the whole input, and a
            // unit with none is `Vector3.ZERO` exactly as battle_sim.gd:802 says.
            let ps = match v.get("positions") {
                Some(Value::Array(a)) => a.clone(),
                None | Some(Value::Null) => vec![],
                Some(_) => return Err(Unsupported::new_err(format!("{k}: positions is not a list"))),
            };
            let mut out = Vec::with_capacity(ps.len());
            for pos in ps {
                let xyz: [f64; 3] = serde_json::from_value(pos)
                    .map_err(|e| Unsupported::new_err(format!("{k}: position: {e}")))?;
                out.push(xyz);
            }
            list.push((k, out));
        }
        Ok(self.inner.los_pairs(&list))
    }

    fn __repr__(&self) -> String {
        format!("<nml_core.Board n {} valid {}>", self.inner.n(), self.inner.is_valid())
    }

    /// The bank v2 prop layer (`terrain.rs::set_bank_props`, steps 4c/4d):
    /// `walls` `[x1, y1, x2, y2]`, `blockers` `[x, y, r]`, `boxes`
    /// `[cx, cy, half_w, half_h, angle, reach]` — table-centred inches
    /// (+ radians), converted with the board's own `in2m`. Empty lists are
    /// default-preserving. NOTE: this OVERWRITES `walls_in`/`walls_world` —
    /// call it on a board built from the bank's own cells, whose header walls
    /// are `[]` by contract.
    fn set_bank_props(
        &mut self,
        walls: &Bound<'_, PyAny>,
        blockers: &Bound<'_, PyAny>,
        boxes: &Bound<'_, PyAny>,
    ) -> PyResult<()> {
        let w: Vec<[f64; 4]> = json_of(walls, "walls")?;
        let b: Vec<[f64; 3]> = json_of(blockers, "blockers")?;
        let x: Vec<[f64; 6]> = json_of(boxes, "boxes")?;
        self.inner.set_bank_props(&w, &b, &x);
        Ok(())
    }
}

/// Reads one act header's `"terrain"` object (or `None`) into a `Board`.
#[pyfunction]
fn board(terrain: Option<&Bound<'_, PyAny>>) -> PyResult<Board> {
    let Some(terrain) = terrain else { return Ok(Board { inner: Terrain::absent() }) };
    if terrain.is_none() {
        return Ok(Board { inner: Terrain::absent() });
    }
    let p: PlainTerrain = serde_json::from_value(value_of(terrain)?)
        .map_err(|e| Unsupported::new_err(format!("terrain: {e}")))?;
    Ok(Board { inner: Terrain::build(&p) })
}

/// `board(terrain).type_at(p)` — the one-shot form.
#[pyfunction]
fn type_at(terrain: Option<&Bound<'_, PyAny>>, p: &Bound<'_, PyAny>) -> PyResult<i32> {
    board(terrain)?.type_at(p)
}

/// `board(terrain).los_blocked(a, b)` — the one-shot form.
#[pyfunction]
fn los_blocked(
    terrain: Option<&Bound<'_, PyAny>>,
    a: &Bound<'_, PyAny>,
    b: &Bound<'_, PyAny>,
) -> PyResult<bool> {
    board(terrain)?.los_blocked(a, b)
}

/// D8a — the rulebook objective layout for one game, derived from the layout seed and
/// the board. `count` is the mission's raw catalog value (a NUMBER draws no die, a
/// "d3+N" string does), `style` a `DeploymentCatalog` style dict. Returns the same
/// stamp `ObjectiveLayout.generate` returns, so the trainer can compare it field for
/// field with the act header's `objectives` block.
#[pyfunction]
#[pyo3(signature = (terrain, layout_seed, count, style, table_w_in=72.0, table_d_in=48.0))]
fn objective_layout(
    py: Python<'_>,
    terrain: Option<&Bound<'_, PyAny>>,
    layout_seed: i64,
    count: &Bound<'_, PyAny>,
    style: &Bound<'_, PyAny>,
    table_w_in: f64,
    table_d_in: f64,
) -> PyResult<Py<PyAny>> {
    let b = board(terrain)?;
    let cells = objectives::Cells::from_terrain(&b.inner);
    let zones = objectives::zones_of_style(&value_of(style)?);
    let lay = objectives::generate(
        layout_seed,
        &value_of(count)?,
        &zones,
        &cells,
        table_w_in,
        table_d_in,
    );
    let out = PyDict::new(py);
    out.set_item("mode", "rulebook")?;
    out.set_item("count_roll", lay.count_roll)?;
    out.set_item("first_placer", lay.first_placer)?;
    out.set_item("layout_seed", lay.layout_seed)?;
    out.set_item("edge_margin_in", lay.edge_margin_in)?;
    out.set_item(
        "positions",
        lay.positions.iter().map(|&(x, z)| vec![x, z]).collect::<Vec<_>>(),
    )?;
    out.set_item("placed_by", lay.placed_by.clone())?;
    out.set_item("swept", lay.swept)?;
    Ok(out.into_any().unbind())
}

/// Missions R2 — `objectives::marker_positions`, the catalog's deterministic layouts
/// next to `objective_layout`'s rulebook draw. `style` is the same `DeploymentCatalog`
/// style dict `objective_layout` takes.
#[pyfunction]
#[pyo3(signature = (placement, edge_in, style, table_w_in=72.0, table_d_in=48.0))]
fn mission_marker_positions(
    placement: &str,
    edge_in: f64,
    style: &Bound<'_, PyAny>,
    table_w_in: f64,
    table_d_in: f64,
) -> PyResult<Vec<(f64, f64)>> {
    Ok(objectives::marker_positions(placement, edge_in, &value_of(style)?, table_w_in, table_d_in))
}

/// NML-1140 step 5 — the doctrine's placement choice for the trainer and the
/// gates: `nmlcore::doctrine_place`, the mode dispatcher over `place_style` /
/// `place_search`, exposed next to `objective_layout`. `armies` is the PAIR
/// (a Python 2-TUPLE) of profile dicts, unit key -> `_unit_profile` block;
/// `count` is the ALREADY drawn marker count — the seed stream stays the
/// caller's, the doctrine draws nothing (design 1). Positions come back in
/// inches, `Layout.positions` shape; `swept` counts sweep-filled markers
/// honestly. A mode word the enum does not know — and "random", which is the
/// caller's own draw stream — raises `Unsupported`: a clean error, never a
/// panic. A `count` over 5 raises too — 8^count search blow-up, and no mission
/// can draw it (d3+2 tops out at 5): the step-5 UNSURE, coordinator-approved.
#[pyfunction]
#[pyo3(signature = (terrain, mode, armies, count, style, table_w_in=72.0, table_d_in=48.0))]
fn doctrine_place(
    py: Python<'_>,
    terrain: Option<&Bound<'_, PyAny>>,
    mode: &str,
    armies: &Bound<'_, PyAny>,
    count: usize,
    style: &Bound<'_, PyAny>,
    table_w_in: f64,
    table_d_in: f64,
) -> PyResult<Py<PyAny>> {
    if count > 5 {
        return Err(Unsupported::new_err(format!(
            "count must be <= 5 (d3+2 is the mission ceiling; the search tree is 8^count), got {count}"
        )));
    }
    let (a, b): (Py<PyAny>, Py<PyAny>) = armies.extract().map_err(|e| {
        Unsupported::new_err(format!(
            "armies must be the pair (army_a, army_b) of profile dicts: {e}"
        ))
    })?;
    let placed = nmlcore::doctrine_place(
        mode,
        &value_of(a.bind(py))?,
        &value_of(b.bind(py))?,
        &value_of(style)?,
        &objectives::Cells::from_terrain(&board(terrain)?.inner),
        count,
        table_w_in,
        table_d_in,
    )
    .map_err(Unsupported::new_err)?;
    let out = PyDict::new(py);
    out.set_item("mode", mode)?;
    out.set_item(
        "positions",
        placed.cells.iter().map(|&(x, z)| vec![x, z]).collect::<Vec<_>>(),
    )?;
    out.set_item("swept", placed.swept)?;
    Ok(out.into_any().unbind())
}

/// NML-1140 step 9b — `nmlcore::place_step` for the mixed placement A/B: the
/// search's NEXT ply on the prefix `placed` (the markers placed so far,
/// inches). The `doctrine_place` contract, minus the draw: zero RNG, count
/// <= 5, one call adds ONE cell, `None` when no grid cell passes (the ply
/// falls to the caller's sweep). A prefix that already reached `count` raises
/// — the search's leaf test needs a ply to place.
#[pyfunction]
#[pyo3(signature = (armies, count, style, placed, table_w_in=72.0, table_d_in=48.0, terrain=None))]
fn doctrine_place_step(
    py: Python<'_>,
    armies: &Bound<'_, PyAny>,
    count: usize,
    style: &Bound<'_, PyAny>,
    placed: Vec<Vec<i64>>,
    table_w_in: f64,
    table_d_in: f64,
    terrain: Option<&Bound<'_, PyAny>>,
) -> PyResult<Option<(i64, i64)>> {
    if count > 5 {
        return Err(Unsupported::new_err(format!(
            "count must be <= 5 (d3+2 is the mission ceiling; the search tree is 8^count), got {count}"
        )));
    }
    let (a, b): (Py<PyAny>, Py<PyAny>) = armies.extract().map_err(|e| {
        Unsupported::new_err(format!(
            "armies must be the pair (army_a, army_b) of profile dicts: {e}"
        ))
    })?;
    let rows: Vec<(i64, i64)> = placed
        .iter()
        .map(|v| match v.as_slice() {
            [x, z] => Ok((*x, *z)),
            _ => Err(Unsupported::new_err(format!(
                "each placed marker is [x, z], got {} entries",
                v.len()
            ))),
        })
        .collect::<PyResult<Vec<_>>>()?;
    if rows.len() >= count {
        return Err(Unsupported::new_err(format!(
            "the prefix must be shorter than count (the search's leaf test needs a ply to place), got {} of {count}",
            rows.len()
        )));
    }
    Ok(nmlcore::place_step(
        &value_of(a.bind(py))?,
        &value_of(b.bind(py))?,
        &value_of(style)?,
        &objectives::Cells::from_terrain(&board(terrain)?.inner),
        count,
        table_w_in,
        table_d_in,
        &rows,
    ))
}

/// `objectives::is_legal` for one candidate marker — the twin's own legality
/// rule handed to Python (NML-1140 step 5), so a gate re-checks every
/// `doctrine_place` cell through the SAME function the doctrine searched
/// with, not a second port. `x`/`z` and `placed` are 1" lattice inches;
/// `placed` is the OTHER markers only (a marker sits 0" from itself).
#[pyfunction]
#[pyo3(signature = (terrain, style, x, z, placed))]
fn objective_is_legal(
    terrain: Option<&Bound<'_, PyAny>>,
    style: &Bound<'_, PyAny>,
    x: i64,
    z: i64,
    placed: Vec<Vec<i64>>,
) -> PyResult<bool> {
    let rows: Vec<(i64, i64)> = placed
        .iter()
        .map(|v| match v.as_slice() {
            [x, z] => Ok((*x, *z)),
            _ => Err(Unsupported::new_err(format!(
                "each placed marker is [x, z], got {} entries",
                v.len()
            ))),
        })
        .collect::<PyResult<Vec<_>>>()?;
    Ok(objectives::is_legal(
        x,
        z,
        &rows,
        &objectives::zones_of_style(&value_of(style)?),
        &objectives::Cells::from_terrain(&board(terrain)?.inner),
    ))
}

/// `board(terrain).los_pairs(units)` — the one-shot form.
#[pyfunction]
fn los_pairs(
    terrain: Option<&Bound<'_, PyAny>>,
    units: &Bound<'_, PyAny>,
) -> PyResult<Vec<String>> {
    board(terrain)?.los_pairs(units)
}

// ----------------------------------- the deployment pipeline (NML-1152 step 7) ---
//
// The twin's deployment pipeline, callable from the trainer (design §3.3):
// `deploy_side` runs the per-side PLACEMENT (fresh stream seeded `seed_value`,
// transport fill → groups → sections → placement order → the step-5 ladder,
// `nmlcore::deployment::deploy_side`), `deploy_finish` runs the table's
// per-side FINISH order (settle + coherency repair, steps 6b-6e). The roll-off
// stays in Python over `Rng` — the game stream's order belongs to the caller
// (arena_match.gd:373 → :462 precedes every deployment). Dicts cross as JSON
// both ways (the module header's marshalling contract, incl. the
// `float_roundtrip` feature both crates enable): the input schema is the serde
// shape of the `deployment` types, the output theirs.

/// One side's `deploy_finish` input: the roster (UnitSpec dicts, ambush rows
/// with empty `model_shapes`), `deploy_side`'s placements, the zone
/// `[x, y, w, h]` metres.
#[derive(serde::Deserialize)]
struct SideIn {
    units: Vec<UnitSpec>,
    placements: Vec<Placement>,
    zone: [f64; 4],
}

/// One JSON-dict argument as `T`, named in the error.
fn json_of<T: serde::de::DeserializeOwned>(v: &Bound<'_, PyAny>, what: &str) -> PyResult<T> {
    serde_json::from_value(value_of(v)?)
        .map_err(|e| Unsupported::new_err(format!("{what}: {e}")))
}

/// Settled model rows written back into the placements (tests/deployment.rs
/// write-back law): the settle state's placement index addresses the result.
fn write_back(
    st: &[(usize, SettleUnit)],
    offset: usize,
    units: &[SettleUnit],
    sd: &mut SideDeploy,
) {
    for (i, (pi, _)) in st.iter().enumerate() {
        sd.placements[*pi].models =
            units[i + offset].models.iter().map(|m| (m[0] as f64, m[1] as f64)).collect();
    }
}

/// The per-side placement (§3.2's plain-dict signature). `units` = the roster
/// in list order (ambush rows included; serde has no defaults, every key
/// present, transport_capacity 0 on the corpus); `objectives` = the rulebook
/// positions in WORLD METRES, f32-narrowed like arena_match.gd:338-346 (the
/// `objective_layout` → positions mapping, tests/deployment.rs:1172-1175 — the
/// inches `objective_layout` returns must be narrowed py-side);
/// `board` = a Board carrying the bank v2 prop layer (`set_bank_props`).
/// Returns `SideDeploy` as a plain dict.
#[pyfunction]
fn deploy_side(
    py: Python<'_>,
    units: &Bound<'_, PyAny>,
    zone: &Bound<'_, PyAny>,
    objectives: &Bound<'_, PyAny>,
    board: PyRef<'_, Board>,
    seed_value: i64,
) -> PyResult<Py<PyAny>> {
    let specs: Vec<UnitSpec> = json_of(units, "units")?;
    let z: [f64; 4] = json_of(zone, "zone")?;
    let objs: Vec<[f64; 2]> = json_of(objectives, "objectives")?;
    let sd = deployment::deploy_side(
        &specs,
        &Rect::new(z[0], z[1], z[2], z[3]),
        &objs.iter().map(|o| (o[0], o[1])).collect::<Vec<_>>(),
        &board.inner,
        seed_value,
    );
    to_py(py, &serde_json::to_value(&sd).map_err(|e| Unsupported::new_err(e.to_string()))?)
}

/// A board that blocks nothing — the ARRIVAL fixture's own reading. Its 98
/// recorded cases were reconstructed from `acts.jsonl`, which carries no
/// per-arrival terrain probe, and its 2 synthetic cases were dumped off a bare
/// `main.tscn` whose `_deploy_blocked_normal` answers false everywhere
/// (`tools/ambush_arrival_dump.gd`). So `board=None` is not a convenience
/// default: it is the oracle's terrain, stated instead of guessed. The twin's
/// own self-play passes its real `Board` and gets the real terrain law.
fn no_terrain() -> Terrain {
    Terrain::build(&nmlcore::terrain::PlainTerrain {
        cells: Vec::new(),
        sandbox: Vec::new(),
        pieces: Vec::new(),
        walls: Vec::new(),
        cell_params: nmlcore::terrain::CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 6.0,
            inches_to_meters: 0.0254,
        },
    })
}

/// `deployment::arrive_one` (SPEC ambush arrival S3/S5) as the gate's contract
/// spells it: `arrive_one(zone, objectives, occupied, enemies, own_ring_m,
/// radius, footprint, base_r, flying) -> [x, z] | None`, `None` = "no legal
/// spot, the unit stays in reserve". `radius` is the ALREADY-PORTED
/// `deploy_footprint_radius`, computed by the caller, so the gate and the
/// trainer hand in the same number.
///
/// `board` and `beacons` are appended, never inserted, so the nine positional
/// arguments `deployment_gate.py --arrival` passes keep meaning what they
/// meant. `occupied` is BORROWED-and-returned rather than mutated in place:
/// the Rust side books the chosen spot into it (the table does that inside
/// `_finish_reserve_arrival`), and the caller reads the booking back off the
/// returned list so the next unit of the same alternating round sees it.
#[pyfunction]
#[pyo3(signature = (zone, objectives, occupied, enemies, own_ring_m, radius, footprint, base_r, flying, board=None, beacons=None))]
#[allow(clippy::too_many_arguments)]
fn arrive_one(
    py: Python<'_>,
    zone: &Bound<'_, PyAny>,
    objectives: &Bound<'_, PyAny>,
    occupied: &Bound<'_, PyAny>,
    enemies: &Bound<'_, PyAny>,
    own_ring_m: f64,
    radius: f64,
    footprint: &Bound<'_, PyAny>,
    base_r: f64,
    flying: bool,
    board: Option<PyRef<'_, Board>>,
    beacons: Option<&Bound<'_, PyAny>>,
) -> PyResult<Py<PyAny>> {
    let z: [f64; 4] = json_of(zone, "zone")?;
    let objs: Vec<[f64; 2]> = json_of(objectives, "objectives")?;
    let mut occ: Vec<deployment::Occupied> = json_of(occupied, "occupied")?;
    let ene: Vec<deployment::ArrivalEnemy> = json_of(enemies, "enemies")?;
    let bcn: Vec<deployment::ArrivalBeacon> = match beacons {
        Some(b) => json_of(b, "beacons")?,
        None => Vec::new(),
    };
    let fp: Vec<[f64; 2]> = json_of(footprint, "footprint")?;
    let owned;
    let terrain = match &board {
        Some(b) => &b.inner,
        None => {
            owned = no_terrain();
            &owned
        }
    };
    let spot = deployment::arrive_one(
        &Rect::new(z[0], z[1], z[2], z[3]),
        &objs.iter().map(|o| (o[0], o[1])).collect::<Vec<_>>(),
        &mut occ,
        &ene,
        &bcn,
        own_ring_m,
        terrain,
        radius,
        &fp.iter().map(|o| (o[0], o[1])).collect::<Vec<_>>(),
        base_r,
        flying,
    );
    if !spot.0.is_finite() {
        return Ok(py.None());
    }
    to_py(py, &serde_json::json!([spot.0, spot.1]))
}

/// `_place_unit_at`'s loose-formation drop (solo_controller.gd:10329-10346) as
/// `deployment::place_unit_models` already ports it: the arriving unit's `n`
/// models on the fixed 0.04 m / 5-column grid, centred on `spot`. Exposed so
/// the trainer's round-start arrival does not re-derive the grid in Python.
#[pyfunction]
fn place_models(py: Python<'_>, spot: (f64, f64), n: usize) -> PyResult<Py<PyAny>> {
    let ms = deployment::place_unit_models(spot, n);
    to_py(py, &Value::Array(ms.iter().map(|m| Value::Array(vec![m.0.into(), m.1.into()])).collect()))
}

/// The RULEBOOK's alternating deployment for BOTH sides in one call
/// (`deployment::deploy_interleaved`, GF v3.5.1 p.6): the roll-off winner
/// places ONE unit, the opponent places one, alternating until every unit is
/// down, then the Scout phase after BOTH main queues, Ambush reserved. Each
/// side keeps its OWN per-side stream (`seed + slot`, passed as `seed1`/`seed2`)
/// and its own `occupied`, so a side's draws and spots are exactly what
/// `deploy_side` produces — only the cross-side ORDER changes. `first` is the
/// winner's slot (1 or 2). Returns `InterleavedDeploy` as a plain dict:
/// `side1`, `side2` (each a `SideDeploy`) and `sequence` = `[[slot, key], ..]`
/// in placement order — the fact `tools/pregame_dump.gd` writes as
/// `placement_sequence`, and the one the interleave gate compares.
#[pyfunction]
#[allow(clippy::too_many_arguments)]
fn deploy_interleaved(
    py: Python<'_>,
    units1: &Bound<'_, PyAny>,
    units2: &Bound<'_, PyAny>,
    zone1: &Bound<'_, PyAny>,
    zone2: &Bound<'_, PyAny>,
    objectives: &Bound<'_, PyAny>,
    board: PyRef<'_, Board>,
    seed1: i64,
    seed2: i64,
    first: i64,
) -> PyResult<Py<PyAny>> {
    let specs1: Vec<UnitSpec> = json_of(units1, "units1")?;
    let specs2: Vec<UnitSpec> = json_of(units2, "units2")?;
    let z1: [f64; 4] = json_of(zone1, "zone1")?;
    let z2: [f64; 4] = json_of(zone2, "zone2")?;
    let objs: Vec<[f64; 2]> = json_of(objectives, "objectives")?;
    let out = deployment::deploy_interleaved(
        &specs1,
        &specs2,
        &Rect::new(z1[0], z1[1], z1[2], z1[3]),
        &Rect::new(z2[0], z2[1], z2[2], z2[3]),
        &objs.iter().map(|o| (o[0], o[1])).collect::<Vec<_>>(),
        &board.inner,
        seed1,
        seed2,
        first,
    );
    to_py(py, &serde_json::to_value(&out).map_err(|e| Unsupported::new_err(e.to_string()))?)
}

/// The table's per-side FINISH order (solo_controller.gd:9180-9188; the finish
/// is caller-driven since step 6d): the FIRST finish runs on the first
/// deployer's units ALONE, its spot-free gate seeing the pre-game tray rows of
/// BOTH armies (the other army still stands on its side tray,
/// tests/deployment.rs:1346-1353); the SECOND over both rosters in slot order
/// (the cross-slot re-sweep, solo_controller.gd:9228-9232,
/// tests/deployment.rs:1354-1372) with both sides' tray remainders. `sides`
/// maps "1"/"2" to `SideIn` dicts; `trays` maps "1"/"2" to the side's pre-game
/// tray rows `[[x, z, r],..]` (pregame_dump.gd `tray_models` — INPUT state; a
/// caller without trays, the twin's own self-play, passes empty dicts, the 6e
/// default-empty guard). Returns `{"1": [placement dicts], "2": [..]}` with
/// the settled models written back.
#[pyfunction]
fn deploy_finish(
    py: Python<'_>,
    sides: &Bound<'_, PyAny>,
    board: PyRef<'_, Board>,
    trays: HashMap<String, Vec<[f64; 3]>>,
    first_slot: i64,
) -> PyResult<Py<PyAny>> {
    let sides: HashMap<String, SideIn> = json_of(sides, "sides")?;
    let (s1, s2) = (
        sides.get("1").ok_or_else(|| Unsupported::new_err("sides[\"1\"] missing"))?,
        sides.get("2").ok_or_else(|| Unsupported::new_err("sides[\"2\"] missing"))?,
    );
    let (specs1, mut sd1, zone1) = (
        &s1.units,
        SideDeploy {
            seed_value: 0,
            fills: Vec::new(),
            placements: s1.placements.clone(),
            reserved: Vec::new(),
            events: Vec::new(),
        },
        Rect::new(s1.zone[0], s1.zone[1], s1.zone[2], s1.zone[3]),
    );
    let (specs2, mut sd2, zone2) = (
        &s2.units,
        SideDeploy {
            seed_value: 0,
            fills: Vec::new(),
            placements: s2.placements.clone(),
            reserved: Vec::new(),
            events: Vec::new(),
        },
        Rect::new(s2.zone[0], s2.zone[1], s2.zone[2], s2.zone[3]),
    );
    let (t1, t2): (Vec<_>, Vec<_>) = (
        trays.get("1").unwrap_or(&Vec::new()).iter().map(|m| ([m[0] as f32, m[1] as f32], m[2])).collect(),
        trays.get("2").unwrap_or(&Vec::new()).iter().map(|m| ([m[0] as f32, m[1] as f32], m[2])).collect(),
    );
    let walls = board.inner.walls_world_m();
    let finish = |specs: &[UnitSpec], sd: &mut SideDeploy, zone: &Rect, tray: &[([f32; 2], f64)]| {
        let st = deployment::settle_units(specs, sd, zone);
        let mut units: Vec<SettleUnit> = st.iter().map(|p| p.1.clone()).collect();
        deployment::deploy_finish_all(&mut units, &board.inner, walls, tray);
        write_back(&st, 0, &units, sd);
    };
    // FIRST finish: the first deployer's units alone; tray rows: own
    // remainders, then the whole other army (tests/deployment.rs:1346-1353).
    let tray_first: Vec<([f32; 2], f64)> = if first_slot == 2 {
        t2.iter().copied().chain(t1.iter().copied()).collect()
    } else {
        t1.iter().copied().chain(t2.iter().copied()).collect()
    };
    if first_slot == 2 {
        finish(&specs2, &mut sd2, &zone2, &tray_first);
    } else {
        finish(&specs1, &mut sd1, &zone1, &tray_first);
    }
    // SECOND finish: BOTH rosters, slot-1 roster then slot-2 (the table's
    // get_all_game_units order; tests/deployment.rs:1354-1372).
    let st1 = deployment::settle_units(&specs1, &sd1, &zone1);
    let st2 = deployment::settle_units(&specs2, &sd2, &zone2);
    let mut all: Vec<SettleUnit> = st1.iter().map(|p| p.1.clone()).collect();
    let n1 = all.len();
    all.extend(st2.iter().map(|p| p.1.clone()));
    let tray_second: Vec<([f32; 2], f64)> = t1.iter().copied().chain(t2.iter().copied()).collect();
    deployment::deploy_finish_all(&mut all, &board.inner, walls, &tray_second);
    write_back(&st1, 0, &all, &mut sd1);
    write_back(&st2, n1, &all, &mut sd2);
    let mut out = Map::new();
    for (slot, sd) in [("1", &sd1), ("2", &sd2)] {
        out.insert(
            slot.into(),
            serde_json::to_value(&sd.placements)
                .map_err(|e| Unsupported::new_err(e.to_string()))?,
        );
    }
    to_py(py, &Value::Object(out))
}

const BUILD_COMMIT: &str = env!("NML_BUILD_COMMIT");

fn build_info() -> Value {
    serde_json::json!({
        "commit": BUILD_COMMIT,
        "dirty": env!("NML_BUILD_DIRTY") == "true",
        "rules_epoch": nmlcore::CURRENT_RULES_EPOCH,
        "crate_version": env!("CARGO_PKG_VERSION"),
        "build_time_utc": env!("NML_BUILD_TIME_UTC"),
    })
}

#[pymodule]
fn nml_core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add("__doc__", "NML-1073 M3-1 — the Niemandsland fast rules core, callable from Python.")?;
    m.add("Unsupported", m.py().get_type::<Unsupported>())?;
    m.add_class::<Core>()?;
    m.add_class::<PyState>()?;
    m.add_class::<Board>()?;
    m.add_class::<PyRng>()?;
    m.add_class::<PyTray>()?;
    m.add_function(wrap_pyfunction!(load, m)?)?;
    m.add_function(wrap_pyfunction!(set_legacy_prefix_rules, m)?)?;
    m.add_function(wrap_pyfunction!(set_legacy_no_cond_ap, m)?)?;
    // NML-1134: the rule vocabulary's version — this build's, and one corpus's.
    m.add_function(wrap_pyfunction!(vocab_version_of_header, m)?)?;
    m.add_function(wrap_pyfunction!(rule_vocab_version, m)?)?;
    m.add("RULE_VOCAB_VERSION", nmlcore::RULE_VOCAB_VERSION)?;
    m.add("LEGACY_VOCAB_VERSION", nmlcore::LEGACY_VOCAB_VERSION)?;
    // The CLASS FIX (external review 03.09. item 3 / F9): the epoch a fresh
    // `play_game()` stamps. See `acts::rule_on`.
    m.add("CURRENT_RULES_EPOCH", nmlcore::CURRENT_RULES_EPOCH)?;
    m.add("BUILD_COMMIT", BUILD_COMMIT)?;
    m.add("BUILD_DIRTY", env!("NML_BUILD_DIRTY") == "true")?;
    m.add("BUILD_INFO", to_py(m.py(), &build_info())?)?;
    // NML-1073 M3-4: the board as a pure lookup — the header's terrain in, the
    // same answers `SchoolTerrain` gives the live game out.
    m.add_function(wrap_pyfunction!(board, m)?)?;
    m.add_function(wrap_pyfunction!(type_at, m)?)?;
    m.add_function(wrap_pyfunction!(los_blocked, m)?)?;
    m.add_function(wrap_pyfunction!(los_pairs, m)?)?;
    m.add_function(wrap_pyfunction!(objective_layout, m)?)?;
    m.add_function(wrap_pyfunction!(mission_marker_positions, m)?)?;
    // NML-1152 step 7 — the twin's deployment pipeline for the trainer.
    m.add_function(wrap_pyfunction!(deploy_side, m)?)?;
    m.add_function(wrap_pyfunction!(deploy_interleaved, m)?)?;
    m.add_function(wrap_pyfunction!(deploy_finish, m)?)?;
    m.add_function(wrap_pyfunction!(arrive_one, m)?)?;
    m.add_function(wrap_pyfunction!(place_models, m)?)?;
    // NML-1140 step 5: the doctrine's choice next to the random-legal layout,
    // plus `objectives::is_legal` so a gate re-checks through the same rule.
    m.add_function(wrap_pyfunction!(doctrine_place, m)?)?;
    // NML-1140 step 9b: the doctrine's next ply on a prefix, for the mixed
    // per-side placement A/B.
    m.add_function(wrap_pyfunction!(doctrine_place_step, m)?)?;
    m.add_function(wrap_pyfunction!(objective_is_legal, m)?)?;
    // `TerrainRules.TerrainType` — terrain_rules.gd:24.
    m.add("TERRAIN_NONE", nmlcore::terrain::NONE)?;
    m.add("TERRAIN_RUINS", nmlcore::terrain::RUINS)?;
    m.add("TERRAIN_FOREST", nmlcore::terrain::FOREST)?;
    m.add("TERRAIN_CONTAINER", nmlcore::terrain::CONTAINER)?;
    m.add("TERRAIN_DANGEROUS", nmlcore::terrain::DANGEROUS)?;
    // The four action kinds `resolve` branches on — battle_sim.gd:570-652.
    m.add("HOLD", nmlcore::HOLD)?;
    m.add("ADVANCE", nmlcore::ADVANCE)?;
    m.add("RUSH", nmlcore::RUSH)?;
    m.add("CHARGE", nmlcore::CHARGE)?;
    Ok(())
}

#[cfg(test)]
mod build_identity_tests {
    #[test]
    fn build_identity_is_valid_and_has_current_epoch() {
        let commit = super::BUILD_COMMIT;
        assert!(
            commit == "unknown"
                || (commit.len() == 40 && commit.bytes().all(|b| b.is_ascii_hexdigit()))
        );
        let info = super::build_info();
        assert_eq!(info["commit"], commit);
        assert_eq!(info["rules_epoch"], nmlcore::CURRENT_RULES_EPOCH);
        assert!(info["dirty"].is_boolean());
        assert_eq!(info["crate_version"], env!("CARGO_PKG_VERSION"));
        assert!(info["build_time_utc"].as_str().unwrap().ends_with('Z'));
    }
}
