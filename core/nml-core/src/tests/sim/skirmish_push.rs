//! The skirmish Pushing rule (3.6 Firefight / AoF: Skirmish p.15): "When a unit is Shaken after being attacked, the
//! attacker may try to push it." The attacker decides after the dice (step 29d: the `push:`/`push_to:` choices); here a
//! push decided up front (`Tray::offer_push`) stands for that answer.
use super::*;
use crate::activation::PushInput;

/// Unit "a" (player 0, `sys`) fires 6 shots (Quality 2) at "b": two models 12 in east, Defense 6, Quality 6, so a lost
/// model usually fails its morale test. `shaken_before` marks "b" Shaken at the start. A push of b's first model 1 in east
/// is offered for `target` (empty: no push declared).
fn push_game(sys: &str, epoch: u32, seed: i64, target: &str, shaken_before: bool) -> ShootResult {
    push_game_at(sys, epoch, seed, target, shaken_before).1
}

/// `push_game` with the state after it.
fn push_game_at(sys: &str, epoch: u32, seed: i64, target: &str, shaken_before: bool) -> (State, ShootResult) {
    let mut st = four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = sys.into();
    st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], vec![at(12.0, 0.0), at(12.0, 1.5)], vec![at(30.0, 20.0)]];
    st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; 2], vec![0.5 * IN2M]]);
    st.wounds = vec![vec![1], vec![1], vec![1, 1], vec![1]];
    st.alive = vec![1, 1, 2, 1];
    st.shaken[2] = shaken_before;
    let gun = ShootProfile { name: "Rifle".into(), attacks: 6, count: 1, range: 24, ..Default::default() };
    let unit = |name: &str, n: i64, q: i64, shoot: Vec<ShootProfile>| UnitStatic {
        name: name.into(), shoot, model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: q, defense: 6, models: n, ..Default::default() }, ..Default::default()
    };
    let statics = vec![unit("Gunners", 1, 2, vec![gun]), unit("Spare", 1, 4, vec![]), unit("Target", 2, 6, vec![]), unit("Far", 1, 4, vec![])];
    let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::seeded(seed);
    if !target.is_empty() {
        tray.offer_push(Some(PushInput { target: target.into(), model: 0, to: at(13.0, 0.0) }));
    }
    resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap()
}

fn push_line(shot: &ShootResult) -> Option<&String> {
    shot.log.iter().find(|l| l.starts_with("Push: "))
}

/// GFF/AOFS-E10 (legality), end to end: the push holds when this attack left the target Shaken. A target that stays steady
/// and one that was Shaken before are each told no; one epoch below, and in gf, no push is read at all.
#[test]
fn a_push_holds_only_against_the_target_this_attack_shook() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    assert_eq!(e, 101);
    assert!(!crate::acts::rule_on(100, e), "a record at 100 replays as recorded");
    assert!(crate::acts::rule_on(crate::acts::CURRENT_RULES_EPOCH, e), "a fresh play_game() stamps it on");
    let shook = (0..200).find(|&s| push_line(&push_game("gff", e, s, "b", false)).is_some_and(|l| l.starts_with("Push: Gunners rolls")))
        .expect("a seed where the volley shakes b");
    assert!(push_line(&push_game("aofs", e, shook, "b", false)).is_some_and(|l| l.starts_with("Push: Gunners rolls")), "aofs holds too");
    // Step 29d: the attacker decides after the dice, so a target this attack did not shake asks nothing and says nothing.
    let steady = (0..200).find(|&s| push_line(&push_game("gff", e, s, "b", false)).is_none() && !push_game("gff", e, s, "b", false).rolls.iter().any(|r| r.kind == "push"))
        .expect("a seed where b holds");
    assert_eq!(push_line(&push_game("gff", e, steady, "b", false)), None);
    assert_eq!(push_line(&push_game("gff", e, shook, "b", true)), None, "Shaken before: no push to decide");
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        assert_eq!(push_line(&push_game(sys, epoch, shook, "b", false)), None, "{sys} at {epoch}");
    }
}

