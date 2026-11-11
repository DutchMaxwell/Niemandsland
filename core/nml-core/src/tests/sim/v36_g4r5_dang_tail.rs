//! Rules 3.6 row G4R5 R1 F-DANG-TAIL (replay rows aof_1000_net_003 act 24, aof_033 act 25, gf_047 act 10, melee gf_002 act 11):
//! when the replay gate cuts the table's Dangerous test it must not lose the test's TAIL - the end-of-activation morale
//! test (shooting) and the charger's self-inflicted wounds in the melee result (charge).
//!
//! The gate hands the core the act-start (alive, wounds) of the unit in the header knob `dangerous_replay` and patches the
//! post-test state in; the core reads the difference. In-game play never sets the knob (`knobs_of` has no key for it), so
//! the live legs here run the core's own test and must come out byte-identical with and without the key.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::plan::seams_of;
use crate::read_act_header;

/// Real units, built the way the game builds them from a profile: a four-model squad and a single six-wound model.
const PROFILES: &str = r#""profiles":{
  "squad":{"unit_id":"squad","name":"Squad","quality":3,
    "defense":4,"tough":1,"wounds_max":[1,1,1,1],"model_count":4,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":4,"ap":0,"rules":[]}]},
  "tyrant":{"unit_id":"tyrant","name":"Tyrant","quality":3,
    "defense":4,"tough":6,"wounds_max":[6],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Cleaver","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// The seams a header resolves to (the replay gate's route: header knobs -> `seams_of`). `replay` is the header's
/// `"dangerous_replay":[alive,wounds]` pair, or None for a header without the key.
fn seams(epoch: u32, cut: bool, replay: Option<(i64, i64)>) -> (Seams, crate::acts::ActHeader) {
    let key = replay.map_or(String::new(), |(a, w)| format!(r#","dangerous_replay":[{a},{w}]"#));
    let knobs = format!(r#"{{"rules_epoch":{epoch},"dangerous":{},"dangerous_end_morale":true{key}}}"#, !cut);
    let header = read_act_header(&format!(r#"{{"kind":"header","knobs":{knobs},{PROFILES}}}"#)).expect("header parses");
    (seams_of(&header.knobs), header)
}

/// Unit "a" built from `profile`, standing at `x_in` with `left` wounds per surviving model (the state AFTER the gate
/// patched the cut test's wounds in); "b" is a sturdy weaponless host 2.5" in front of it.
fn line(profile: &str, left: Vec<i64>, x_in: f64, header: &crate::acts::ActHeader) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    let n = left.len();
    st.positions = vec![
        (0..n).map(|k| [(x_in + 0.02 * k as f64) * IN2M, 0.0, 0.0]).collect(),
        vec![],
        vec![[(x_in + 2.5) * IN2M, 0.0, 0.0], [(x_in + 2.52) * IN2M, 0.0, 0.0]],
        vec![],
    ];
    st.radii = Rc::new(vec![vec![IN2M; n], vec![], vec![IN2M; 2], vec![]]);
    st.wounds = vec![left, vec![], vec![60; 2], vec![]];
    st.alive = vec![n as i64, 0, 2, 0];
    let mut reg = crate::rules::Registries::new(&repo_root());
    let unit = UnitStatic::build_for(&mut reg, header.profiles.get(profile).expect(profile), header.knobs.rules_epoch);
    let host = UnitStatic { name: "Host".into(), model_count: 2, wounds_max: vec![60; 2], ..Default::default() };
    (st, vec![unit, UnitStatic { name: "ah".into(), ..Default::default() }, host, UnitStatic { name: "bh".into(), ..Default::default() }])
}

fn act(kind: i64, charge: bool) -> Action {
    Action { kind, unit: "a".into(), dest: None, shoot: None, charge: charge.then(|| "b".into()), patient: false, split: None, traced: None, teleport: None }
}

fn run(st: &State, statics: &[UnitStatic], kind: i64, seams: Seams, board: &Terrain, seed: i64) -> ShootResult {
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    resolve_stochastic_tray_on_board(statics, st, &act(kind, kind == CHARGE), board, seams, &mut rng, &mut tray).unwrap().1
}

/// The squad lost two of its four models in the table's cut test: half the unit is gone, so the end-of-activation morale
/// die is due. The core draws it from the act-start snapshot (4 alive, 4 wounds) and the log names the Dangerous rule.
#[test]
fn a_cut_test_that_halves_the_squad_still_draws_its_morale_die() {
    let (s, h) = seams(EPOCH_73_V36, true, Some((4, 4)));
    let (st, statics) = line("squad", vec![1, 1], 0.0, &h);
    let shot = run(&st, &statics, HOLD, s, &Terrain::default(), 3);
    assert_eq!(shot.rolls.len(), 1, "exactly the morale die: {:?}", shot.rolls);
    assert_eq!((shot.rolls[0].count, shot.rolls[0].owner.as_str()), (1, "Squad"));
    assert!(shot.log.iter().any(|l| l.starts_with("Dangerous terrain:")), "the applied rule names itself: {:?}", shot.log);
}

/// A single model reads its morale in wounds: 4 -> 3 of 6 is half its Tough value, so the cut test's tail is a die.
/// CONTROLS: no wound lost (3 -> 3) and a loss that stays above half (5 -> 4) draw nothing.
#[test]
fn a_single_model_tests_morale_only_when_the_cut_test_took_it_to_half() {
    let (s, h) = seams(EPOCH_73_V36, true, Some((1, 4)));
    let (st, statics) = line("tyrant", vec![3], 0.0, &h);
    let shot = run(&st, &statics, HOLD, s, &Terrain::default(), 3);
    assert_eq!(shot.rolls.len(), 1, "4 -> 3 of 6 draws the die: {:?}", shot.rolls);
    for (before, left) in [(3, 3), (5, 4)] {
        let (s, h) = seams(EPOCH_73_V36, true, Some((1, before)));
        let (st, statics) = line("tyrant", vec![left], 0.0, &h);
        let shot = run(&st, &statics, HOLD, s, &Terrain::default(), 3);
        assert!(shot.rolls.is_empty(), "{before} -> {left} of 6 draws nothing: {:?}", shot.rolls);
    }
}

/// Knob off = the numbers main always had: the same cut test without the key draws nothing and logs nothing; so does a
/// record below 73 even when the key is present.
#[test]
fn without_the_knob_or_below_73_the_cut_test_stays_silent() {
    for (epoch, replay) in [(EPOCH_73_V36, None), (EPOCH_72_PLAYTEST_RULES, Some((4, 4)))] {
        let (s, h) = seams(epoch, true, replay);
        let (st, statics) = line("squad", vec![1, 1], 0.0, &h);
        let shot = run(&st, &statics, HOLD, s, &Terrain::default(), 3);
        assert!(shot.rolls.is_empty(), "epoch {epoch}, replay {replay:?}: {:?}", shot.rolls);
        assert!(shot.log.iter().all(|l| !l.starts_with("Dangerous terrain:")), "{:?}", shot.log);
    }
}

/// THE PLAY LEG: in-game the core rolls its own test (knob `dangerous` stays on) and nothing sets the replay key, so the
/// activation must be byte-identical with and without it - the key is ignored while the test is not cut. The squad
/// Holds on the Dangerous bar (x = 4"), so the test IS drawn (the control that this leg can fail).
#[test]
fn the_live_test_is_untouched_by_the_replay_key() {
    let board = dangerous_bar_board();
    let seed = (1i64..)
        .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() >= 2)
        .unwrap();
    let play = |replay: Option<(i64, i64)>| {
        let (s, h) = seams(EPOCH_73_V36, false, replay);
        let (st, statics) = line("squad", vec![1; 4], 4.0, &h);
        let shot = run(&st, &statics, HOLD, s, &board, seed);
        (format!("{:?}", shot.rolls), format!("{:?}", shot.log))
    };
    let (old, with_key) = (play(None), play(Some((4, 4))));
    assert!(old.0.contains("count: 4"), "the live Dangerous test was drawn: {}", old.0);
    assert_eq!(old, with_key, "the key must change nothing while the core rolls its own test");
}

/// CHARGE: the charger's cut test cost it 2 wounds (6 -> 4). They count as wounds it TOOK in the melee result, so the
/// log reads "took 2 wounds" - without the knob it reads 0, which is how main loses the melee tally.
#[test]
fn a_chargers_cut_test_wounds_count_in_the_melee_result() {
    let took = |replay: Option<(i64, i64)>| {
        let (s, h) = seams(EPOCH_73_V36, true, replay);
        let (st, statics) = line("tyrant", vec![4], 0.0, &h);
        let shot = run(&st, &statics, CHARGE, s, &Terrain::default(), 5);
        shot.log.iter().find(|l| l.starts_with("[Melee result] Tyrant took")).cloned().unwrap_or_default()
    };
    assert!(took(Some((1, 6))).starts_with("[Melee result] Tyrant took 2 wounds"), "{}", took(Some((1, 6))));
    assert!(took(None).starts_with("[Melee result] Tyrant took 0 wounds"), "{}", took(None));
}
