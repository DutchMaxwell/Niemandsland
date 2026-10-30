//! Rules 3.6 lane ux tests for the sim module; owned by lane ux.

use super::*;

// ------------------------------- UX-19: the Hit & Run all-models gate ---

/// The refusal line a unit writes when only some of its models carry the
/// Hit & Run family (the table's twin: `SoloController.last_hit_and_run_note`).
const HNR_REFUSAL: &str = "Hit & Run: a stays put - not every model in the unit has the rule";

/// One HOLD-and-shoot activation of `buff_line`'s host "a" (its joined hero is
/// "ah"), with the Hit & Run flag on the host and/or the hero, at `epoch`.
fn hnr_shot(host: bool, hero: bool, epoch: u32) -> (State, State, ShootResult) {
    let (st, mut statics) = buff_line();
    statics[0].hit_and_run_active = host;
    statics[1].hit_and_run_active = hero;
    let terrain = crate::terrain::Terrain::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray,
    )
    .unwrap();
    (st, next, shot)
}

/// The host took the post-attack step: the once-per-round use is spent and
/// its models stand somewhere else.
fn stepped(st: &State, next: &State) -> bool {
    next.hit_and_run_round[0] == next.round && next.positions[0] != st.positions[0]
}

#[test]
fn hit_and_run_host_with_a_joined_hero_without_it_still_steps_at_epoch_72() {
    let (st, next, shot) = hnr_shot(true, false, crate::acts::EPOCH_72_PLAYTEST_RULES);
    assert!(stepped(&st, &next), "below the 3.6 epoch the host alone decides, as before");
    assert!(!shot.log.iter().any(|l| l.contains("stays put")), "{:?}", shot.log);
}

#[test]
fn hit_and_run_host_with_a_joined_hero_without_it_stays_put_and_says_why_at_epoch_73() {
    let (st, next, shot) = hnr_shot(true, false, crate::acts::EPOCH_73_V36);
    assert!(!stepped(&st, &next), "the hero lacks the rule, so the unit may not step");
    assert_ne!(next.hit_and_run_round[0], next.round, "the once-per-round use stays unspent");
    assert!(shot.log.iter().any(|l| l == HNR_REFUSAL), "rules-must-log: {:?}", shot.log);
}

#[test]
fn hit_and_run_on_the_joined_hero_alone_never_steps_and_says_why_from_epoch_73() {
    let (st, next, shot) = hnr_shot(false, true, crate::acts::EPOCH_72_PLAYTEST_RULES);
    assert!(!stepped(&st, &next), "the host's rules decide below the 3.6 epoch");
    assert!(!shot.log.iter().any(|l| l.contains("stays put")), "epoch 72 stays silent: {:?}", shot.log);
    let (st, next, shot) = hnr_shot(false, true, crate::acts::EPOCH_73_V36);
    assert!(!stepped(&st, &next), "one carrier among the models is not enough");
    assert!(shot.log.iter().any(|l| l == HNR_REFUSAL), "rules-must-log: {:?}", shot.log);
}

#[test]
fn hit_and_run_steps_when_every_model_carries_it_at_epoch_73() {
    let (st, next, shot) = hnr_shot(true, true, crate::acts::EPOCH_73_V36);
    assert!(stepped(&st, &next), "host and hero both carry it: the step stays");
    assert!(shot.log.iter().any(|l| l.contains("Hit & Run: a steps up to 3\"")), "{:?}", shot.log);
    assert!(!shot.log.iter().any(|l| l.contains("stays put")), "{:?}", shot.log);
}
