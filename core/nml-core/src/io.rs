//! Loader for the node corpus written by `AiPlanner._record_node`
//! (ai_planner.gd:470-487): line 1 is `{"profiles": {key: profile}}`, every line
//! after it is one rollout node.
//!
//! The `units` object carries CAPTURE ORDER in its key order, and serde's
//! `MapAccess` hands entries over in document order — that is why the units are
//! read through `Ordered<T>` into a `Vec` and never through `serde_json::Value`
//! (whose default map sorts).

use std::collections::HashMap;
use std::fmt;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::rc::Rc;

use serde::de::{MapAccess, Visitor};
use serde::{Deserialize, Deserializer};

use crate::state::{
    Bands, Marker, Mods, Objective, Profile, ProfileCache, ProfileDyn, Profiles, Roster, State,
};

/// A JSON object read as an ordered `Vec` of entries.
pub(crate) struct Ordered<T>(pub(crate) Vec<(String, T)>);

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Ordered<T> {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct V<T>(std::marker::PhantomData<T>);
        impl<'de, T: Deserialize<'de>> Visitor<'de> for V<T> {
            type Value = Ordered<T>;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("a JSON object")
            }
            fn visit_map<A: MapAccess<'de>>(self, mut m: A) -> Result<Ordered<T>, A::Error> {
                let mut out = Vec::with_capacity(m.size_hint().unwrap_or(16));
                while let Some((k, v)) = m.next_entry::<String, T>()? {
                    out.push((k, v));
                }
                Ok(Ordered(out))
            }
        }
        d.deserialize_map(V(std::marker::PhantomData))
    }
}

fn neg_one() -> i64 {
    -1
}

#[derive(Deserialize)]
pub(crate) struct PlainUnit {
    #[serde(default)]
    player: i64,
    #[serde(default)]
    alive: i64,
    #[serde(default)]
    activated: bool,
    #[serde(default)]
    shaken: bool,
    #[serde(default)]
    fatigued: bool,
    #[serde(default)]
    in_cover: bool,
    #[serde(default)]
    aircraft: bool,
    #[serde(default)]
    dormant: bool,
    #[serde(default)]
    casts: i64,
    #[serde(default)]
    morale_bonus: i64,
    #[serde(default = "neg_one")]
    ambush_arrived_round: i64,
    #[serde(default = "neg_one")]
    earliest_arrival_round: i64,
    #[serde(default)]
    wound_frac: f64,
    #[serde(default)]
    positions: Vec<[f64; 3]>,
    #[serde(default)]
    wounds: Vec<i64>,
    #[serde(default)]
    radii: Vec<f64>,
    #[serde(default)]
    mods: Mods,
    #[serde(default)]
    mods_base: Mods,
    /// NML-1073 S1 attachment keys (battle_sim.gd:1249-1258). Absent on a corpus
    /// recorded before that commit, which is what the defaults answer.
    #[serde(default)]
    attached: Vec<String>,
    #[serde(default)]
    attached_to: String,
    #[serde(default)]
    los: Option<HashMap<String, bool>>,
    /// NML-1073 M2-0c/M2-0d gate reads — present on the ACT corpus only
    /// (`AiActRecorder._stamp_gate_reads`, battle_sim.gd:1402). The node corpus
    /// carries none of them, which is what the defaults answer.
    /// ABSENT on the node corpus, which is why this is an `Option`: the
    /// fallback is the unit's PROFILE `move_bands` (also a
    /// `SoloController.sim_move_bands` reading, taken once per game), not
    /// `Bands::default()` — a defaulted 6"/12" would answer for a Slow unit
    /// that the profile already reads as 4"/8".
    #[serde(default)]
    bands: Option<Bands>,
    #[serde(default)]
    shroud: Option<Vec<f64>>,
    #[serde(default)]
    charge_no_difficult: bool,
    #[serde(default = "default_probe_r")]
    charge_probe_r: f64,
    /// NML-1073 M2-5b — the DYNAMIC half of the unit's profile AS OF THIS
    /// ACTIVATION (`BattleSim.unit_profile_dyn`, stamped by
    /// `AiActRecorder._stamp_gate_reads`). `None` on the node corpus and on any
    /// act corpus recorded before M2-5b, where the header's deployment reading
    /// is all there is.
    #[serde(default)]
    prof: Option<ProfileDyn>,
}

/// `SeparationChecker.DEFAULT_BASE_RADIUS_M` — the fallback
/// `BattleSim.charge_illegal_plain` (battle_sim.gd:1563) reads for an absent key.
fn default_probe_r() -> f64 {
    0.016
}

