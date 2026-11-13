//! One-core P3: one activation as the ordered inputs the table sends, the
//! answers the core gives, the order rules on the inputs, and
//! `step_activation`, which resolves the activation through the step API.

use crate::dice::Tray;
use crate::gate::INCHES_TO_METERS;
use crate::io::{Action, Seams};
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
    /// The declared action (`sim::HOLD` ..); `shoot` is `Some` when it shoots.
    Intent { kind: i64, shoot: Option<String> },
    /// One thrown face group, in the order the core asked for them.
    Faces(Vec<u8>),
    /// The unit's model positions after a drag (`at`) and each model's walked path this
    /// activation (world XZ metres, in the order of `at`; empty = none).
    Placed { at: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>> },
    /// "Cancel", allowed until the first die of the activation.
    Cancel,
}

/// The core's answer to the inputs so far. `Done` and `Cancelled` are the
/// two terminal states of an activation in the core.
#[derive(Debug)]
// One per step call, never stored in bulk: `State` by value (the plan's API) costs nothing here.
#[allow(clippy::large_enum_variant)]
pub enum ActStep {
    /// Roll `faces` dice and send them as the next `Faces`; `lines` and
    /// `landings` are only those before the starved draw.
    NeedRoll { index: usize, faces: usize, kind: &'static str, count: i64, target: i64, owner: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    /// The activation is open and waits for the next input.
    Open,
    /// Input `index` breaks an order rule; `reason` is the sentence the player sees.
    Refused { index: usize, reason: String },
    /// The activation was cancelled before its first die; the state is untouched
    /// and the table puts the models back. `lines` is the one cancel sentence.
    Cancelled { lines: Vec<LogLine> },
    Done { state: State, lines: Vec<LogLine>, landings: Vec<Landing> },
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
/// run from its start to its placed position within 0.01", plus every climb its legs pay, else its
/// horizontal straight line) within the mode's allowance (+0.01" float noise), at most 6" for every model once any
/// model's trail crosses Difficult terrain or the unit carries the Difficult debuff (not for Flying or Strider). An
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
    for (i, (a, b)) in start.iter().zip(&drop.placed).enumerate() {
        let (a, b) = ([a[0], a[2]], [b[0], b[2]]);
        let walked = match drop.trails.get(i).filter(|t| t.len() >= 2) {
            Some(t) if inch(t[0], a) > 0.01 || inch(t[t.len() - 1], b) > 0.01 => {
                return Check::Refused { reason: "trail does not match the placed model".to_string() };
            }
            Some(t) => crate::mv::step::trail_walk_in(t, &ledges).0,
            None => inch(a, b),
        };
        x = x.max(walked);
    }
    // GF p.11: Difficult terrain caps the WHOLE unit; Flying and Strider ignore it (read as `mv::step` reads them).
    let strider = state.profile(si).special_rules.iter().any(|r| r == "Strider");
    let crosses = |t: &Vec<[f64; 2]>, r: &f64| {
        let leg: Vec<[f32; 2]> = t.iter().map(|p| terrain.to_inch([p[0] as f32, 0.0, p[1] as f32])).collect();
        leg_crosses(&leg, *r, terrain, is_difficult)
    };
    let difficult = !(flying || strider)
        && (drop.trails.iter().zip(&state.radii[si]).any(|(t, r)| crosses(t, r)) || terrain_debuff_folds(statics, state, si).0);
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
        Input::Intent { kind, shoot } => Some((i, *kind, shoot.clone())),
        _ => None,
    });
    let Some((at_intent, declared, shoot)) = declared else {
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
    let action = Action { kind, unit: unit.to_string(), dest: None, shoot, charge: None, patient: false, split: None, traced: None, teleport: None };
    let faces: Vec<Vec<u8>> = t.iter().filter_map(|x| if let Input::Faces(f) = x { Some(f.clone()) } else { None }).collect();
    // The spike's non-tray seed: a plain activation never draws from it.
    let resolve = |tray: &mut Tray| {
        if let Some((p, trails)) = placed {
            tray.place(p, trails);
        }
        resolve_stochastic_tray_on_board(statics, state, &action, terrain, seams, &mut GodotRng::new(0), tray)
    };
    match step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice())) {
        Step::NeedRoll { index, faces, kind, count, target, owner, lines, landings } => ActStep::NeedRoll { index, faces, kind, count, target, owner, lines: [moved, lines].concat(), landings },
        Step::Refused { reason, .. } => ActStep::Refused { index: t.len(), reason },
        Step::Done(Ok((state, _)), lines, landings) => ActStep::Done { state, lines: [moved, lines].concat(), landings },
        Step::Done(Err(u), ..) => ActStep::Refused { index: t.len(), reason: format!("{u:?}") },
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
        if b != a || before.alive[u] != after.alive[u] || before.shaken[u] != after.shaken[u] || moved {
            out.push(UnitDelta { key: key.clone(), removed, shaken: after.shaken[u], alive: after.alive[u], moved, unknown });
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
        Input::Intent { kind, shoot: shoot.map(String::from) }
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

    /// The stepped activation equals one straight seeded run, state and roll records alike; the
    /// straight run's non-tray stream differs (seed vs 0), so a draw from it would show here too.
    #[test]
    fn a_stepped_activation_equals_the_seeded_run() {
        let (st, statics) = volley_line();
        let (mut killed, mut shaken) = (0, 0);
        for seed in 0..200i64 {
            let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
            let (want, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, rolls) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            assert_eq!((&state.alive, &state.shaken), (&want.alive, &want.shaken), "seed {seed}");
            assert_eq!(rolls, shot.rolls, "seed {seed}");
            assert_eq!(state, want, "seed {seed}");
            (killed, shaken) = (killed + (want.alive[2] < st.alive[2]) as i32, shaken + want.shaken[2] as i32);
        }
        assert!(killed > 0 && shaken > 0, "fixture must kill and shake: {killed} {shaken}");
    }

    /// O3: a unit that moved as a Rush cannot shoot (RED: drop the Rush check).
    #[test]
    fn a_rush_cannot_shoot() {
        let (st, statics) = volley_line();
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
}