/// `push_holds` on its own (ruling D15): an enemy the attack hit and left Shaken; never the attacker's side, never a unit
/// that was Shaken already, is gone, or was Shaken by something the attack did not hit it with.
#[test]
fn push_holds_reads_enemy_hit_newly_shaken_and_standing() {
    let before = four_unit_line();
    let mut now = before.clone();
    now.shaken = vec![false, true, true, true];
    let hit = [1, 2];
    assert!(push_holds(&before, &now, 0, 2, &hit), "the enemy the attack hit, Shaken now");
    assert!(!push_holds(&before, &now, 0, 3, &hit), "an enemy Shaken now that the attack never hit");
    assert!(!push_holds(&before, &now, 0, 1, &hit), "the attacker's own side, Shaken now");
    let mut shaken_before = before.clone();
    shaken_before.shaken[2] = true;
    assert!(!push_holds(&shaken_before, &now, 0, 2, &hit), "Shaken before the attack");
    now.alive[2] = 0;
    assert!(!push_holds(&before, &now, 0, 2, &hit), "gone");
}

/// A game recorded at epoch 100 (the live epoch before the bump) replays unchanged: on the seed where a gff push rolls 4+
/// and moves Target model 1 to 13 in east at 101, at 100 no push die is rolled, no push line is said and the model stays put.
#[test]
fn a_record_at_epoch_100_rolls_no_push() {
    let pushed = [13.0 * IN2M, 0.0, 0.0];
    let seed = (0..400).find(|&s| push_game_at("gff", 101, s, "b", false).0.positions[2].first() == Some(&pushed)).expect("a seed where the push lands at 101");
    let (st, shot) = push_game_at("gff", 100, seed, "b", false);
    assert_eq!(shot.rolls.iter().filter(|r| r.kind == "push").count(), 0, "100: no push die: {:?}", shot.rolls);
    assert_eq!(push_line(&shot), None, "100: no push line");
    assert!(st.positions[2].iter().all(|q| *q != pushed), "100: no Target model is pushed: {:?}", st.positions[2]);
}

/// GFF/AOFS-E10-01 / -02: a holding push rolls one die for the attacker; 4+ moves the named model to its spot (1 in east
/// here), 1-3 moves nothing.
#[test]
fn e10_01_02_a_push_moves_the_model_on_4_plus_only() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let face = |shot: &ShootResult| shot.rolls.iter().find(|r| r.kind == "push").map(|r| (r.owner.clone(), r.target, r.faces.clone()));
    let runs: Vec<(State, ShootResult)> = (0..400).map(|s| push_game_at("gff", e, s, "b", false)).filter(|(_, shot)| face(shot).is_some()).collect();
    let (st, shot) = runs.iter().find(|(_, shot)| face(shot).is_some_and(|f| f.2[0] >= 4)).expect("a seed where the push rolls 4+");
    assert_eq!(face(shot).map(|f| (f.0, f.1)), Some(("Gunners".to_string(), 4)));
    assert_eq!(st.positions[2][0], [13.0 * IN2M, 0.0, 0.0], "pushed 1 in east: {:?}", shot.log);
    assert!(shot.log.iter().any(|l| l.contains("rolls") && l.contains("pushes Target model 1")), "{:?}", shot.log);
    let (st, shot) = runs.iter().find(|(_, shot)| face(shot).is_some_and(|f| f.2[0] < 4)).expect("a seed where the push rolls 1-3");
    assert!(st.positions[2].iter().all(|q| *q != [13.0 * IN2M, 0.0, 0.0]), "nobody moved to the push spot: {:?}", st.positions[2]);
    assert!(shot.log.iter().any(|l| l.ends_with("no push on 1-3")), "{:?}", shot.log);
}

