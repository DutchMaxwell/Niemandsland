//! NML-1073 M3-6a — the two vectors the LEARNING side of the planner reads off
//! a state: the encoder BOARD ROWS (`BattleSim.board_rows`, battle_sim.gd:
//! 176-249, plus `board_row_indices` :166-173 and `_rule_pairs` :115-160) and
//! the eval's raw FEATURE VECTOR (`AiMissionEval.features`, ai_mission_eval.gd:
//! 480-584).
//!
//! Both are ported expression by expression, in the GDScript's own accumulation
//! order — a feature sum that visits the units in a different order lands a few
//! ULP away, and the row encoder's `snappedf` sits directly on top of an EV.
//!
//! Three precision seams are load-bearing and are reproduced, not approximated:
//!
//! * The row's `x_in`/`z_in` are `snappedf(centre / IN2M, 0.1)` over a
//!   `Vector3` centroid — SINGLE precision, summed and divided as f32, exactly
//!   like `geom::centre` (the engine's `real_t` is 32-bit).
//! * `snappedf(v, step)` is Godot's `floor(v / step + 0.5) * step`, which is
//!   round-HALF-UP, not Rust's round-half-away-from-zero.
//! * `sev`/`mev` value the UNSTAMPED weapon sets. battle_sim.gd:206-209 calls
//!   `AiShooting.profiles_in_range` / `melee_profiles` directly, NOT
//!   `BattleSim._profiles_of`, so the `AiEv.stamp_sergeant` facets and the
//!   unit-level Bane/Rending/Unstoppable scan never reach these two numbers.
//!   `UnitStatic.shoot`/`.melee` are the stamped sets and must not be used here.
//!
//! ONE deliberate reading, called out because the plain state cannot carry it:
//! `board_rows` values a unit against `AiEv.ctx_for(gu)`, whose `models` is the
//! LIVE `GameUnit.get_alive_count()` — not the snapshot's `alive`. The recorder
//! never writes the live count back onto the `GameUnit`, so in every recorded
//! game that number is the unit's full model count, and `Profile.model_count`
//! IS that number. `att.models` reads it here (it only ever moves `mev`, through
//! `impact_ev`/`ravage_ev`).

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::Path;

use serde_json::Value;

use crate::combat::{melee_ev, shoot_ev};
use crate::geom;
use crate::rules::has_special_rule;
use crate::score::{can_hold_marker, control_gap_in, presence, Incoming};
use crate::sim::{melee_threat, reply_threat, CONTACT_IN};
use crate::state::{Profile, State};
use crate::unit::{melee_profiles, profiles_in_range, Ctx, UnitStatic};
use crate::{IN2M, OBJECTIVE_CONTROL_IN};

/// `BattleSim.EV_REF_DIST_IN` battle_sim.gd:75 — the reference distance the
/// row's shooting EV is valued at.
pub const EV_REF_DIST_IN: f64 = 12.0;

/// `BattleSim.FLAG_RULES` battle_sim.gd:76, in order: row slots 14..19.
pub const FLAG_RULES: [&str; 6] =
    ["Fearless", "Ambush", "Flying", "Stealth", "Furious", "Regeneration"];

/// `BattleSim.RULE_VOCAB_PATH` battle_sim.gd:77, relative to the repo root.
pub const RULE_VOCAB_PATH: &str = "data/encoder_rule_vocab_v1.json";

/// NML-1134 — the vocabulary version THIS build reads, `BattleSim.
/// RULE_VOCAB_VERSION` battle_sim.gd:131. The file is SHARED by the table and
/// this crate, so a build that reads a version it was not written for refuses
/// to slot anything at all rather than move every board row in silence.
pub const RULE_VOCAB_VERSION: i64 = 4;

/// NML-1134 — the version a corpus was recorded under when its act header
/// carries no `rule_vocab_version` at all. Every corpus cut before the stamp
/// (m3_ref_v2/v3/v4, m3_oracle/_v2/_v3/_v4, m4_corpus_v2, qa_ref, qb*_ref,
/// golden_planner*) is one of those, and every one of them is version 2.
pub const LEGACY_VOCAB_VERSION: i64 = 2;

/// `AiEv.NEUTRAL_DEFENDER` ai_ev.gd:37 — `{"defense": 4, "tough": 1,
/// "models": 5}`. Every other key is absent, and GDScript's `.get(k, default)`
/// then answers the reader's own fallback, which is what `Ctx::default()` is.
pub fn neutral_defender() -> Ctx {
    Ctx { defense: 4, tough: 1, models: 5, ..Ctx::default() }
}

/// `Math::snapped` (core/math/math_funcs.h) — round HALF UP onto the step grid.
#[inline]
pub fn snappedf(value: f64, step: f64) -> f64 {
    if step != 0.0 {
        (value / step + 0.5).floor() * step
    } else {
        value
    }
}

/// One board-row entry. GDScript builds the row as an untyped `Array`, and
/// `JSON.stringify` then writes an int without a decimal point and a float with
/// one — the distinction survives into the corpus, so it survives here.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Cell {
    I(i64),
    F(f64),
}

impl Cell {
    pub fn as_f64(self) -> f64 {
        match self {
            Cell::I(v) => v as f64,
            Cell::F(v) => v,
        }
    }
    pub fn is_int(self) -> bool {
        matches!(self, Cell::I(_))
    }
}

