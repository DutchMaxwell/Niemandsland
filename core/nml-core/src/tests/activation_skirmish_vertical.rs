//! The skirmish vertical rules (3.6 Firefight / AoF: Skirmish p.15): Jumping. `super::*` is activation's own items.
use super::*;
use crate::acts::{EPOCH_94_PARITY_BATCH, EPOCH_100_SKIRMISH_JUMP};
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
    let e = EPOCH_100_SKIRMISH_JUMP;
    assert_eq!(e, 100);
    assert!(!crate::acts::rule_on(99, e), "a record at 99 replays as recorded");
    assert!(crate::acts::rule_on(crate::acts::CURRENT_RULES_EPOCH, e), "a fresh play_game() stamps it on");
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

/// A game recorded at epoch 99 (the live epoch before the bump) replays unchanged: a gff 4 in drop is the cliff it always was -
/// refused, no jump dice - while at 100 the same drop is a 4-dice jump.
#[test]
fn a_record_at_epoch_99_keeps_a_4_in_drop_a_cliff() {
    assert_eq!(drop_off(4.0, "gff", &[], 99), (cliff(), vec![]), "99: the cliff, no dice");
    let (c, jumps) = drop_off(4.0, "gff", &[], 100);
    assert!(ok(&c), "100: {c:?}");
    assert_eq!(jumps, vec![(0, 4, 4.0)], "100: one model, 4 dice, 4 in");
}

/// The jump's height is not counted: 6 in down a ledge plus a 2 in walk fits a 6 in Advance only because the drop is free.
#[test]
fn a_jump_does_not_count_toward_the_move() {
    let (c, jumps) = drop_off(6.0, "gff", &[], EPOCH_100_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 6, 6.0)]);
}

/// GFF/AOFS-E14-01: Strider halves the jump dice, rounding up: 5 in -> 3 dice.
#[test]
fn e14_01_strider_halves_jump_dice() {
    let (c, jumps) = drop_off(5.0, "gff", &["Strider"], EPOCH_100_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 3, 5.0)]);
}

/// Guards (green before the rule too): a 3 in drop is regular movement with no jump, a 7 in drop is refused, and a Flying
/// unit goes over a 5 in edge without dice.
#[test]
fn e11_01_e11_04_e13_01_guards() {
    let e = EPOCH_100_SKIRMISH_JUMP;
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
    let e = EPOCH_100_SKIRMISH_JUMP;
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
    let seams = Seams { rules_epoch: EPOCH_100_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
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
    let seams = Seams { rules_epoch: EPOCH_100_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
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

/// A two-model squad on the 4 in ledge: model 1 jumps off (placed 1 in below the edge), model 2 stays on top; the
/// ADVANCE names "b" as its shooting target. Landed with the supplied dice; the result and the state after.
fn squad_jump(dice: Vec<Vec<u8>>) -> (State, crate::dice::ShootResult) {
    let (mut st, mut statics, t) = ledge(4.0, "gff", &[]);
    let top = [1.0 * INCHES_TO_METERS, 4.0 * INCHES_TO_METERS, -1.5 * INCHES_TO_METERS];
    st.positions[0].push(top);
    Rc::make_mut(&mut st.radii)[0].push(INCHES_TO_METERS);
    st.wounds[0] = vec![1, 1];
    st.alive[0] = 2;
    st.positions[2] = vec![[-5.0 * INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]]; // "b", on the ground in sight
    statics[0].model_count = 2;
    statics[0].wounds_max = vec![1, 1];
    statics[0].ctx.models = 2;
    let seams = Seams { rules_epoch: EPOCH_100_SKIRMISH_JUMP, tray_exact: true, moved_shoot: true, ..Seams::default() };
    let mut tray = Tray::supplied(dice);
    tray.place(vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS], top], Vec::new());
    // a damage spell offered for this activation: cast only when the activation goes on
    statics[0].is_caster = true;
    statics[0].spells = vec![crate::rules::Spell { name: "Bolt".into(), status: "modeled".into(), range_in: 18.0, target_count: 1,
        effect_kind: "damage".into(), effect_hits: 1, ..Default::default() }];
    st.casts[0] = 2;
    tray.offer_casts(vec![CastInput { seq: 0, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], base: 4, threshold: 1, ..Default::default() }]);
    let action = Action { kind: ADVANCE, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
    crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap()
}

/// 3.6 p.15: after a fall "the unit's activation ends immediately" - its planned shot is dropped and said - and the fall's
/// wounds count at the end like any end-of-activation wounds: the squad, down to one of two models, tests morale once.
/// A jump that lands keeps the activation going and tests nothing.
#[test]
fn a_fall_ends_the_activation_and_tests_morale_at_its_end() {
    let ends = "Falling: Squad's activation ends, so it does not shoot";
    let (after, shot) = squad_jump(vec![vec![2, 1, 4, 5], vec![1, 6, 6, 6], vec![6]]);
    assert_eq!(after.alive[0], 1, "the fallen model died: {:?}", shot.log);
    assert!(shot.log.iter().any(|l| l == ends), "{:?}", shot.log);
    let morale: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| !matches!(r.kind, "jump" | "fall") && r.owner == "Squad").collect();
    assert_eq!(morale.iter().filter(|r| r.kind != "cast").count(), 1, "one morale die at the end: {:?}", shot.rolls);
    assert!(!shot.rolls.iter().any(|r| r.kind == "cast"), "no cast after the fall: {:?}", shot.rolls);
    let (after, shot) = squad_jump(vec![vec![2, 3, 5, 6], vec![6]]);
    assert_eq!(after.alive[0], 2);
    assert!(shot.rolls.iter().any(|r| r.kind == "cast"), "the fixture casts when nobody fell: {:?}", shot.rolls);
    assert!(!shot.log.iter().any(|l| l == ends), "{:?}", shot.log);
    assert!(shot.falls.is_empty());
}