/// `push_spot`: up to 2 in, on the ground it stood on or lower by under 2 in, never up a ledge, a push off 2 in or more
/// held back until the fall is wired, never into a building or another model.
#[test]
fn push_spot_takes_a_free_spot_within_2_in_on_the_same_ground() {
    let mut st = four_unit_line();
    let at = |x: f64, y: f64, z: f64| [x * IN2M, y * IN2M, z * IN2M];
    st.positions[2] = vec![at(-1.5, 3.0, 1.5)];
    st.positions[3] = vec![at(-1.5, 3.0, -1.0)];
    for u in [0, 1] {
        st.alive[u] = 0;
    }
    // columns of 3 in cells from x -6: -6..-3 at 4 in, -3..0 (where the model stands) at 3 in, 0..6 at 1 in
    let lv = |c: usize| match c { 0 => 4.0, 1 => 3.0, _ => 1.0 };
    let t = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| lv(i % 4)).collect(), Vec::new());
    let go = |to: [f64; 3]| push_spot(&st, 2, &crate::activation::PushInput { target: "b".into(), model: 0, to }, Cover::Board(&t));
    assert!(go(at(-2.5, 3.0, 1.5)).is_ok_and(|(d, fall)| (d - 1.0).abs() < 1e-9 && fall.is_none()), "1 in along the strip");
    assert_eq!(go(at(-1.5, 3.0, 4.0)), Err("2.5 in is over the 2 in".to_string()));
    assert_eq!(go(at(-3.2, 4.0, 1.5)), Err("a push never goes up a ledge".to_string()));
    assert!(go(at(0.3, 1.0, 1.5)).is_ok_and(|(d, fall)| (d - 1.8).abs() < 1e-9 && fall == Some(2.0)), "off the 2 in edge: a fall");
    assert_eq!(go(at(-1.5, 3.0, 0.5)), Err("another model stands there".to_string()));
    let mut gone = st.clone();
    gone.positions[2].clear();
    assert!(push_spot(&gone, 2, &crate::activation::PushInput { target: "b".into(), model: 0, to: at(-1.0, 3.0, 1.0) }, Cover::Board(&t)).is_err());
}

/// Ruling D15, spells: a damage spell whose hits leave its target Shaken attacked it, so the caster may push it.
#[test]
fn a_target_shaken_by_a_damage_spell_may_be_pushed() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let game = |cast_lands: bool| {
        let mut st = four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
        let mut p = st.profiles.list[0].clone();
        p.game_system = "gff".into();
        st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
        let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
        st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], vec![at(12.0, 0.0), at(12.0, 1.5)], vec![at(30.0, 20.0)]];
        st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; 2], vec![0.5 * IN2M]]);
        st.wounds = vec![vec![1], vec![1], vec![1, 1], vec![1]];
        st.alive = vec![1, 1, 2, 1];
        st.casts = vec![2, 0, 0, 0];
        let unit = |name: &str, n: i64, q: i64| UnitStatic {
            name: name.into(), model_count: n, wounds_max: vec![1; n as usize],
            ctx: Ctx { quality: q, defense: 6, models: n, ..Default::default() }, ..Default::default()
        };
        let bolt = crate::rules::Spell { name: "Bolt".into(), status: "modeled".into(), range_in: 18.0, target_count: 1,
            effect_kind: "damage".into(), effect_hits: 3, ..Default::default() };
        let statics = vec![UnitStatic { is_caster: true, spells: vec![bolt], casts_per_round: 2, ..unit("Mystic", 1, 4) }, unit("Spare", 1, 4), unit("Target", 2, 6), unit("Far", 1, 4)];
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
        // cast 6, saves [1, 6, 6] (one model down: half strength), morale 1 (Shaken), push 5
        let mut tray = Tray::supplied(if cast_lands { vec![vec![6], vec![1, 6, 6], vec![1], vec![5]] } else { vec![vec![1]] });
        tray.offer_casts(vec![crate::activation::CastInput { seq: 0, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], base: 2, threshold: 1, ..Default::default() }]);
        tray.offer_push(Some(PushInput { target: "b".into(), model: 0, to: at(13.0, 0.0) }));
        resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), Seams { rules_epoch: e, tray_exact: true, ..Seams::default() }, &mut GodotRng::new(0), &mut tray).unwrap()
    };
    let (st, shot) = game(true);
    assert_eq!((st.alive[2], st.shaken[2]), (1, true), "the spell shook the target: {:?}", shot.log);
    assert!(shot.log.iter().any(|l| l.starts_with("Push: Mystic rolls 5 and pushes Target model 1")), "the push holds, rolls and moves: {:?}", shot.log);
    let (_, shot) = game(false);
    assert!(!shot.log.iter().any(|l| l.starts_with("Push:")), "a failed cast hits nothing, so there is no push to decide: {:?}", shot.log);
}

