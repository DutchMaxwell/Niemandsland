//! Loader for the ACT corpus written by `AiActRecorder` (scripts/solo/
//! act_recorder.gd): line 1 is the header
//! `{"kind":"header","profiles":{...},"terrain":{...}|null,"knobs":{...}}`,
//! every line after it is one ACTIVATION — the full input the search read plus
//! the pick it returned and the search trace (`trace.menus` is the menu oracle
//! this milestone's gate replays).
//!
//! It reuses `io.rs`'s plain-state reader wholesale: the act corpus writes the
//! SAME `BattleSim.state_to_plain` object, only with the M2-0c/M2-0d gate reads
//! stamped into each unit (`bands`, `shroud`, `charge_no_difficult`,
//! `charge_probe_r`). Unit order is document order, which is what `Ordered<T>`
//! preserves — see the note on `roster_of`.

use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::rc::Rc;

use serde::Deserialize;

use crate::io::{roster_of, state_of, Ordered, PlainState};
use crate::menu::Candidate;
use crate::state::{Profile, ProfileCache, Profiles, Roster, State};
use crate::terrain::{PlainTerrain, Terrain};

/// The header's `"knobs"` object — `AiActRecorder._header_line`
/// act_recorder.gd:126-133. Search settings, recorded so a replay never guesses
/// which A/B arm produced the line.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Knobs {
    #[serde(default)]
    pub top_k: i64,
    #[serde(default)]
    pub horizon: i64,
    #[serde(default)]
    pub tail_cap_p1: i64,
    #[serde(default)]
    pub tail_cap_p2: i64,
    #[serde(default)]
    pub imagined_round_end: bool,
    #[serde(default)]
    pub depth_discount: f64,
    #[serde(default)]
    pub seat_mode: i64,
    #[serde(default)]
    pub playout_margin: f64,
    #[serde(default)]
    pub playout_rich: bool,
    /// `BattleSim.cast_phase_enabled()` — NML_SIM_CAST.
    #[serde(default)]
    pub seam_cast: bool,
    /// `BattleSim.spacing_enabled()` — NML_SIM_SPACING.
    #[serde(default)]
    pub seam_spacing: bool,
    /// NML-1073 M4-7 — NML_SIM_PATH, the tier-2 path seam of the imagination.
    #[serde(default)]
    pub seam_path: bool,
    /// NML-1073 M3-5 — whether the CALLER wires `state["charge_illegal"]` at
    /// all. The arena does (solo_controller.gd:3002), `tools/core_selfplay.gd`
    /// never does, and both menu sites skip the gate outright for a caller that
    /// does not (`illegal_cb.is_valid()`, ai_planner.gd:1024/1308). Absent from
    /// every recorded header, so the default is `true` and no corpus moves; the
    /// Godot-free harness writes `false` because its GDScript twin is gateless.
    /// The act line records the same bit per activation as `charge_gate`.
    #[serde(default = "yes")]
    pub charge_gate: bool,
    /// NML-1073 M5 D1-B4b — `Seams::hero_attach`, carried in the header the way
    /// every other seam is. Absent from every corpus recorded before it, so the
    /// default is OFF and nothing replays differently.
    #[serde(default)]
    pub hero_attach: bool,
    /// NML-1073 M5 D5-1 — `Seams::charge_landing`, carried in the header the
    /// way every other seam is. Absent from every corpus recorded before it, so
    /// the default is OFF and nothing replays differently.
    #[serde(default)]
    pub charge_landing: bool,
    /// NML-1073 M5 D6a-B4 — how a volley counts its shooters. `"unit"` is the
    /// default and today's behaviour (every ALIVE model of the unit fires);
    /// `"model"` is the table's own rule, per model and per weapon. Absent from
    /// every corpus recorded before it, so the default replays byte-identical.
    #[serde(default)]
    pub sighting: Sighting,
    /// NML-1073 M5 D5-2 — `Seams::movement`, carried in the header the way every
    /// other seam is. Absent from every corpus recorded before it, so the
    /// default is OFF and nothing replays differently.
    #[serde(default)]
    pub movement: bool,
    /// NML-1073 M5 D1-B8 — the p.12 DANGEROUS-terrain test. NOT a feature knob:
    /// the test is part of `dice="table"` and defaults ON, exactly the way
    /// `charge_gate` defaults ON. It exists so a gate can switch it OFF and prove
    /// the numbers come back (`--red-no-dangerous`).
    #[serde(default = "yes")]
    pub dangerous: bool,
}

