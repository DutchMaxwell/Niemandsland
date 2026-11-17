//! One-core P3: one activation as the ordered inputs the table sends, the
//! answers the core gives, the order rules on the inputs, and
//! `step_activation`, which resolves the activation through the step API.

use crate::dice::Tray;
use crate::gate::INCHES_TO_METERS;
use crate::io::{Action, Seams, SplitShot};
use crate::landing::Landing;
use crate::logline::{Category, LogLine};
use crate::mv::step::{leg_crosses, DIFFICULT_MOVE_CAP_IN};
use crate::rng::GodotRng;
use crate::sim::{band_parts, resolve_stochastic_tray_on_board, terrain_debuff_folds, Cover, ADVANCE, CHARGE, HOLD, REPOSITION, RUSH};
use crate::state::State;
use crate::step::{step_with, Step};
use crate::terrain::{is_difficult, Terrain};
use crate::unit::UnitStatic;

/// One thing the table tells the core during an activation, in order.
#[derive(Debug, Clone, PartialEq)]
pub enum Input {
    /// "Activate" on the unit's card starts the activation.
    Begin,
    /// The declared action (`sim::HOLD` ..); `shoot` is `Some` when it shoots. `split` is split fire's aim,
    /// per (member, weapon) the target key it fires at; `None` (or empty) = the one `shoot` target.
    Intent { kind: i64, shoot: Option<String>, split: Option<Vec<SplitShot>> },
    /// One thrown face group, in the order the core asked for them.
    Faces(Vec<u8>),
    /// The unit's model positions after a drag (`at`) and each model's walked path this
    /// activation (world XZ metres, in the order of `at`; empty = none).
    Placed { at: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>> },
    /// "Cancel", allowed until the first die of the activation.
    Cancel,
    /// P4.0-5: one answer to a `NeedChoice`, by the choice's stable `id` and an option id. An EMPTY
    /// `option` asks the core what it is waiting for: the next answer is `ActStep::NeedChoice`.
    /// A transcript without a `Choice` keeps the core's automatic pick (the default policy).
    Choice { id: String, option: String },
}

