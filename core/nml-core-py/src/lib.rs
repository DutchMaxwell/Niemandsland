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
use pyo3::types::PyDict;

use serde_json::{Map, Value};

use nmlcore::acts::{ActHeader, ActStatics, Knobs};
use nmlcore::arbitration::Arbitration;
use nmlcore::menu::{candidates_in, Candidate};
use nmlcore::plan::{Pick, Search};
use nmlcore::playout::Policy;
use nmlcore::rollout::Rollout;
use nmlcore::sim::Scratch;
use nmlcore::state::{Marker, ProfileCache, Roster};
use nmlcore::unit::{StaticsCache, UnitStatic};
use nmlcore::{
    geom, io, mission, reply_threat, resolve_on_board, resolve_stochastic_on_board, score, Action,
    GodotRng, PlainTerrain, Registries, Seams, State as CoreState, Terrain,
    Unsupported as CoreUnsupported,
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
            .filter(|&i| st.player[i] == player && !st.activated[i] && st.alive[i] > 0)
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
        Seams { spacing: self.knobs.seam_spacing, cast: self.knobs.seam_cast, path: self.knobs.seam_path }
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
        to_py(py, &Value::Object(m))
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
        let roll =
            Rollout::new(Policy::new(&statics, &self.terrain, self.seams()), self.knobs);
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
        let menu = candidates_in(st, &self.terrain, &statics, i, &mut sc);
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
    }
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
    m.add_function(wrap_pyfunction!(load, m)?)?;
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