#[derive(Deserialize)]
pub(crate) struct PlainState {
    round: i64,
    rounds_total: i64,
    #[serde(default)]
    scoring: String,
    #[serde(default)]
    objectives: Vec<Objective>,
    #[serde(deserialize_with = "units_in_capture_order")]
    units: Ordered<PlainUnit>,
    #[serde(default)]
    markers_meta: Vec<Marker>,
    #[serde(default)]
    destroy_seq: Vec<i64>,
    #[serde(default)]
    vp: Option<serde_json::Value>,
    #[serde(default)]
    vp_flavour: Option<serde_json::Value>,
    #[serde(default)]
    vp_memo: Option<serde_json::Value>,
    #[serde(default)]
    cast_events: Vec<serde_json::Value>,
    /// One string per unit in capture order, one character per unit: "1" = the
    /// line of fire is clear (`BattleSim._los_clear`). Written by
    /// `BattleSim.state_to_plain`; absent when the state has no los_blocked seam.
    #[serde(default)]
    los_pairs: Option<Vec<String>>,
}

/// One rollout action — `AiPlanner._policy_candidates` ai_planner.gd:517-545.
#[derive(Debug, Clone, Deserialize)]
pub struct Action {
    pub kind: i64,
    pub unit: String,
    #[serde(default)]
    pub dest: Option<[f64; 3]>,
    #[serde(default)]
    pub shoot: Option<String>,
    #[serde(default)]
    pub charge: Option<String>,
    /// "patient" is a FLAG on the ADVANCE candidate (ai_planner.gd:517-545), not a key.
    #[serde(default)]
    pub patient: bool,
}

#[derive(Deserialize)]
struct PlainNode {
    state_before: PlainState,
    action: Action,
    state_after: PlainState,
    score: f64,
    player: i64,
    /// The mover's cover at its destination — `resolve`'s recorded `terrain_at`
    /// answer; absent on a node whose action has no dest.
    #[serde(default)]
    cover_dest: Option<bool>,
    /// Which leaf priced this node: RICH (`score + reply_threat`) or CHEAP
    /// (`score` alone) — `AiPlanner._policy_step` ai_planner.gd:508-510.
    #[serde(default)]
    rich: bool,
}

#[derive(Debug)]
pub struct Node {
    pub state_before: State,
    pub action: Action,
    pub state_after: State,
    /// The score `AiMissionEval.score` returned for `state_after` in the game.
    pub score: f64,
    pub player: i64,
    /// `resolve`'s terrain answer for this node; `None` when the action has no dest.
    pub cover_dest: Option<bool>,
    /// True when the recorded score carries the reply threat (the RICH leaf).
    pub rich: bool,
}

/// Which A/B seams `resolve()` branched on while the corpus was played —
/// header line 1's `"seams"` (ai_planner.gd:483-489, added with M1-3).
/// A corpus recorded before that (the M1-2 one) has no key and defaults to
/// both OFF, which is what it was probed to be.
#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Seams {
    /// `BattleSim.spacing_enabled()` — NML_SIM_SPACING, battle_sim.gd:25-31.
    #[serde(default)]
    pub spacing: bool,
    /// `BattleSim.cast_phase_enabled()` — NML_SIM_CAST, battle_sim.gd:37-42.
    #[serde(default)]
    pub cast: bool,
    /// NML-1073 M4-7 — NML_SIM_PATH: the imagined move follows a tier-2
    /// `mv::reach` route instead of a straight line. No corpus was ever
    /// recorded with it, so it defaults OFF and every recorded rollout replays
    /// digest-identical.
    #[serde(default)]
    pub path: bool,
    /// NML-1073 M5 D1-B4b — the trainer plays `hero_attach="table"`, so a
    /// JOINED HERO is folded into its host the way the live game folds it:
    /// the host's activation marks the hero activated too
    /// (`SoloController.can_activate` solo_controller.gd:411 — a joined hero
    /// never activates alone) and the hero's models take the host's
    /// displacement (`_moving_models` :5319-5321 walks
    /// `get_alive_models_with_attached()`).
    ///
    /// A SEAM and not a plain rule, because `BattleSim` — the parity authority
    /// for every planner gate — does neither: `ai_planner.gd:27/131/645`
    /// filters on player/activated/alive only, and `battle_sim.gd:699-700`
    /// moves `su["positions"]` and nothing else. A table RECORDING carries
    /// attachment on every host, so folding it in unconditionally would move
    /// the recorded rollout values and redden GATE G5. Default OFF: no corpus
    /// moves. `selfplay.play_game(hero_attach="table")` turns it on, which is
    /// what stops an attached hero from both firing in its host's volley
    /// (D1-B4b) and spending a full activation of its own.
    #[serde(default)]
    pub hero_attach: bool,
    /// NML-1073 M5 D5-1 — the trainer plays `charge_landing="table"`, so a
    /// CHARGE fights only when the table would have fought it.
    ///
    /// Landing within `MELEE_ENGAGE_IN` is only the FIRST question
    /// `main._run_ai_melee` asks (main.gd:8005-8006). The second is whether the
    /// SNAP that closes the residual base gap still fits the move budget the
    /// charge left over: `snap_charge(unit, target, last_move_remaining_in())`
    /// returning negative is a falls-short and no fight (main.gd:8015-8022,
    /// solo_controller.gd:8639/8644/8659). On `~/selfplay_out/qbe_ref` that one
    /// gate accounts for 53 of the 116 recorded charges the table never fought,
    /// all of them landed within an inch — median residual 0.14".
    ///
    /// WHAT THIS SEAM DOES NOT DO, so the number is not read as more than it
    /// is: the port's move is still a rigid translation toward the planner's
    /// `dest`, so its spent arc is a LOWER bound on the table's bent route and
    /// the gate under-refuses. Routing the move is D5-2 and it needs the exact
    /// solver — the tier-2 `mv::reach` route was measured here and is WORSE
    /// (its coarse arc starves charges the table lands).
    ///
    /// Default OFF: every corpus recorded before this replays unchanged.
    #[serde(default)]
    pub charge_landing: bool,
    /// NML-1073 M5 D6a-B4 — `Knobs::sighting == Model`: the tray volley counts
    /// its shooters per model and per weapon instead of taking the unit's
    /// `alive`. Scoped to the TRAY resolver on purpose: the planner's EV must
    /// keep scaling by `alive` on both sides, because the table itself is
    /// asymmetric — it plans in `alive` (`AiEv.shoot_ev` via
    /// `BattleSim._profiles_of`) and resolves in `sighted`.
    #[serde(default)]
    pub sighting: bool,
}

