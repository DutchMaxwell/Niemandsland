//! Rules 3.6 row UX-21 tests (Dangerous dice = wounds left) for the sim module; owned by lane ux.
use super::*;

// ---- UX-21 (rules 3.6): at 73 a Dangerous terrain test rolls one die per WOUND THE WHOLE JOINED UNIT
//      HAS LEFT, not one die per model's full Tough value. Epoch 72 keeps the Tough count. ------------

/// `dangerous_line`'s unit "a" as ONE Tough(6) model that already lost four wounds (two left), standing on
/// the bar (x = 4", z = 0) where `dangerous_bar_board` marks the cells Dangerous. The joined hero is cut off
/// so the unit is the single model alone.
fn hurt_tough_six() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = dangerous_line();
    Rc::make_mut(&mut st.attached)[0].clear();
    Rc::make_mut(&mut st.attached_to)[1] = None;
    st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0]];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    st.wounds[0] = vec![2];
    st.alive[0] = 1;
    statics[0].wounds_max = vec![6];
    statics[0].model_count = 1;
    statics[0].ctx.tough = 6;
    (st, statics)
}

/// Three full-health one-wound host models plus a joined Tough(3) hero that lost one wound (two left), every
/// model standing on the bar so the whole unit is affected at either epoch.
fn host_and_hurt_hero() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = dangerous_line();
    Rc::make_mut(&mut st.attached)[0] = vec![1];
    Rc::make_mut(&mut st.attached_to)[1] = Some(0);
    st.positions[0] = vec![
        [4.0 * IN2M, 0.0, 0.0],
        [4.02 * IN2M, 0.0, 0.0],
        [4.04 * IN2M, 0.0, 0.0],
    ];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 3];
    st.wounds[0] = vec![1; 3];
    st.alive[0] = 3;
    statics[0].wounds_max = vec![1; 3];
    statics[0].model_count = 3;
    st.positions[1] = vec![[7.0 * IN2M, 0.0, 0.0]];
    st.wounds[1] = vec![2];
    st.alive[1] = 1;
    statics[1].name = "ah".into();
    statics[1].wounds_max = vec![3];
    (st, statics)
}

/// The dangerous dice of unit 0 standing where it is, on the bar board, at `epoch`.
fn standing_dice(st: &State, statics: &[UnitStatic], epoch: u32) -> (i64, crate::dice::ShootResult) {
    let t = dangerous_bar_board();
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    let mut shot = crate::dice::ShootResult::default();
    let n = dangerous_dice(statics, st, st, 0, seams, None, Cover::Board(&t), &mut shot);
    (n, shot)
}

/// The control leg: a hurt Tough(6) model still rolls its full Tough value at 72.
#[test]
fn a_hurt_tough_six_model_rolls_six_dice_at_epoch_72() {
    let (st, statics) = hurt_tough_six();
    assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_72_PLAYTEST_RULES).0, 6);
}

/// The new leg: the same model rolls only the wounds it has left at 73.
#[test]
fn a_hurt_tough_six_model_rolls_its_wounds_left_at_epoch_73() {
    let (st, statics) = hurt_tough_six();
    assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_73_V36).0, 2);
}

/// The control leg for a joined unit: at 72 the whole unit's FULL Tough values roll (host three one-wound
/// models plus the hero's Tough(3)).
#[test]
fn a_joined_hurt_hero_sums_full_tough_at_epoch_72() {
    let (st, statics) = host_and_hurt_hero();
    assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_72_PLAYTEST_RULES).0, 6);
}

/// The new leg: at 73 host and hero together roll only the wounds they have left (3 + 2).
#[test]
fn a_joined_hurt_hero_sums_wounds_left_at_epoch_73() {
    let (st, statics) = host_and_hurt_hero();
    assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_73_V36).0, 5);
}