/// Ruling D14: after the push the unit's other models stand within 1 in of the moved one - a model already that close
/// stays; a far one goes to the spot 1 in from its base on the straight line toward where it stood; with no room it stays
/// and the line says so. (1 in bases: the far model lands 3 in from the moved model's centre.)
#[test]
fn push_regroup_puts_the_rest_within_1_in() {
    let mut st = four_unit_line();
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions[2] = vec![at(0.0, 0.0), at(0.0, 2.5), at(8.0, 0.0)];
    Rc::make_mut(&mut st.radii)[2] = vec![IN2M; 3];
    st.alive = vec![0, 0, 3, 0];
    let tail = push_regroup(&mut st, 2, 0, Cover::Recorded(None));
    assert_eq!(st.positions[2][1], at(0.0, 2.5), "within 1 in already: stays");
    assert!((st.positions[2][2][0] - 3.0 * IN2M).abs() < 1e-9 && st.positions[2][2][2].abs() < 1e-9, "1 in from the base, straight toward where it stood: {:?}", st.positions[2]);
    assert_eq!(tail, "; model 3 placed within 1 in of it");
    // a 10 in model of another unit fills every spot 1 in around: the far model stays and the line says so
    let mut boxed = four_unit_line();
    boxed.positions[2] = vec![at(0.0, 0.0), at(8.0, 0.0)];
    Rc::make_mut(&mut boxed.radii)[2] = vec![IN2M; 2];
    boxed.positions[3] = vec![at(0.0, 0.0)];
    Rc::make_mut(&mut boxed.radii)[3] = vec![10.0 * IN2M];
    boxed.alive = vec![0, 0, 2, 1];
    assert_eq!(push_regroup(&mut boxed, 2, 0, Cover::Recorded(None)), "; model 2 found no room within 1 in and stays");
    assert_eq!(boxed.positions[2][1], at(8.0, 0.0));
}

/// Ruling D14 end to end: a push that lands pulls the pushed unit's far model within 1 in of the moved one, and says so.
/// Four Target models, a spell drops two, the morale fails, the push (5) moves model 1 2 in east.
#[test]
fn a_landed_push_regroups_the_rest_of_the_unit() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let game4 = || {
        let mut st = four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
        let mut p = st.profiles.list[0].clone();
        p.game_system = "gff".into();
        st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
        let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
        st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], vec![at(12.0, 0.0), at(12.0, 1.5), at(12.0, 3.0), at(12.0, 4.5)], vec![at(30.0, 20.0)]];
        st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; 4], vec![0.5 * IN2M]]);
        st.wounds = vec![vec![1], vec![1], vec![1; 4], vec![1]];
        st.alive = vec![1, 1, 4, 1];
        st.casts = vec![2, 0, 0, 0];
        let unit = |name: &str, n: i64, q: i64| UnitStatic {
            name: name.into(), model_count: n, wounds_max: vec![1; n as usize],
            ctx: Ctx { quality: q, defense: 6, models: n, ..Default::default() }, ..Default::default()
        };
        let bolt = crate::rules::Spell { name: "Bolt".into(), status: "modeled".into(), range_in: 18.0, target_count: 1,
            effect_kind: "damage".into(), effect_hits: 3, ..Default::default() };
        let statics = vec![UnitStatic { is_caster: true, spells: vec![bolt], casts_per_round: 2, ..unit("Mystic", 1, 4) }, unit("Spare", 1, 4), unit("Target", 4, 6), unit("Far", 1, 4)];
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
        // cast 6, saves [1, 1, 6] (two of four down: half strength), morale 1 (Shaken), push 5
        let mut tray = Tray::supplied(vec![vec![6], vec![1, 1, 6], vec![1], vec![5]]);
        tray.offer_casts(vec![crate::activation::CastInput { seq: 0, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], base: 2, threshold: 1, ..Default::default() }]);
        tray.offer_push(Some(PushInput { target: "b".into(), model: 0, to: at(14.0, 3.0) }));
        resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), Seams { rules_epoch: e, tray_exact: true, ..Seams::default() }, &mut GodotRng::new(0), &mut tray).unwrap()
    };
    let (st, shot) = game4();
    assert_eq!((st.alive[2], st.shaken[2]), (2, true), "{:?}", shot.log);
    let (m, others) = (st.positions[2][0], &st.positions[2][1..]);
    assert!(others.iter().all(|q| (q[0] - m[0]).hypot(q[2] - m[2]) - IN2M <= IN2M + 1e-9), "the rest within 1 in: {:?}", st.positions[2]);
    assert!(shot.log.iter().any(|l| l.starts_with("Push: Mystic rolls 5 and pushes Target model 1") && l.ends_with("placed within 1 in of it")), "{:?}", shot.log);
}