impl Node {
    /// The caster's line-of-sight row for the CAST sub-phase — the answers
    /// `BattleSim._best_spell_target` (battle_sim.gd:930) gets from `_los_clear`
    /// with the POST-move centres, which `state_before.los_pairs` (a pre-move
    /// matrix) cannot supply. Read off `state_after.los_pairs`, the same
    /// recorded-Callable-answer trick `cover_dest` uses for terrain.
    ///
    /// CAVEAT, stated rather than hidden: `state_after` is the end of the whole
    /// activation, so on a node where the cast or a melee removed models the
    /// centres have moved on again. `None` when the state carries no matrix.
    pub fn cast_los(&self) -> Option<&[bool]> {
        let m = self.state_after.los_pairs.as_ref()?;
        let si = *self.state_after.roster.index.get(self.action.unit.as_str())?;
        let n = self.state_after.units();
        m.get(si * n..si * n + n)
    }
}

#[derive(Debug)]
pub struct NodeCorpus {
    pub profiles: Rc<Profiles>,
    pub nodes: Vec<Node>,
    pub seams: Seams,
}

/// Builds (or reuses) the roster for one plain state. Every node of one game has
/// the same unit keys in the same order, so the roster is interned across nodes.
pub(crate) fn roster_of(
    plain: &PlainState,
    profiles: &Profiles,
    cache: &mut Option<Rc<Roster>>,
) -> Result<Rc<Roster>, String> {
    if let Some(r) = cache.as_ref() {
        if r.keys.len() == plain.units.0.len()
            && r.keys.iter().zip(&plain.units.0).all(|(a, (b, _))| a == b)
        {
            return Ok(Rc::clone(r));
        }
    }
    let mut roster = Roster::default();
    for (k, _) in &plain.units.0 {
        let pi = *profiles
            .index
            .get(k.as_str())
            .ok_or_else(|| format!("no profile for unit key {k}"))?;
        roster.index.insert(k.clone(), roster.keys.len());
        roster.profile.push(pi);
        roster.keys.push(k.clone());
    }
    let rc = Rc::new(roster);
    *cache = Some(Rc::clone(&rc));
    Ok(rc)
}

/// `(side, index)` of a recorder-shaped unit id `p<player>_<index>_<token>`, or
/// `None` for an id this port did not shape.
fn natural_key(id: &str) -> Option<(i64, i64)> {
    let mut it = id.split('_');
    let side = it.next()?.strip_prefix('p')?.parse::<i64>().ok()?;
    let index = it.next()?.parse::<i64>().ok()?;
    Some((side, index))
}

