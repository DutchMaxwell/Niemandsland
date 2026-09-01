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

use crate::geom;

use serde::{Deserialize, Serialize};

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
    /// NML-1073 M5 D5-4b (#447) — the base SHAPE `base_radius` cannot carry.
    /// That scalar is `BaseShape.bounding_radius()`, the CIRCUMSCRIBING circle,
    /// while the table measures an oval's exact support extent
    /// (separation_checker.gd:290). "oval" / "round"; absent on every corpus
    /// recorded before #447, and "" then reads as round — today's path.
    #[serde(default)]
    pub base_shape: String,
    /// The unit's UNSCALED base axes in millimetres (battle_sim.gd:1649-1655),
    /// local X and local Z. Zero when the header did not write them.
    #[serde(default)]
    pub base_w_mm: f64,
    #[serde(default)]
    pub base_d_mm: f64,
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

fn six() -> f64 {
    6.0
}

/// `SoloController.sim_move_bands(unit)` as the recorder writes it into the
/// DYNAMIC layer — `BattleSim.state_to_plain` battle_sim.gd:1402. Distinct from
/// `Profile.move_bands` on purpose: the profile's copy is written ONCE per game,
/// this one is re-read per activation because `move_bands_for_props`
/// (movement_range_controller.gd:80) derives the bands from a dict that GROWS
/// during a live game. The two defaults are the caller's own fallbacks —
/// `bands.get("advance", 6)` (ai_planner.gd:713) and `bands.get("rush", 12)`
/// (ai_planner.gd:1192) — so an absent key answers what the GDScript answers.
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub struct Bands {
    #[serde(default = "six")]
    pub advance: f64,
    #[serde(default = "twelve")]
    pub rush: f64,
}