/// The spell-and-push fixture on a tier board: "Mystic" at the centre on the ground casts a 3-hit Bolt (no sight needed) at
/// the two-model "Target" standing on a raised strip x 9..12 in of `strip` in; the push moves its model 1 to `to_x` (z 0).
fn ledge_push(strip: f64, to_x: f64, dice: Vec<Vec<u8>>) -> (State, ShootResult) {
    let (st, shot, _) = ledge_push_tray(strip, to_x, dice);
    (st, shot)
}

/// `ledge_push` with the tray after it (its landings: what the table lands).
/// The ledge scene's start (its wounds and models only: the landings' replay base).
fn ledge_push_start() -> State {
    let mut st = four_unit_line();
    st.wounds = vec![vec![1], vec![1], vec![1, 1], vec![1]];
    st
}

fn ledge_push_tray(strip: f64, to_x: f64, dice: Vec<Vec<u8>>) -> (State, ShootResult, Tray) {
    let mut st = four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = "gff".into();
    st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
    let at = |x: f64, y: f64, z: f64| [x * IN2M, y * IN2M, z * IN2M];
    st.positions = vec![vec![at(0.0, 0.0, 0.0)], vec![at(-10.0, 0.0, -10.0)], vec![at(10.0, strip, 0.0), at(10.0, strip, 1.2)], vec![at(-10.0, 0.0, 10.0)]];
    st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; 2], vec![0.5 * IN2M]]);
    st.wounds = vec![vec![1], vec![1], vec![1, 1], vec![1]];
    st.alive = vec![1, 1, 2, 1];
    st.casts = vec![2, 0, 0, 0];
    let unit = |name: &str, n: i64, q: i64| UnitStatic {
        name: name.into(), model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: q, defense: 6, models: n, ..Default::default() }, ..Default::default()
    };
    let bolt = crate::rules::Spell { name: "Bolt".into(), status: "modeled".into(), range_in: 18.0, target_count: 1, needs_los: false,
        effect_kind: "damage".into(), effect_hits: 3, ..Default::default() };
    let statics = vec![UnitStatic { is_caster: true, spells: vec![bolt], casts_per_round: 2, ..unit("Mystic", 1, 4) }, unit("Spare", 1, 4), unit("Target", 2, 6), unit("Far", 1, 4)];
    let t = crate::terrain::tier_board_for_test(8, 8, (0..64).map(|i| if i % 8 == 7 { strip } else { 0.0 }).collect(), Vec::new());
    let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
    let mut tray = Tray::supplied(dice);
    tray.offer_casts(vec![crate::activation::CastInput { seq: 0, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], base: 2, threshold: 1, ..Default::default() }]);
    tray.offer_push(Some(PushInput { target: "b".into(), model: 0, to: at(to_x, 0.0, 0.0) }));
    let seams = Seams { rules_epoch: crate::acts::EPOCH_101_SKIRMISH_PUSH, tray_exact: true, ..Seams::default() };
    let (st, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &t, seams, &mut GodotRng::new(0), &mut tray).unwrap();
    (st, shot, tray)
}

/// LANDING-INVARIANT: the push-off-a-ledge activation's landings, replayed onto its start, give the core's end state
/// (`landing::landing_gaps` is empty). Red with #3961's landing taken out: Target ends with 0 models in the core, 1 landed.
#[test]
fn the_push_fall_leaves_no_landing_gap() {
    let start = ledge_push_start();
    let (end, _shot, tray) = ledge_push_tray(3.0, 8.7, vec![vec![6], vec![1, 6, 6], vec![1], vec![5], vec![1, 6, 6]]);
    assert_eq!(crate::landing::landing_gaps(&start, &end, &tray.all_landings()), Vec::<String>::new());
}