/// The `units` object, read in CAPTURE order whatever order the document holds.
///
/// `BattleSim.capture()` (battle_sim.gd:1128-1240) says it outright: "units are
/// a Dict — INSERTION ORDER is roster order and load-bearing". Two writers lose
/// that order on the way out and neither can be asked to keep it:
/// `JSON.stringify(rec, "", true, true)` key-SORTS the recorded corpus
/// (ai_planner.gd:505), and `plain_of` below builds the object in a
/// `serde_json::Map`, i.e. a `BTreeMap`, which sorts it again on every
/// `state.plain()` round-trip of the Python trainer.
///
/// While no side fields ten units the two orders agree and this is a no-op. The
/// moment one does they come apart — "p1_10_..." sorts BEFORE "p1_1_..." — and
/// the roster, the board rows the trainer logs, the activation pool order and
/// the `los_pairs` mapping all read one slot off. An id shape this port did not
/// write leaves the document order alone, which is what a hand-built state and
/// every pre-recorder corpus need.
fn units_in_capture_order<'de, D: Deserializer<'de>>(
    d: D,
) -> Result<Ordered<PlainUnit>, D::Error> {
    let mut units = Ordered::<PlainUnit>::deserialize(d)?;
    let mut keyed: Vec<(i64, i64, usize)> = Vec::with_capacity(units.0.len());
    for (i, (k, _)) in units.0.iter().enumerate() {
        match natural_key(k) {
            Some((s, x)) => keyed.push((s, x, i)),
            None => return Ok(units), // unknown id shape -> document order
        }
    }
    keyed.sort();
    if keyed.iter().enumerate().all(|(row, &(_, _, i))| row == i) {
        return Ok(units);
    }
    let mut slots: Vec<Option<(String, PlainUnit)>> = units.0.into_iter().map(Some).collect();
    units = Ordered(
        keyed
            .into_iter()
            .map(|(_, _, i)| slots[i].take().expect("each index taken once"))
            .collect(),
    );
    Ok(units)
}

/// The row/column each ROSTER index owns in the `los_pairs` matrix.
///
/// The matrix is written KEY-SORTED by both writers that produce one:
/// `BattleSim.state_to_plain` sorts explicitly (battle_sim.gd:1492-1506,
/// `los_keys.sort()` — "row i is one character per unit KEY-SORTED"), and
/// `Terrain::los_pairs` (terrain.rs:295) ports that sort. The ROSTER, however,
/// is the capture order `units_in_capture_order` restores, because that is the
/// order `AiPlanner`'s root loop walks (`for key in state["units"]`).
///
/// The two agree only while every unit id sorts the way it was captured. They
/// come apart the moment a side fields eleven units: the ids are
/// `p<player>_<index>_<token>`, and lexically "p1_10_..." sorts BEFORE
/// "p1_1_...", so twelve of a twenty-unit matrix's rows land on the wrong unit
/// — and the sight gate of `reply_threat` (battle_sim.gd:1013-1014) and of
/// `resolve`'s shoot branch (:629) then answers for the wrong pair.
///
/// `pub` because the IN-GAME seam needs the identical mapping: the Variant
/// marshaller (`nml-core-godot/src/plain.rs`) is handed the very same plain
/// form straight from `state_to_plain`, so it reads the very same key-sorted
/// matrix against a capture-ordered roster.
pub fn los_positions(keys: &[String]) -> Vec<usize> {
    let n = keys.len();
    let mut sorted: Vec<(&str, usize)> =
        keys.iter().enumerate().map(|(i, k)| (k.as_str(), i)).collect();
    sorted.sort();
    let mut pos = vec![0usize; n];
    for (row, &(_, roster_i)) in sorted.iter().enumerate() {
        pos[roster_i] = row;
    }
    pos
}

impl PlainState {
    /// NML-1073 M2-5b — this activation's dynamic profile reading per unit, in
    /// DOCUMENT order, which is roster order (`roster_of` walks the same list).
    /// Read BEFORE `state_of` consumes the plain state, because the effective
    /// profile table it produces is what `state_of` must be handed.
    pub(crate) fn dyn_profiles(&self) -> Vec<Option<ProfileDyn>> {
        self.units.0.iter().map(|(_, u)| u.prof.clone()).collect()
    }
}