/// A 6 x 2 board of 3 in cells (x -9..9 in): columns whose index is in `low` stand at 0, the others at `h`; the far side
/// (columns >= 3) adds `far_up`. Unit "a" (`sys`) stands on top at `from_in`; it moves straight east to `to_in` with `mode`.
fn gap_move(sys: &str, epoch: u32, (low, h, far_up): (&[usize], f64, f64), (from_in, to_in): (f64, f64), mode: i64) -> (Check, Vec<(usize, u32, f64)>) {
    let (mut st, statics) = squad_line();
    let level = |c: usize| if low.contains(&c) { 0.0 } else if c >= 3 { h + far_up } else { h };
    st.positions[0] = vec![[from_in * INCHES_TO_METERS, level(((from_in + 9.0) / 3.0) as usize) * INCHES_TO_METERS, 1.5 * INCHES_TO_METERS]];
    Rc::get_mut(&mut st.profiles).expect("owned").list[0].game_system = sys.into();
    for u in 1..4 {
        st.alive[u] = 0;
    }
    let t = crate::terrain::tier_board_for_test(6, 2, (0..12).map(|i| level(i % 6)).collect(), Vec::new());
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let to = [to_in * INCHES_TO_METERS, level(((to_in + 9.0) / 3.0) as usize) * INCHES_TO_METERS, 1.5 * INCHES_TO_METERS];
    let drop = Drop { mode, placed: vec![to], ..Default::default() };
    (check_move(&statics, &st, 0, seams, &t, &drop, true), jump_dice_of(&st, 0, seams, &t, &drop).into_iter().map(|j| (j.0, j.1, j.2)).collect())
}

/// GFF/AOFS-E11-05 on the 3 in grid (the boards have no narrower gap): two equal 2 in tiers with a 3 in gap between is a
/// 3-dice jump across whose depth is not walked (6 in fits an Advance); a 6 in gap is 6 dice (a Rush). A far side 1 in
/// higher is no gap and stays refused, as does every gap in gf and one epoch below.
#[test]
fn e11_05_a_gap_between_equal_tiers_is_a_jump_across() {
    let e = EPOCH_100_SKIRMISH_JUMP;
    let (c, jumps) = gap_move("gff", e, (&[2], 2.0, 0.0), (-4.5, 1.5), ADVANCE);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 3, 2.0)], "3 dice, a fall would be the gap's 2 in depth");
    let Check::Ok { lines } = c else { unreachable!() };
    assert!(lines.iter().any(|l| l.text == "Squad: model 1 jumps a 3 in gap - 3 dice at 2+, the jump does not count toward the move"), "{lines:?}");
    let (c, jumps) = gap_move("aofs", e, (&[1, 2], 2.0, 0.0), (-7.5, 1.5), RUSH);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 6, 2.0)]);
    assert_eq!(gap_move("gff", e, (&[2], 2.0, 1.0), (-4.5, 1.5), ADVANCE).0, cliff(), "the far side is higher: a climb");
    assert_eq!(gap_move("gff", e - 1, (&[2], 2.0, 0.0), (-4.5, 1.5), ADVANCE), (cliff(), vec![]), "one epoch below");
    assert_eq!(gap_move("gf", e, (&[2], 2.0, 0.0), (-4.5, 1.5), ADVANCE), (cliff(), vec![]), "gf");
}