/// The `sighting` knob's two settings — the header writes them as strings, the
/// way `dice` writes `"expected"` / `"table"`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sighting {
    /// `BattleSim._profiles_of` (battle_sim.gd:714-749): the whole unit fires.
    #[default]
    Unit,
    /// `main._run_ai_shooting` :3131-3134: per (member, weapon), the models with
    /// both range and line of sight (GF Advanced Rules v3.5.1 p.8).
    Model,
}

/// `#[serde(default)]` on a `bool` is `false`; `charge_gate` defaults the other
/// way, because a header that predates the field came from a gated caller.
fn yes() -> bool {
    true
}

impl Default for Knobs {
    fn default() -> Self {
        Knobs {
            top_k: 6,
            horizon: 2,
            tail_cap_p1: 0,
            tail_cap_p2: 0,
            imagined_round_end: true,
            depth_discount: 0.5,
            seat_mode: 0,
            playout_margin: 0.02,
            playout_rich: true,
            seam_cast: false,
            seam_spacing: false,
            seam_path: false,
            charge_gate: true,
            hero_attach: false,
            charge_landing: false,
            sighting: Sighting::Unit,
            movement: false,
            dangerous: true,
        }
    }
}

#[derive(Deserialize)]
struct Header {
    profiles: Ordered<Profile>,
    #[serde(default)]
    terrain: Option<PlainTerrain>,
    #[serde(default)]
    knobs: Knobs,
}

/// One entry of `trace.scored` — `AiPlanner.plan_with_rollout` ai_planner.gd:
/// 150-155, written AFTER the sort, so the array is in ranked order and `idx`
/// is the candidate's position in the unsorted build order.
#[derive(Debug, Clone, Deserialize)]
pub struct Scored {
    pub idx: i64,
    pub unit: String,
    pub kind: i64,
    pub score: f64,
}

/// One entry of `trace.rs` — ai_planner.gd:203-204: the ROLLOUT value of one
/// pool candidate, in the order the pool was played out. This is the number
/// milestone M2-2 reproduces.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct RolloutValue {
    pub idx: i64,
    pub rs: f64,
}

/// `AiPlanner.plan_with_rollout`'s `expectation` — ai_planner.gd:273.
#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Expectation {
    #[serde(default)]
    pub before: f64,
    #[serde(default)]
    pub after: f64,
}

/// The pick's `runner_up` — the SECOND best rolled candidate (:274). The
/// GDScript writes an EMPTY dictionary when the pool held a single candidate,
/// which is why `action` is optional rather than the whole record.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct RunnerRec {
    #[serde(default)]
    pub unit_key: String,
    #[serde(default)]
    pub action: Option<Candidate>,
    #[serde(default)]
    pub score: f64,
}

/// The RECORDED pick — the dictionary `plan_with_rollout` returned
/// (ai_planner.gd:272-275), minus `intent` (a battle-log label, not a decision).
/// This is the M2-3 oracle.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct PickRec {
    #[serde(default)]
    pub used: bool,
    #[serde(default)]
    pub unit_key: String,
    #[serde(default)]
    pub action: Option<Candidate>,
    #[serde(default)]
    pub expectation: Expectation,
    #[serde(default)]
    pub waits: i64,
    #[serde(default)]
    pub rolled_units: Vec<String>,
    #[serde(default)]
    pub runner_up: RunnerRec,
}

/// `AiPlanner.trace` — the search bookkeeping `AiActRecorder.finish` attaches
/// (act_recorder.gd:80-82). `arbitration` carries the stochastic arbitration's
/// own verdict (:263-264); M2-4 reproduces it from the recorded `sig`, and a
/// corpus that never triggered it must still be able to PROVE that, so the field
/// is read either way.
#[derive(Debug, Default, Deserialize)]
struct PlainTrace {
    #[serde(default)]
    menus: HashMap<String, Vec<Candidate>>,
    #[serde(default)]
    scored: Vec<Scored>,
    /// The `idx` of every candidate that survived the prefilter, in pool order.
    #[serde(default)]
    pool_idx: Vec<i64>,
    #[serde(default)]
    rs: Vec<RolloutValue>,
    /// Positions in the SORTED `scored` array, not `idx` values (:210, :217).
    #[serde(default = "neg_one")]
    best_idx: i64,
    #[serde(default = "neg_one")]
    runner_idx: i64,
    /// `null` unless the stochastic arbitration decided that pick.
    #[serde(default)]
    arbitration: serde_json::Value,
}