pub(crate) fn state_of(plain: PlainState, profiles: &Rc<Profiles>, roster: Rc<Roster>) -> State {
    let n = roster.keys.len();
    // Roster index -> its row/column in the KEY-SORTED matrix; see `los_positions`.
    let cap = los_positions(&roster.keys);
    let mut st = State {
        roster,
        profiles: Rc::clone(profiles),
        round: plain.round,
        rounds_total: plain.rounds_total,
        scoring: Rc::from(plain.scoring.as_str()),
        objectives: plain.objectives,
        markers_meta: plain.markers_meta,
        destroy_seq: plain.destroy_seq,
        vp: plain.vp.map(Rc::new),
        vp_flavour: plain.vp_flavour.map(Rc::new),
        vp_memo: plain.vp_memo.map(Rc::new),
        cast_events: plain.cast_events.into_iter().map(Rc::new).collect(),
        player: Vec::with_capacity(n),
        alive: Vec::with_capacity(n),
        activated: Vec::with_capacity(n),
        shaken: Vec::with_capacity(n),
        fatigued: Vec::with_capacity(n),
        in_cover: Vec::with_capacity(n),
        aircraft: Vec::with_capacity(n),
        dormant: Vec::with_capacity(n),
        casts: Vec::with_capacity(n),
        morale_bonus: Vec::with_capacity(n),
        ambush_arrived_round: Vec::with_capacity(n),
        earliest_arrival_round: Vec::with_capacity(n),
        wound_frac: Vec::with_capacity(n),
        positions: Vec::with_capacity(n),
        wounds: Vec::with_capacity(n),
        radii: Vec::with_capacity(n),
        mods: Vec::with_capacity(n),
        mods_base: Vec::with_capacity(n),
        attached: Rc::new(Vec::new()),
        attached_to: Rc::new(Vec::new()),
        los: Vec::with_capacity(n),
        bands: Vec::with_capacity(n),
        shroud: Vec::with_capacity(n),
        charge_no_difficult: Vec::with_capacity(n),
        charge_probe_r: Vec::with_capacity(n),
        los_pairs: plain.los_pairs.as_ref().map(|rows| {
            // Read the matrix in its own (key-sorted) order and STORE it in
            // roster order, so `_los_clear`'s port can index it with roster
            // indices.
            let raw: Vec<&[u8]> = rows.iter().map(|r| r.as_bytes()).collect();
            let mut m = Vec::with_capacity(n * n);
            for i in 0..n {
                for j in 0..n {
                    let (ri, rj) = (cap[i], cap[j]);
                    m.push(raw.get(ri).and_then(|r| r.get(rj)).copied() == Some(b'1'));
                }
            }
            Rc::new(m)
        }),
    };
    // The attachment keys can only be resolved once every unit key is known, so
    // they are collected here and mapped after the per-unit loop.
    let mut attached_keys: Vec<Vec<String>> = Vec::with_capacity(n);
    let mut host_keys: Vec<String> = Vec::with_capacity(n);
    for (ui, (_, u)) in plain.units.0.into_iter().enumerate() {
        attached_keys.push(u.attached);
        host_keys.push(u.attached_to);
        st.player.push(u.player);
        st.alive.push(u.alive);
        st.activated.push(u.activated);
        st.shaken.push(u.shaken);
        st.fatigued.push(u.fatigued);
        st.in_cover.push(u.in_cover);
        st.aircraft.push(u.aircraft);
        st.dormant.push(u.dormant);
        st.casts.push(u.casts);
        st.morale_bonus.push(u.morale_bonus);
        st.ambush_arrived_round.push(u.ambush_arrived_round);
        st.earliest_arrival_round.push(u.earliest_arrival_round);
        st.wound_frac.push(u.wound_frac);
        st.positions.push(u.positions);
        st.wounds.push(u.wounds);
        st.radii.push(u.radii);
        st.mods.push(u.mods);
        st.mods_base.push(Rc::new(u.mods_base));
        st.los.push(u.los.map(Rc::new));
        // `SoloController.sim_move_bands(su["unit"])` — the LIVE read
        // `BattleSim.resolve` (:636) and `AiMissionEval._presence` (:602) take
        // on every call. The act corpus stamps it per activation because the
        // dict it derives from GROWS during a game (battle_sim.gd:1391-1401);
        // the node corpus predates that stamp, and its profile copy of the SAME
        // call (battle_sim.gd:1471) is the closest reading there is.
        st.bands.push(u.bands.unwrap_or_else(|| {
            let mb = st.profiles.list[st.roster.profile[ui]].move_bands;
            Bands { advance: mb.advance, rush: mb.rush }
        }));
        // `_melee_shroud_charge_in_plain` (battle_sim.gd:1572) takes the pair only
        // when the recorded array holds BOTH numbers; anything shorter is "absent".
        st.shroud.push(match u.shroud {
            Some(v) if v.len() >= 2 => Some([v[0], v[1]]),
            _ => None,
        });
        st.charge_no_difficult.push(u.charge_no_difficult);
        st.charge_probe_r.push(u.charge_probe_r);
    }
    st.attached = Rc::new(
        attached_keys
            .iter()
            .map(|ks| ks.iter().filter_map(|k| st.roster.index.get(k.as_str()).copied()).collect())
            .collect(),
    );
    st.attached_to = Rc::new(
        host_keys.iter().map(|k| st.roster.index.get(k.as_str()).copied()).collect(),
    );
    st
}

#[derive(Deserialize)]
struct Header {
    profiles: Ordered<Profile>,
    #[serde(default)]
    seams: Seams,
}

