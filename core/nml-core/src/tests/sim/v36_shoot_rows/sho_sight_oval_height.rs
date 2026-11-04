//! AI-G4 C-SIGHT: the table reads a model's sight height off its base size, and an OVAL base feeds the MEAN of
//! its two axes into the height table (`_solo_model_base_mm`). The core read the circumscribing radius instead and
//! so stood an oval cavalry model about 1.3" taller than the table does. From `EPOCH_73_V36` the volley's sight
//! (blockers and the two eyes) takes the height from the profile's `base_w_mm` / `base_d_mm`; below it nothing moves.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::state::{Profile, Profiles, Roster};

const ROUND: &str = r#"{"unit_id": "u", "name": "u"}"#;
const OVAL_60X35: &str = r#"{"unit_id": "u", "name": "u", "base_shape": "oval", "base_w_mm": 60, "base_d_mm": 35}"#;

/// The recorded (circumscribing) radius of a 60 x 35 mm oval, in metres: 1.37".
fn oval_radius_m() -> f64 {
    (60.0f64 * 60.0 + 35.0 * 35.0).sqrt() / 2000.0
}

/// Shooter `a` (two models at x = 0) and enemy `b` (three models at x = 12", 50.8 mm round, eye 2.08") with a
/// FRIENDLY single-model unit `ah` standing between them at x = 6". Nobody is attached, so `ah` blocks.
/// `shooter` / `blocker` are (profile json, recorded radius in metres).
fn sight_line(shooter: (&str, f64), blocker: (&str, f64)) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    let mk = |json: &str| -> Profile { serde_json::from_str(json).unwrap() };
    st.profiles = Rc::new(Profiles { list: vec![mk(shooter.0), mk(blocker.0), mk(ROUND)], index: HashMap::new() });
    st.roster = Rc::new(Roster {
        keys: st.roster.keys.clone(),
        index: st.roster.index.clone(),
        profile: vec![0, 1, 2, 2],
    });
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions[1] = vec![[6.0 * IN2M, 0.0, 0.0]];
    st.radii = Rc::new(vec![vec![shooter.1; 2], vec![blocker.1], vec![IN2M; 3], vec![]]);
    statics[0].shoot[0].attacks = 2; // the unit's merged total: one die per model
    (st, statics)
}

fn volley(st: &State, statics: &[UnitStatic], epoch: u32) -> ShootResult {
    let action = Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let seams = Seams { sighting: true, rules_epoch: epoch, ..Seams::default() };
    resolve_stochastic_tray_on_board(
        statics, st, &action, &crate::terrain::Terrain::default(), seams,
        &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(11),
    )
    .unwrap()
    .1
}

fn attack_dice(shot: &ShootResult) -> i64 {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "a").map(|r| r.count).sum()
}

/// RED on main: a friendly 60 x 35 oval stands between two 2.08" eyes. The table gives it the mean axis (47.5 mm,
/// 1.88" tall), so the line passes over it and both models fire; the core made it 3.24" tall and rolled nothing.
#[test]
fn a_line_passes_over_an_oval_blocker_the_table_reads_as_short_at_epoch_73() {
    let (st, statics) = sight_line((ROUND, IN2M), (OVAL_60X35, oval_radius_m()));
    let dice = attack_dice(&volley(&st, &statics, EPOCH_73_V36));
    assert_eq!(dice, 2, "both rifles fire over the 1.88\" oval blocker (RED on main: 0)");
}

/// Control: epoch 72 keeps the circumscribed-radius height, so the same board is still blocked.
#[test]
fn an_oval_blocker_keeps_its_circumscribed_height_at_epoch_72() {
    let (st, statics) = sight_line((ROUND, IN2M), (OVAL_60X35, oval_radius_m()));
    assert_eq!(attack_dice(&volley(&st, &statics, EPOCH_72_PLAYTEST_RULES)), 0, "epoch 72 replays the old height");
}

/// Control (passes before and after): a ROUND 69.5 mm blocker of the same radius is 3.24" tall in both readings and
/// blocks the 2.08" line - the round path is the number it always was, and the board does block.
#[test]
fn a_round_blocker_of_the_same_radius_still_blocks_at_epoch_73() {
    let (st, statics) = sight_line((ROUND, IN2M), (ROUND, oval_radius_m()));
    assert_eq!(attack_dice(&volley(&st, &statics, EPOCH_73_V36)), 0, "a 3.24\" round blocker hides the target");
}

/// RED on main: the SHOOTER is the oval. Its own eye is 1.88" (mean axis), not 3.24" (circumscribed), so the line
/// to the 2.08" target dips under a 54 mm round blocker (2.4") and the volley is refused; main's high eye saw over it.
#[test]
fn an_oval_shooters_eye_is_its_mean_axis_height_at_epoch_73() {
    let (st, statics) = sight_line((OVAL_60X35, oval_radius_m()), (ROUND, 0.027));
    assert_eq!(attack_dice(&volley(&st, &statics, EPOCH_73_V36)), 0, "the low oval eye is blocked (RED on main: 2)");
    assert_eq!(attack_dice(&volley(&st, &statics, EPOCH_72_PLAYTEST_RULES)), 2, "epoch 72 keeps the 3.24\" eye");
}