/// The core's answer to the inputs so far. `Done` and `Cancelled` are the
/// two terminal states of an activation in the core.
#[derive(Debug)]
// One per step call, never stored in bulk: `State` by value (the plan's API) costs nothing here.
#[allow(clippy::large_enum_variant)]
pub enum ActStep {
    /// Roll `faces` dice and send them as the next `Faces`; `lines` and
    /// `landings` are only those before the starved draw. `owner` is the rolling unit's name (a label), `owner_key`
    /// its roster key (who rolls; "" when the core cannot tell, see `owner_key_of`).
    NeedRoll { index: usize, faces: usize, kind: &'static str, count: i64, target: i64, owner: String, owner_key: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    /// The activation is open and waits for the next input.
    Open,
    /// P4.0-5: the core needs one answer before it can resolve (`option: ""` asked). `id` and every
    /// option are stable ids (a target unit key and `slot:<n>` model slots), `owner` is the roster
    /// key of the unit whose side answers. Answer with `Input::Choice { id, option }`.
    NeedChoice { id: String, options: Vec<String>, owner: String },
    /// Input `index` breaks an order rule; `reason` is the sentence the player sees.
    Refused { index: usize, reason: String },
    /// The activation was cancelled before its first die; the state is untouched
    /// and the table puts the models back. `lines` is the one cancel sentence.
    Cancelled { lines: Vec<LogLine> },
    /// `unported`: the resolver's own `ShootResult.unported` marks (dice.rs `mark`), so a core that
    /// knows it diverged from the table says so; `[]` on a fully ported volley.
    Done { state: State, lines: Vec<LogLine>, landings: Vec<Landing>, unported: Vec<&'static str> },
}

/// The order rules, checked in their numbered order on each input; the error
/// is the first offending input's index and its sentence. `name` is the unit's.
pub fn order_check(name: &str, t: &[Input]) -> Result<(), (usize, String)> {
    let (mut declared, mut shot, mut rolled, mut over) = (false, false, false, false);
    for (i, x) in t.iter().enumerate() {
        let why = match x {
            _ if i == 0 && *x != Input::Begin => Some("the activation was not started".to_string()),
            Input::Begin if i > 0 => Some("the activation is already started".to_string()),
            _ if over => Some("the activation is over".to_string()),
            Input::Cancel if rolled => Some("cancel is not possible after the first die".to_string()),
            Input::Faces(_) if !declared => Some("faces before the action was declared".to_string()),
            Input::Choice { .. } if !declared => Some("the choice was answered before the action was declared".to_string()),
            Input::Intent { .. } if declared => Some("one action per activation".to_string()),
            Input::Placed { .. } if shot => Some(format!("{name} has already shot this round — it cannot move now")),
            Input::Intent { kind, .. } if *kind == CHARGE || *kind == REPOSITION => Some("not on the step path yet".to_string()),
            _ => None,
        };
        if let Some(reason) = why {
            return Err((i, reason));
        }
        match x {
            Input::Intent { shoot, .. } => (declared, shot) = (true, shoot.is_some()),
            Input::Faces(_) => rolled = true,
            Input::Cancel => over = true,
            _ => {}
        }
    }
    Ok(())
}

/// O5: no unit begins while another unit's activation is open; `Some(a)`
/// names the unit whose activation is open.
pub fn begin_check(open_elsewhere: Option<&str>) -> Result<(), String> {
    match open_elsewhere {
        Some(a) => Err(format!("Finish {a}'s activation first.")),
        None => Ok(()),
    }
}

/// The table's own drop floor in inches (`main.gd` `_on_units_dropped`, the
/// `<= 0.1` skip): a model that moved no more than this did not move.
pub const DROP_FLOOR_IN: f64 = 0.1;

/// Not moving is Hold: the core reads the declaration from the selector, never
/// from distance. ADVANCE or RUSH with no placement, or with every model within
/// `DROP_FLOOR_IN` (horizontal, the table's measure) of its start, is HOLD;
/// every other case is `declared`. A placement that does not match the unit's
/// models is not proven still, so it stays `declared` for the move check.
pub fn effective_kind(declared: i64, start: &[[f64; 3]], placed: Option<&[[f64; 3]]>) -> i64 {
    let still = |p: &[[f64; 3]]| p.len() == start.len() && p.iter().zip(start).all(|(a, b)| (a[0] - b[0]).hypot(a[2] - b[2]) / INCHES_TO_METERS <= DROP_FLOOR_IN);
    if (declared == ADVANCE || declared == RUSH) && placed.is_none_or(still) {
        HOLD
    } else {
        declared
    }
}

/// What a unit may move this activation per declared mode, in inches: the parts the real move
/// spends (`sim::band_parts`), one number for both. `widened_by` = the rules whose part is non-zero.
#[derive(Debug, Clone, PartialEq)]
pub struct Allowance { pub advance: f64, pub rush: f64, pub charge: f64, pub widened_by: Vec<String> }

/// The unit's `Allowance` at its activation start in `state`; Bounding is 0.0 here (gap G2).
pub fn allowance(statics: &[UnitStatic], state: &State, si: usize, seams: Seams, terrain: &Terrain) -> Allowance {
    let parts = [ADVANCE, RUSH, CHARGE].map(|k| band_parts(statics, state, state, si, k, None, 0.0, Cover::Board(terrain), seams, false));
    let grants: Vec<&str> = ["Fast", "Rapid Advance", "Rapid Rush", "Slow"].into_iter().filter(|g| crate::mods::granted(state, si, g)).collect();
    let names: [&[&str]; 7] = [&["Bounding"], &["Versatile Reach"], &["Grounded Speed"], &["Speed Feat"], &["Great Musician"], &grants, &["Rapid Charge"]];
    let on = |i: usize| parts.iter().any(|p| [p.bounding, p.vr, p.gs, p.feat, p.buff, p.grant, p.rapid_mark][i] != 0.0);
    let widened_by = (0..7).filter(|&i| on(i)).flat_map(|i| names[i].iter().map(|n| n.to_string())).collect();
    Allowance { advance: parts[0].total(), rush: parts[1].total(), charge: parts[2].total(), widened_by }
}

/// One drop: the declared mode, each model's position (`state.positions` order) and each model's
/// walked path this activation (world XZ metres, same order; empty = none). Literals: `..Default::default()`.
#[derive(Debug, Clone, Default)]
pub struct Drop { pub mode: i64, pub placed: Vec<[f64; 3]>, pub trails: Vec<Vec<[f64; 2]>> }

/// `check_move`'s answer: accepted (with the overrun line when not enforced) or refused.
#[derive(Debug, Clone, PartialEq)]
pub enum Check { Ok { lines: Vec<LogLine> }, Refused { reason: String } }

/// The move check of one drop against the unit's start in `state`: (1) a declared mode, (2) one
/// position per model, (3) every model's walked path (its trail when it has 2+ points, which must
/// run from its start to its placed position within 0.01"; else the straight segment from start to end once the model
/// moved more than `DROP_FLOOR_IN`), plus every climb its legs pay, within the mode's allowance (+0.01" float noise), at
/// most 6" for every model once any model's path crosses Difficult terrain or the unit carries the Difficult debuff (not
/// for Flying or Strider). An
/// overrun is refused with the O3 sentence when `enforce`, else accepted with that sentence as one log line.
pub fn check_move(statics: &[UnitStatic], state: &State, si: usize, seams: Seams, terrain: &Terrain, drop: &Drop, enforce: bool) -> Check {
    let (mode, m) = match drop.mode {
        ADVANCE => ("Advance", 0),
        RUSH => ("Rush", 1),
        CHARGE => ("Charge", 2),
        _ => return Check::Refused { reason: "movement mode not declared".to_string() },
    };
    let start = &state.positions[si];
    if drop.placed.len() != start.len() {
        return Check::Refused { reason: "placement does not match the unit's models".to_string() };
    }
    let inch = |p: [f64; 2], q: [f64; 2]| (p[0] - q[0]).hypot(p[1] - q[1]) / INCHES_TO_METERS;
    // The climbs the AI's move pays (GF p.11), in the trail's world frame: none for Flying or below epoch 74.
    let flying = state.profile(si).special_rules.iter().any(|r| r == "Flying");
    let ledges = crate::mv::step::world_ledges_of(terrain, flying, seams.rules_epoch);
    let mut x = 0.0f64;
    // Each model's path: its trail, else (R3: no chord bypass) the straight segment [start, end] once it moved past the
    // drop floor, so its climbs and its Difficult crossing count all the same; a model that stayed has none.
    let mut paths: Vec<Vec<[f64; 2]>> = Vec::with_capacity(start.len());
    for (i, (a, b)) in start.iter().zip(&drop.placed).enumerate() {
        let (a, b) = ([a[0], a[2]], [b[0], b[2]]);
        let path = match drop.trails.get(i).filter(|t| t.len() >= 2) {
            Some(t) if inch(t[0], a) > 0.01 || inch(t[t.len() - 1], b) > 0.01 => {
                return Check::Refused { reason: "trail does not match the placed model".to_string() };
            }
            Some(t) => t.clone(),
            None if inch(a, b) > DROP_FLOOR_IN => vec![a, b],
            None => Vec::new(),
        };
        x = x.max(if path.is_empty() { inch(a, b) } else { crate::mv::step::trail_walk_in(&path, &ledges).0 });
        paths.push(path);
    }
    // GF p.11: Difficult terrain caps the WHOLE unit; Flying and Strider ignore it (read as `mv::step` reads them).
    let strider = state.profile(si).special_rules.iter().any(|r| r == "Strider");
    let crosses = |t: &Vec<[f64; 2]>, r: &f64| {
        let leg: Vec<[f32; 2]> = t.iter().map(|p| terrain.to_inch([p[0] as f32, 0.0, p[1] as f32])).collect();
        leg_crosses(&leg, *r, terrain, is_difficult)
    };
    let difficult = !(flying || strider)
        && (paths.iter().zip(&state.radii[si]).any(|(t, r)| crosses(t, r)) || terrain_debuff_folds(statics, state, si).0);
    let a = allowance(statics, state, si, seams, terrain);
    let full = [a.advance, a.rush, a.charge][m];
    let capped = difficult && full > DIFFICULT_MOVE_CAP_IN;
    let y = if capped { DIFFICULT_MOVE_CAP_IN } else { full };
    if x <= y + 0.01 {
        return Check::Ok { lines: Vec::new() };
    }
    let text = format!("{}: a model moved {x:.1}\" - the {mode} allowance is {y:.1}\".", statics[state.roster.profile[si]].name);
    if enforce {
        return Check::Refused { reason: text };
    }
    let detail = if capped { Some("Difficult terrain".to_string()) } else { (!a.widened_by.is_empty()).then(|| a.widened_by.join(", ")) };
    Check::Ok { lines: vec![LogLine { rule: "move_overrun", category: Category::Movement, side: state.player[si], text, detail }] }
}

/// P4.0-5: the one choice the step API offers so far — the Takedown model pick (`sim::takedown_pick`'s
/// automatic answer). `Some((id, options, owner))` when the activation shoots a Takedown weapon at a
/// target with 2+ living models: `id` = `takedown_model:<shooter key>:<target key>`, `options` = the
/// target's living capture slots as `slot:<n>`, `owner` = the shooter's roster key (its side answers,
/// as on the table). `None` otherwise, so every other transcript sees no choice at all.
fn takedown_choice(statics: &[UnitStatic], state: &State, si: usize, shoot: Option<&str>) -> Option<(String, Vec<String>, String)> {
    let target = shoot?;
    let ti = *state.roster.index.get(target)?;
    let living: Vec<usize> = (0..state.wounds[ti].len()).filter(|&i| state.wounds[ti][i] > 0).collect();
    if living.len() < 2 || !statics[state.roster.profile[si]].shoot.iter().any(|p| p.takedown) {
        return None;
    }
    let owner = state.roster.keys[si].clone();
    let id = format!("takedown_model:{owner}:{target}");
    Some((id, living.iter().map(|i| format!("slot:{i}")).collect(), owner))
}

/// P4.D-20: the ids of the wound-allocation choice (`wound_alloc:<shooter>:<target>:<group>`) start with this.
const WOUND_ALLOC: &str = "wound_alloc:";

/// One activation through the step API: the order rules, then the declared
/// action (not moving = Hold) on the supplied faces and the LAST placement (`check_move` first).
/// A new entry: the AI's resolver path is untouched. `NeedRoll.index` is the
/// roll's, not the transcript's; a refusal of the whole transcript is at `t.len()`.
pub fn step_activation(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input], enforce: bool) -> ActStep {
    let at = state.roster.index.get(unit).copied();
    let name = at.map_or(unit, |i| statics[state.roster.profile[i]].name.as_str());
    if let Err((index, reason)) = order_check(name, t) {
        return ActStep::Refused { index, reason };
    }
    // Before any resolver runs: no die is drawn and no state is resolved. A `Placed` in the
    // transcript is simply dropped (the table puts the models back).
    if t.last() == Some(&Input::Cancel) {
        let side = at.map_or(0, |i| state.player[i]);
        let text = format!("{name} cancelled its activation - back at its start.");
        return ActStep::Cancelled { lines: vec![LogLine { rule: "activation_cancel", category: Category::Movement, side, text, detail: None }] };
    }
    let declared = t.iter().enumerate().find_map(|(i, x)| match x {
        Input::Intent { kind, shoot, split } => Some((i, *kind, shoot.clone(), split.clone())),
        _ => None,
    });
    let Some((at_intent, declared, shoot, split)) = declared else {
        return ActStep::Open;
    };
    let placed = t.iter().rev().find_map(|x| match x {
        Input::Placed { at, trails } => Some((at.clone(), trails.clone())),
        _ => None,
    });
    let start = at.map_or(&[][..], |i| state.positions[i].as_slice());
    let kind = effective_kind(declared, start, placed.as_ref().map(|(p, _)| p.as_slice()));
    if kind == RUSH && shoot.is_some() {
        return ActStep::Refused { index: at_intent, reason: format!("{name} rushed this activation - it cannot shoot.") };
    }
    // P4.0-5: the last `Choice` in the transcript answers (or asks) the open choice; without one the
    // core's automatic pick stands and nothing below changes.
    let mut seams = seams;
    if let Some((i, id, option)) = t.iter().enumerate().rev().find_map(|(i, x)| match x {
        Input::Choice { id, option } if !id.starts_with(WOUND_ALLOC) => Some((i, id, option)),
        _ => None,
    }) {
        let Some((want, options, owner)) = at.and_then(|si| takedown_choice(statics, state, si, shoot.as_deref())) else {
            return ActStep::Refused { index: i, reason: format!("no choice is open in this activation (got {id})") };
        };
        if *id != want {
            return ActStep::Refused { index: i, reason: format!("the open choice is {want}, not {id}") };
        }
        if option.is_empty() {
            return ActStep::NeedChoice { id: want, options, owner };
        }
        let Some(slot) = option.strip_prefix("slot:").and_then(|n| n.parse::<usize>().ok()).filter(|_| options.iter().any(|o| o == option)) else {
            return ActStep::Refused { index: i, reason: format!("{option} is not an option of {want} (options: {})", options.join(", ")) };
        };
        seams = Seams { takedown_pick: Some(slot), ..seams };
    }
    // P4.D-20/21: every wound-allocation `Choice` (the last one per id, one per target group): an empty option asks (the
    // core opens it at that group's landing, once the saves are in), `slot:<n>,..` answers; none = automatic.
    let mut wound: Vec<(usize, String, Option<Vec<usize>>)> = Vec::new();
    for (i, x) in t.iter().enumerate() {
        let Input::Choice { id, option } = x else { continue };
        if !id.starts_with(WOUND_ALLOC) {
            continue;
        }
        let slots = option.split(',').map(|s| s.strip_prefix("slot:")?.parse::<usize>().ok()).collect::<Option<Vec<_>>>();
        if !option.is_empty() && slots.is_none() {
            return ActStep::Refused { index: i, reason: format!("{option} is not a slot list (slot:<n>,..) for {id}") };
        }
        wound.retain(|w| w.1 != *id);
        wound.push((i, id.clone(), slots.filter(|_| !option.is_empty())));
    }
    // Not HOLD: a mode was declared and the last placement moved (or does not match the models).
    let mut moved = Vec::new();
    if let (true, Some((p, trails)), Some(pi), Some(si)) = (kind != HOLD, &placed, t.iter().rposition(|x| matches!(x, Input::Placed { .. })), at) {
        #[allow(clippy::needless_update)] // the plan's literal form: step 78 adds `from` to `Drop`
        let drop = Drop { mode: declared, placed: p.clone(), trails: trails.clone(), ..Default::default() };
        match check_move(statics, state, si, seams, terrain, &drop, enforce) {
            Check::Refused { reason } => return ActStep::Refused { index: pi, reason },
            Check::Ok { lines } => moved = lines,
        }
    }
    let action = Action { kind, unit: unit.to_string(), dest: None, shoot, charge: None, patient: false, split, traced: None, teleport: None };
    let faces: Vec<Vec<u8>> = t.iter().filter_map(|x| if let Input::Faces(f) = x { Some(f.clone()) } else { None }).collect();
    // The spike's non-tray seed: a plain activation never draws from it.
    let reached = std::cell::RefCell::new(Vec::new());
    let run = |statics: &[UnitStatic]| {
        let resolve = |tray: &mut Tray| {
            if let Some((p, trails)) = placed.clone() {
                tray.place(p, trails);
            }
            for (_, id, answer) in &wound {
                tray.offer_wound_alloc(id.clone(), answer.clone());
            }
            let out = resolve_stochastic_tray_on_board(statics, state, &action, terrain, seams, &mut GodotRng::new(0), tray);
            *reached.borrow_mut() = tray.feed().map(|f| f.wound_choices.clone()).unwrap_or_default();
            out
        };
        step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice()))
    };
    let first = run(statics);
    // P4.D-20/21: the choices the landings came to, in the order they came, each before the first starved roll (after it, a
    // landing read made-up dice): a bad slot is refused, an unanswered ask is the answer. An answer no landing asked for is
    // refused too.
    let at_input = |id: &str| wound.iter().find(|w| w.1 == id).map_or(0, |w| w.0);
    let mut choices = reached.take();
    choices.sort_by_key(|c| c.reached.as_ref().map(|r| r.0));
    for c in &choices {
        let Some((at, options, owner)) = &c.reached else {
            if c.answer.is_some() && matches!(first, Step::Done(..)) {
                return ActStep::Refused { index: at_input(&c.id), reason: format!("no wound allocation is open in this activation (got {})", c.id) };
            }
            continue;
        };
        if matches!(first, Step::NeedRoll { index, .. } if index < *at) {
            continue;
        }
        if let Some(s) = c.bad {
            return ActStep::Refused { index: at_input(&c.id), reason: format!("slot:{s} is not an option of {}", c.id) };
        }
        if c.answer.is_none() {
            return ActStep::NeedChoice { id: c.id.clone(), options: options.iter().map(|s| format!("slot:{s}")).collect(), owner: owner.clone() };
        }
    }
    match first {
        Step::NeedRoll { index, faces, kind, count, target, owner, owner_unit, lines, landings } => {
            let owner_key = owner_key_of(statics, state, &owner, owner_unit, |keyed| match run(keyed) {
                Step::NeedRoll { index: i, kind: k, count: c, target: g, owner, .. } if (i, k, c, g) == (index, kind, count, target) => Some(owner),
                _ => None,
            });
            ActStep::NeedRoll { index, faces, kind, count, target, owner, owner_key, lines: [moved, lines].concat(), landings }
        }
        Step::Refused { reason, .. } => ActStep::Refused { index: t.len(), reason },
        Step::Done(Ok((state, shot)), lines, landings) => ActStep::Done { state, lines: [moved, lines].concat(), landings, unported: shot.unported },
        Step::Done(Err(u), ..) => ActStep::Refused { index: t.len(), reason: format!("{u:?}") },
    }
}