/// Reads `nodes.jsonl` into the immutable profile table and the node list.
pub fn load_nodes(path: &str) -> Result<NodeCorpus, String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    read_nodes(BufReader::new(file), path)
}

/// Same, from any reader — `origin` only labels the error messages.
pub fn read_nodes<R: BufRead>(reader: R, origin: &str) -> Result<NodeCorpus, String> {
    let path = origin;
    let mut lines = reader.lines();
    let head = lines
        .next()
        .ok_or_else(|| format!("{path}: empty file"))?
        .map_err(|e| e.to_string())?;
    let header: Header =
        serde_json::from_str(&head).map_err(|e| format!("{path}:1 profiles header: {e}"))?;
    let seams = header.seams;
    let mut profiles = Profiles::default();
    for (k, p) in header.profiles.0 {
        profiles.index.insert(k, profiles.list.len());
        profiles.list.push(p);
    }
    let profiles = Rc::new(profiles);
    let mut cache: Option<Rc<Roster>> = None;
    let mut nodes = Vec::new();
    for (i, line) in lines.enumerate() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let pn: PlainNode =
            serde_json::from_str(&line).map_err(|e| format!("{path}:{}: {e}", i + 2))?;
        let rb = roster_of(&pn.state_before, &profiles, &mut cache)?;
        let ra = roster_of(&pn.state_after, &profiles, &mut cache)?;
        nodes.push(Node {
            state_before: state_of(pn.state_before, &profiles, rb),
            action: pn.action,
            state_after: state_of(pn.state_after, &profiles, ra),
            score: pn.score,
            player: pn.player,
            cover_dest: pn.cover_dest,
            rich: pn.rich,
        });
    }
    Ok(NodeCorpus { profiles, nodes, seams })
}

/// Reads ONE plain state — the object the ACT corpus carries under `"state"`,
/// i.e. exactly `BattleSim.state_to_plain` plus the M2-0c/M2-0d gate reads and
/// the M2-5b per-unit `prof` block.
///
/// It takes JSON TEXT rather than a `serde_json::Value` on purpose: `units`
/// carries CAPTURE ORDER in its key order, and `serde_json::Value`'s map is a
/// `BTreeMap` that would sort it away. `roster_cache` interns the roster across
/// calls and `profiles` interns the per-activation table — the same two caches,
/// used the same way, as `read_acts`. A caller that skipped `ProfileCache` here
/// would replay every activation on the DEPLOYMENT reading, which is exactly
/// the staleness M2-5b removed.
pub fn state_from_json(
    text: &str,
    profiles: &mut ProfileCache,
    roster_cache: &mut Option<Rc<Roster>>,
) -> Result<State, String> {
    let plain: PlainState = serde_json::from_str(text).map_err(|e| e.to_string())?;
    let roster = roster_of(&plain, profiles.base(), roster_cache)?;
    let eff = profiles.effective(&roster, &plain.dyn_profiles());
    Ok(state_of(plain, &eff, roster))
}

