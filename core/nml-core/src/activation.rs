//! One-core P3: one activation as the ordered inputs the table sends, the
//! answers the core gives, and the order rules on the inputs. Nothing
//! resolves an activation yet.

use crate::landing::Landing;
use crate::logline::LogLine;
use crate::sim::{CHARGE, REPOSITION};
use crate::state::State;

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::{ADVANCE, HOLD};
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
}