impl Default for Bands {
    fn default() -> Self {
        Bands { advance: 6.0, rush: 12.0 }
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

/// NML-1073 M2-5b — the DYNAMIC half of `Profile`: every field a LIVE game
/// rewrites between two activations. `BattleSim.unit_profile_dyn`
/// (battle_sim.gd) reads them fresh per activation and `AiActRecorder.
/// _stamp_gate_reads` stamps them into the act line under the unit key `prof`;
/// the header's copy of the same fields is the DEPLOYMENT reading and is the
/// fallback for a corpus recorded before this contract.
///
/// Why each one moves (the GDScript source of the drift):
/// * `special_rules` — `main.gd` `_solo_apply_grant` / `_solo_revoke_grant`
///   add and remove a `" (spell)"`-suffixed rule per cast.
/// * `tough` — `AiEv.unit_rating(u, "Tough")`, derived from `special_rules`.
/// * `caster_value` — `GameUnit.get_caster_value` answers a **Caster Group**
///   unit with its ALIVE model count (game_unit.gd:382-414).
/// * `item_grants` — `unit_properties["item_grants"]`, the registry input of
///   `RulesRegistry.unit_rules_of_primitive` (rules_registry.gd:167-170).
/// * `attached_hero_rules` — ALIVE attached heroes only. A hero that FALLS
///   stops voting in `AiEv.rule_on_all_models` (ai_ev.gd:79-83), so the host
///   GAINS every unit-wide rule that hero happened to lack. This is the gap
///   this record exists for.
///
/// `shooting_range_bonus` / `max_activation_advance_bonus_in` travel in the same
/// act block but are deliberately absent here: no function of this port reads
/// them (the menu prices reach off the weapons' own ranges), so parsing them
/// would only make the struct claim a coverage it does not have. They are read
/// by the GDScript stand-in in tools/node_recheck.gd.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
pub struct ProfileDyn {
    #[serde(default)]
    pub special_rules: Vec<String>,
    #[serde(default)]
    pub tough: i64,
    #[serde(default)]
    pub caster_value: i64,
    #[serde(default)]
    pub item_grants: Vec<String>,
    #[serde(default)]
    pub attached_hero_rules: Vec<Vec<String>>,
}

impl Profile {
    /// The recorded footprint as `SeparationChecker.shape_for_model` :267-278
    /// builds it. Anything but "oval" — including the "rect" the readers accept
    /// and the recorder never writes — is a ROUND base, which is exactly what
    /// that function does with a `base_is_square` unit.
    pub fn shape(&self) -> geom::BaseShape {
        if self.base_shape == "oval" && self.base_w_mm > 0.0 && self.base_d_mm > 0.0 {
            geom::BaseShape::Oval { w_mm: self.base_w_mm, d_mm: self.base_d_mm, yaw: 0.0 }
        } else {
            geom::BaseShape::Round
        }
    }
}

impl ProfileDyn {
    /// The reading the HEADER profile itself carries — what an act with no
    /// `prof` block answers with, and the baseline every comparison starts from.
    pub fn of(p: &Profile) -> ProfileDyn {
        ProfileDyn {
            special_rules: p.special_rules.clone(),
            tough: p.tough,
            caster_value: p.caster_value,
            item_grants: p.item_grants.clone(),
            attached_hero_rules: p.attached_hero_rules.clone(),
        }
    }

    /// `p` with this activation's reading in place of the header's.
    pub fn apply(&self, p: &Profile) -> Profile {
        let mut out = p.clone();
        out.special_rules = self.special_rules.clone();
        out.tough = self.tough;
        out.caster_value = self.caster_value;
        out.item_grants = self.item_grants.clone();
        out.attached_hero_rules = self.attached_hero_rules.clone();
        out
    }
}

/// NML-1073 M2-5b — interns the per-ACTIVATION profile table.
///
/// The header's own table is handed back unchanged while every unit's `prof`
/// block still reads the way the header does; the first activation that differs
/// (a hero falls, a spell grants a rule) gets ONE rebuild that is then reused
/// for as long as the reading holds. Pointer identity is load-bearing, not an
/// optimisation: `StaticsCache` keys the derived `UnitStatic` closure on
/// `Rc::ptr_eq`, so handing back a fresh `Rc` with identical contents would
/// rebuild the whole closure on every activation.
#[derive(Debug)]
pub struct ProfileCache {
    base: Rc<Profiles>,
    base_dyn: Vec<ProfileDyn>,
    last: Option<(Vec<ProfileDyn>, Rc<Profiles>)>,
}

impl ProfileCache {
    pub fn new(base: Rc<Profiles>) -> ProfileCache {
        let base_dyn = base.list.iter().map(ProfileDyn::of).collect();
        ProfileCache { base, base_dyn, last: None }
    }

    /// The HEADER table this cache overrides — what `roster_of` has to resolve
    /// unit keys against, so a caller never has to carry the two side by side
    /// and let them drift apart.
    pub fn base(&self) -> &Rc<Profiles> {
        &self.base
    }

    /// The table THIS activation reads. `dyns` is in ROSTER order and
    /// `roster.profile[i]` names the profile entry each one overrides; `None`
    /// (a corpus without the block) keeps the header's reading for that unit.
    pub fn effective(&mut self, roster: &Roster, dyns: &[Option<ProfileDyn>]) -> Rc<Profiles> {
        let mut want = self.base_dyn.clone();
        for (i, d) in dyns.iter().enumerate() {
            if let (Some(d), Some(&pi)) = (d.as_ref(), roster.profile.get(i)) {
                if pi < want.len() {
                    want[pi] = d.clone();
                }
            }
        }
        if want == self.base_dyn {
            return Rc::clone(&self.base);
        }
        if let Some((k, t)) = self.last.as_ref() {
            if *k == want {
                return Rc::clone(t);
            }
        }
        let list: Vec<Profile> =
            self.base.list.iter().zip(&want).map(|(p, d)| d.apply(p)).collect();
        let table = Rc::new(Profiles { list, index: self.base.index.clone() });
        self.last = Some((want, Rc::clone(&table)));
        table
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
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
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

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub struct Objective {
    pub pos: [f64; 3],
    #[serde(default)]
    pub owner: i64,
}

/// Marker-mission state — `SoloController` :33, read by `_score_hand` :368-380.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Marker {
    #[serde(default)]
    pub owned_by: i64,
    #[serde(default)]
    pub destructible: bool,
    #[serde(default)]
    pub destroyed: bool,
    /// `BattleSim.apply_destroy_step` (:405-423) stamps the destruction ORDER
    /// here; `vp_score_round`'s demolition branch (:365-383) reads it back to
    /// decide who collects the revenge VP.
    #[serde(default)]
    pub destroyed_seq: i64,
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
    /// `capture()`'s attachment keys resolved to ROSTER indices — battle_sim.gd:
    /// 1249-1258 stamps `attached` (a unit's attached heroes' snapshot keys, in
    /// capture order) and `attached_to` (its host's key, "" for none).
    /// `_unit_group` (battle_sim.gd:528-547) reads them and nothing ever writes
    /// them, so `clone_state` shares the reference (battle_sim.gd:490-494) and an
    /// `Rc` bump is the whole copy here. A key the roster does not carry is
    /// dropped: the GDScript puts it in the key set too, but the obstacle loop
    /// walks `next["units"]` and can never match it. Empty/None on a corpus
    /// recorded before NML-1073 S1.
    pub attached: Rc<Vec<Vec<usize>>>,
    pub attached_to: Rc<Vec<Option<usize>>>,
    pub los: Vec<Option<Rc<HashMap<String, bool>>>>,
    /// `BattleSim._los_clear` (battle_sim.gd:666-670) answers for this state, as
    /// a row-major n x n matrix in capture order: `los_pairs[i * n + j]` is true
    /// when the line of fire from unit i to unit j is clear. `None` = the state
    /// carried no `los_blocked` seam, and `_los_clear` then returns true for
    /// every pair. Shared across clones because it is never rewritten — see the
    /// staleness note on `sim::resolve`.
    pub los_pairs: Option<Rc<Vec<bool>>>,
    // --- NML-1073 M2-0c/M2-0d gate reads, per unit, act corpus only ---
    /// `SoloController.sim_move_bands(unit)` at capture time — battle_sim.gd:1402.
    pub bands: Vec<Bands>,
    /// `[penalty_in, floor_in]` of `SoloController.melee_shroud_charge_in`
    /// (:5150), resolved at record time — `AiActRecorder._melee_shroud_params`.
    /// `None` = the victim carries no rule of the Melee-Shrouding family, and
    /// the charge reach is then the raw band.
    pub shroud: Vec<Option<[f64; 2]>>,
    /// `has_special_rule("Strider") or has_special_rule("Flying")` — the p.13
    /// difficult-terrain exemption (`AiActRecorder._stamp_gate_reads`).
    pub charge_no_difficult: Vec<bool>,
    /// `SoloController._move_base_radius_m(_moving_models(unit))` (:4735/:4915) —
    /// NOT `radii`: the gate measures unit PLUS attached heroes and floors at
    /// `SeparationChecker.DEFAULT_BASE_RADIUS_M`.
    pub charge_probe_r: Vec<f64>,
    // --- NML block B2b: the LIVE modifier ledger (see `crate::mods`) ---
    /// `main._solo_spell_mods` (main.gd:370) — the DICE path's own buff
    /// records, per unit. Written by the Utility-Buff arms on the tray path and
    /// read back at the roll; deep-cloned with the state like `mods` is, and
    /// deliberately NOT serialised: the table's own snapshot carries the NET
    /// (`SoloController.active_mod_net_of`, battle_sim.gd:1530), never records,
    /// so a captured state can only start this ledger empty.
    pub buffs: Vec<Vec<crate::mods::LiveMod>>,
    /// `unit_properties["vs_mark_round"]` (main.gd:16752) — the once-per-
    /// activation stamp of the vs-target Mark arm, -1 for never.
    pub vs_mark_round: Vec<i64>,
}

impl State {

    /// NML-1073 M5 D1-B4b — may unit `i` take an activation of its OWN this
    /// round? `SoloController.can_activate` (solo_controller.gd:405-411) ends on
    /// `not u.is_attached()`: a joined hero NEVER activates alone. It acts
    /// inside its host's activation — firing its own guns in the host's volley
    /// (`main._run_ai_shooting` :2954-2958) and moving with the host's models
    /// (`SoloController._moving_models` :5319-5321, which walks
    /// `get_alive_models_with_attached()`).
    ///
    /// The other three terms are the GDScript planner's own pool filter
    /// verbatim (ai_planner.gd:27, :131, :645): the unit's side, its `activated`
    /// flag and a living model — and they are ALL the filter unless
    /// `hero_attach` is on. `BattleSim`/`AiPlanner` never refuse a joined hero
    /// (only `SoloController` does, one layer up), and a table RECORDING carries
    /// attachment on every host, so an unconditional refusal here would move
    /// every recorded rollout value and redden GATE G5. `Seams::hero_attach`
    /// (io.rs) is therefore the switch, default OFF.
    pub fn can_activate(&self, i: usize, player: i64, hero_attach: bool) -> bool {
        self.player[i] == player
            && !self.activated[i]
            && self.alive[i] > 0
            && !(hero_attach && self.attached_to[i].is_some())
    }
    pub fn units(&self) -> usize {
        self.roster.len()
    }
    pub fn key(&self, i: usize) -> &str {
        &self.roster.keys[i]
    }
    pub fn profile(&self, i: usize) -> &Profile {
        &self.profiles.list[self.roster.profile[i]]
    }
    /// The unit's recorded base footprint — `Profile::shape`, per unit, so an
    /// attached hero (its own roster slot) answers with its own base.
    pub fn base_shape(&self, i: usize) -> geom::BaseShape {
        self.profile(i).shape()
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