/// The inverse of `state_from_json` (NML-1073 M3-2) — the plain form
/// `BattleSim.state_to_plain(state, false)` would have written for this state.
/// Mirrors `core/nml-core-godot/src/plain.rs:418-548`, with one difference that
/// is stated rather than hidden: the Godot seam replays the CAPTURED key mask,
/// this one has no mask and writes a key whenever the value can be told apart
/// from "the sim never carried it" —
///
///   * `dormant` only when true, `earliest_arrival_round` only when it is not
///     the `-1` the reader defaults to, `wound_frac` only when non-zero (the
///     same rule plain.rs:508 applies), `los`/`shroud` only when present;
///   * `ambush_arrived_round`, `bands`, `charge_no_difficult` and
///     `charge_probe_r` unconditionally — the act corpus always carries them;
///   * state-level `markers_meta`, `destroy_seq`, `cast_events` only when
///     non-empty and the three `vp` blobs only when present.
///
/// So `plain_of(state_from_json(x)) == x` holds for a state written by the act
/// recorder, and a state that GREW a key inside `resolve` reports it.
///
/// ONE key is deliberately not written: the M2-5b `prof` block. It is a
/// recorded READ, not state this port derives, and two of its seven fields
/// (`shooting_range_bonus`, `max_activation_advance_bonus_in`) are not modelled
/// at all — see `ProfileDyn`. A writer that invented them would claim a
/// coverage the port does not have. A caller that has to hand the plain form
/// back whole keeps the blocks it read, the way the Godot seam keeps its
/// captured key mask (`nml-core-godot/src/plain.rs`, `Captured`).
pub fn plain_of(st: &State) -> serde_json::Value {
    use serde_json::{Map, Value};
    let n = st.units();
    let mut units = Map::new();
    for i in 0..n {
        let mut u = Map::new();
        u.insert("player".into(), st.player[i].into());
        u.insert("alive".into(), st.alive[i].into());
        u.insert("activated".into(), st.activated[i].into());
        u.insert("shaken".into(), st.shaken[i].into());
        u.insert("fatigued".into(), st.fatigued[i].into());
        u.insert("in_cover".into(), st.in_cover[i].into());
        u.insert("aircraft".into(), st.aircraft[i].into());
        u.insert("casts".into(), st.casts[i].into());
        u.insert("morale_bonus".into(), st.morale_bonus[i].into());
        u.insert("ambush_arrived_round".into(), st.ambush_arrived_round[i].into());
        if st.dormant[i] {
            u.insert("dormant".into(), true.into());
        }
        if st.earliest_arrival_round[i] != -1 {
            u.insert("earliest_arrival_round".into(), st.earliest_arrival_round[i].into());
        }
        // `_apply_expected_wounds` (battle_sim.gd:1050-1059) CREATES the key the
        // first time a volley lands; a zero carry is indistinguishable from
        // "never touched" and stays absent — plain.rs:506-509 says the same.
        if st.wound_frac[i] != 0.0 {
            u.insert("wound_frac".into(), st.wound_frac[i].into());
        }
        u.insert(
            "positions".into(),
            Value::Array(
                st.positions[i]
                    .iter()
                    .map(|p| Value::Array(p.iter().map(|&x| x.into()).collect()))
                    .collect(),
            ),
        );
        u.insert("wounds".into(), Value::Array(st.wounds[i].iter().map(|&w| w.into()).collect()));
        u.insert("radii".into(), Value::Array(st.radii[i].iter().map(|&r| r.into()).collect()));
        u.insert("mods".into(), serde_json::to_value(st.mods[i]).unwrap_or(Value::Null));
        u.insert("mods_base".into(), serde_json::to_value(*st.mods_base[i]).unwrap_or(Value::Null));
        u.insert(
            "attached".into(),
            Value::Array(st.attached[i].iter().map(|&h| st.key(h).into()).collect()),
        );
        u.insert(
            "attached_to".into(),
            st.attached_to[i].map(|h| st.key(h)).unwrap_or("").into(),
        );
        if let Some(row) = &st.los[i] {
            let mut m = Map::new();
            for (k, v) in row.iter() {
                m.insert(k.clone(), (*v).into());
            }
            u.insert("los".into(), Value::Object(m));
        }
        u.insert("bands".into(), serde_json::to_value(st.bands[i]).unwrap_or(Value::Null));
        if let Some(s) = st.shroud[i] {
            u.insert("shroud".into(), Value::Array(vec![s[0].into(), s[1].into()]));
        }
        u.insert("charge_no_difficult".into(), st.charge_no_difficult[i].into());
        u.insert("charge_probe_r".into(), st.charge_probe_r[i].into());
        units.insert(st.roster.keys[i].clone(), Value::Object(u));
    }
    let mut out = Map::new();
    out.insert("round".into(), st.round.into());
    out.insert("rounds_total".into(), st.rounds_total.into());
    out.insert("scoring".into(), Value::String(st.scoring.to_string()));
    out.insert(
        "objectives".into(),
        serde_json::to_value(&st.objectives).unwrap_or(Value::Array(Vec::new())),
    );
    out.insert("units".into(), Value::Object(units));
    if !st.markers_meta.is_empty() {
        out.insert(
            "markers_meta".into(),
            serde_json::to_value(&st.markers_meta).unwrap_or(Value::Array(Vec::new())),
        );
    }
    if !st.destroy_seq.is_empty() {
        out.insert(
            "destroy_seq".into(),
            Value::Array(st.destroy_seq.iter().map(|&s| s.into()).collect()),
        );
    }
    if let Some(v) = &st.vp {
        out.insert("vp".into(), (**v).clone());
    }
    if let Some(v) = &st.vp_flavour {
        out.insert("vp_flavour".into(), (**v).clone());
    }
    if let Some(v) = &st.vp_memo {
        out.insert("vp_memo".into(), (**v).clone());
    }
    if !st.cast_events.is_empty() {
        out.insert(
            "cast_events".into(),
            Value::Array(st.cast_events.iter().map(|e| (**e).clone()).collect()),
        );
    }
    if let Some(m) = &st.los_pairs {
        // KEY-SORTED, which is the one order `state_to_plain` writes and
        // `state_of` reads — the state carries it in ROSTER order.
        let pos = los_positions(&st.roster.keys);
        let mut at = vec![0usize; n];
        for (i, &row) in pos.iter().enumerate() {
            at[row] = i;
        }
        let mut rows = Vec::with_capacity(n);
        for &i in &at {
            let mut s = String::with_capacity(n);
            for &j in &at {
                s.push(if m[i * n + j] { '1' } else { '0' });
            }
            rows.push(Value::String(s));
        }
        out.insert("los_pairs".into(), Value::Array(rows));
    }
    Value::Object(out)
}