/// `trace.arbitration` (ai_planner.gd:263-264) as a typed record — the M2-4
/// oracle. `sig` is `_playout_sig`'s value AT RECORD TIME and is an INPUT to the
/// port, not something it recomputes (see `arbitration.rs`'s module header).
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct ArbitrationRec {
    pub sig: i64,
    /// Playouts run PER BRANCH: 3, 5 or 7.
    pub n: i64,
    pub sum_b: f64,
    pub sum_r: f64,
    pub swapped: bool,
}

fn neg_one() -> i64 {
    -1
}

/// The per-act `"statics"` object — `AiActRecorder.begin` act_recorder.gd:62-63.
/// These are settings the search read off class statics rather than off the
/// state, so a replay that does not restore them replays a different search.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ActStatics {
    /// `AiPlanner.opener_seat` — true when OUR side opened the current round.
    /// `_blend_score` (:439-441) branches on it under seat modes 1 and 2.
    #[serde(default)]
    pub opener_seat: bool,
    #[serde(default)]
    pub playout_search: bool,
    /// `AiMissionEval.fit_mode` — `score.rs` ports the HAND half only.
    #[serde(default)]
    pub fit_mode: bool,
    /// `AiPlanner.playout_net` — a NON-empty dict routes every imagined
    /// activation through a trained network (`_policy_step_net`, :627-645),
    /// which this port declines rather than approximates.
    #[serde(default)]
    pub playout_net: serde_json::Value,
}

impl ActStatics {
    /// True when the recording used the heuristic playout this port implements.
    pub fn heuristic_playout(&self) -> bool {
        match &self.playout_net {
            serde_json::Value::Null => true,
            serde_json::Value::Object(m) => m.is_empty(),
            _ => false,
        }
    }
}

#[derive(Deserialize)]
struct PlainAct {
    round: i64,
    player: i64,
    state: PlainState,
    #[serde(default)]
    pool: Vec<String>,
    /// `AiActRecorder._charge_illegal_matrix` — "attacker|victim" -> the live
    /// gate's answer at the pair's ROOT gap.
    #[serde(default)]
    charge_illegal: HashMap<String, bool>,
    /// `AiActRecorder._charge_illegal_grid` — "attacker|victim" -> 29 answers at
    /// gaps 0", 0.5", ... 14".
    #[serde(default)]
    charge_illegal_grid: HashMap<String, Vec<bool>>,
    #[serde(default)]
    trace: PlainTrace,
    #[serde(default)]
    statics: ActStatics,
    #[serde(default)]
    pick: Option<PickRec>,
}

/// `AiActRecorder.GATE_GRID_STEPS` / `GATE_GRID_STEP_IN` — act_recorder.gd:239-240.
pub const GATE_GRID_STEPS: usize = 29;
pub const GATE_GRID_STEP_IN: f64 = 0.5;

#[derive(Debug)]
pub struct Act {
    pub round: i64,
    pub player: i64,
    pub state: State,
    /// The un-activated units the search chose between, in the state's own order.
    pub pool: Vec<String>,
    pub charge_illegal: HashMap<String, bool>,
    pub charge_illegal_grid: HashMap<String, Vec<bool>>,
    /// The RECORDED menu per pool unit — the oracle `menu::candidates` replays.
    pub menus: HashMap<String, Vec<Candidate>>,
    /// Every (unit, candidate) pair the 1-ply prefilter scored, RANKED.
    pub scored: Vec<Scored>,
    /// The `idx` of every candidate that reached a full rollout, in pool order.
    pub pool_idx: Vec<i64>,
    /// The RECORDED rollout value per pool candidate — the M2-2 oracle.
    pub rs: Vec<RolloutValue>,
    pub best_idx: i64,
    pub runner_idx: i64,
    pub statics: ActStatics,
    /// `trace.arbitration` — `Value::Null` unless the playout arbitration fired.
    pub arbitration: serde_json::Value,
    pub pick: Option<PickRec>,
}

