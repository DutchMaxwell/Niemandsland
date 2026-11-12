//! One-core P3: one activation as the ordered inputs the table sends, the
//! answers the core gives, the order rules on the inputs, and
//! `step_activation`, which resolves the activation through the step API.

use crate::dice::Tray;
use crate::gate::INCHES_TO_METERS;
use crate::io::{Action, Seams};
use crate::landing::Landing;
use crate::logline::{Category, LogLine};
use crate::rng::GodotRng;
use crate::sim::{resolve_stochastic_tray_on_board, ADVANCE, CHARGE, HOLD, REPOSITION, RUSH};
use crate::state::State;
use crate::step::{step_with, Step};
use crate::terrain::Terrain;
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
    /// The unit's model positions after a drag.
    Placed(Vec<[f64; 3]>),
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
            Input::Placed(_) if shot => Some(format!("{name} has already shot this round — it cannot move now")),
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

/// One activation through the step API: the order rules, then the declared
/// action (not moving = Hold) on the supplied faces and the LAST placement.
/// A new entry: the AI's resolver path is untouched. `NeedRoll.index` is the
/// roll's, not the transcript's; a refusal of the whole transcript is at `t.len()`.
pub fn step_activation(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input]) -> ActStep {
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
        Input::Placed(p) => Some(p.clone()),
        _ => None,
    });
    let start = at.map_or(&[][..], |i| state.positions[i].as_slice());
    let kind = effective_kind(declared, start, placed.as_deref());
    if kind == RUSH && shoot.is_some() {
        return ActStep::Refused { index: at_intent, reason: format!("{name} rushed this activation - it cannot shoot.") };
    }
    let action = Action { kind, unit: unit.to_string(), dest: None, shoot, charge: None, patient: false, split: None, traced: None, teleport: None };
    let faces: Vec<Vec<u8>> = t.iter().filter_map(|x| if let Input::Faces(f) = x { Some(f.clone()) } else { None }).collect();
    // The spike's non-tray seed: a plain activation never draws from it.
    let resolve = |tray: &mut Tray| {
        if let Some(p) = placed {
            tray.place(p);
        }
        resolve_stochastic_tray_on_board(statics, state, &action, terrain, seams, &mut GodotRng::new(0), tray)
    };
    match step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice())) {
        Step::NeedRoll { index, faces, kind, count, target, owner, lines, landings } => ActStep::NeedRoll { index, faces, kind, count, target, owner, lines, landings },
        Step::Refused { reason, .. } => ActStep::Refused { index: t.len(), reason },
        Step::Done(Ok((state, _)), lines, landings) => ActStep::Done { state, lines, landings },
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
    use Input::{Begin, Cancel, Faces, Placed};

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
        refused(&[Begin, Placed(vec![]), Begin], 2, "the activation is already started");
    }

    #[test]
    fn rule3_nothing_after_a_cancel() {
        refused(&[Begin, Cancel, Placed(vec![])], 2, "the activation is over");
    }

    #[test]
    fn rule4_cancel_only_until_the_first_die() {
        refused(&[Begin, intent(ADVANCE, None), Faces(vec![3]), Cancel], 3, "cancel is not possible after the first die");
    }

    #[test]
    fn rule5_faces_need_a_declared_action() {
        refused(&[Begin, Placed(vec![]), Faces(vec![4])], 2, "faces before the action was declared");
    }

    #[test]
    fn rule6_one_action_per_activation() {
        refused(&[Begin, intent(HOLD, None), intent(ADVANCE, None)], 2, "one action per activation");
    }

    #[test]
    fn rule7_no_move_after_the_unit_shot() {
        let t = [Begin, intent(ADVANCE, Some("Rifles")), Faces(vec![5]), Placed(vec![[0.0; 3]])];
        refused(&t, 3, "Squad has already shot this round — it cannot move now");
        assert_eq!(order_check("Squad", &[Begin, intent(ADVANCE, None), Placed(vec![])]), Ok(()));
    }

    #[test]
    fn rule8_charge_and_reposition_are_not_on_the_step_path() {
        refused(&[Begin, intent(CHARGE, None)], 1, "not on the step path yet");
        refused(&[Begin, Placed(vec![]), intent(REPOSITION, None)], 2, "not on the step path yet");
    }

    #[test]
    fn moves_before_the_shooting_intent_are_fine() {
        let t = [Begin, Placed(vec![[1.0, 0.0, 0.0]]), Placed(vec![[2.0, 0.0, 0.0]]), intent(ADVANCE, Some("Rifles"))];
        assert_eq!(order_check("Squad", &t), Ok(()));
    }

    #[test]
    fn cancel_after_a_move_is_fine() {
        assert_eq!(order_check("Squad", &[Begin, Placed(vec![[1.0, 0.0, 0.0]]), Cancel]), Ok(()));
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
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t) {
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
        let t = [Begin, Placed(moved), intent(RUSH, Some("b"))];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t) {
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
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t);
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
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t);
        for t in [
            vec![Begin, Cancel],
            vec![Begin, Placed(moved.clone()), Cancel],
            vec![Begin, intent(HOLD, Some("b")), Cancel],
            vec![Begin, Placed(moved), intent(RUSH, Some("b")), Cancel], // the O3 refusal never shows: nothing was resolved
        ] {
            let ActStep::Cancelled { lines } = ask(&t) else { panic!("{t:?}") };
            assert_eq!(lines, vec![cancel_line("a", 0)], "{t:?}");
        }
        // the other seat's unit: its own name and player slot on the line
        let ActStep::Cancelled { lines } = step_activation(&statics, &st, "b", &Terrain::default(), seams(), &[Begin, Cancel]) else { panic!("b") };
        assert_eq!(lines, vec![cancel_line("b", 1)]);
        assert_eq!(st, before, "the caller's state is untouched");
    }

    /// After the first die a cancel stays refused with rule 4's sentence.
    #[test]
    fn a_cancel_after_the_first_die_is_refused() {
        let (st, statics) = volley_line();
        let t = [Begin, intent(HOLD, Some("b")), Faces(vec![5, 5, 5, 5]), Cancel];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t) {
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
}