/// #3961 (FT-17): the fall's wounds on the pushed model are a landing of their own - the table lands only landings, so
/// without one the pushed model stayed alive on the table while the core had it dead. After the push's move landing,
/// one landing on Target marks the pushed survivor (slot 1) dead.
#[test]
fn a_pushed_models_fall_wounds_land_on_the_table() {
    let (st, _shot, tray) = ledge_push_tray(3.0, 8.7, vec![vec![6], vec![1, 6, 6], vec![1], vec![5], vec![1, 6, 6]]);
    assert_eq!(st.alive[2], 0, "the core: the fall killed it");
    let landings = tray.landings_upto(usize::MAX);
    let push_move = landings.iter().position(|l| l.unit == 2 && !l.moved_to.is_empty()).expect("the push's move landing");
    // (the volley's own landing killed slot 0 before; the pushed survivor is slot 1)
    let dead = landings.iter().enumerate().skip(push_move + 1).find(|(_, l)| l.unit == 2 && l.moved_to.is_empty() && l.models.iter().any(|m| m.dead && m.slot == 1));
    assert!(dead.is_some(), "a landing kills Target's pushed model after its move: {landings:?}");
}

/// GFF/AOFS-E12-01: pushed off a 3 in strip the model falls - three dice, each 1-3 a wound on it ([1, 6, 6]: one, its last).
/// GFF/AOFS-E12-02: off a 1 in strip there is no fall (under 2 in), only the push. (cast 6, saves [1, 6, 6] -> one of two
/// down, morale 1 -> Shaken, push 5.)
#[test]
fn e12_01_02_a_push_off_2_in_or_more_falls() {
    let (st, shot) = ledge_push(3.0, 8.7, vec![vec![6], vec![1, 6, 6], vec![1], vec![5], vec![1, 6, 6]]);
    let fall: Vec<(String, Vec<u8>)> = shot.rolls.iter().filter(|r| r.kind == "fall").map(|r| (r.owner.clone(), r.faces.clone())).collect();
    assert_eq!(fall, vec![("Target".to_string(), vec![1, 6, 6])], "{:?}", shot.log);
    assert_eq!(st.alive[2], 0, "the fall's wound was the model's last");
    assert!(shot.log.iter().any(|l| l.starts_with("Push: Mystic rolls 5 and pushes Target model 1") && l.contains("off a 3 in drop - it falls, [1, 6, 6], 1 wound on 1-3")), "{:?}", shot.log);
    let (st, shot) = ledge_push(1.0, 8.7, vec![vec![6], vec![1, 6, 6], vec![1], vec![5]]);
    assert!(!shot.rolls.iter().any(|r| r.kind == "fall"), "1 in is no fall: {:?}", shot.log);
    assert_eq!((st.alive[2], st.positions[2][0][0]), (1, 8.7 * IN2M), "pushed down the 1 in, standing");
}

/// Step 19, the AI default: an activation that declares no push (the AI never does) says once, where a push would hold,
/// that it does not push - and nothing else changes. One epoch below, and in gf, it says nothing.
#[test]
fn an_undeclared_push_is_said_and_declined() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let declined = |shot: &ShootResult| shot.log.iter().filter(|l| l.starts_with("Push: ")).cloned().collect::<Vec<_>>();
    let shook = (0..200).find(|&s| push_game_at("gff", e, s, "", false).0.shaken[2]).expect("a seed where the volley shakes b");
    assert_eq!(declined(&push_game("gff", e, shook, "", false)), vec!["Push: Gunners does not push Target".to_string()]);
    assert!(!push_game("gff", e, shook, "", false).rolls.iter().any(|r| r.kind == "push"), "nothing rolled");
    let steady = (0..200).find(|&s| !push_game_at("gff", e, s, "", false).0.shaken[2]).expect("a seed where b holds");
    assert!(declined(&push_game("gff", e, steady, "", false)).is_empty(), "hit but steady: no push to decline");
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        assert!(declined(&push_game(sys, epoch, shook, "", false)).is_empty(), "{sys} at {epoch}");
    }
}
