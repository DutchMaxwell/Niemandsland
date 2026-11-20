//! PLAN_COVER_36 step 6: the played volley reads cover from sight blockers (`sight::screen_of`) from
//! `PENDING_EPOCH_COVER_SCREEN`. The buff line with the target's hero detached and standing 2" in front of the target as a
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

fn volley(epoch: u32) -> ShootResult {
    let (st, statics) = screened_line();
    let seams = Seams { sighting: true, rules_epoch: epoch, ..Default::default() };
    let terrain = crate::terrain::Terrain::default();
    let (mut tray, mut rng) = (Tray::seeded(11), crate::rng::GodotRng::new(0));
    resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray).unwrap().1
}

const SCREEN: &str = "Cover: b is behind a sight blocker from a (3 of 3 models) - +1 Defense";
const COVER: &str = "b is in cover: +1 Defense (saves on 3+)";

/// At 95 the target behind the third unit saves one better and the log says why; at 94 the same volley has no cover at all
/// (records stamped 94 replay byte-exact). RED before the seam: `screened` was never stamped, no line, no +1.
#[test]
fn a_unit_behind_another_unit_saves_one_better_from_95_only() {
    let at95 = volley(crate::acts::PENDING_EPOCH_COVER_SCREEN);
    assert!(at95.log.iter().any(|l| l == SCREEN), "the screen line: {:?}", at95.log);
    assert!(at95.log.iter().any(|l| l == COVER), "the save used the +1: {:?}", at95.log);
    let saves = |r: &ShootResult| r.rolls.iter().filter(|r| r.kind == "defense").map(|r| r.target).collect::<Vec<_>>();
    assert!(!saves(&at95).is_empty() && saves(&at95).iter().all(|&t| t == 3), "Defense 4+ saves on 3+: {:?}", at95.rolls);
    let at94 = volley(94);
    assert!(at94.log.iter().all(|l| !l.contains("cover") && !l.contains("Cover")), "no cover at 94: {:?}", at94.log);
    assert!(!saves(&at94).is_empty() && saves(&at94).iter().all(|&t| t == 4), "no +1 at 94: {:?}", at94.rolls);
}