/// The committed append-only rule vocabulary — `BattleSim._load_vocab`
/// battle_sim.gd:86-102. Unit slots 0-199, weapon 200+, spell 300+.
#[derive(Debug, Default)]
pub struct RowVocab {
    /// False when the file was unreadable OR carried a version this build does
    /// not read — `push_error` on the GDScript side, and every rule then
    /// collects as unknown instead of landing on a slot the two sides disagree
    /// about. `error` says which of the two it was.
    pub loaded: bool,
    /// The version this instance READS: `RULE_VOCAB_VERSION` for a fresh game,
    /// an older one when a corpus header asked for it (see `for_version`).
    pub version: i64,
    /// The loud half of `loaded == false`.
    pub error: Option<String>,
    unit: HashMap<String, i64>,
    weapon: HashMap<String, i64>,
    spell: HashMap<String, i64>,
}

impl RowVocab {
    /// The committed vocabulary at THIS build's version — what a fresh game and
    /// a freshly recorded corpus use.
    pub fn load(repo_root: &str) -> RowVocab {
        RowVocab::for_version(repo_root, RULE_VOCAB_VERSION)
    }

    /// NML-1134 — the committed vocabulary AS OF `want`. The file is
    /// APPEND-ONLY, so every older version is a PREFIX of the committed one and
    /// the older reading is exactly "truncate each list to the length it had
    /// then" (`legacy_lengths` in the file itself, so the two loaders share one
    /// source). A name past the cut is not in the map and therefore collects
    /// LOUDLY into `unknown`, which is what the corpus recorded at the time.
    pub fn for_version(repo_root: &str, want: i64) -> RowVocab {
        let path = Path::new(repo_root).join(RULE_VOCAB_PATH);
        let Some(text) = std::fs::read_to_string(&path).ok() else {
            return RowVocab::broken(want, format!("rule vocab unreadable at {}", path.display()));
        };
        match serde_json::from_str::<Value>(&text) {
            Ok(v) => RowVocab::from_value(&v, want),
            Err(e) => RowVocab::broken(want, format!("rule vocab unparsable at {}: {e}", path.display())),
        }
    }

    /// The reading itself, split off the file so a test can hand it a
    /// vocabulary that is NOT the committed one.
    pub fn from_value(v: &Value, want: i64) -> RowVocab {
        if !v.is_object() {
            return RowVocab::broken(want, "rule vocab is not an object".into());
        }
        let have = v.get("version").and_then(|x| x.as_i64()).unwrap_or(0);
        if have != RULE_VOCAB_VERSION {
            return RowVocab::broken(
                want,
                format!("rule vocab version {have}, this build reads {RULE_VOCAB_VERSION}"),
            );
        }
        // How long each list was at `want`. The committed version is the whole
        // file; an older one is a documented prefix, and a version the file does
        // not describe is an error, never a guess.
        let cut: Option<HashMap<String, usize>> = if want == RULE_VOCAB_VERSION {
            None
        } else {
            let by_version = v.get("legacy_lengths").and_then(|x| x.as_object());
            let entry = by_version.and_then(|m| m.get(&want.to_string())).and_then(|x| x.as_object());
            match entry {
                Some(e) => Some(
                    e.iter()
                        .filter_map(|(k, x)| x.as_u64().map(|n| (k.clone(), n as usize)))
                        .collect(),
                ),
                None => {
                    return RowVocab::broken(
                        want,
                        format!("rule vocab has no legacy_lengths for version {want}"),
                    )
                }
            }
        };
        let list = |key: &str, base: i64| -> HashMap<String, i64> {
            let mut m = HashMap::new();
            if let Some(a) = v.get(key).and_then(|x| x.as_array()) {
                let n = match &cut {
                    Some(c) => c.get(key).copied().unwrap_or(a.len()).min(a.len()),
                    None => a.len(),
                };
                for (i, e) in a.iter().take(n).enumerate() {
                    // `str(ul[i])` — the committed lists are plain strings.
                    let name = match e {
                        Value::String(s) => s.clone(),
                        other => other.to_string(),
                    };
                    // A duplicate name keeps the LAST index, like the GDScript
                    // dictionary assignment does.
                    m.insert(name, base + i as i64);
                }
            }
            m
        };
        RowVocab {
            loaded: true,
            version: want,
            error: None,
            unit: list("unit", 0),
            weapon: list("weapon", 200),
            spell: list("spell", 300),
        }
    }

    fn broken(want: i64, why: String) -> RowVocab {
        RowVocab { loaded: false, version: want, error: Some(why), ..RowVocab::default() }
    }
}

/// `BattleSim._parse_rule` battle_sim.gd:105-112 — `"Tough(3)"` -> `("Tough", 3)`.
///
/// The GDScript regex is `^(.*?)\s*\((\d+)\)\s*$` over the TRIMMED text: the
/// rating must be plain digits (so `"Deadly(+3)"` does NOT parse and keeps its
/// whole text as the name), and because the match is anchored at both ends the
/// only candidate opening bracket is the one closed by the final `)`.
pub fn parse_rule(raw: &str) -> (String, i64) {
    let s = raw.trim();
    if s.ends_with(')') {
        if let Some(open) = s.rfind('(') {
            let inner = &s[open + 1..s.len() - 1];
            if !inner.is_empty() && inner.chars().all(|c| c.is_ascii_digit()) {
                if let Ok(n) = inner.parse::<i64>() {
                    return (s[..open].trim_end().to_string(), n);
                }
            }
        }
    }
    (s.to_string(), 0)
}

/// `BattleSim.board_row_indices` battle_sim.gd:166-173 — for each LIVING unit,
/// in the same filter and order as `board_rows`, its index in capture order.
pub fn board_row_indices(state: &State) -> Vec<i64> {
    (0..state.units())
        .filter(|&i| state.alive[i] > 0)
        .map(|i| i as i64)
        .collect()
}