impl Act {
    /// The typed `trace.arbitration`, or `None` when it did not fire on this act.
    /// A present-but-malformed record panics rather than reading as "absent":
    /// a gate that quietly skipped it would report green on nothing.
    pub fn arbitration_rec(&self) -> Option<ArbitrationRec> {
        if self.arbitration.is_null() {
            return None;
        }
        Some(
            serde_json::from_value(self.arbitration.clone())
                .unwrap_or_else(|e| panic!("trace.arbitration: {e}")),
        )
    }
}

#[derive(Debug)]
pub struct ActCorpus {
    /// The HEADER table — the deployment reading. The table an act is actually
    /// replayed on is `act.state.profiles`, which carries that activation's own
    /// dynamic reading (NML-1073 M2-5b); ask `nml_core::act_statics` for the
    /// matching per-act `UnitStatic` closures rather than deriving them here.
    pub profiles: Rc<Profiles>,
    pub terrain: Terrain,
    pub knobs: Knobs,
    pub acts: Vec<Act>,
}

/// The header line's three products — the profile table, the board and the
/// search knobs. Factored out of `read_acts` so a caller that never sees the
/// file (the Python seam, NML-1073 M3-1) builds them from the SAME code path
/// instead of a second reading of the header.
#[derive(Debug)]
pub struct ActHeader {
    pub profiles: Rc<Profiles>,
    pub terrain: Terrain,
    pub knobs: Knobs,
}

/// Parses one act-corpus header line (`{"kind":"header", ...}`).
pub fn read_act_header(text: &str) -> Result<ActHeader, String> {
    let header: Header = serde_json::from_str(text).map_err(|e| format!("act header: {e}"))?;
    Ok(header_of(header))
}

fn header_of(header: Header) -> ActHeader {
    let terrain = match &header.terrain {
        Some(t) => Terrain::build(t),
        None => Terrain::absent(),
    };
    let mut profiles = Profiles::default();
    for (k, p) in header.profiles.0 {
        profiles.index.insert(k, profiles.list.len());
        profiles.list.push(p);
    }
    ActHeader { profiles: Rc::new(profiles), terrain, knobs: header.knobs }
}

/// Reads `acts.jsonl` into the profile table, the board and the activations.
pub fn load_acts(path: &str) -> Result<ActCorpus, String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    read_acts(BufReader::new(file), path)
}

/// Same, from any reader — `origin` only labels the error messages.
pub fn read_acts<R: BufRead>(reader: R, origin: &str) -> Result<ActCorpus, String> {
    let path = origin;
    let mut lines = reader.lines();
    let head = lines
        .next()
        .ok_or_else(|| format!("{path}: empty file"))?
        .map_err(|e| e.to_string())?;
    let ActHeader { profiles, terrain, knobs } =
        read_act_header(&head).map_err(|e| format!("{path}:1 {e}"))?;
    // NML-1073 M2-5b: the header table is the DEPLOYMENT reading. Every act
    // carries its own reading of the fields a live game rewrites, and the state
    // that act is replayed on gets the table THAT says — interned, so acts that
    // read alike share one table (and one derived `UnitStatic` closure).
    let mut profile_cache = ProfileCache::new(Rc::clone(&profiles));
    let mut cache: Option<Rc<Roster>> = None;
    let mut acts = Vec::new();
    for (i, line) in lines.enumerate() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let pa: PlainAct =
            serde_json::from_str(&line).map_err(|e| format!("{path}:{}: {e}", i + 2))?;
        let roster = roster_of(&pa.state, &profiles, &mut cache)?;
        let eff = profile_cache.effective(&roster, &pa.state.dyn_profiles());
        acts.push(Act {
            round: pa.round,
            player: pa.player,
            state: state_of(pa.state, &eff, roster),
            pool: pa.pool,
            charge_illegal: pa.charge_illegal,
            charge_illegal_grid: pa.charge_illegal_grid,
            menus: pa.trace.menus,
            scored: pa.trace.scored,
            pool_idx: pa.trace.pool_idx,
            rs: pa.trace.rs,
            best_idx: pa.trace.best_idx,
            runner_idx: pa.trace.runner_idx,
            statics: pa.statics,
            arbitration: pa.trace.arbitration,
            pick: pa.pick,
        });
    }
    Ok(ActCorpus { profiles, terrain, knobs, acts })
}
