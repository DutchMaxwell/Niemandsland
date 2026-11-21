//! PLAN_COVER_36 step 6: the played volley reads cover from sight blockers (`sight::screen_of`) from
//! `EPOCH_95_PARITY_BATCH`. The buff line with the target's hero detached and standing 2" in front of the target as a
//! short third unit: the shooters see the target's heads over it, not its feet.
use super::*;

fn screened_line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, None]);
    st.positions[3] = vec![[10.0 * IN2M, 0.0, 0.0]];
    let mut radii = (*st.radii).clone();
    radii[3] = vec![0.5 * IN2M];
    st.radii = Rc::new(radii);
    st.wounds[3] = vec![1];
    st.alive[3] = 1;
    statics[0].shoot = vec![gun("Rifle", 10, 24)];
    (st, statics)
}

fn volley_said(epoch: u32) -> (ShootResult, Vec<String>) {
    let (st, statics) = screened_line();
    let seams = Seams { sighting: true, rules_epoch: epoch, ..Default::default() };
    let terrain = crate::terrain::Terrain::default();
    let (mut tray, mut rng) = (Tray::seeded(11), crate::rng::GodotRng::new(0));
    let shot = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray).unwrap().1;
    // A door's tray (supplied with the same faces) keeps the lines it is told.
    let mut door = Tray::supplied(shot.rolls.iter().map(|r| r.faces.clone()).collect());
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut door).unwrap();
    (shot, door.all_lines().into_iter().map(|l| l.text).collect())
}

fn volley(epoch: u32) -> ShootResult {
    volley_said(epoch).0
}

/// PLAN_COVER_36 step 9c: the doors write the tray's lines (#3286), so the screen line is said there too, once.
/// RED before: it stood in `ShootResult.log` only.
#[test]
fn the_door_tray_says_the_screen_line() {
    let (_, said) = volley_said(crate::acts::EPOCH_95_PARITY_BATCH);
    assert_eq!(said.iter().filter(|l| *l == SCREEN).count(), 1, "the tray says it once: {said:?}");
}

const SCREEN: &str = "Cover: b is behind a sight blocker from a (3 of 3 models) - +1 Defense";
const COVER: &str = "b is in cover: +1 Defense (saves on 3+)";

/// At 95 the target behind the third unit saves one better and the log says why; at 94 the same volley has no cover at all
/// (records stamped 94 replay byte-exact). RED before the seam: `screened` was never stamped, no line, no +1.
#[test]
fn a_unit_behind_another_unit_saves_one_better_from_95_only() {
    let at95 = volley(crate::acts::EPOCH_95_PARITY_BATCH);
    assert!(at95.log.iter().any(|l| l == SCREEN), "the screen line: {:?}", at95.log);
    assert!(at95.log.iter().any(|l| l == COVER), "the save used the +1: {:?}", at95.log);
    let saves = |r: &ShootResult| r.rolls.iter().filter(|r| r.kind == "defense").map(|r| r.target).collect::<Vec<_>>();
    assert!(!saves(&at95).is_empty() && saves(&at95).iter().all(|&t| t == 3), "Defense 4+ saves on 3+: {:?}", at95.rolls);
    let at94 = volley(94);
    assert!(at94.log.iter().all(|l| !l.contains("cover") && !l.contains("Cover")), "no cover at 94: {:?}", at94.log);
    assert!(!saves(&at94).is_empty() && saves(&at94).iter().all(|&t| t == 4), "no +1 at 94: {:?}", at94.rolls);
}

/// PLAN_COVER_36 step 8: the Takedown pick (resolved as a unit of one) is in cover when the volley's screen hides THAT model,
/// in slot order after the earlier groups landed; no screen (below 95) leaves the unit flag. Three models: the launcher
/// (Tough 2, picked first) hidden behind a wall, two in the open. RED before: `hidden` was not read, the pick had no cover.
#[test]
fn the_takedown_pick_reads_its_own_screen() {
    let mut st = four_unit_line();
    st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [7.0 * IN2M, 0.0, 0.0], [8.0 * IN2M, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![2, 1, 1], vec![0.016; 3], 3);
    let k = |w: u16, x: i64| crate::state::Kit { weapons: vec![w], equipment: 0, wounds_max: x };
    st.kits = vec![Rc::new(vec![k(1, 2), k(0, 1), k(0, 1)])];
    let hidden = [true, false, false];
    let at = |h: Option<&[bool]>, groups: &[i64]| takedown_pick_info_after(&[], &st, 0, Cover::Recorded(None), false, h, groups, None).0;
    assert!(at(Some(&hidden), &[]), "the launcher behind the wall is in cover of its own");
    assert!(!at(Some(&hidden), &[2]), "killed: the next pick stands in the open");
    assert!(!at(None, &[]), "no screen (below 95): the unit flag, no cover");
}