/// The row encoder: the vocabulary plus the loud `unknown_rules` collector
/// (`BattleSim.unknown_rules` battle_sim.gd:82 — a name that is not in the
/// committed vocabulary is REPORTED, never silently slotted).
#[derive(Debug)]
pub struct RowEncoder {
    pub vocab: RowVocab,
    /// Every rule/spell name the vocabulary does not carry, `"spell:"`-prefixed
    /// for a spell exactly like the GDScript key.
    pub unknown: BTreeSet<String>,
    /// LEGACY REPLAY ONLY — a fixed reading for columns 10 and 11. `None` (the
    /// default, and the only setting a fresh corpus may use) reads the unit's
    /// own `quality`/`defense`, which is what `gu.source_data` carries since the
    /// harness fill (#392). A corpus recorded before that fix reads the blank
    /// `OPRApiClient.OPRUnit` defaults (4/4) in every row; `Some((4, 4))`
    /// reproduces it.
    pub source_qd: Option<(i64, i64)>,
}

impl RowEncoder {
    pub fn new(repo_root: &str) -> RowEncoder {
        RowEncoder::for_version(repo_root, RULE_VOCAB_VERSION)
    }

    /// NML-1134 — an encoder that slots the way the vocabulary did at `want`.
    /// A REPLAY of a corpus recorded under an older vocabulary uses this;
    /// nothing that plays a fresh game may.
    pub fn for_version(repo_root: &str, want: i64) -> RowEncoder {
        RowEncoder {
            vocab: RowVocab::for_version(repo_root, want),
            unknown: BTreeSet::new(),
            source_qd: None,
        }
    }

    /// Swap the vocabulary reading (keeping everything already collected in
    /// `unknown`) — a no-op when it is already the wanted one.
    pub fn set_vocab_version(&mut self, repo_root: &str, want: i64) {
        if self.vocab.version != want || !self.vocab.loaded {
            self.vocab = RowVocab::for_version(repo_root, want);
        }
    }

    /// `BattleSim._rule_pairs` battle_sim.gd:115-160 — the flat
    /// `[slot, value, slot, value, ...]` tail of a unit row, slots ascending.
    pub fn rule_pairs(&mut self, p: &Profile, us: &UnitStatic) -> Vec<i64> {
        let mut vals: BTreeMap<i64, i64> = BTreeMap::new();
        // Unit rules: an unrated rule counts as 1.
        for r in &p.special_rules {
            let (name, rating) = parse_rule(r);
            if name.is_empty() {
                continue;
            }
            match self.vocab.unit.get(&name) {
                Some(&slot) => {
                    let v = if rating > 0 { rating } else { 1 };
                    let e = vals.entry(slot).or_insert(0);
                    *e = (*e).max(v);
                }
                None => {
                    self.unknown.insert(name);
                }
            }
        }
        // Weapon rules, over EVERY weapon of the unit (melee and Strafing too —
        // this loop is `for w in od.weapons`, not a profile set).
        for w in &p.weapons {
            for r in &w.rules {
                let (name, rating) = parse_rule(r);
                if name.is_empty() {
                    continue;
                }
                match self.vocab.weapon.get(&name) {
                    Some(&slot) => {
                        let e = vals.entry(slot).or_insert(0);
                        *e = (*e).max(rating.max(1));
                    }
                    None => {
                        self.unknown.insert(name);
                    }
                }
            }
        }
        // v1c: a caster's whole SPELL BOOK, (slot 300+, threshold).
        if us.is_caster {
            for sp in &us.spells {
                let name = sp.name.trim();
                if name.is_empty() {
                    continue;
                }
                match self.vocab.spell.get(name) {
                    Some(&slot) => {
                        let e = vals.entry(slot).or_insert(0);
                        *e = (*e).max(sp.threshold.max(1));
                    }
                    None => {
                        self.unknown.insert(format!("spell:{name}"));
                    }
                }
            }
        }
        vals.into_iter().flat_map(|(k, v)| [k, v]).collect()
    }

