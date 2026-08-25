//! Battle state as a struct-of-arrays plus the immutable profile table.
//!
//! Origin: `BattleSim.capture()` battle_sim.gd:1128-1240 (units are a Dict —
//! INSERTION ORDER is roster order and load-bearing), flattened to plain JSON by
//! `BattleSim.state_to_plain` battle_sim.gd:1255-1284. Every per-unit array here
//! is indexed by that capture order; never iterate a hash map instead.
//!
//! All numbers are `f64`. The engine's `Vector3` is single precision, but the
//! score only ever reads geometry through an integer (`needed`), so the width
//! difference cannot move a score away from a ring boundary — and `CONTROL_EPS`
//! guards the one inclusive comparison.

use std::collections::HashMap;
use std::rc::Rc;

use serde::Deserialize;

/// One weapon line of the static profile — `BattleSim._unit_profile` :1304-1330.
#[derive(Debug, Clone, Deserialize)]
pub struct Weapon {
    pub name: String,
    #[serde(default)]
    pub range: f64,
    #[serde(default)]
    pub attacks: i64,
    #[serde(default)]
    pub count: i64,
    #[serde(default)]
    pub ap: i64,
    #[serde(default)]
    pub rules: Vec<String>,
}

/// Everything `resolve`/`score` read off a live `GameUnit`, flattened once per
/// game — `BattleSim._unit_profile` battle_sim.gd:1304-1330.
#[derive(Debug, Clone, Deserialize)]
pub struct Profile {
    pub unit_id: String,
    pub name: String,
    #[serde(default)]
    pub quality: i64,
    #[serde(default)]
    pub defense: i64,
    #[serde(default)]
    pub tough: i64,
    #[serde(default)]
    pub wounds_max: Vec<i64>,
    #[serde(default)]
    pub model_count: i64,
    #[serde(default)]
    pub weapons: Vec<Weapon>,
    #[serde(default)]
    pub special_rules: Vec<String>,
    #[serde(default)]
    pub caster_value: i64,
    #[serde(default)]
    pub base_radius: f64,
    #[serde(default)]
    pub game_system: String,
    #[serde(default)]
    pub faction_folder: String,
    /// Item-granted rule names, flattened in `item_grants.values()` order —
    /// `RulesRegistry.unit_rules_of_primitive` rules_registry.gd:167-170 counts
    /// them as the unit's own.
    #[serde(default)]
    pub item_grants: Vec<String>,
    /// The special rules of every ALIVE attached hero — the quantifier
    /// `AiEv.rule_on_all_models` (ai_ev.gd:79-83) evaluates before a unit-wide
    /// rule may fire.
    #[serde(default)]
    pub attached_hero_rules: Vec<Vec<String>>,
    /// `SoloController.sim_move_bands(unit)` — the only live read left in
    /// `AiMissionEval._presence` (ai_mission_eval.gd:610), static per unit.
    #[serde(default)]
    pub move_bands: MoveBands,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct MoveBands {
    #[serde(default)]
    pub advance: f64,
    /// `_presence` reads it as `bands.get("rush", 12)` (ai_mission_eval.gd:610) —
    /// the 12" fallback lives in that default, not in the caller.
    #[serde(default = "twelve")]
    pub rush: f64,
}

fn twelve() -> f64 {
    12.0
}

impl Default for MoveBands {
    fn default() -> Self {
        MoveBands { advance: 0.0, rush: 12.0 }
    }
}

/// The immutable per-game profile table; units index into it.
#[derive(Debug, Default)]
pub struct Profiles {
    pub list: Vec<Profile>,
    pub index: HashMap<String, usize>,
}

impl Profiles {
    pub fn get(&self, key: &str) -> Option<&Profile> {
        self.index.get(key).map(|&i| &self.list[i])
    }
}

/// Capture order + the profile index per unit. Never written after capture, so
/// clones share it (`clone_state` battle_sim.gd:463-505 keeps the GameUnit ref).
#[derive(Debug, Default)]
pub struct Roster {
    pub keys: Vec<String>,
    pub index: HashMap<String, usize>,
    pub profile: Vec<usize>,
}

impl Roster {
    pub fn len(&self) -> usize {
        self.keys.len()
    }
    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }
}