/// A three-model Tough squad on the 4 in ledge (models at z -4.5, 1.5, 4.5 in, 1 in east of the edge, wounds `wounds`);
/// the models in `jumpers` are placed 1.5 in below the edge, the others stay. Landed with the supplied dice.
fn tough_fall(wounds: Vec<i64>, jumpers: &[usize], dice: Vec<Vec<u8>>) -> (State, crate::dice::ShootResult) {
    let (mut st, mut statics, t) = ledge(4.0, "gff", &[]);
    let zs = [-4.5, 1.5, 4.5];
    st.positions[0] = zs.iter().map(|z| [INCHES_TO_METERS, 4.0 * INCHES_TO_METERS, z * INCHES_TO_METERS]).collect();
    Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS; 3];
    st.wounds[0] = wounds;
    st.alive = vec![3, 0, 0, 0];
    (statics[0].model_count, statics[0].wounds_max, statics[0].ctx.models, statics[0].ctx.tough) = (3, vec![3; 3], 3, 3);
    let placed: Vec<[f64; 3]> = (0..3).map(|i| if jumpers.contains(&i) { [-1.5 * INCHES_TO_METERS, 0.0, zs[i] * INCHES_TO_METERS] } else { st.positions[0][i] }).collect();
    let seams = Seams { rules_epoch: EPOCH_100_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::supplied(dice);
    tray.place(placed, Vec::new());
    let action = Action { kind: ADVANCE, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
    crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap()
}

/// 3.6 p.15: "the model falls ... and takes one wound" - the wounds go on the model that fell, not down the unit's casualty
/// order. Model 3 of a Tough(3) squad falls for two wounds and keeps its last one; models 1 and 2 are untouched. With two
/// jumpers whose first fall kills its model, the second fall still finds its own model one slot further up.
#[test]
fn a_falls_wounds_land_on_the_model_that_fell() {
    let (after, shot) = tough_fall(vec![3, 3, 3], &[2], vec![vec![1, 2, 2, 2], vec![1, 3, 4, 6]]);
    assert_eq!(after.wounds[0], vec![3, 3, 1], "{:?}", shot.log);
    let (after, shot) = tough_fall(vec![1, 3, 3], &[0, 2], vec![vec![1, 2, 2, 2], vec![1, 3, 6, 6], vec![1, 2, 2, 2], vec![1, 6, 6, 6]]);
    assert_eq!(after.wounds[0], vec![3, 2], "the first faller died, the second took its one wound: {:?}", shot.log);
    assert_eq!(after.alive[0], 2);
}

/// Plan step 27b (found by an e2e of a core fall on the table): the fall is its own landing, before its wounds - the unit's
/// models with the faller at its foot (`moved_to`), then the wound whose `at` is that foot - so the table moves the model
/// first and finds it there. Without it the table looked for the wounded model at the foot, found none and landed nothing.
#[test]
fn a_fall_lands_the_move_before_its_wounds() {
    let (mut st, mut statics, t) = ledge(4.0, "gff", &[]);
    let zs = [-4.5, 1.5, 4.5];
    st.positions[0] = zs.iter().map(|z| [INCHES_TO_METERS, 4.0 * INCHES_TO_METERS, z * INCHES_TO_METERS]).collect();
    Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS; 3];
    st.wounds[0] = vec![3, 3, 3];
    st.alive = vec![3, 0, 0, 0];
    (statics[0].model_count, statics[0].wounds_max, statics[0].ctx.models, statics[0].ctx.tough) = (3, vec![3; 3], 3, 3);
    let placed: Vec<[f64; 3]> = (0..3).map(|i| if i == 2 { [-1.5 * INCHES_TO_METERS, 0.0, zs[i] * INCHES_TO_METERS] } else { st.positions[0][i] }).collect();
    let seams = Seams { rules_epoch: EPOCH_100_SKIRMISH_JUMP, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::supplied(vec![vec![1, 2, 2, 2], vec![1, 3, 4, 6]]);
    tray.place(placed, Vec::new());
    let action = Action { kind: ADVANCE, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
    let (after, _) = crate::sim::resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut crate::rng::GodotRng::new(0), &mut tray).unwrap();
    let landings = tray.landings_upto(usize::MAX);
    let mv = landings.iter().position(|l| l.unit == 0 && !l.moved_to.is_empty()).expect("the fall's move lands");
    let foot = landings[mv].moved_to[2];
    assert!((foot[0] - after.positions[0][2][0]).abs() < 1e-9 && (foot[2] - after.positions[0][2][2]).abs() < 1e-9, "the faller at its foot");
    let hurt = landings.iter().position(|l| l.unit == 0 && l.models.iter().any(|m| m.slot == 2)).expect("the fall's wounds land");
    assert!(mv < hurt, "the move lands before the wounds: {mv} vs {hurt}");
    assert!(landings[hurt].models.iter().all(|m| (m.at[0] - foot[0]).abs() < 1e-9), "the wounds' `at` is the foot");
}

/// Plan step 27-pre-R (found by the R3 ruin e2e): the same 4 in ledge as `ledge`, but as a free ruin's FLOOR on a flat board
/// (x >= 0 in, top 4 in). From `PENDING_EPOCH_RUIN_LEDGES` the drop off it is the tier ledge's: the same check, the same
/// jump dice and the same foot to land a fall on - `jump_foot` read the drop's top from the flat tier grid and found none.
#[test]
fn a_ruin_floor_ledge_plays_like_a_tier_ledge() {
    let e = crate::acts::PENDING_EPOCH_RUIN_LEDGES;
    let seams = Seams { rules_epoch: e, tray_exact: true, ..Seams::default() };
    let drop = Drop { mode: ADVANCE, placed: vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], ..Default::default() };
    let (st, statics, tier) = ledge(4.0, "gff", &[]);
    let i = INCHES_TO_METERS;
    let slab = crate::terrain::Slab { c: [3.0 * i, 0.0], he: [3.0 * i, 6.0 * i], yaw: 0.0, y0: 4.0 * i - 0.01, y1: 4.0 * i };
    let floor = Terrain::build(&crate::terrain::PlainTerrain {
        cell_params: crate::terrain::CellParams { table_size_feet: [1.0, 1.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: i },
        tiers: Some(crate::terrain::TierGrid { nx: 4, nz: 4, cell_in: 3.0, level_in: vec![0.0; 16], ladders: vec![], stairs: vec![] }),
        sandbox: vec![crate::terrain::Obb { c: slab.c, he: slab.he, yaw: 0.0, kind: 1, slabs: vec![slab] }],
        ..Default::default()
    });
    let run = |t: &Terrain| (ok(&check_move(&statics, &st, 0, seams, t, &drop, true)), jump_dice_of(&st, 0, seams, t, &drop));
    let (tier_ok, tier_jumps) = run(&tier);
    let (floor_ok, floor_jumps) = run(&floor);
    assert!(tier_ok && floor_ok, "both drops are allowed");
    assert_eq!(floor_jumps.len(), 1, "one jump off the floor, with a foot to land on");
    let key = |j: &[(usize, u32, f64, [f64; 3])]| j.iter().map(|x| (x.0, x.1, x.2)).collect::<Vec<_>>();
    assert_eq!(key(&floor_jumps), key(&tier_jumps), "the same model, dice and height as off the tier ledge");
    // the foot to the micrometre (the floor's edge is found by halving the leg, the cliff's exactly)
    assert!((0..3).all(|k| (floor_jumps[0].3[k] - tier_jumps[0].3[k]).abs() < 1e-6), "{floor_jumps:?} vs {tier_jumps:?}");
}