    /// `BattleSim.board_rows` battle_sim.gd:176-249 — the v5 encoder input:
    /// one row per LIVING unit in capture order, then one per objective, then
    /// the single game-state row.
    ///
    /// `statics` is the closure of THIS state's profile table (the same one
    /// `score`/`resolve` take), used for `AiEv.ctx_for` and the caster's spell
    /// book; every weapon number comes off the profile itself.
    pub fn board_rows(&mut self, state: &State, statics: &[UnitStatic]) -> Vec<Vec<Cell>> {
        let mut rows: Vec<Vec<Cell>> = Vec::new();
        let def = neutral_defender();
        for i in 0..state.units() {
            if state.alive[i] <= 0 {
                continue;
            }
            let c = geom::centre(&state.positions[i]);
            let wl: i64 = state.wounds[i].iter().sum();
            let p = state.profile(i);
            let us = &statics[state.roster.profile[i]];
            // `gu.source_data is OPRApiClient.OPRUnit` (battle_sim.gd:195): every
            // recorded game is an OPR game, and the plain profile carries no
            // source flag to tell a non-OPR unit apart — see the module note.
            let mut rmax = 0i64;
            let mut atk = 0i64;
            for w in &p.weapons {
                rmax = rmax.max(w.range as i64);
                atk += w.attacks * w.count.max(1);
            }
            let mut att = us.ctx;
            att.models = p.model_count.max(1);
            let shoot = profiles_in_range(&p.weapons, EV_REF_DIST_IN);
            let keep: Vec<usize> = (0..shoot.len()).collect();
            let s_attacks: Vec<i64> = shoot.iter().map(|s| s.attacks).collect();
            let sev = snappedf(
                shoot_ev(&shoot, &keep, &s_attacks, &att, &def, EV_REF_DIST_IN),
                0.01,
            );
            let mel = melee_profiles(&p.weapons);
            let m_attacks: Vec<i64> = mel.iter().map(|s| s.attacks).collect();
            let mev = snappedf(melee_ev(&mel, &m_attacks, &att, &def, true), 0.01);
            let pairs = self.rule_pairs(p, us);
            let mut row = vec![
                Cell::I(state.player[i]),
                Cell::F(snappedf(c[0] as f64 / IN2M, 0.1)),
                Cell::F(snappedf(c[2] as f64 / IN2M, 0.1)),
                Cell::I(state.alive[i]),
                Cell::I(wl),
                Cell::I(state.shaken[i] as i64),
                Cell::I(state.fatigued[i] as i64),
                Cell::I(state.activated[i] as i64),
                Cell::I(rmax),
                Cell::I(atk),
                Cell::I(self.source_qd.map_or(p.quality, |(q, _)| q)),
                Cell::I(self.source_qd.map_or(p.defense, |(_, d)| d)),
                Cell::F(sev),
                Cell::F(mev),
            ];
            for r in FLAG_RULES {
                row.push(Cell::I(has_special_rule(&p.special_rules, r) as i64));
            }
            row.push(Cell::I(pairs.len() as i64 / 2));
            row.extend(pairs.into_iter().map(Cell::I));
            rows.push(row);
        }
        for o in &state.objectives {
            let mut row = vec![
                Cell::I(3),
                Cell::F(snappedf(o.pos[0] / IN2M, 0.1)),
                Cell::F(snappedf(o.pos[2] / IN2M, 0.1)),
                Cell::I(o.owner),
            ];
            row.extend(std::iter::repeat(Cell::I(0)).take(17));
            rows.push(row);
        }
        // NML-1012 input v1 — the GAME-STATE row (type 4).
        let fl = state.vp_flavour.as_deref();
        let sc_code = match &*state.scoring {
            "round_vp" => 1,
            "sabotage" => 2,
            _ => 0,
        };
        let mj = fl
            .and_then(|v| v.get("majority"))
            .and_then(|v| v.as_str())
            .unwrap_or("end");
        let mj_code = if mj == "none" {
            0
        } else if mj == "end" {
            1
        } else {
            2
        };
        let first_seize = fl
            .and_then(|v| v.get("first_seize"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        // `state.get("vp", [0, 0])`, then a size-2 guard: an absent ledger and a
        // malformed one both read 0/0.
        let (vp0, vp1) = match state.vp.as_deref().and_then(|v| v.as_array()) {
            Some(a) if a.len() == 2 => {
                (a[0].as_i64().unwrap_or(0), a[1].as_i64().unwrap_or(0))
            }
            _ => (0, 0),
        };
        let mut row = vec![
            Cell::I(4),
            Cell::I(state.round),
            Cell::I(state.rounds_total),
            Cell::I(vp0),
            Cell::I(vp1),
            Cell::I(sc_code),
            Cell::I(mj_code),
            Cell::I(first_seize as i64),
        ];
        row.extend(std::iter::repeat(Cell::I(0)).take(13));
        rows.push(row);
        rows
    }
}

// ------------------------------------------------------------- features ---

/// `AiMissionEval.features` ai_mission_eval.gd:481-509 — the key order the
/// GDScript dictionary is BUILT in, which is the order it iterates in.
pub const FEATURE_KEYS: [&str; 30] = [
    "round_frac",
    "my_wounds",
    "their_wounds",
    "my_units",
    "their_units",
    "my_unactivated",
    "their_unactivated",
    "my_incoming",
    "presence_mine",
    "presence_theirs",
    "tail_mine",
    "tail_theirs",
    "obj_owned_mine",
    "obj_owned_theirs",
    "cover_mine",
    "cover_theirs",
    "my_charge_exposed",
    "their_charge_exposed",
    "my_incoming_max",
    "their_incoming",
    "my_melee_in",
    "their_melee_in",
    "my_near_half",
    "their_near_half",
    "my_shaken",
    "their_shaken",
    "my_fatigued",
    "their_fatigued",
    "my_reserve",
    "their_reserve",
];

// Slot constants, in FEATURE_KEYS order.
const ROUND_FRAC: usize = 0;
const MY_WOUNDS: usize = 1;
const MY_UNITS: usize = 3;
const MY_UNACTIVATED: usize = 5;
const MY_INCOMING: usize = 7;
const PRESENCE_MINE: usize = 8;
const TAIL_MINE: usize = 10;
const OBJ_OWNED_MINE: usize = 12;
const OBJ_OWNED_THEIRS: usize = 13;
const COVER_MINE: usize = 14;
const MY_CHARGE_EXPOSED: usize = 16;
const MY_INCOMING_MAX: usize = 18;
const THEIR_INCOMING: usize = 19;
const MY_MELEE_IN: usize = 20;
const MY_NEAR_HALF: usize = 22;
const MY_SHAKEN: usize = 24;
const MY_FATIGUED: usize = 26;
const MY_RESERVE: usize = 28;
const THEIR_RESERVE: usize = 29;

/// `state.get("reserves", {})` is absent on every state this port can be handed:
/// `BattleSim.capture` never writes it, `clone_state` drops it and
/// `state_to_plain` does not carry it — only `SoloController._with_reserves`
/// (:3317) stamps it, at the two in-game logging sites. Pass the counts there,
/// `NO_RESERVES` everywhere else.
pub const NO_RESERVES: (f64, f64) = (0.0, 0.0);

/// `AiMissionEval.features` ai_mission_eval.gd:480-584, as a vector in
/// `FEATURE_KEYS` order.
///
/// `incoming` is `BattleSim.reply_threat(state, player)` indexed by capture
/// order (`score::Incoming`); `rich` is the feature-wave gate — true at the two
/// LOGGING sites (which is what the trainer corpus records), false in the eval
/// hot path, where it buys the mirror `their_incoming` and the melee magnitudes.
pub fn features(
    state: &State,
    statics: &[UnitStatic],
    player: i64,
    incoming: Incoming,
    rich: bool,
    reserves: (f64, f64),
) -> Vec<f64> {
    let mut f = [0.0f64; FEATURE_KEYS.len()];
    f[ROUND_FRAC] = state.round as f64 / (state.rounds_total as f64).max(1.0);
    f[MY_RESERVE] = reserves.0;
    f[THEIR_RESERVE] = reserves.1;
    // `for v in incoming.values()` — the Rust vector carries an explicit 0.0
    // where the GDScript dictionary carries no key, which changes neither the
    // sum nor the max.
    for v in incoming {
        f[MY_INCOMING] += *v;
        f[MY_INCOMING_MAX] = f[MY_INCOMING_MAX].max(*v);
    }
    if rich {
        for v in reply_threat(statics, state, 3 - player) {
            f[THEIR_INCOMING] += v;
        }
    }
    // `mine` picks the first of each pair, `theirs` the second — every pair is
    // adjacent in FEATURE_KEYS, so the offset IS the side.
    let side = |slot: usize, mine: bool| -> usize { if mine { slot } else { slot + 1 } };
    for i in 0..state.units() {
        if state.alive[i] <= 0 {
            continue;
        }
        let mine = state.player[i] == player;
        let mut wounds = 0.0f64;
        for w in &state.wounds[i] {
            wounds += *w as f64;
        }
        f[side(MY_WOUNDS, mine)] += wounds;
        f[side(MY_UNITS, mine)] += 1.0;
        if !state.activated[i] {
            f[side(MY_UNACTIVATED, mine)] += 1.0;
        }
        if state.in_cover[i] {
            f[side(COVER_MINE, mine)] += 1.0;
        }
        if state.shaken[i] {
            f[side(MY_SHAKEN, mine)] += 1.0;
        }
        if state.fatigued[i] {
            f[side(MY_FATIGUED, mine)] += 1.0;
        }
        // Morale proximity: `for m in (su["unit"] as GameUnit).models` — the
        // FULL model list, which is what `Profile.wounds_max` carries.
        let mut wounds_max = 0.0f64;
        for w in &statics[state.roster.profile[i]].wounds_max {
            wounds_max += *w as f64;
        }
        if wounds_max > 0.0 && wounds > wounds_max * 0.5 && wounds <= wounds_max * 0.7 {
            f[side(MY_NEAR_HALF, mine)] += 1.0;
        }
        // Charge exposure, and (rich) the worst single charger's melee damage.
        let mut exposed = false;
        let mut worst_melee = 0.0f64;
        for j in 0..state.units() {
            if state.player[j] == state.player[i] || state.alive[j] <= 0 {
                continue;
            }
            let oreach = state.bands[j].rush + CONTACT_IN;
            if geom::dist_in(&state.positions[i], &state.positions[j]) <= oreach {
                exposed = true;
                if rich {
                    worst_melee = worst_melee.max(melee_threat(statics, state, j, i));
                } else {
                    break; // pre-wave behaviour: the binary flag is enough
                }
            }
        }
        if exposed {
            f[side(MY_CHARGE_EXPOSED, mine)] += 1.0;
            f[side(MY_MELEE_IN, mine)] += worst_melee;
        }
        let rush = state.bands[i].rush;
        let eligible = can_hold_marker(state, i, state.round);
        let threat = incoming.get(i).copied().unwrap_or(0.0);
        for o in &state.objectives {
            f[side(PRESENCE_MINE, mine)] += presence(state, i, o.pos, threat);
            if eligible
                && !state.activated[i]
                && control_gap_in(state, i, o.pos) <= OBJECTIVE_CONTROL_IN + rush
            {
                f[side(TAIL_MINE, mine)] += 1.0;
            }
        }
    }
    for o in &state.objectives {
        if o.owner == player {
            f[OBJ_OWNED_MINE] += 1.0;
        } else if o.owner != 0 {
            f[OBJ_OWNED_THEIRS] += 1.0;
        }
    }
    f.to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::acts::read_act_header;
    use crate::io::state_from_json;
    use crate::rules::Registries;
    use crate::state::ProfileCache;

    /// The checkout this crate lives in — the mechanics assets and the row
    /// vocabulary are read from there, exactly as the binaries read them.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":3,
        "wounds_max":[3,3],"model_count":2,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Fearless","Tough(3)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[
          {"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":5,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Stealth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Pistol","range":6,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Two units on opposite sides plus one objective. Unit A sits at x = 10",
    /// B at x = -10"; the marker is on the centre line. Distances are written in
    /// metres, the way the snapshot carries them.
    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end",
      "objectives":[{"pos":[0.0,0.0,0.0],"owner":1}],
      "units":{
        "p1_0_a":{"player":1,"alive":2,"wounds":[3,2],"radii":[0.016,0.016],
          "positions":[[0.254,0.0,0.0],[0.2794,0.0,0.0]],
          "in_cover":false,"shaken":false,"fatigued":false,"activated":false,
          "casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
          "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
          "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
        "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
          "positions":[[-0.254,0.0,0.0]],
          "in_cover":true,"shaken":false,"fatigued":false,"activated":true,
          "casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
          "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
          "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn two_unit_state() -> (crate::State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let state = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let mut reg = Registries::new(&repo_root());
        let statics =
            state.profiles.list.iter().map(|p| UnitStatic::build(&mut reg, p)).collect();
        (state, statics)
    }

    /// The same state with one extra unit rule on side 1 — the lever the
    /// vocabulary version pulls.
    fn state_with(rule: &str) -> (crate::State, Vec<UnitStatic>) {
        let header = read_act_header(&HEADER.replace(
            r#""special_rules":["Fearless","Tough(3)"]"#,
            &format!(r#""special_rules":["Fearless","Tough(3)","{rule}"]"#),
        ))
        .expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let state = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let mut reg = Registries::new(&repo_root());
        let statics =
            state.profiles.list.iter().map(|p| UnitStatic::build(&mut reg, p)).collect();
        (state, statics)
    }

    /// NML-1134 RED-GREEN — the vocabulary version is LOAD-BEARING on the board
    /// rows themselves, which is why the bump and the oracle re-record had to
    /// land together. One appended name (`Warden`, unit slot 137) on one unit:
    /// under the shipped vocabulary the row grows by one `(slot, value)` pair
    /// and nothing is collected; under the version-2 reading the row keeps its
    /// old LENGTH and the name is collected loudly, exactly as the corpora
    /// recorded before the bump have it.
    #[test]
    fn the_vocabulary_version_decides_the_row_length_and_the_unknown_set() {
        let (state, statics) = state_with("Warden");
        let plain = {
            let mut enc = RowEncoder::new(&repo_root());
            let rows = enc.board_rows(&state, &statics);
            (rows[0].len(), rows[0][20], enc.unknown.clone())
        };
        let legacy = {
            let mut enc = RowEncoder::for_version(&repo_root(), LEGACY_VOCAB_VERSION);
            let rows = enc.board_rows(&state, &statics);
            (rows[0].len(), rows[0][20], enc.unknown.clone())
        };
        // GREEN: the shipped vocabulary slots it — four pairs, no unknown.
        assert_eq!(plain.1, Cell::I(4), "Fearless, Tough(3), Warden and the rifle's AP(1)");
        assert!(plain.2.is_empty(), "{:?}", plain.2);
        // RED: the version-2 reading does not have the name at all.
        assert_eq!(legacy.1, Cell::I(3), "the same row without Warden's pair");
        assert_eq!(legacy.0 + 2, plain.0, "one pair is two cells of row LENGTH");
        assert_eq!(legacy.2.iter().cloned().collect::<Vec<_>>(), vec!["Warden".to_string()]);
    }

    fn f(vals: &[f64], key: &str) -> f64 {
        vals[FEATURE_KEYS.iter().position(|k| *k == key).expect(key)]
    }

    #[test]
    fn board_rows_of_a_hand_built_two_unit_state() {
        let (state, statics) = two_unit_state();
        let mut enc = RowEncoder::new(&repo_root());
        assert!(enc.vocab.loaded, "the committed rule vocabulary must be readable");
        let rows = enc.board_rows(&state, &statics);
        // Two living units, one objective, one game-state row.
        assert_eq!(rows.len(), 4);
        assert_eq!(board_row_indices(&state), vec![0, 1]);

        let a = &rows[0];
        assert_eq!(a[0], Cell::I(1), "player");
        // Centroid of 0.254 m and 0.2794 m is 0.2667 m = 10.5", snapped to 0.1.
        assert_eq!(a[1], Cell::F(10.5), "x_in");
        assert_eq!(a[2], Cell::F(0.0), "z_in");
        assert_eq!(a[3], Cell::I(2), "alive");
        assert_eq!(a[4], Cell::I(5), "wounds left, 3 + 2");
        assert_eq!(a[5], Cell::I(0), "shaken");
        assert_eq!(a[6], Cell::I(0), "fatigued");
        assert_eq!(a[7], Cell::I(0), "activated");
        assert_eq!(a[8], Cell::I(24), "range_max over ALL weapons, melee included");
        assert_eq!(a[9], Cell::I(4), "attacks 2 + 2, each x count 1");
        assert_eq!(a[10], Cell::I(4), "quality");
        assert_eq!(a[11], Cell::I(3), "defense");
        assert!(a[12].as_f64() > 0.0, "the 24\" rifle reaches the 12\" reference");
        assert!(a[13].as_f64() > 0.0, "the blade strikes");
        assert_eq!(a[14], Cell::I(1), "Fearless");
        assert_eq!(&a[15..20], &[Cell::I(0); 5], "the other five flag rules");
        // Fearless (unit slot 27), Tough(3) (114) and the rifle's AP(1) (200).
        assert_eq!(a[20], Cell::I(3), "three rule pairs");
        assert_eq!(a.len(), 21 + 6);
        assert_eq!(
            &a[21..],
            &[
                Cell::I(27),
                Cell::I(1),
                Cell::I(114),
                Cell::I(3),
                Cell::I(200),
                Cell::I(1)
            ],
            "slots ascending, unrated rules valued 1"
        );

        let b = &rows[1];
        assert_eq!(b[0], Cell::I(2));
        assert_eq!(b[1], Cell::F(-10.0), "x_in");
        assert_eq!(b[7], Cell::I(1), "activated");
        assert_eq!(b[12], Cell::F(0.0), "a 6\" pistol does not reach 12\"");
        assert_eq!(b[13], Cell::F(0.0), "no melee weapon, no Impact, no Ravage");
        assert_eq!(b[17], Cell::I(1), "Stealth");

        // The objective row and the game-state row are both 21 long.
        assert_eq!(rows[2][0], Cell::I(3));
        assert_eq!(rows[2][1], Cell::F(0.0));
        assert_eq!(rows[2][3], Cell::I(1), "owner");
        assert_eq!(rows[2].len(), 21);
        assert_eq!(&rows[2][4..], &[Cell::I(0); 17]);
        let g = &rows[3];
        assert_eq!(
            &g[..8],
            &[
                Cell::I(4),
                Cell::I(2),
                Cell::I(4),
                Cell::I(0),
                Cell::I(0),
                Cell::I(0),
                Cell::I(1),
                Cell::I(0)
            ],
            "type, round, rounds_total, vp 0/0, scoring 'end', majority 'end', no first-seize"
        );
        assert_eq!(g.len(), 21);
    }

    #[test]
    fn features_of_a_hand_built_two_unit_state() {
        let (state, statics) = two_unit_state();
        let v = features(&state, &statics, 1, crate::NO_INCOMING, false, NO_RESERVES);
        assert_eq!(v.len(), FEATURE_KEYS.len());
        assert_eq!(f(&v, "round_frac"), 0.5, "round 2 of 4");
        assert_eq!(f(&v, "my_units"), 1.0);
        assert_eq!(f(&v, "their_units"), 1.0);
        assert_eq!(f(&v, "my_wounds"), 5.0);
        assert_eq!(f(&v, "their_wounds"), 1.0);
        assert_eq!(f(&v, "my_unactivated"), 1.0);
        assert_eq!(f(&v, "their_unactivated"), 0.0, "B has already acted");
        assert_eq!(f(&v, "cover_mine"), 0.0);
        assert_eq!(f(&v, "cover_theirs"), 1.0);
        assert_eq!(f(&v, "obj_owned_mine"), 1.0);
        assert_eq!(f(&v, "obj_owned_theirs"), 0.0);
        // 10.5" and 10" from the marker, both inside 3" + a 12" rush.
        assert_eq!(f(&v, "tail_mine"), 1.0);
        assert_eq!(f(&v, "tail_theirs"), 0.0, "an ACTIVATED unit is no tail");
        // 20.5" apart: neither can be charged from a 12" rush + 1" contact.
        assert_eq!(f(&v, "my_charge_exposed"), 0.0);
        assert_eq!(f(&v, "their_charge_exposed"), 0.0);
        assert_eq!(f(&v, "my_incoming"), 0.0, "NO_INCOMING is the empty-dict default");
        assert_eq!(f(&v, "their_incoming"), 0.0, "rich is off");
        assert!(f(&v, "presence_mine") > 0.0 && f(&v, "presence_theirs") > 0.0);
        // The mirror is the same state from the other seat.
        let w = features(&state, &statics, 2, crate::NO_INCOMING, false, NO_RESERVES);
        assert_eq!(f(&w, "my_units"), 1.0);
        assert_eq!(f(&w, "obj_owned_theirs"), 1.0);
        assert_eq!(f(&w, "presence_mine"), f(&v, "presence_theirs"));
    }

    #[test]
    fn snapped_rounds_half_up_like_godot() {
        // The multiply back onto the grid is not exact in binary (-204 * 0.1 is
        // -20.400000000000002), and `JSON.stringify` then prints Godot's own
        // identical result at 14 significant digits — which is why the row's
        // float columns are compared at 1e-9 and never bitwise.
        let near = |a: f64, b: f64| assert!((a - b).abs() < 1e-9, "{a} vs {b}");
        near(snappedf(0.784999, 0.01), 0.78);
        near(snappedf(2.925, 0.01), 2.93);
        // Round HALF UP, not away from zero: -20.35 lands on -20.3, not -20.4.
        near(snappedf(-20.35, 0.1), -20.3);
        near(snappedf(-20.36, 0.1), -20.4);
        assert_eq!(snappedf(1.0, 0.0), 1.0, "a zero step is the identity");
    }

    /// NML-1134 — the committed file is the version this build reads, it carries
    /// the 11 item-granted names at slots 128-138, and every one of them is a
    /// name the pre-NML-1105 loader never granted.
    #[test]
    fn the_committed_vocabulary_is_this_builds_version() {
        let v = RowVocab::load(&repo_root());
        assert!(v.loaded, "{:?}", v.error);
        assert_eq!(v.version, RULE_VOCAB_VERSION);
        for (slot, name) in [
            (128, "Adrenaline Fueled"),
            (129, "Combat Bio-Engineer"),
            (130, "Combat Mutations"),
            (131, "Courage"),
            (132, "Flagellant"),
            (133, "For the Hive!"),
            (134, "Paradox Shielding Device"),
            (135, "Toxic Cysts"),
            (136, "Versatile Reach"),
            (137, "Warden"),
            (138, "Winged Breed"),
        ] {
            assert_eq!(v.unit.get(name), Some(&slot), "unit slot of {name}");
        }
    }

    /// NML-1144b — the v4 append: the 61 names gen0's corpus collected as
    /// unknown sit at unit slots 139-199, each exactly once, and none of them
    /// was already listed in another band (the file has never carried one name
    /// in two lists — "Lust Boon" lives in the spell list and was skipped).
    #[test]
    fn every_appended_v4_name_sits_at_its_slot() {
        let v = RowVocab::load(&repo_root());
        assert!(v.loaded, "{:?}", v.error);
        assert_eq!(v.unit.len(), 200, "unit band 0-199 is exactly full");
        assert_eq!(v.weapon.len(), 22, "no weapon name appended");
        assert_eq!(v.spell.len(), 463, "no spell name appended");
        assert_eq!(v.unit.get("Army Standard Bearer"), Some(&139));
        assert_eq!(v.unit.get("Trekker Tires"), Some(&199));
        let mut slots: Vec<_> = v.unit.values().copied().collect();
        slots.sort_unstable();
        slots.dedup();
        assert_eq!(slots.len(), v.unit.len(), "no name shares a slot");
    }

    /// NML-1144b — the LEGACY reading: a corpus recorded under version 3
    /// replays with the vocabulary as it was then. The file is append-only, so
    /// that is the same map minus the 61 appended names, which then collect as
    /// unknown exactly as they did in the recording.
    #[test]
    fn the_legacy_reading_is_the_vocabulary_as_of_version_3() {
        let now = RowVocab::load(&repo_root());
        let old = RowVocab::for_version(&repo_root(), 3);
        assert!(old.loaded, "{:?}", old.error);
        assert_eq!(old.version, 3);
        assert_eq!(old.unit.len() + 61, now.unit.len(), "61 unit names appended");
        assert_eq!(old.weapon.len(), now.weapon.len(), "no weapon name appended");
        assert_eq!(old.spell.len(), now.spell.len(), "no spell name appended");
        assert_eq!(old.unit.get("Trekker Tires"), None, "appended after version 3");
        assert_eq!(now.unit.get("Trekker Tires"), Some(&199));
        // Everything the old reading DOES carry sits on the same slot as now —
        // that is what append-only means, and a gate replaying a v2 corpus
        // depends on it.
        for (name, slot) in &old.unit {
            assert_eq!(now.unit.get(name), Some(slot), "slot of {name} moved");
        }
    }

    /// NML-1134 RED — a vocabulary file whose version is not this build's is
    /// REFUSED, loudly, and fills nothing. Without this the two loaders would
    /// slot the same rule differently and every board row would move in silence.
    #[test]
    fn a_vocabulary_of_the_wrong_version_is_refused() {
        let wrong = serde_json::json!({
            "version": RULE_VOCAB_VERSION + 1,
            "unit": ["Fearless"], "weapon": [], "spell": [],
        });
        let v = RowVocab::from_value(&wrong, RULE_VOCAB_VERSION);
        assert!(!v.loaded, "a version this build does not read must not load");
        assert!(v.unit.is_empty(), "and it must fill nothing");
        let err = v.error.expect("a loud error");
        assert!(err.contains(&format!("version {}", RULE_VOCAB_VERSION + 1)), "{err}");
        assert!(err.contains(&format!("reads {RULE_VOCAB_VERSION}")), "{err}");

        // GREEN counterpart on the same shape: the right version does load.
        let right = serde_json::json!({
            "version": RULE_VOCAB_VERSION,
            "unit": ["Fearless"], "weapon": [], "spell": [],
        });
        let ok = RowVocab::from_value(&right, RULE_VOCAB_VERSION);
        assert!(ok.loaded && ok.unit.get("Fearless") == Some(&0));

        // And a legacy version the file does not describe is an error too,
        // never a guess at where the older list ended.
        let no_lengths = RowVocab::from_value(&right, LEGACY_VOCAB_VERSION);
        assert!(!no_lengths.loaded);
        assert!(no_lengths.error.unwrap().contains("legacy_lengths"));
    }

    /// NML-1134 — the ONE rule that decides which vocabulary a corpus replays
    /// under, read off its own act header.
    #[test]
    fn a_header_says_which_vocabulary_it_was_recorded_under() {
        use crate::acts::vocab_version_of_header;
        // The stamp the recorder writes since NML-1134.
        assert_eq!(vocab_version_of_header(r#"{"knobs":{"rule_vocab_version":3}}"#), 3);
        // Every corpus recorded before it: a knobs block without the key ...
        assert_eq!(vocab_version_of_header(r#"{"knobs":{"top_k":6}}"#), LEGACY_VOCAB_VERSION);
        // ... no knobs block at all ...
        assert_eq!(vocab_version_of_header(r#"{"kind":"header"}"#), LEGACY_VOCAB_VERSION);
        // ... and something that is not a header at all.
        assert_eq!(vocab_version_of_header("not json"), LEGACY_VOCAB_VERSION);
        // The typed reader agrees with the standalone one, because it IS it.
        let head = read_act_header(HEADER).expect("header");
        assert_eq!(head.knobs.rule_vocab_version, LEGACY_VOCAB_VERSION);
        assert_eq!(vocab_version_of_header(HEADER), head.knobs.rule_vocab_version);
    }

    #[test]
    fn rule_text_parses_the_way_the_regex_does() {
        assert_eq!(parse_rule("Tough(3)"), ("Tough".into(), 3));
        assert_eq!(parse_rule("  Ambush (2) "), ("Ambush".into(), 2));
        assert_eq!(parse_rule("Fearless"), ("Fearless".into(), 0));
        // `(\d+)` is digits only — a signed rating keeps its whole text.
        assert_eq!(parse_rule("Deadly(+3)"), ("Deadly(+3)".into(), 0));
        assert_eq!(parse_rule("A(1) B(2)"), ("A(1) B".into(), 2));
        assert_eq!(parse_rule("()"), ("()".into(), 0));
    }
}