/// The roster key of the unit whose name a roll's `owner` is: the unit the supplied tray stamped for this draw (4.0-9),
/// else the one unit carrying that name, else (two units share it, as in a mirror match) the owner of the same roll when
/// `replay` runs the activation again with every unit named by its own key. A name decides no rule on this path, so the
/// replay draws the same rolls; one that asks for a different roll, or a name no unit carries, gives "" (the core cannot
/// tell). Never by the roll's kind: a unit can owe a defence or morale die for its own move (Dangerous terrain).
fn owner_key_of(statics: &[UnitStatic], state: &State, owner: &str, owner_unit: Option<usize>, replay: impl FnOnce(&[UnitStatic]) -> Option<String>) -> String {
    if let Some(u) = owner_unit.filter(|&u| u < state.units() && statics[state.roster.profile[u]].name == owner) {
        return state.roster.keys[u].clone();
    }
    let named: Vec<usize> = (0..state.units()).filter(|&u| statics[state.roster.profile[u]].name == owner).collect();
    match named[..] {
        [] => String::new(),
        [u] => state.roster.keys[u].clone(),
        _ => {
            let mut keyed = statics.to_vec();
            for (u, key) in state.roster.keys.iter().enumerate() {
                keyed[state.roster.profile[u]].name = key.clone();
            }
            replay(&keyed).filter(|k| named.iter().any(|&u| state.roster.keys[u] == *k)).unwrap_or_default()
        }
    }
}