/// Per-unit modifier snapshot — `mods` is per clone, `mods_base` is the
/// capture-time reading and is never written (battle_sim.gd:475-479).
/// All six are FLOATS, not integers: `BattleSim._apply_cast_effect`
/// (battle_sim.gd:976-982) adds `landed * modifier`, and `landed` is the D3
/// weight times the cast chance — a third of a half. A snapshot that has never
/// been cast on carries plain `0`, which is why the M1-2 port could type the
/// first three as ints and get away with it.
#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Mods {
    #[serde(default)]
    pub hit: f64,
    #[serde(default)]
    pub def: f64,
    #[serde(default)]
    pub morale: f64,
    #[serde(default)]
    pub range_in: f64,
    #[serde(default)]
    pub advance: f64,
    #[serde(default)]
    pub rush: f64,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Objective {
    pub pos: [f64; 3],
    #[serde(default)]
    pub owner: i64,
}

/// Marker-mission state — `SoloController` :33, read by `_score_hand` :368-380.
#[derive(Debug, Clone, Deserialize)]
pub struct Marker {
    #[serde(default)]
    pub owned_by: i64,
    #[serde(default)]
    pub destructible: bool,
    #[serde(default)]
    pub destroyed: bool,
}

/// The dynamic layer. `#[derive(Clone)]` reproduces `BattleSim.clone_state`
/// battle_sim.gd:463-505 exactly: positions/wounds/radii/mods/objectives/
/// markers_meta/destroy_seq are deep, roster + profiles + mods_base + los + the
/// vp blobs are shared `Rc`s, and `reserves` simply does not exist here — the
/// GDScript clone drops it, so every rollout node reads it as absent.
#[derive(Debug, Clone)]
pub struct State {
    pub roster: Rc<Roster>,
    pub profiles: Rc<Profiles>,
    pub round: i64,
    pub rounds_total: i64,
    pub scoring: Rc<str>,
    pub objectives: Vec<Objective>,
    pub markers_meta: Vec<Marker>,
    pub destroy_seq: Vec<i64>,
    pub vp: Option<Rc<serde_json::Value>>,
    pub vp_flavour: Option<Rc<serde_json::Value>>,
    pub vp_memo: Option<Rc<serde_json::Value>>,
    pub cast_events: Vec<Rc<serde_json::Value>>,
    // --- per-unit arrays, indexed by `roster` order (= capture order) ---
    pub player: Vec<i64>,
    pub alive: Vec<i64>,
    pub activated: Vec<bool>,
    pub shaken: Vec<bool>,
    pub fatigued: Vec<bool>,
    pub in_cover: Vec<bool>,
    pub aircraft: Vec<bool>,
    pub dormant: Vec<bool>,
    pub casts: Vec<i64>,
    pub morale_bonus: Vec<i64>,
    pub ambush_arrived_round: Vec<i64>,
    pub earliest_arrival_round: Vec<i64>,
    pub wound_frac: Vec<f64>,
    pub positions: Vec<Vec<[f64; 3]>>,
    pub wounds: Vec<Vec<i64>>,
    pub radii: Vec<Vec<f64>>,
    pub mods: Vec<Mods>,
    pub mods_base: Vec<Rc<Mods>>,
    pub los: Vec<Option<Rc<HashMap<String, bool>>>>,
    /// `BattleSim._los_clear` (battle_sim.gd:666-670) answers for this state, as
    /// a row-major n x n matrix in capture order: `los_pairs[i * n + j]` is true
    /// when the line of fire from unit i to unit j is clear. `None` = the state
    /// carried no `los_blocked` seam, and `_los_clear` then returns true for
    /// every pair. Shared across clones because it is never rewritten — see the
    /// staleness note on `sim::resolve`.
    pub los_pairs: Option<Rc<Vec<bool>>>,
}

impl State {
    pub fn units(&self) -> usize {
        self.roster.len()
    }
    pub fn key(&self, i: usize) -> &str {
        &self.roster.keys[i]
    }
    pub fn profile(&self, i: usize) -> &Profile {
        &self.profiles.list[self.roster.profile[i]]
    }
    /// `BattleSim.sees` battle_sim.gd:683-686 — no matrix means everyone sees
    /// everyone; a present matrix defaults an unlisted key to `true`.
    pub fn sees(&self, i: usize, other_key: &str) -> bool {
        match &self.los[i] {
            None => true,
            Some(m) => *m.get(other_key).unwrap_or(&true),
        }
    }
}
