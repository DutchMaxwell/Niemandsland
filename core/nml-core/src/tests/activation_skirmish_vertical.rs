//! The skirmish vertical rules (3.6 Firefight / AoF: Skirmish p.15): Jumping. `super::*` is activation's own items.
use super::*;
use crate::acts::{EPOCH_94_PARITY_BATCH, PENDING_EPOCH_SKIRMISH_JUMP};
use crate::state::Roster;
use std::rc::Rc;

/// `four_unit_line` with its roster indexed, one static "Squad".
fn squad_line() -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
    (st, vec![UnitStatic { name: "Squad".into(), ..Default::default() }])
}

/// A 4 x 4 board of 3 in cells (x, z -6..6 in): columns x >= 0 at `h` in, no ladder. Unit "a" (`sys`) stands 1 in east of
/// the edge on top; `rules` are written onto its profile.
fn ledge(h: f64, sys: &str, rules: &[&str]) -> (State, Vec<UnitStatic>, Terrain) {
    let (mut st, statics) = squad_line();
    st.positions[0] = vec![[1.0 * INCHES_TO_METERS, h * INCHES_TO_METERS, 1.5 * INCHES_TO_METERS]];
    let p = &mut Rc::get_mut(&mut st.profiles).expect("owned").list[0];
    p.game_system = sys.into();
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    let t = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { h } else { 0.0 }).collect(), Vec::new());
    (st, statics, t)
}

/// The drop 2 in west, off the ledge, at `epoch`: the check's answer and the jumps it asks for.
fn drop_off(h: f64, sys: &str, rules: &[&str], epoch: u32) -> (Check, Vec<(usize, u32, f64)>) {
    let (st, statics, t) = ledge(h, sys, rules);
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let drop = Drop { mode: ADVANCE, placed: vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], ..Default::default() };
    (check_move(&statics, &st, 0, seams, &t, &drop, true), jump_dice_of(&st, 0, seams, &t, &drop).into_iter().map(|j| (j.0, j.1, j.2)).collect())
}

fn cliff() -> Check {
    Check::Refused { reason: "Squad: cliff: no ladder here".into() }
}

fn ok(c: &Check) -> bool {
    matches!(c, Check::Ok { .. })
}

/// GFF/AOFS-E11-02: from the Jumping epoch a 4 in drop is a 4-dice jump whose height does not count toward the move;
/// one epoch below it is the cliff it always was.
#[test]
fn e11_02_a_4_in_drop_is_a_4_dice_jump() {
    let e = PENDING_EPOCH_SKIRMISH_JUMP;
    assert!(e > crate::acts::CURRENT_RULES_EPOCH, "a placeholder no record has played");
    for sys in ["gff", "aofs"] {
        let (c, jumps) = drop_off(4.0, sys, &[], e);
        assert!(ok(&c), "{sys}: {c:?}");
        assert_eq!(jumps, vec![(0, 4, 4.0)], "{sys}");
        let Check::Ok { lines } = c else { unreachable!() };
        assert!(lines.iter().any(|l| l.rule == "jump" && l.text == "Squad: model 1 jumps down 4 in - 4 dice at 2+, the jump does not count toward the move"), "{lines:?}");
        assert_eq!(drop_off(4.0, sys, &[], e - 1), (cliff(), vec![]), "{sys} one epoch below");
    }
    assert_eq!(drop_off(4.0, "gf", &[], e), (cliff(), vec![]), "gf has no drops");
}

/// The jump's height is not counted: 6 in down a ledge plus a 2 in walk fits a 6 in Advance only because the drop is free.
#[test]
fn a_jump_does_not_count_toward_the_move() {
    let (c, jumps) = drop_off(6.0, "gff", &[], PENDING_EPOCH_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 6, 6.0)]);
}

/// GFF/AOFS-E14-01: Strider halves the jump dice, rounding up: 5 in -> 3 dice.
#[test]
fn e14_01_strider_halves_jump_dice() {
    let (c, jumps) = drop_off(5.0, "gff", &["Strider"], PENDING_EPOCH_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 3, 5.0)]);
}

