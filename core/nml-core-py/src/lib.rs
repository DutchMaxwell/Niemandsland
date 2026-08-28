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

use std::rc::Rc;

use pyo3::create_exception;
use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList};

use serde_json::{Map, Value};

use nmlcore::acts::{ActHeader, ActStatics, Knobs, Sighting};
use nmlcore::arbitration::Arbitration;
use nmlcore::menu::{candidates_tuned, Candidate, Tuning};
use nmlcore::plan::{Pick, Search};
use nmlcore::playout::Policy;
use nmlcore::rollout::Rollout;
use nmlcore::sim::Scratch;
use nmlcore::state::{Marker, ProfileCache, Roster};
use nmlcore::rows::{Cell, RowEncoder};
use nmlcore::unit::{StaticsCache, UnitStatic};
use nmlcore::{
    geom, io, mission, reply_threat, resolve_on_board, resolve_stochastic_on_board,
    resolve_stochastic_tray_on_board, score, Action, GodotRng, PlainTerrain, Registries, Seams,
    State as CoreState, Terrain, Tray, Unsupported as CoreUnsupported,
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
/// `trace` and the winning rollout's leaf state in plain form.
fn pick_plain(p: &Pick) -> Value {
    let mut out = Map::new();
    out.insert("used".into(), true.into());
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
    fn pool(&self, player: i64) -> Vec<String> {
        let st = &self.inner;
        (0..st.units())
            // D1-B4b: a JOINED HERO is never an activation of its own
            // (`SoloController.can_activate` solo_controller.gd:411) — it fires
            // and moves inside its host's. Unconditional here, unlike the
            // planner's own filter, because this is the HARNESS's "is the side
            // dry?" question and not a parity surface; under
            // `hero_attach="off"` no unit has a host and it is the old filter
            // verbatim anyway.
            .filter(|&i| st.can_activate(i, player, true))
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
            path: self.knobs.seam_path,
            hero_attach: self.knobs.hero_attach,
            charge_landing: self.knobs.charge_landing,
            // NML-1073 M5 D6a-B4 — `sighting="model"` in the header turns the
            // per-model, per-weapon die count on for the TRAY resolver only.
            sighting: self.knobs.sighting == Sighting::Model,
            movement: self.knobs.movement,
            // NML-1073 M5 D1-B8 — the header's RED switch, inverted: `dangerous`
            // defaults true, so the p.12 test runs unless a gate turns it off.
            no_dangerous: !self.knobs.dangerous,
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
        self.statics = StaticsCache::new();
        self.terrain = terrain;
        self.knobs = knobs;
        self.roster = None;
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
        m.insert("charge_gate".into(), self.knobs.charge_gate.into());
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
        m.insert("dangerous".into(), self.knobs.dangerous.into());
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
        let land = nmlcore::mv::step::charge_move(
            st,
            &self.terrain,
            si,
            ci,
            st.bands[si].rush,
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

    /// `AiPlanner.plan_with_rollout` ai_planner.gd:118-275 — the whole search.
    ///
    /// `statics` is the per-activation class-static snapshot the recorder writes
    /// (`opener_seat`, `playout_search`, `fit_mode`, `playout_net`); `sig` is
    /// `AiPlanner._playout_sig` at record time and is an INPUT — without it a
    /// close top-2 declines rather than inventing a dice stream.
    ///
    /// Returns the pick plus `trace` and `leaf_state`, or `{"used": false,
    /// "unsupported": <reason>}` when the port declines.
    #[pyo3(signature = (state, player, statics, sig = None))]
    fn plan_with_rollout(
        &mut self,
        py: Python<'_>,
        state: PyRef<'_, PyState>,
        player: i64,
        statics: &Bound<'_, PyAny>,
        sig: Option<i64>,
    ) -> PyResult<Py<PyAny>> {
        let act: ActStatics = serde_json::from_value(value_of(statics)?)
            .map_err(|e| Unsupported::new_err(format!("statics: {e}")))?;
        let statics = self.statics_for(&state.inner)?;
        let mut policy = Policy::new(&statics, &self.terrain, self.seams());
        policy.tuning = self.tuning();
        let roll = Rollout::new(policy, self.knobs);
        let mut search = Search::new(roll, &act);
        search.sig = sig;
        let mut sc = Scratch::default();
        match search.run(&state.inner, player, &mut sc) {
            Ok(pick) => to_py(py, &pick_plain(&pick)),
            Err(u) => {
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
    /// "target", "faces"}], "unported": [name, ...]}` — `rolls` in draw order
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
        });
        Ok((PyState::derived(next), to_py(py, &report)?))
    }

    /// `AiMissionEval.score` with the reply threat — the RICH leaf
    /// (`AiPlanner._policy_step` ai_planner.gd:508-510).
    fn score(&mut self, state: PyRef<'_, PyState>, player: i64) -> PyResult<f64> {
        let statics = self.statics_for(&state.inner)?;
        let incoming = reply_threat(&statics, &state.inner, player);
        Ok(score(&state.inner, player, &incoming))
    }

    /// The same score WITHOUT the reply threat — the cheap leaf.
    fn score_cheap(&self, state: PyRef<'_, PyState>, player: i64) -> f64 {
        score(&state.inner, player, nmlcore::NO_INCOMING)
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

    /// `BattleSim.board_rows` battle_sim.gd:176 — the v5 encoder input: one row
    /// per LIVING unit in capture order, then one per objective (type 3), then
    /// the single game-state row (type 4). Ints come back as Python ints and
    /// floats as Python floats, the way `JSON.stringify` writes them.
    fn board_rows(&mut self, py: Python<'_>, state: PyRef<'_, PyState>) -> PyResult<Py<PyAny>> {
        if !self.rows.vocab.loaded {
            return Err(Unsupported::new_err(format!(
                "rule vocab unreadable at {}/data/encoder_rule_vocab_v1.json",
                self.repo_root
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
    }

    /// Drop the legacy column-10/11 override — back to the profile's own
    /// quality/defense, the default and the only setting a fresh corpus may use.
    fn clear_encoder_source_qd(&mut self) {
        self.rows.source_qd = None;
    }

    /// Rule/spell names the committed vocabulary does not carry, collected
    /// across every `board_rows` call — `BattleSim.unknown_rules` (:82), which
    /// the GDScript also stamps into its result rather than slotting silently.
    fn unknown_rules(&self) -> Vec<String> {
        self.rows.unknown.iter().cloned().collect()
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

/// `board(terrain).los_pairs(units)` — the one-shot form.
#[pyfunction]
fn los_pairs(
    terrain: Option<&Bound<'_, PyAny>>,
    units: &Bound<'_, PyAny>,
) -> PyResult<Vec<String>> {
    board(terrain)?.los_pairs(units)
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
    // NML-1073 M3-4: the board as a pure lookup — the header's terrain in, the
    // same answers `SchoolTerrain` gives the live game out.
    m.add_function(wrap_pyfunction!(board, m)?)?;
    m.add_function(wrap_pyfunction!(type_at, m)?)?;
    m.add_function(wrap_pyfunction!(los_blocked, m)?)?;
    m.add_function(wrap_pyfunction!(los_pairs, m)?)?;
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
