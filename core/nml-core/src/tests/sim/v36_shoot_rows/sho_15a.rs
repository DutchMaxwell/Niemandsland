use super::super::*;

// SHO-15a Scourge (`EPOCH_73_V36`): every unmodified 1 the target rolls to block a Scourge hit
// counts as 2 extra wounds when the post-volley morale trigger is read, and nowhere else: nothing
// is removed. Below 73 the trigger reads the real wounds alone.

/// The buff line's shooter with an 8-shot rifle (Scourge when `scourge`) against `b`, widened to
/// five Tough(1) models: half is 2.5, so 3 or 4 left is "just above half".
fn scourge_line(scourge: bool) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    statics[0].shoot[0].attacks = 8;
    if scourge {
        statics[0].shoot[0].rules = vec!["Scourge".into()];
    }
    st.positions[2] = (0..5).map(|k| [(12.0 + 0.02 * k as f64) * IN2M, 0.0, 0.0]).collect();
    Rc::make_mut(&mut st.radii)[2] = vec![IN2M; 5];
    st.wounds[2] = vec![1; 5];
    st.alive[2] = 5;
    statics[2].model_count = 5;
    statics[2].wounds_max = vec![1; 5];
    (st, statics)
}

/// One volley on `seed`: `b`'s models left, the 1s on its save dice, whether a morale die was
/// drawn for `b` (the trigger's own roll, owner `b`) and the activation's rule log.
fn volley(scourge: bool, epoch: u32, seed: i64) -> (i64, i64, bool, Vec<String>) {
    let (st, statics) = scourge_line(scourge);
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &st, &buff_action(Some("b")), &crate::terrain::Terrain::default(),
        Seams { rules_epoch: epoch, ..Default::default() }, &mut rng, &mut tray,
    )
    .unwrap();
    let ones = shot.rolls.iter().filter(|r| r.kind == "defense")
        .flat_map(|r| r.faces.iter()).filter(|&&f| f == 1).count() as i64;
    let morale = shot.rolls.iter().any(|r| r.kind == "attack" && r.owner == "b");
    (next.alive[2], ones, morale, shot.log)
}

/// The volleys of 300 seeds that leave `b` just above half on real wounds with at least one 1 on
/// its saves; the precondition is read from each run, so a shifted dice stream cannot pass silently.
fn above_half_with_ones(scourge: bool, epoch: u32) -> Vec<(i64, i64, bool, Vec<String>)> {
    let hits: Vec<_> = (0..300)
        .map(|seed| volley(scourge, epoch, seed))
        .filter(|(alive, ones, _, _)| *alive * 2 > 5 && *ones > 0)
        .collect();
    assert!(!hits.is_empty(), "fixture: no volley left b just above half with a 1 on its saves");
    hits
}

/// NEW leg: at 73 each such volley draws the morale die (3 or 4 left minus 2 per 1 is at most
/// half) and the phantom wounds name themselves in the log.
#[test]
fn scourge_ones_tip_the_shooting_morale_test_at_epoch_73() {
    for (alive, ones, morale, log) in above_half_with_ones(true, crate::acts::EPOCH_73_V36) {
        assert!(morale, "{ones} Scourge 1s against {alive} of 5 left: the phantom wounds put b at half or less");
        assert!(log.iter().any(|l| l.starts_with("Scourge:")), "rules-must-log: no Scourge line in {log:?}");
    }
}

/// OLD leg: at 72 the same volleys draw no morale die, the real wounds leave b above half.
#[test]
fn scourge_ones_do_not_count_at_epoch_72() {
    let hits = above_half_with_ones(true, crate::acts::EPOCH_72_PLAYTEST_RULES);
    assert!(hits.iter().all(|h| !h.2), "72 reads the real wounds alone");
}

/// Control: at 73 a rifle without Scourge leaves the trigger on the real wounds.
#[test]
fn plain_ones_do_not_count_at_epoch_73() {
    let hits = above_half_with_ones(false, crate::acts::EPOCH_73_V36);
    assert!(hits.iter().all(|h| !h.2), "only the 1s against Scourge hits count");
}