/// Guards (green before the rule too): a 3 in drop is regular movement with no jump, a 7 in drop is refused, and a Flying
/// unit goes over a 5 in edge without dice.
#[test]
fn e11_01_e11_04_e13_01_guards() {
    let e = PENDING_EPOCH_SKIRMISH_JUMP;
    for epoch in [EPOCH_94_PARITY_BATCH, e] {
        let (c, jumps) = drop_off(3.0, "gff", &[], epoch);
        assert!(ok(&c) && jumps.is_empty(), "3 in at {epoch}: {c:?} {jumps:?}");
        assert_eq!(drop_off(7.0, "gff", &[], epoch).0, cliff(), "7 in at {epoch}");
        let (c, jumps) = drop_off(5.0, "gff", &["Flying"], epoch);
        assert!(ok(&c) && jumps.is_empty(), "Flying at {epoch}: {c:?} {jumps:?}");
    }
}

/// The placed drop off the 4 in ledge, landed through the core's move with the supplied dice `faces`.
fn land_jump(sys: &str, epoch: u32, faces: Vec<u8>) -> crate::dice::ShootResult {
    let (st, statics, t) = ledge(4.0, sys, &[]);
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::supplied(vec![faces]);
    tray.place(vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], Vec::new());
    let action = Action { kind: ADVANCE, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
    crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap().1
}

/// GFF/AOFS-E11-02 / -03, the roll: a 4 in jump rolls 4 dice at 2+ on the move's tray. [2, 3, 5, 6] lands; [2, 1, 4, 5]
/// falls and leaves the fall marker (unit, model, inches) for the fall. One epoch below, and in gf, nothing is rolled.
#[test]
fn a_placed_jump_rolls_its_dice_and_a_miss_falls() {
    let e = PENDING_EPOCH_SKIRMISH_JUMP;
    let jump = |shot: &crate::dice::ShootResult| shot.rolls.iter().filter(|r| r.kind == "jump").map(|r| (r.count, r.faces.clone())).collect::<Vec<_>>();
    let lands = land_jump("gff", e, vec![2, 3, 5, 6]);
    assert_eq!(jump(&lands), vec![(4, vec![2, 3, 5, 6])]);
    assert!(lands.falls.is_empty() && lands.log.iter().any(|l| l == "Jump: Squad model 1 jumps down 4 in - [2, 3, 5, 6] at 2+ - it lands"), "{:?}", lands.log);
    let falls = land_jump("aofs", e, vec![2, 1, 4, 5]);
    assert_eq!(falls.falls, vec![(0, 0, 4.0)], "{:?}", falls.log);
    assert!(falls.log.iter().any(|l| l.ends_with("a 1, it falls")), "{:?}", falls.log);
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        let shot = land_jump(sys, epoch, vec![2, 1, 4, 5]);
        assert!(jump(&shot).is_empty() && shot.falls.is_empty(), "{sys} at {epoch}: {:?}", shot.rolls);
    }
}

/// The ledge with another unit's single model standing at `at_in` (x, z) on the ground, radius `r_in`.
fn ledge_with_blocker(at_in: [f64; 2], r_in: f64) -> (State, Vec<UnitStatic>, Terrain) {
    let (mut st, statics, t) = ledge(4.0, "gff", &[]);
    st.positions[2] = vec![[at_in[0] * INCHES_TO_METERS, 0.0, at_in[1] * INCHES_TO_METERS]];
    Rc::make_mut(&mut st.radii)[2] = vec![r_in * INCHES_TO_METERS];
    st.alive[2] = 1;
    for u in [1, 3] {
        st.alive[u] = 0;
    }
    (st, statics, t)
}

fn foot_of(st: &State, statics: &[UnitStatic], t: &Terrain) -> (Check, Vec<[f64; 3]>) {
    let seams = Seams { rules_epoch: PENDING_EPOCH_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
    let drop = Drop { mode: ADVANCE, placed: vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], ..Default::default() };
    (check_move(statics, st, 0, seams, t, &drop, true), jump_dice_of(st, 0, seams, t, &drop).into_iter().map(|j| j.3).collect())
}