#[cfg(test)]
mod tests {
    use super::{los_positions, units_in_capture_order};

    /// GATE Q-A-2 (NML-1073) — a `units` OBJECT is key-sorted by both writers
    /// that produce one (`JSON.stringify(.., sort_keys)` for the corpus,
    /// `plain_of`'s `serde_json::Map` on every `state.plain()` round-trip), and
    /// on a side of eleven units that is NOT the capture order. Read back, the
    /// eleventh unit has to be eleventh again — the first assertion here is the
    /// RED half: it states what the document order actually is.
    #[test]
    fn a_key_sorted_units_object_is_read_back_in_capture_order() {
        let mut keys: Vec<String> = (0..11).map(|i| format!("p1_{i}_a")).collect();
        keys.sort();
        assert_eq!(keys[1], "p1_10_a", "sorted document order puts p1_10 second");
        let doc = format!(
            "{{{}}}",
            keys.iter().map(|k| format!("\"{k}\":{{}}")).collect::<Vec<_>>().join(",")
        );
        let mut de = serde_json::Deserializer::from_str(&doc);
        let units = units_in_capture_order(&mut de).expect("plain units");
        let read: Vec<&str> = units.0.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(read[1], "p1_1_a", "capture order puts p1_1 second");
        assert_eq!(read[10], "p1_10_a", "captured LAST — the eleventh unit");
    }

    /// Ten units a side and fewer: the two orders agree, and the read must not
    /// move a single entry — the 1000/1500pt corpora ride on that.
    #[test]
    fn under_ten_units_a_side_the_document_order_is_kept() {
        let mut keys: Vec<String> = (0..9)
            .map(|i| format!("p1_{i}_a"))
            .chain((0..9).map(|i| format!("p2_{i}_b")))
            .collect();
        keys.sort();
        let doc = format!(
            "{{{}}}",
            keys.iter().map(|k| format!("\"{k}\":{{}}")).collect::<Vec<_>>().join(",")
        );
        let mut de = serde_json::Deserializer::from_str(&doc);
        let units = units_in_capture_order(&mut de).expect("plain units");
        let read: Vec<String> = units.0.iter().map(|(k, _)| k.clone()).collect();
        assert_eq!(read, keys);
    }

    /// Red-green for the `los_pairs` mapping: while no side fields eleven
    /// units the KEY-SORTED matrix order IS the capture order, and the mapping
    /// must stay the identity — anything else would move the 1000/1500pt
    /// corpora.
    #[test]
    fn nine_units_a_side_keep_the_identity_mapping() {
        let keys: Vec<String> = (0..9)
            .map(|i| format!("p1_{i}_aaa"))
            .chain((0..9).map(|i| format!("p2_{i}_bbb")))
            .collect();
        assert_eq!(los_positions(&keys), (0..18).collect::<Vec<_>>());
    }

    /// The case the 2000pt lists field: "p2_10_..." sorts BEFORE "p2_1_...", so
    /// the CAPTURE-ordered roster and the KEY-SORTED matrix come apart — the
    /// eleventh p2 unit owns row 3, not the row its roster index names.
    #[test]
    fn a_two_digit_unit_index_moves_the_matrix_rows() {
        // capture order — what `units_in_capture_order` restores
        let keys: Vec<String> = (0..2)
            .map(|i| format!("p1_{i}_aaa"))
            .chain((0..11).map(|i| format!("p2_{i}_bbb")))
            .collect();
        let pos = los_positions(&keys);
        let at = |id: &str| pos[keys.iter().position(|k| k == id).unwrap()];
        assert_eq!(at("p2_10_bbb"), 3, "sorted order puts p2_10 straight after p2_0");
        assert_eq!(at("p2_1_bbb"), 4);
        assert_eq!(at("p2_9_bbb"), 12);
        assert_eq!(at("p1_0_aaa"), 0);
        let mut seen = pos.clone();
        seen.sort();
        assert_eq!(seen, (0..13).collect::<Vec<_>>(), "still a permutation");
    }

    /// An id shape this port did not write keeps the DOCUMENT order, so a
    /// hand-built state degrades to the pre-fix reading instead of guessing.
    #[test]
    fn an_unparsable_id_keeps_the_document_order() {
        let doc = "{\"hero\":{},\"p1_0_aaa\":{}}";
        let mut de = serde_json::Deserializer::from_str(doc);
        let units = units_in_capture_order(&mut de).expect("plain units");
        let read: Vec<&str> = units.0.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(read, vec!["hero", "p1_0_aaa"]);
    }
}
