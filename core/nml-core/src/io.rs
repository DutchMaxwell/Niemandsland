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

use crate::state::{Marker, Mods, Objective, Profile, Profiles, Roster, State};

/// A JSON object read as an ordered `Vec` of entries.
struct Ordered<T>(Vec<(String, T)>);

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
struct PlainUnit {
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
    #[serde(default)]
    los: Option<HashMap<String, bool>>,
}

#[derive(Deserialize)]
struct PlainState {
    round: i64,
    rounds_total: i64,
    #[serde(default)]
    scoring: String,
    #[serde(default)]
    objectives: Vec<Objective>,
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

#[derive(Debug)]
pub struct NodeCorpus {
    pub profiles: Rc<Profiles>,
    pub nodes: Vec<Node>,
}

/// Builds (or reuses) the roster for one plain state. Every node of one game has
/// the same unit keys in the same order, so the roster is interned across nodes.
fn roster_of(
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

fn state_of(plain: PlainState, profiles: &Rc<Profiles>, roster: Rc<Roster>) -> State {
    let n = roster.keys.len();
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
        los: Vec::with_capacity(n),
        los_pairs: plain.los_pairs.as_ref().map(|rows| {
            let mut m = Vec::with_capacity(n * n);
            for r in rows {
                for c in r.chars() {
                    m.push(c == '1');
                }
            }
            Rc::new(m)
        }),
    };
    for (_, u) in plain.units.0 {
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
    }
    st
}

#[derive(Deserialize)]
struct Header {
    profiles: Ordered<Profile>,
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
    Ok(NodeCorpus { profiles, nodes })
}