/// Ruling D13: a failed jump lands at the foot of the drop on the model's own path - its base just clear of the edge, on
/// the ground; a model standing there pushes the foot further out along the path; with no room within 2 in the jump is
/// refused before any die is rolled.
#[test]
fn a_jumps_foot_is_the_first_free_spot_below_the_edge() {
    let r = crate::sim::tests::four_unit_line().radii[0][0] / INCHES_TO_METERS;
    let (st, statics, t) = ledge_with_blocker([30.0, 30.0], 0.5);
    let (c, feet) = foot_of(&st, &statics, &t);
    assert!(ok(&c), "{c:?}");
    assert_eq!(feet.len(), 1);
    assert!((feet[0][0] / INCHES_TO_METERS + r + 0.01).abs() < 1e-6 && feet[0][1] == 0.0, "at the foot, on the ground: {feet:?}");
    // a 0.5 in model standing 1 in to the side, just past the edge: the first spots touch it, so the foot moves out along
    // the path until the bases clear, still within 2 in
    let (st, statics, t) = ledge_with_blocker([-0.5, 2.5], 0.5);
    let (c, feet) = foot_of(&st, &statics, &t);
    assert!(ok(&c), "{c:?}");
    let x = feet[0][0] / INCHES_TO_METERS;
    assert!(x < -(r + 0.01) - 1e-6 && x >= -2.0 - 1e-9, "moved out, within 2 in: {feet:?}");
    assert!((x + 0.5).hypot(1.5 - 2.5) >= r + 0.5 - 1e-6, "clear of the blocker: {feet:?}");
    // a 3 in wide model covering the whole 2 in: no room, refused before any roll
    let (st, statics, t) = ledge_with_blocker([-1.0, 1.5], 3.0);
    let (c, feet) = foot_of(&st, &statics, &t);
    assert_eq!(c, Check::Refused { reason: "Squad: model 1 has no room to land at the foot of the drop".into() });
    assert!(feet.is_empty());
}

/// GFF/AOFS-E11-03: a 4 in jump on [2, 1, 4, 5] fails; the fall rolls 4 dice, [1, 3, 4, 6] is two wounds (1 and 3), and
/// the model (3 wounds here, so it survives) stands at the foot of the drop on its own path, on the ground.
#[test]
fn e11_03_a_failed_jump_falls_takes_its_wounds_and_lands_at_the_foot() {
    let (mut st, statics, t) = ledge(4.0, "gff", &[]);
    st.wounds[0] = vec![3];
    let seams = Seams { rules_epoch: PENDING_EPOCH_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
    let drop = Drop { mode: ADVANCE, placed: vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], ..Default::default() };
    let foot = jump_dice_of(&st, 0, seams, &t, &drop)[0].3;
    let mut tray = Tray::supplied(vec![vec![2, 1, 4, 5], vec![1, 3, 4, 6]]);
    tray.place(drop.placed.clone(), Vec::new());
    let action = Action { kind: ADVANCE, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
    let (after, shot) = crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap();
    let fall: Vec<(i64, Vec<u8>)> = shot.rolls.iter().filter(|r| r.kind == "fall").map(|r| (r.count, r.faces.clone())).collect();
    assert_eq!(fall, vec![(4, vec![1, 3, 4, 6])]);
    assert_eq!(after.wounds[0], vec![1], "two wounds landed: {:?}", shot.log);
    assert_eq!(after.positions[0], vec![foot], "the model stands at the foot, not where it was placed");
    assert!(foot[1] == 0.0 && foot[0] > -1.1 * INCHES_TO_METERS, "the foot is on the ground just past the edge: {foot:?}");
    assert!(shot.log.iter().any(|l| l.starts_with("Falling: Squad model 1 falls 4 in and lands at the foot of the drop") && l.ends_with("2 wounds on 1-3")), "{:?}", shot.log);
    // the book's faces cannot tell 1-3 from 4-6 (two each); [1, 2, 3, 6] can: three wounds, not one
    let mut tray = Tray::supplied(vec![vec![2, 1, 4, 5], vec![1, 2, 3, 6]]);
    tray.place(drop.placed.clone(), Vec::new());
    st.wounds[0] = vec![4];
    let (after, _) = crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap();
    assert_eq!(after.wounds[0], vec![1], "three wounds on 1-3");
}