/// What one activation did to one unit: the table's final cross-check of the
/// per-step landings (which carry the per-model news). `shaken` and `alive`
/// are the unit's values AFTER; `unknown` marks a unit that both moved and
/// lost models (not reachable on the plain path; the driver refuses it).
#[derive(Debug, Clone, PartialEq)]
pub struct UnitDelta {
    pub key: String,
    /// Indices into `before.positions[u]` (capture order) of the models that are gone.
    pub removed: Vec<usize>,
    pub shaken: bool,
    pub alive: i64,
    pub moved: bool,
    pub unknown: bool,
    /// P4.0-4d: the table-owned per-activation ledger AFTER — the fatigue flag and the unspent spell
    /// tokens. A plain activation changes neither; carrying them makes a table/core split visible.
    pub fatigued: bool,
    pub casts: i64,
    /// P4.0-4e: the per-unit once-per-round stamps AFTER (inventory class (a)), keyed by the `State`
    /// field name; `land_delta` maps the two names the table spells differently.
    pub stamps: Vec<(&'static str, i64)>,
    /// P4.0-4f: the per-unit marker pools AFTER (inventory class (a)), keyed by the table's own
    /// property name (every name is 1:1; absent on the table reads 0).
    pub pools: Vec<(&'static str, i64)>,
    /// P4.0-4g: the latched Versatile pick AFTER (inventory class (a)): 0 = none, 1 = +1 to hit,
    /// 2 = AP(+1). `land_delta` maps it onto the table's `versatile_pick` Dictionary.
    pub versatile_pick_mode: i64,
    /// P4.D-38a: the once-per-game feat latches this activation SPENT (inventory class (a)): the names `State::feats_used`
    /// gained, in the order they were spent. `land_delta` closes the table's flag for each, so the next capture sends it back.
    pub feats_used: Vec<String>,
    /// C-11: the once-per-game name lists this activation SPENT (inventory class (a)), the `feats_used` shape: the names
    /// `State::limited_used` / `storm_used` / `precision_used` gained, in the order they were spent. `land_delta` closes the
    /// table's latch for each (the weapon through `mark_limited_used`, the other two through their flag).
    pub limited_used: Vec<String>,
    pub storm_used: Vec<String>,
    pub precision_used: Vec<String>,
    /// C-13: the unit's Growth Markers counter AFTER (inventory class (a), `State::growth_markers`). One counter per unit
    /// whatever rules it carries; `land_delta` writes it through the unit's Growth Markers rule.
    pub growth_markers: i64,
}

/// The names `after` holds that `before` did not, in `after`'s order.
fn gained(before: &[String], after: &[String]) -> Vec<String> {
    after.iter().filter(|n| !before.contains(n)).cloned().collect()
}

/// P4.0-4f: the marker pools the inventory marks table-owned, in `State` declaration order, AFTER.
fn pools_of(s: &State, u: usize) -> Vec<(&'static str, i64)> {
    vec![
        ("spot_markers", s.spot_markers[u]),
        ("tag_markers", s.tag_markers[u]),
        ("piercing_tag_markers", s.piercing_tag_markers[u]),
        ("vengeance_markers", s.vengeance_markers[u]),
    ]
}

/// P4.0-4e: every round stamp the inventory marks table-owned, in `State` declaration order, AFTER.
fn stamps_of(s: &State, u: usize) -> Vec<(&'static str, i64)> {
    vec![
        ("vs_mark_round", s.vs_mark_round[u]),
        ("hit_and_run_round", s.hit_and_run_round[u]),
        ("moved_round", s.moved_round[u]),
        ("reckless_rolled_round", s.reckless_rolled_round[u]),
        ("reckless_ap_round", s.reckless_ap_round[u]),
        ("reckless_backfire_round", s.reckless_backfire_round[u]),
        ("versatile_pick_round", s.versatile_pick_round[u]),
        ("retreating_strike_round", s.retreating_strike_round[u]),
        ("mind_control_moved_round", s.mind_control_moved_round[u]),
        ("growth_strike_round", s.growth_strike_round[u]),
        ("spot_round", s.spot_round[u]),
        ("piercing_spot_round", s.piercing_spot_round[u]),
    ]
}

/// Every unit whose alive, shaken, positions or moved_round changed. `removed`
/// holds the positions of `before` that no longer appear in `after`, by exact
/// f64 equality: removal shifts slots but never edits a survivor.
pub fn delta_of(before: &State, after: &State) -> Vec<UnitDelta> {
    let mut out = Vec::new();
    for (u, key) in before.roster.keys.iter().enumerate() {
        let (b, a) = (&before.positions[u], &after.positions[u]);
        let (mut removed, mut j) = (Vec::new(), 0);
        for (i, p) in b.iter().enumerate() {
            if a.get(j) == Some(p) {
                j += 1;
            } else {
                removed.push(i);
            }
        }
        // `a` is not `b` minus some entries: a survivor was edited, i.e. a model moved.
        let moved = j < a.len() || before.moved_round.get(u) != after.moved_round.get(u);
        let unknown = moved && a.len() < b.len();
        if j < a.len() || unknown {
            removed.clear();
        }
        let stamps_changed = stamps_of(before, u) != stamps_of(after, u);
        let pools_changed = pools_of(before, u) != pools_of(after, u);
        if b != a || before.alive[u] != after.alive[u] || before.shaken[u] != after.shaken[u] || moved
            || before.fatigued[u] != after.fatigued[u] || before.casts[u] != after.casts[u]
            || stamps_changed || pools_changed
            || before.versatile_pick_mode[u] != after.versatile_pick_mode[u]
            || before.feats_used[u] != after.feats_used[u]
            || before.limited_used[u] != after.limited_used[u]
            || before.storm_used[u] != after.storm_used[u]
            || before.precision_used[u] != after.precision_used[u]
            || before.growth_markers[u] != after.growth_markers[u]
        {
            out.push(UnitDelta {
                key: key.clone(),
                removed,
                shaken: after.shaken[u],
                alive: after.alive[u],
                moved,
                unknown,
                fatigued: after.fatigued[u],
                casts: after.casts[u],
                stamps: stamps_of(after, u),
                pools: pools_of(after, u),
                versatile_pick_mode: after.versatile_pick_mode[u],
                feats_used: gained(&before.feats_used[u], &after.feats_used[u]),
                limited_used: gained(&before.limited_used[u], &after.limited_used[u]),
                storm_used: gained(&before.storm_used[u], &after.storm_used[u]),
                precision_used: gained(&before.precision_used[u], &after.precision_used[u]),
                growth_markers: after.growth_markers[u],
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use Input::{Begin, Cancel, Faces};

    /// A `Placed` without walked paths.
    fn placed(at: Vec<[f64; 3]>) -> Input {
        Input::Placed { at, trails: Vec::new() }
    }

    fn intent(kind: i64, shoot: Option<&str>) -> Input {
        Input::Intent { kind, shoot: shoot.map(String::from), split: None }
    }

    fn refused(t: &[Input], index: usize, reason: &str) {
        assert_eq!(order_check("Squad", t), Err((index, reason.to_string())), "{t:?}");
    }

    #[test]
    fn rule1_the_first_input_must_be_begin() {
        refused(&[intent(ADVANCE, None)], 0, "the activation was not started");
    }

    #[test]
    fn rule2_a_second_begin_is_refused() {
        refused(&[Begin, placed(vec![]), Begin], 2, "the activation is already started");
    }

    #[test]
    fn rule3_nothing_after_a_cancel() {
        refused(&[Begin, Cancel, placed(vec![])], 2, "the activation is over");
    }

    #[test]
    fn rule4_cancel_only_until_the_first_die() {
        refused(&[Begin, intent(ADVANCE, None), Faces(vec![3]), Cancel], 3, "cancel is not possible after the first die");
    }

    #[test]
    fn rule5_faces_need_a_declared_action() {
        refused(&[Begin, placed(vec![]), Faces(vec![4])], 2, "faces before the action was declared");
    }

    #[test]
    fn rule6_one_action_per_activation() {
        refused(&[Begin, intent(HOLD, None), intent(ADVANCE, None)], 2, "one action per activation");
    }

    #[test]
    fn rule7_no_move_after_the_unit_shot() {
        let t = [Begin, intent(ADVANCE, Some("Rifles")), Faces(vec![5]), placed(vec![[0.0; 3]])];
        refused(&t, 3, "Squad has already shot this round — it cannot move now");
        assert_eq!(order_check("Squad", &[Begin, intent(ADVANCE, None), placed(vec![])]), Ok(()));
    }

    #[test]
    fn rule8_charge_and_reposition_are_not_on_the_step_path() {
        refused(&[Begin, intent(CHARGE, None)], 1, "not on the step path yet");
        refused(&[Begin, placed(vec![]), intent(REPOSITION, None)], 2, "not on the step path yet");
    }

    #[test]
    fn moves_before_the_shooting_intent_are_fine() {
        let t = [Begin, placed(vec![[1.0, 0.0, 0.0]]), placed(vec![[2.0, 0.0, 0.0]]), intent(ADVANCE, Some("Rifles"))];
        assert_eq!(order_check("Squad", &t), Ok(()));
    }

    #[test]
    fn cancel_after_a_move_is_fine() {
        assert_eq!(order_check("Squad", &[Begin, placed(vec![[1.0, 0.0, 0.0]]), Cancel]), Ok(()));
    }

    #[test]
    fn begin_names_the_open_activation() {
        assert_eq!(begin_check(Some("A")), Err("Finish A's activation first.".to_string()));
        assert_eq!(begin_check(None), Ok(()));
    }

    /// Two models at the origin and 1 m east, the second one moved `dx` inches east and `dy` up.
    fn shifted(dx: f64, dy: f64) -> Vec<[f64; 3]> {
        vec![[0.0, 0.0, 0.0], [1.0 + dx * INCHES_TO_METERS, dy * INCHES_TO_METERS, 0.0]]
    }

    #[test]
    fn not_moving_is_hold() {
        let start = shifted(0.0, 0.0);
        assert_eq!(effective_kind(ADVANCE, &start, None), HOLD);
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.05, 0.0))), HOLD, "inside the 0.1\" floor");
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.0, 3.0))), HOLD, "height is not horizontal");
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.5, 0.0))), ADVANCE);
        assert_eq!(effective_kind(RUSH, &start, Some(&shifted(0.5, 0.0))), RUSH);
        assert_eq!(effective_kind(RUSH, &start, None), HOLD);
    }

    #[test]
    fn only_advance_and_rush_fall_back_to_hold() {
        let start = shifted(0.0, 0.0);
        assert_eq!(effective_kind(HOLD, &start, Some(&shifted(0.5, 0.0))), HOLD);
        assert_eq!(effective_kind(CHARGE, &start, None), CHARGE);
        assert_eq!(effective_kind(ADVANCE, &start, Some(&start[..1])), ADVANCE, "a short placement is not proven still");
    }

    // ---- step 11: a whole activation through the step API ----

    use crate::dice::Roll;
    use crate::sim::tests::volley_landings::volley_line;
    use crate::unit::ShootProfile;

    fn seams() -> Seams {
        Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() }
    }

    /// The step-1 driver loop: roll each `NeedRoll` from the seeded tray `seed`
    /// and append it; returns the last answer and the roll records it asked for.
    fn drive(statics: &[UnitStatic], st: &State, mut t: Vec<Input>, seed: i64) -> (ActStep, Vec<Roll>) {
        let (mut dice, mut rolls) = (Tray::seeded(seed), Vec::new());
        dice.set_zero_draws(true); // exactly the faces asked for: the feed already applied the epoch
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { faces, kind, count, target, owner, .. } => {
                    let f = dice.roll(faces);
                    rolls.push(Roll { kind, count, target, faces: f.clone(), owner });
                    t.push(Faces(f));
                }
                other => return (other, rolls),
            }
        }
    }

    /// C-1: the step answer keeps the resolver's `unported` marks. A Strafing rifle in a normal volley
    /// (dice.rs `mark("strafing")`, the per-model split is not ported) answers `["strafing"]`, the
    /// plain rifle `[]` (RED: drop the field at the `Step::Done` arm and the Strafing side reads `[]`).
    #[test]
    fn a_done_step_answers_the_unported_marks() {
        let (st, mut statics) = volley_line();
        let marks = |statics: &[UnitStatic]| match drive(statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7).0 {
            ActStep::Done { unported, .. } => unported,
            other => panic!("{other:?}"),
        };
        assert_eq!(marks(&statics), Vec::<&str>::new());
        statics[0].shoot[0].strafing = true;
        assert_eq!(marks(&statics), vec!["strafing"]);
    }

    /// The stepped activation equals one straight seeded run, state and roll records alike; the
    /// straight run's non-tray stream differs (seed vs 0), so a draw from it would show here too.
    #[test]
    fn a_stepped_activation_equals_the_seeded_run() {
        let (st, statics) = volley_line();
        let (mut killed, mut shaken, mut morale) = (0, 0, 0);
        for seed in 0..200i64 {
            let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
            let (want, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, rolls) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            assert_eq!((&state.alive, &state.shaken), (&want.alive, &want.shaken), "seed {seed}");
            // The step asks for the morale die as "morale" (the table's kind); its record keeps the replay's "attack".
            morale += rolls.iter().filter(|r| r.kind == "morale").count();
            let fold = |r: Roll| Roll { kind: if r.kind == "morale" { "attack" } else { r.kind }, ..r };
            assert_eq!(rolls.into_iter().map(fold).collect::<Vec<_>>(), shot.rolls, "seed {seed}");
            assert_eq!(state, want, "seed {seed}");
            (killed, shaken) = (killed + (want.alive[2] < st.alive[2]) as i32, shaken + want.shaken[2] as i32);
        }
        assert!(killed > 0 && shaken > 0 && morale > 0, "fixture must kill, shake and test morale: {killed} {shaken} {morale}");
    }

    /// `volley_line` with split fire's second target: "bh" stands alone (not attached) 10" north of "a", which
    /// now carries a second weapon; the rifle's aim is "b", the pistol's is "bh".
    fn split_line() -> (State, Vec<UnitStatic>, Vec<SplitShot>) {
        let (mut st, mut statics) = volley_line();
        st.attached = std::rc::Rc::new(vec![Vec::new(); 4]);
        st.attached_to = std::rc::Rc::new(vec![None; 4]);
        st.positions[3] = vec![[0.0, 0.0, 10.0 * INCHES_TO_METERS]];
        statics[0].shoot.push(crate::unit::ShootProfile { name: "pistol".into(), attacks: 4, count: 1, range: 24, ..Default::default() });
        (statics[3].model_count, statics[3].wounds_max, statics[3].ctx.defense) = (1, vec![1], 4);
        let aim = |weapon: &str, target: &str| SplitShot { member: "a".into(), weapon: weapon.into(), target: target.into() };
        (st, statics, vec![aim("rifle", "b"), aim("pistol", "bh")])
    }

    /// Split fire on the step API: an intent that carries `split` equals one straight seeded run with the
    /// same `Action.split`, state, roll records and lines alike, over 200 seeds. RED: carry `split: None` into the
    /// action (both targets are then pooled on "b", "bh" is never fired at and the rolls differ).
    #[test]
    fn a_split_fire_intent_equals_the_seeded_run_with_the_same_aim() {
        let (st, statics, aim) = split_line();
        let (mut both, mut pooled_differs) = (0, 0);
        for seed in 0..200i64 {
            let split = |split: Option<Vec<SplitShot>>| Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split, traced: None, teleport: None };
            let (want, shot) = resolve_stochastic_tray_on_board(&statics, &st, &split(Some(aim.clone())), &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, rolls) = drive(&statics, &st, vec![Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: Some(aim.clone()) }], seed);
            let ActStep::Done { state, lines, .. } = got else { panic!("seed {seed}: {got:?}") };
            let fold = |r: Roll| Roll { kind: if r.kind == "morale" { "attack" } else { r.kind }, ..r };
            assert_eq!(rolls.into_iter().map(fold).collect::<Vec<_>>(), shot.rolls, "seed {seed}");
            assert_eq!(state, want, "seed {seed}");
            // The step's own lines name each aimed target's volley, in the aim's group order.
            let said: Vec<&str> = lines.iter().map(|l| l.text.as_str()).filter(|t| t.starts_with("a fires at ")).collect();
            assert_eq!(said, ["a fires at b", "a fires at bh"], "seed {seed}");
            // The aim bites: both targets lose something here, and the pooled run (no aim) is another run.
            both += (want.wounds[2] != st.wounds[2] && want.alive[3] < st.alive[3]) as i32;
            let pooled = resolve_stochastic_tray_on_board(&statics, &st, &split(None), &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap().0;
            pooled_differs += (pooled != want) as i32;
        }
        assert!(both > 0 && pooled_differs > 0, "fixture must hurt both targets and differ from the pooled run: {both} {pooled_differs}");
    }

    // ---- P4.0-5: NeedChoice in the step API ----

    /// `volley_line` with "a" carrying one Takedown sniper shot into "b" (two Tough(3) models).
    fn takedown_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = volley_line();
        statics[0].shoot = vec![ShootProfile { name: "sniper".into(), takedown: true, attacks: 1, count: 1, range: 24, ..Default::default() }];
        (st, statics)
    }

    /// The fixture's choice id: stable (the shooter's and the target's roster keys).
    const TAKEDOWN_ID: &str = "takedown_model:a:b";

    /// One choice point: without a `Choice` the automatic pick stands (the last living slot); with
    /// `Input::Choice` answered, the OTHER model takes the Takedown wound. RED: drop the answer ->
    /// both runs equal; accept any slot -> the default's model is named again.
    #[test]
    fn a_takedown_choice_answered_explicitly_differs_from_the_default() {
        let (st, statics) = takedown_line();
        for seed in 0..200i64 {
            let (auto, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let answer = [Begin, intent(HOLD, Some("b")), Input::Choice { id: TAKEDOWN_ID.into(), option: "slot:0".into() }];
            let (explicit, _) = drive(&statics, &st, answer.to_vec(), seed);
            let (ActStep::Done { state: a, .. }, ActStep::Done { state: e, .. }) = (&auto, &explicit) else { continue };
            if a.wounds[2] == e.wounds[2] {
                continue; // no Takedown group landed on this seed
            }
            assert_eq!(a.wounds[2], vec![3, 2], "seed {seed}: the automatic pick is the last living slot");
            assert_eq!(e.wounds[2], vec![2, 3], "seed {seed}: the answer names slot 0");
            assert_eq!(a.alive[2], e.alive[2], "seed {seed}: the group is nonlethal, only the pick differs");
            return;
        }
        panic!("no seed in 0..200 landed a Takedown group");
    }

    /// The empty option asks the open choice: stable id, every living slot as an option, the answering
    /// unit's key as `owner`.
    #[test]
    fn an_empty_option_asks_the_choice_with_its_stable_id_and_slots() {
        let (st, statics) = takedown_line();
        let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: TAKEDOWN_ID.into(), option: String::new() }];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::NeedChoice { id, options, owner } => {
                assert_eq!((id.as_str(), owner.as_str()), (TAKEDOWN_ID, "a"));
                assert_eq!(options, vec!["slot:0".to_string(), "slot:1".to_string()]);
            }
            other => panic!("expected NeedChoice, got {other:?}"),
        }
    }

    /// A wrong id and a wrong option are refusals at the choice's input, never a silent acceptance
    /// (RED: drop the option check -> a bogus `slot:9` resolves as the automatic pick).
    #[test]
    fn a_wrong_choice_id_or_option_is_refused() {
        let (st, statics) = takedown_line();
        let ask = |id: &str, option: &str| {
            let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: id.into(), option: option.into() }];
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        };
        match ask("takedown_model:a:zzz", "slot:0") {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains(TAKEDOWN_ID), "{reason}"),
            other => panic!("a wrong id must be refused, got {other:?}"),
        }
        match ask(TAKEDOWN_ID, "slot:9") {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains("slot:9"), "{reason}"),
            other => panic!("a wrong option must be refused, got {other:?}"),
        }
    }

    // ---- P4.D-20: the wound-allocation choice ----

    use crate::state::Kit;
    const ALLOC_ID: &str = "wound_alloc:a:b:0";

    /// `volley_line` with "b" a mixed-kit unit: two Tough(3) models (6 wounds) carrying different weapons; "a" fires 4 shots.
    fn mixed_line() -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = volley_line();
        let kit = |w: u16| Kit { weapons: vec![w], equipment: 0, wounds_max: 3 };
        st.kits = vec![Rc::new(Vec::new()), Rc::new(Vec::new()), Rc::new(vec![kit(1), kit(2)]), Rc::new(Vec::new())];
        (st, statics)
    }

    /// The activation to its next answer: 4 hits, every save fails (4 unsaved wounds on "b"), morale passes; `choice` is the
    /// option of the wound-allocation `Choice` sent first (`Some("")` = only asked, `None` = no choice in the transcript).
    fn alloc(st: &State, statics: &[UnitStatic], choice: Option<&str>) -> ActStep {
        let mut t = vec![Begin, intent(HOLD, Some("b"))];
        t.extend(choice.map(|o| Input::Choice { id: ALLOC_ID.into(), option: o.into() }));
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { faces, kind, .. } => t.push(Faces(vec![if kind == "defense" { 1 } else { 6 }; faces])),
                other => return other,
            }
            assert!(t.len() < 12, "{t:?}");
        }
    }

    /// No `Choice` in the transcript is today's landing, mixed kits or not: the stepped activation equals the seeded run.
    #[test]
    fn without_a_wound_allocation_choice_the_landing_is_the_automatic_one() {
        let (st, statics) = mixed_line();
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
        for seed in 0..200i64 {
            let (want, _) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            assert_eq!(state, want, "seed {seed}");
        }
    }

    /// The ask is answered once the saves are in (the wounds are unknown before): `NeedChoice` with the stable id, the target's
    /// living slots and the target as owner; asked before the dice, the dice come first.
    #[test]
    fn a_wound_allocation_ask_opens_after_the_saves() {
        let (st, statics) = mixed_line();
        match alloc(&st, &statics, Some("")) {
            ActStep::NeedChoice { id, options, owner } => {
                assert_eq!((id.as_str(), owner.as_str()), (ALLOC_ID, "b"));
                assert_eq!(options, vec!["slot:0".to_string(), "slot:1".to_string()]);
            }
            other => panic!("expected NeedChoice, got {other:?}"),
        }
        let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: ALLOC_ID.into(), option: String::new() }];
        let first = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true);
        assert!(matches!(first, ActStep::NeedRoll { index: 0, .. }), "{first:?}");
    }

    /// The answer lands on the named slots, in order, a slot repeating (one wound each); the automatic landing (no choice
    /// in the transcript, today's) leaves the OTHER model standing. RED: ignore the answer -> both runs equal.
    #[test]
    fn an_answered_wound_allocation_lands_on_the_named_slots() {
        let (st, statics) = mixed_line();
        let survivor = |step: ActStep| match step {
            ActStep::Done { state, lines, .. } => (state.positions[2].clone(), state.wounds[2].clone(), lines),
            other => panic!("expected Done, got {other:?}"),
        };
        let (auto_at, auto_wounds, _) = survivor(alloc(&st, &statics, None));
        assert_eq!((auto_at.len(), auto_wounds.iter().sum::<i64>()), (1, 2), "fixture: auto kills one model, wounds the other");
        // Three wounds kill one model, the fourth wounds the other: kill the one the automatic order spares.
        let against = if auto_at[0] == st.positions[2][0] { "slot:0,slot:0,slot:0,slot:1" } else { "slot:1,slot:1,slot:1,slot:0" };
        let (at, wounds, lines) = survivor(alloc(&st, &statics, Some(against)));
        assert_ne!(at, auto_at, "the answer, not the automatic order, decides who survives");
        assert_eq!((at.len(), wounds), (1, vec![2]));
        assert!(lines.iter().any(|l| l.rule == "wound_alloc" && l.text == "b: the owner allocates 4 wounds"), "{lines:?}");
    }

    /// A slot that is no option, and an answer that is no slot list, are refused at the choice's input (RED: accept any slot ->
    /// the bogus pick lands nothing and the activation is `Done`).
    #[test]
    fn a_bad_wound_allocation_answer_is_refused() {
        let (st, statics) = mixed_line();
        for (option, said) in [("slot:5", "slot:5 is not an option of wound_alloc:a:b:0"), ("slot:0,slot:7", "slot:7 is not an option"), ("b", "is not a slot list")] {
            match alloc(&st, &statics, Some(option)) {
                ActStep::Refused { index: 2, reason } => assert!(reason.contains(said), "{option}: {reason}"),
                other => panic!("{option}: expected a refusal, got {other:?}"),
            }
        }
    }

    /// P4.D-21: the owner places a Deadly(2) volley's wounds too (D17): a wound goes to the next pick and deals X there; a wound
    /// the auto pick FORCES onto the already-wounded Tough model takes no pick. Two unsaved wounds, pick slot 1: slot 1 takes
    /// 2 of its 3, then the forced second wound finishes it - slot 0 stands; the automatic landing spares the other model.
    /// With no pool wound the ask still opens. RED: land Deadly by the automatic pick -> both runs equal.
    #[test]
    fn a_deadly_volley_lands_on_the_owners_picks_and_forced_wounds_take_none() {
        let (mut st, mut statics) = mixed_line();
        // Deadly reads the dynamic `Profile` of every roster entry (the fixture has one).
        st.profiles = Rc::new(crate::state::Profiles { list: vec![st.profiles.list[0].clone(); 4], index: Default::default() });
        statics[0].shoot = vec![crate::unit::ShootProfile { name: "lance".into(), attacks: 2, count: 1, range: 24, deadly: 2, ..Default::default() }];
        let ask = alloc(&st, &statics, Some(""));
        assert!(matches!(ask, ActStep::NeedChoice { ref id, .. } if id == ALLOC_ID), "{ask:?}");
        let end = |choice: Option<&str>| match alloc(&st, &statics, choice) {
            ActStep::Done { state, lines, .. } => (state.positions[2].clone(), state.wounds[2].clone(), lines),
            other => panic!("expected Done, got {other:?}"),
        };
        let (auto_at, ..) = end(None);
        let (at, wounds, lines) = end(Some("slot:1,slot:0"));
        assert_eq!((at.clone(), wounds), (vec![st.positions[2][0]], vec![3]), "slot 1 died, slot 0 stands untouched");
        assert_eq!(auto_at, vec![st.positions[2][1]], "the automatic landing kills the lead, slot 0");
        assert!(lines.iter().any(|l| l.text == "b: the owner allocates 1 wound"), "the forced wound took no pick: {lines:?}");
    }

    /// P4.D-21: a split volley has one choice per target group, the group's place in the plan in its id. Two mixed-kit
    /// targets, the rifle aimed at "b" (group 0) and the pistol at "bh" (group 1): each answer lands on its own target, and an
    /// answer under the wrong group index is no answer (RED: id every group `:0` -> the "bh" answer is never read).
    #[test]
    fn a_split_volley_has_one_choice_per_target_group() {
        let (mut st, mut statics) = mixed_line();
        let kit = |w: u16| Kit { weapons: vec![w], equipment: 0, wounds_max: 3 };
        st.attached = Rc::new(vec![Vec::new(); 4]);
        st.attached_to = Rc::new(vec![None; 4]);
        st.positions[3] = vec![[12.0 * INCHES_TO_METERS, 0.0, 10.0 * INCHES_TO_METERS], [12.0 * INCHES_TO_METERS, 0.0, 12.5 * INCHES_TO_METERS]];
        (st.wounds[3], st.alive[3], st.kits[3]) = (vec![3, 3], 2, Rc::new(vec![kit(1), kit(2)]));
        Rc::make_mut(&mut st.radii)[3] = vec![INCHES_TO_METERS; 2];
        statics[3] = UnitStatic { name: "bh".into(), ..statics[2].clone() };
        statics[0].shoot.push(ShootProfile { name: "pistol".into(), attacks: 4, count: 1, range: 24, ..Default::default() });
        let aim = |weapon: &str, target: &str| crate::io::SplitShot { member: "a".into(), weapon: weapon.into(), target: target.into() };
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: Some(vec![aim("rifle", "b"), aim("pistol", "bh")]), traced: None, teleport: None };
        // Every attack hits, every save fails, morale passes: run the activation to its end under the given answers.
        let run = |answers: &[(&str, &str)]| {
            let (mut faces, choices) = (Vec::<Vec<u8>>::new(), std::cell::RefCell::new(Vec::new()));
            loop {
                let resolve = |tray: &mut Tray| {
                    for (id, o) in answers {
                        tray.offer_wound_alloc((*id).into(), Some(o.split(',').map(|s| s[5..].parse().unwrap()).collect()));
                    }
                    let out = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(0), tray);
                    *choices.borrow_mut() = tray.feed().unwrap().wound_choices.clone();
                    out
                };
                match step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice())) {
                    Step::NeedRoll { faces: n, kind, .. } => faces.push(vec![if kind == "defense" { 1 } else { 6 }; n]),
                    Step::Done(Ok((state, _)), ..) => return (state, choices.take()),
                    other => panic!("{other:?}"),
                }
            }
        };
        // Both groups: three wounds kill slot 1, the fourth wounds slot 0 - slot 0 is the survivor, one wound down.
        let (id0, id1, against) = ("wound_alloc:a:b:0", "wound_alloc:a:bh:1", "slot:1,slot:1,slot:1,slot:0");
        let (end, seen) = run(&[(id0, against), (id1, against)]);
        for u in [2, 3] {
            assert_eq!((&end.positions[u], &end.wounds[u]), (&vec![st.positions[u][0]], &vec![2]), "unit {u}");
        }
        let reached: Vec<_> = seen.iter().filter_map(|c| c.reached.as_ref().map(|r| (c.id.as_str(), r.1.clone()))).collect();
        assert_eq!(reached, vec![(id0, vec![0, 1]), (id1, vec![0, 1])]);
        // The pistol's group is group 1: an answer under index 0 is never read, so "bh" lands automatically (slot 1 survives).
        let (end, seen) = run(&[(id0, against), ("wound_alloc:a:bh:0", against)]);
        assert_eq!(end.positions[3], vec![st.positions[3][1]]);
        assert!(seen[1].reached.is_none(), "{seen:?}");
    }

    /// An answer no landing asked for - the unit has no real choice here - is refused, not dropped (RED: ignore a stale answer ->
    /// `Done`).
    #[test]
    fn a_wound_allocation_answer_nobody_asked_for_is_refused() {
        let (mut st, statics) = mixed_line();
        let plain = Kit { weapons: vec![1], equipment: 0, wounds_max: 1 };
        st.kits[2] = Rc::new(vec![plain.clone(), plain]);
        match alloc(&st, &statics, Some("slot:0")) {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains("no wound allocation is open"), "{reason}"),
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    /// No choice where nothing is chosen: one kit and no Tough, or an answer that would wipe the unit. The ask finds nothing
    /// to open and the activation just ends.
    #[test]
    fn a_wound_allocation_ask_without_a_real_choice_just_resolves() {
        let (mut st, statics) = mixed_line();
        let plain = Kit { weapons: vec![1], equipment: 0, wounds_max: 1 };
        st.kits[2] = Rc::new(vec![plain.clone(), plain]);
        assert!(matches!(alloc(&st, &statics, Some("")), ActStep::Done { .. }), "one kit, no Tough");
        let (mut st, statics) = mixed_line();
        st.wounds[2] = vec![2, 2];
        assert!(matches!(alloc(&st, &statics, Some("")), ActStep::Done { .. }), "4 wounds kill both models: nothing to choose");
        let (st, statics) = mixed_line();
        let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Choice { id: ALLOC_ID.into(), option: String::new() }];
        for faces in [vec![6; 4], vec![6; 4]] {
            t.push(Faces(faces)); // every attack hits, every save holds: no wound to allocate
        }
        let end = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true);
        assert!(matches!(end, ActStep::Done { .. }), "no unsaved wound, no choice: {end:?}");
    }

    /// O3: a unit that moved as a Rush cannot shoot (RED: drop the Rush check).
    #[test]
    fn a_rush_cannot_shoot() {        let (st, statics) = volley_line();
        let moved: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0] + 3.0 * INCHES_TO_METERS, p[1], p[2]]).collect();
        let t = [Begin, placed(moved), intent(RUSH, Some("b"))];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (2, "a rushed this activation - it cannot shoot.")),
            other => panic!("expected the O3 refusal, got {other:?}"),
        }
    }

    /// Not moving is Hold: a Rush with no placement resolves as the Hold run, die for die.
    #[test]
    fn a_rush_that_never_moved_is_the_hold_run() {
        let (st, statics) = volley_line();
        for seed in 0..20i64 {
            let (hold, hold_rolls) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let (rush, rush_rolls) = drive(&statics, &st, vec![Begin, intent(RUSH, Some("b"))], seed);
            let (ActStep::Done { state: h, .. }, ActStep::Done { state: r, .. }) = (&hold, &rush) else { panic!("seed {seed}: {hold:?} {rush:?}") };
            assert_eq!((h, &hold_rolls), (r, &rush_rolls), "seed {seed}");
        }
    }

    #[test]
    fn open_until_the_intent() {
        let (st, statics) = volley_line();
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        assert!(matches!(ask(&[Begin]), ActStep::Open));
        assert!(matches!(ask(&[intent(HOLD, None)]), ActStep::Refused { index: 0, .. }));
    }

    // ---- step 12: cancel ----

    /// The one cancel sentence (O15 (3)); `side` is the unit's player slot.
    fn cancel_line(name: &str, side: i64) -> LogLine {
        LogLine { rule: "activation_cancel", category: Category::Movement, side, text: format!("{name} cancelled its activation - back at its start."), detail: None }
    }

    /// A cancel before the first die ends the activation with exactly that line and leaves the
    /// state alone, with or without a drag or an intent in front of it (RED: cancel arm deleted ->
    /// `Refused`; cancel arm behind the resolver -> `Open`, `NeedRoll` or the O3 refusal instead).
    #[test]
    fn a_cancel_before_the_first_die_is_cancelled() {
        let (st, statics) = volley_line();
        let moved: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0] + 3.0 * INCHES_TO_METERS, p[1], p[2]]).collect();
        let before = st.clone();
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        for t in [
            vec![Begin, Cancel],
            vec![Begin, placed(moved.clone()), Cancel],
            vec![Begin, intent(HOLD, Some("b")), Cancel],
            vec![Begin, placed(moved), intent(RUSH, Some("b")), Cancel], // the O3 refusal never shows: nothing was resolved
        ] {
            let ActStep::Cancelled { lines } = ask(&t) else { panic!("{t:?}") };
            assert_eq!(lines, vec![cancel_line("a", 0)], "{t:?}");
        }
        // the other seat's unit: its own name and player slot on the line
        let ActStep::Cancelled { lines } = step_activation(&statics, &st, "b", &Terrain::default(), seams(), &[Begin, Cancel], true) else { panic!("b") };
        assert_eq!(lines, vec![cancel_line("b", 1)]);
        assert_eq!(st, before, "the caller's state is untouched");
    }

    /// After the first die a cancel stays refused with rule 4's sentence.
    #[test]
    fn a_cancel_after_the_first_die_is_refused() {
        let (st, statics) = volley_line();
        let t = [Begin, intent(HOLD, Some("b")), Faces(vec![5, 5, 5, 5]), Cancel];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (3, "cancel is not possible after the first die")),
            other => panic!("expected rule 4, got {other:?}"),
        }
    }
    /// The delta of a plain Hold+shoot names exactly the models that died: as many as the target
    /// lost, and every survivor is an untouched start position (RED: `removed = 0..n_dead`).
    #[test]
    fn the_delta_names_the_models_that_died_and_nothing_else() {
        let (st, statics) = volley_line();
        let (mut hit, mut first_alive) = (0, 0);
        for seed in 0..200i64 {
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            let d = delta_of(&st, &state);
            assert!(d.iter().all(|x| x.key == "b"), "seed {seed}: only the target changes: {d:?}");
            let lost = st.alive[2] - state.alive[2];
            let Some(b) = d.first() else {
                assert_eq!((lost, state.shaken[2]), (0, false), "seed {seed}: a changed target must have a delta");
                continue;
            };
            assert_eq!((b.removed.len() as i64, b.alive, b.shaken, b.moved, b.unknown), (lost, state.alive[2], state.shaken[2], false, false), "seed {seed}");
            for (i, p) in st.positions[2].iter().enumerate() {
                assert_eq!(b.removed.contains(&i), !state.positions[2].contains(p), "seed {seed}: slot {i}");
            }
            assert!(state.positions[2].iter().all(|p| st.positions[2].contains(p)), "seed {seed}: a survivor moved");
            (hit, first_alive) = (hit + (lost > 0) as i32, first_alive + (lost > 0 && b.removed[0] > 0) as i32);
        }
        assert!(hit > 0, "fixture must kill");
        println!("delta fixture: {hit} seeds lost a model, {first_alive} of them not slot 0 first");
    }
    /// The seeded fixture kills slot 0 first on every seed, so slot order proves little there: pin
    /// the other cases by hand (RED: `removed = 0..n_dead` fails the slot-1 case).
    #[test]
    fn the_delta_tells_a_removal_from_a_move() {
        let (st, _) = volley_line();
        let one = |f: &dyn Fn(&mut State)| {
            let mut after = st.clone();
            f(&mut after);
            delta_of(&st, &after)
        };
        let shift = |p: &mut [f64; 3]| p[0] += 3.0 * INCHES_TO_METERS;
        assert_eq!(one(&|_| {}), vec![]);
        for dead in 0..2 {
            let d = one(&|s| (s.positions[2].remove(dead), s.alive[2] -= 1).1);
            assert_eq!(d.len(), 1);
            assert_eq!((d[0].key.as_str(), &d[0].removed[..], d[0].alive, d[0].moved, d[0].unknown), ("b", &[dead][..], 1, false, false));
        }
        let d = one(&|s| s.positions[0].iter_mut().for_each(shift));
        assert_eq!((d[0].key.as_str(), d[0].removed.len(), d[0].moved, d[0].unknown), ("a", 0, true, false));
        let d = one(&|s| (shift(&mut s.positions[2][0]), s.positions[2].remove(1), s.alive[2] -= 1).0);
        assert_eq!((d[0].removed.len(), d[0].moved, d[0].unknown), (0, true, true));
        assert!(one(&|s| s.moved_round[3] += 1)[0].moved);
        assert!(one(&|s| s.shaken[2] = true)[0].shaken);
    }
    /// P4.0-4d: a unit whose ONLY change is the table-owned ledger (fatigue, casts) still gets a row, and
    /// the row carries both values AFTER (RED: drop the ledger term -> no row; drop a field -> the default).
    #[test]
    fn the_delta_carries_the_ledger_a_plain_activation_cannot_change() {
        let (st, _) = volley_line();
        let one = |f: &dyn Fn(&mut State)| {
            let mut after = st.clone();
            f(&mut after);
            delta_of(&st, &after)
        };
        assert_eq!(one(&|_| {}), vec![], "no change, no row");
        let d = one(&|s| {
            s.fatigued[2] = true;
            s.casts[2] = 3;
        });
        assert_eq!(d.len(), 1);
        assert_eq!((d[0].key.as_str(), d[0].fatigued, d[0].casts), ("b", true, 3));
        assert_eq!((d[0].shaken, d[0].moved, d[0].removed.len()), (false, false, 0), "no board news");
    }
    /// P4.0-4e: a unit whose only change is a round stamp gets a row carrying all twelve, AFTER; a core-resolved
    /// volley's rows carry them too (RED: drop the stamp term -> no row; drop a pair -> the count is 11).
    #[test]
    fn the_delta_carries_the_round_stamps() {
        let (st, statics) = volley_line();
        let mut after = st.clone();
        after.spot_round[2] = 4;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].stamps.len(), 12);
        assert!(d[0].stamps.contains(&("spot_round", 4)));
        assert!(d[0].stamps.contains(&("moved_round", st.moved_round[2])));
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(delta_of(&st, &state).iter().all(|x| x.stamps.len() == 12), "a core row carries the stamps");
    }
    /// P4.0-4g: a core-resolved Versatile volley carries the latched pick in its delta (the int mode the table's
    /// `versatile_pick` Dictionary is built from). RED: drop `versatile_pick_mode` from the push -> 0, no pick.
    #[test]
    fn a_core_versatile_volley_carries_the_pick_mode() {
        let (st, mut statics) = volley_line();
        statics[0].shoot[0].versatile_attack = true;
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(matches!(state.versatile_pick_mode[0], 1 | 2), "the core picked: {:?}", state.versatile_pick_mode);
        assert_eq!(state.versatile_pick_round[0], state.round);
        assert_eq!(delta_of(&st, &state)[0].versatile_pick_mode, state.versatile_pick_mode[0], "the delta carries the pick");
    }
    /// P4.0-4f: a unit whose only change is a marker pool gets a row carrying all four, AFTER; a core-resolved
    /// volley's rows carry them too (RED: drop the pool term -> no row; drop a pair -> the count is 3).
    #[test]
    fn the_delta_carries_the_marker_pools() {
        let (st, statics) = volley_line();
        let mut after = st.clone();
        after.tag_markers[2] = 2;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].pools.len(), 4);
        assert!(d[0].pools.contains(&("tag_markers", 2)));
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(delta_of(&st, &state).iter().all(|x| x.pools.len() == 4), "a core row carries the pools");
    }

    /// P4.D-38a: a unit whose only change is a spent feat gets a row naming the feat; a latch already spent in `before` is no news.
    /// RED: drop the `feats_used` term from the change test -> no row; drop the field from the push -> an empty list.
    #[test]
    fn the_delta_carries_the_spent_feats() {
        let (st, _) = volley_line();
        let mut after = st.clone();
        std::rc::Rc::make_mut(&mut after.feats_used)[2].push("Protection Feat".to_string());
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1, "a spent feat is a change: {d:?}");
        assert_eq!(d[0].feats_used, vec!["Protection Feat".to_string()]);
        assert!(delta_of(&st, &st).is_empty(), "no spend, no row");
        let again = delta_of(&after, &after);
        assert!(again.is_empty(), "a latch that was already spent is no news: {again:?}");
    }

    /// C-11: a unit whose only change is a spent Limited weapon / Storm Attack / Precision latch gets a row naming each; a name
    /// already spent in `before` is no news. RED: drop a term from the change test -> no row; drop a field from the push -> [].
    #[test]
    fn the_delta_carries_the_spent_once_lists() {
        let (st, _) = volley_line();
        for (field, set) in [("limited_used", 0), ("storm_used", 1), ("precision_used", 2)] {
            let mut after = st.clone();
            let list = match set {
                0 => &mut after.limited_used,
                1 => &mut after.storm_used,
                _ => &mut after.precision_used,
            };
            std::rc::Rc::make_mut(list)[2].push("Spent Rule".to_string());
            let d = delta_of(&st, &after);
            assert_eq!(d.len(), 1, "{field}: a spend is a change: {d:?}");
            let named = [&d[0].limited_used, &d[0].storm_used, &d[0].precision_used];
            assert_eq!(named[set], &vec!["Spent Rule".to_string()], "{field}");
            assert_eq!(named.iter().map(|l| l.len()).sum::<usize>(), 1, "{field}: only its own list names it");
            assert!(delta_of(&after, &after).is_empty(), "{field}: already spent is no news");
        }
    }
    /// C-11: a core-resolved volley of a Limited weapon spends it in the core's state and its delta says so (the table path
    /// writes it through `mark_limited_used`, a core door must land it). RED: drop `limited_used` from the push -> [].
    #[test]
    fn a_core_limited_volley_carries_its_spend() {
        let (st, mut statics) = volley_line();
        statics[0].shoot[0].limited = true;
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert_eq!(state.limited_used[0], vec!["rifle".to_string()], "the core spent it");
        let d = delta_of(&st, &state);
        assert_eq!(d.iter().find(|x| x.key == "a").map(|x| x.limited_used.clone()), Some(vec!["rifle".to_string()]), "{d:?}");
    }

    /// C-13: a unit whose only change is its Growth marker count gets a row carrying the count AFTER; a core volley that fully
    /// destroys a target spends the kill into the shooter's counter and the row says so (the table's `_solo_growth_on_kill` did not
    /// run on that path). RED: drop the term from the change test -> no row; drop the field from the push -> 0.
    #[test]
    fn the_delta_carries_the_growth_markers() {
        let (st, mut statics) = volley_line();
        let mut after = st.clone();
        after.growth_markers[2] = 3;
        let d = delta_of(&st, &after);
        assert_eq!((d.len(), d[0].growth_markers), (1, 3), "{d:?}");
        assert!(delta_of(&st, &st).is_empty());
        statics[0].growth = vec![crate::unit::GrowthRule { name: "Frenzy".into(), on_kill: true, max_markers: 2, ..Default::default() }];
        let mut st = st;
        (st.wounds[2], statics[2].wounds_max, statics[2].ctx.tough) = (vec![1, 1], vec![1, 1], 1);
        let mut kills = 0;
        for seed in 0..40i64 {
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            if state.alive[2] == 0 {
                kills += 1;
                assert_eq!(state.growth_markers[0], 1, "seed {seed}: the kill banks a marker");
                assert_eq!(delta_of(&st, &state).iter().find(|x| x.key == "a").map(|x| x.growth_markers), Some(1), "seed {seed}");
            }
        }
        assert!(kills > 0, "no seed destroyed the target: the volley proves nothing");
    }

    // ---- step 14: allowance and move check ----

    use crate::state::{Bands, Roster};
    use std::rc::Rc;

    /// `four_unit_line` with its roster indexed; every unit reads the one static "Squad". Unit "a"
    /// is one model at the origin.
    fn squad_line() -> (State, Vec<UnitStatic>) {
        let mut st = crate::sim::tests::four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
        (st, vec![UnitStatic { name: "Squad".into(), ..Default::default() }])
    }

    /// Unit "a"'s one model dropped `d` inches east of its start.
    fn east(d: f64) -> Vec<[f64; 3]> {
        vec![[d * INCHES_TO_METERS, 0.0, 0.0]]
    }

    fn check(st: &State, statics: &[UnitStatic], mode: i64, placed: Vec<[f64; 3]>, enforce: bool) -> Check {
        check_move(statics, st, 0, seams(), &Terrain::default(), &Drop { mode, placed, ..Default::default() }, enforce)
    }

    fn refusal(reason: &str) -> Check {
        Check::Refused { reason: reason.to_string() }
    }

    const OK: Check = Check::Ok { lines: Vec::new() };

    #[test]
    fn a_plain_unit_s_allowance_is_its_printed_band() {
        let (st, statics) = squad_line();
        let want = Allowance { advance: 6.0, rush: 12.0, charge: 12.0, widened_by: vec![] };
        assert_eq!(allowance(&statics, &st, 0, seams(), &Terrain::default()), want);
    }

    /// Each model's horizontal straight line against the declared mode's allowance, refused with
    /// the O3 sentence when enforced (RED: drop the distance check -> 6.2" Advance and 12.2" Rush Ok).
    #[test]
    fn an_enforced_move_past_the_allowance_is_refused() {
        let (st, statics) = squad_line();
        let go = |mode, placed| check(&st, &statics, mode, placed, true);
        assert_eq!(go(ADVANCE, east(5.9)), OK);
        assert_eq!(go(ADVANCE, east(6.009)), OK, "inside the 0.01\" float noise");
        assert_eq!(go(ADVANCE, east(6.2)), refusal("Squad: a model moved 6.2\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(RUSH, east(6.2)), OK);
        assert_eq!(go(RUSH, east(12.2)), refusal("Squad: a model moved 12.2\" - the Rush allowance is 12.0\"."));
        assert_eq!(go(CHARGE, east(12.2)), refusal("Squad: a model moved 12.2\" - the Charge allowance is 12.0\"."));
        assert_eq!(go(ADVANCE, vec![[0.0, 9.0 * INCHES_TO_METERS, 0.0]]), OK, "height is not horizontal");
        assert_eq!(go(HOLD, east(1.0)), refusal("movement mode not declared"));
        assert_eq!(go(ADVANCE, vec![]), refusal("placement does not match the unit's models"));
    }

    /// Enforce off: the drop stands and exactly one line names the overrun (O3 verbatim).
    #[test]
    fn an_overrun_without_enforce_is_accepted_with_one_line() {
        let (st, statics) = squad_line();
        let text = "Squad: a model moved 6.2\" - the Advance allowance is 6.0\".".to_string();
        let line = LogLine { rule: "move_overrun", category: Category::Movement, side: 0, text, detail: None };
        assert_eq!(check(&st, &statics, ADVANCE, east(6.2), false), Check::Ok { lines: vec![line] });
    }

    /// Fast rides the printed band (8"/16", step 13's fixture), so it names no rule.
    #[test]
    fn a_fast_unit_moves_its_wider_band() {
        let (mut st, statics) = squad_line();
        st.bands[0] = Bands { advance: 8.0, rush: 16.0, charge: None };
        let want = Allowance { advance: 8.0, rush: 16.0, charge: 16.0, widened_by: vec![] };
        assert_eq!(allowance(&statics, &st, 0, seams(), &Terrain::default()), want);
        assert_eq!(check(&st, &statics, ADVANCE, east(7.9), true), OK);
    }

    /// A live Great Musician row (the `ev_move_grants.rs` row with `move_mod` 1) is +1" over the
    /// printed band, and the overrun line names it (RED: read `live_bands_of` -> a buff row is no
    /// grant, the no-grants shortcut answers the printed 6").
    #[test]
    fn a_great_musician_row_widens_the_allowance() {
        let (mut st, statics) = squad_line();
        st.buffs[0].push(crate::mods::LiveMod { hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 1, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: false, name: Rc::from("Great Musician") });
        let a = allowance(&statics, &st, 0, seams(), &Terrain::default());
        assert_eq!((a.advance, a.rush, &a.widened_by[..]), (7.0, 13.0, &["Great Musician".to_string()][..]));
        assert_eq!(check(&st, &statics, ADVANCE, east(6.9), true), OK);
        let Check::Ok { lines } = check(&st, &statics, ADVANCE, east(7.2), false) else { panic!("enforce off accepts") };
        assert_eq!(lines.len(), 1);
        assert_eq!((lines[0].text.as_str(), lines[0].detail.as_deref()), ("Squad: a model moved 7.2\" - the Advance allowance is 7.0\".", Some("Great Musician")));
    }

    /// A trail in world XZ metres from inch points.
    fn trail(points: &[[f64; 2]]) -> Vec<[f64; 2]> {
        points.iter().map(|p| [p[0] * INCHES_TO_METERS, p[1] * INCHES_TO_METERS]).collect()
    }

    /// With a trail of 2+ points the check measures the walked path, which must run from the
    /// model's start to its placed position (RED: measure the chord when a trail exists -> the
    /// 4"+4" walk, chord 5.66", turns Ok; skip the start check -> the 1"-off trail, 5.1" long, Ok).
    #[test]
    fn the_check_measures_the_walked_path() {
        let (st, statics) = squad_line();
        let go = |placed: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>>| {
            check_move(&statics, &st, 0, seams(), &Terrain::default(), &Drop { mode: ADVANCE, placed, trails }, true)
        };
        let corner = vec![[4.0 * INCHES_TO_METERS, 0.0, 4.0 * INCHES_TO_METERS]];
        assert_eq!(go(corner.clone(), vec![trail(&[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]])]), refusal("Squad: a model moved 8.0\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(corner.clone(), vec![]), OK, "no trail: the chord, 5.66\"");
        assert_eq!(go(corner, vec![trail(&[[4.0, 4.0]])]), OK, "one point is no path: the chord");
        assert_eq!(go(east(5.9), vec![trail(&[[0.0, 0.0], [5.9, 0.0]])]), OK);
        assert_eq!(go(east(6.2), vec![]), refusal("Squad: a model moved 6.2\" - the Advance allowance is 6.0\"."));
        let mismatch = refusal("trail does not match the placed model");
        assert_eq!(go(east(5.0), vec![trail(&[[0.0, 1.0], [5.0, 0.0]])]), mismatch, "starts 1\" off the start");
        assert_eq!(go(east(5.0), vec![trail(&[[0.0, 0.0], [4.0, 0.0]])]), mismatch, "ends 1\" short of the placement");
    }

    /// `mv::step`'s climb board: one long container, x 3..6", z -18..18", on a 6x4 ft table; its two
    /// long edges are 2.5" climbs from epoch 73, priced from epoch 74.
    fn container_board() -> Terrain {
        use crate::terrain::{CellParams, Obb, PlainTerrain};
        let e = |ax: f64, az: f64, bx: f64, bz: f64| [[ax * INCHES_TO_METERS, az * INCHES_TO_METERS], [bx * INCHES_TO_METERS, bz * INCHES_TO_METERS]];
        Terrain::build(&PlainTerrain {
            cells: (9..=20).map(|j| [16.0, j as f64, crate::terrain::CONTAINER as f64]).collect(),
            sandbox: Vec::<Obb>::new(),
            pieces: Vec::new(),
            containers: Vec::new(),
            walls: vec![e(3.0, -18.0, 6.0, -18.0), e(6.0, -18.0, 6.0, 18.0), e(6.0, 18.0, 3.0, 18.0), e(3.0, 18.0, 3.0, -18.0)],
            cell_params: CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS },
        })
    }

    /// A trail that walks 4.0" east from the origin climbs onto the container over one edge: 4.0 +
    /// 2.5 = 6.5" (RED: skip the climb sum -> 4.0", Advance Ok; ignore Flying -> the Flying case
    /// refused). Epoch 73 has the ledge but does not price it, as for the AI.
    #[test]
    fn check_pays_the_climb() {
        let (mut st, statics) = squad_line();
        let t = container_board();
        let go = |st: &State, mode, epoch| {
            let drop = Drop { mode, placed: east(4.0), trails: vec![trail(&[[0.0, 0.0], [4.0, 0.0]])] };
            check_move(&statics, st, 0, Seams { rules_epoch: epoch, ..seams() }, &t, &drop, true)
        };
        assert_eq!(go(&st, ADVANCE, 75), refusal("Squad: a model moved 6.5\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(&st, RUSH, 75), OK);
        assert_eq!(go(&st, ADVANCE, 73), OK, "epoch 73: the ledge is not priced");
        let mut p = st.profiles.list[0].clone();
        p.special_rules.push("Flying".into());
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
        assert_eq!(go(&st, ADVANCE, 75), OK, "Flying climbs nothing");
    }

    /// `sim::tests::forest_bar_board`: a 72" x 48" board with Difficult forest at x 3..6", z -3..3".
    fn forest_bar_board() -> Terrain {
        use crate::terrain::{CellParams, PlainTerrain, FOREST};
        let cells = vec![[16.0, 14.0, FOREST as f64], [16.0, 15.0, FOREST as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params })
    }

    /// RUSH: model A's trail clips the forest, so EVERY model is capped at 6" and B's 8" in the open
    /// is refused (RED: cap only the model whose trail crosses -> B's 8" passes; drop the Strider
    /// exemption -> the Strider case refused). A trail that stops short of the forest caps nothing.
    #[test]
    fn check_difficult_caps_every_model() {
        let (mut st, statics) = squad_line();
        st.positions[0] = vec![[0.0; 3], [0.0, 0.0, 6.0 * INCHES_TO_METERS]];
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS; 2];
        let t = forest_bar_board();
        let go = |st: &State, a: f64, b: f64, enforce| {
            let placed = vec![[a * INCHES_TO_METERS, 0.0, 0.0], [b * INCHES_TO_METERS, 0.0, 6.0 * INCHES_TO_METERS]];
            let trails = vec![trail(&[[0.0, 0.0], [a, 0.0]]), trail(&[[0.0, 6.0], [b, 6.0]])];
            check_move(&statics, st, 0, seams(), &t, &Drop { mode: RUSH, placed, trails }, enforce)
        };
        let over = "Squad: a model moved 8.0\" - the Rush allowance is 6.0\".";
        assert_eq!(go(&st, 5.0, 8.0, true), refusal(over));
        assert_eq!(go(&st, 5.9, 5.9, true), OK);
        assert_eq!(go(&st, 1.5, 8.0, true), OK, "A stops short of the forest: no cap");
        let Check::Ok { lines } = go(&st, 5.0, 8.0, false) else { panic!("enforce off accepts") };
        assert_eq!((lines.len(), lines[0].text.as_str(), lines[0].detail.as_deref()), (1, over, Some("Difficult terrain")));
        let mut debuffed = st.clone();
        debuffed.buffs[0].push(crate::mods::LiveMod { hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 0, grants_rule: Rc::from("Difficult Terrain"), scope: Rc::from(""), attackers: false, once: false, name: Rc::from("Debuff") });
        assert_eq!(go(&debuffed, 1.5, 8.0, true), refusal(over), "the carried debuff caps without forest");
        let mut p = st.profiles.list[0].clone();
        p.special_rules.push("Strider".into());
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
        assert_eq!(go(&st, 5.0, 8.0, true), OK, "Strider ignores Difficult");
    }

    /// The last `Placed`'s walked paths reach the move check: a 4"+4" walk (chord 5.66") is refused
    /// at that `Placed` (RED: build the check's `Drop` without them -> the chord passes, `Done`).
    #[test]
    fn step_activation_checks_the_last_placement_s_trails() {
        let (st, statics) = squad_line();
        let walk = Input::Placed { at: vec![[4.0 * INCHES_TO_METERS, 0.0, 4.0 * INCHES_TO_METERS]], trails: vec![trail(&[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]])] };
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &[Begin, walk, intent(ADVANCE, None)], true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (1, "Squad: a model moved 8.0\" - the Advance allowance is 6.0\".")),
            other => panic!("expected the walked-path refusal, got {other:?}"),
        }
    }

    /// The activation checks its last placement: an enforced overrun is refused at that `Placed`
    /// (RED: skip the check in `step_activation` -> the moving shot resolves on to the resolver's
    /// `Refused { index: 3, "MovedShootLos" }`, this fixture carries no LOS). Without a shot, enforce
    /// off resolves with the overrun line first, and a move inside the band is the same either way.
    #[test]
    fn step_activation_checks_the_last_placement() {
        let (st, statics) = squad_line();
        let ask = |d: f64, shoot, enforce| step_activation(&statics, &st, "a", &Terrain::default(), seams(), &[Begin, placed(east(d)), intent(ADVANCE, shoot)], enforce);
        match ask(6.2, Some("b"), true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (1, "Squad: a model moved 6.2\" - the Advance allowance is 6.0\".")),
            other => panic!("expected the overrun refusal, got {other:?}"),
        }
        let r = ask(6.2, None, false);
        let ActStep::Done { lines, .. } = r else { panic!("enforce off resolves: {r:?}") };
        assert_eq!(lines.iter().filter(|l| l.rule == "move_overrun").count(), 1);
        assert_eq!(lines[0].rule, "move_overrun");
        let (ActStep::Done { state: a, lines: la, .. }, ActStep::Done { state: b, lines: lb, .. }) = (ask(5.9, None, true), ask(5.9, None, false)) else { panic!("5.9\" resolves") };
        assert!(la.iter().all(|l| l.rule != "move_overrun"));
        assert_eq!((a, la), (b, lb));
    }

    /// R2: "a" and "b" both named "Riflemen" (a mirror match). "a" stands in Dangerous terrain (x 3..6") with two
    /// one-wound models, holds and shoots "b"; its test kills one, so after "b"'s saves and morale the activation ends
    /// with "a"'s OWN morale test. Every roll names its unit by roster key (RED: the first unit carrying the name ->
    /// "a" owns "b"'s dice; morale and saves by kind to the target -> "b" owns "a"'s last die; no replay -> "").
    #[test]
    fn every_roll_names_its_unit_by_key_when_two_units_share_a_name() {
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let (mut st, mut statics) = volley_line();
        (statics[0].name, statics[2].name) = ("Riflemen".into(), "Riflemen".into());
        st.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0], [5.0 * INCHES_TO_METERS, 0.0, 0.0]];
        (st.wounds[0], st.alive[0]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS / 2.0; 2];
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params });
        let seams = Seams { dangerous_end_morale: true, ..seams() };
        let (mut t, mut asked) = (vec![Begin, intent(HOLD, Some("b"))], Vec::new());
        while let ActStep::NeedRoll { faces, kind, owner, owner_key, .. } = step_activation(&statics, &st, "a", &board, seams, &t, true) {
            assert_eq!(owner, "Riflemen", "the label stays the name");
            asked.push((kind, owner_key));
            // the Dangerous test kills one of "a", every hit lands, every save fails, both morale tests pass
            t.push(Faces(match asked.len() { 1 => vec![1, 6], 3 => vec![1; faces], _ => vec![6; faces] }));
            assert!(asked.len() < 8, "{asked:?}");
        }
        let want = [("attack", "a"), ("attack", "a"), ("defense", "b"), ("morale", "b"), ("morale", "a")];
        assert_eq!(asked, want.map(|(k, o)| (k, o.to_string())));
    }

    /// P4.0-9: the same duplicate name without the Dangerous detour. Two units are both "Riflemen"; "a" holds and
    /// shoots "b". Every asked roll names its owner by roster key per step: the attack die is the shooter's ("a"), the
    /// saves and the morale die the target's ("b"). The step answers from the draw's stamped unit, never a second
    /// resolve — the keys pin both readings. (RED: name-only owner gives "a" for the saves; first named unit too.)
    #[test]
    fn a_duplicate_name_keeps_the_attack_with_the_shooter_and_the_saves_with_the_target() {
        let (st, mut statics) = volley_line();
        (statics[0].name, statics[2].name) = ("Riflemen".into(), "Riflemen".into());
        let (mut t, mut asked) = (vec![Begin, intent(HOLD, Some("b"))], Vec::new());
        while let ActStep::NeedRoll { faces, kind, owner, owner_key, .. } =
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        {
            assert_eq!(owner, "Riflemen", "the label stays the name");
            asked.push((kind, owner_key));
            t.push(Faces(match kind { "attack" => vec![6; faces], "defense" => vec![1; faces], _ => vec![6; faces] }));
            assert!(asked.len() < 8, "{asked:?}");
        }
        let want = [("attack", "a"), ("defense", "b"), ("morale", "b")];
        assert_eq!(asked, want.map(|(k, o)| (k, o.to_string())));
    }

    /// R3: a model that moved without a 2+ point trail is checked as its straight segment [start, end]: a trail-less
    /// (or one-point) 4" drop onto the container pays the 2.5" climb (6.5" > the 6" Advance), and a trail-less 8" Rush
    /// across the forest strip is capped at 6" (RED: the bare chord, 4.0" and no crossing -> both accepted). Open ground
    /// and a model that stayed are unchanged.
    #[test]
    fn a_trailless_drop_is_checked_along_its_straight_line() {
        let (st, statics) = squad_line();
        let go = |t: &Terrain, mode, placed, trails| check_move(&statics, &st, 0, seams(), t, &Drop { mode, placed, trails }, true);
        let climb = refusal("Squad: a model moved 6.5\" - the Advance allowance is 6.0\".");
        assert_eq!(go(&container_board(), ADVANCE, east(4.0), vec![]), climb);
        assert_eq!(go(&container_board(), ADVANCE, east(4.0), vec![trail(&[[0.0, 0.0]])]), climb, "one point is no trail");
        assert_eq!(go(&forest_bar_board(), RUSH, east(8.0), vec![]), refusal("Squad: a model moved 8.0\" - the Rush allowance is 6.0\"."));
        assert_eq!(go(&Terrain::default(), ADVANCE, east(5.9), vec![]), OK, "open ground: the straight line");
        assert_eq!(go(&forest_bar_board(), RUSH, east(0.05), vec![]), OK, "a model that stayed crosses nothing");
    }
}
