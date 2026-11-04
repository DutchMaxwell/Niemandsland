//! G4R4 row C-GRANTED-BANE: a cast that hands the shooter "Bane when Shooting" ("Breath of Change") makes its ranged
//! weapons Bane weapons for the volley: the defender re-rolls its unmodified Defense 6s. The table reads the live grant
//! (`_solo_striker_has_bane`); the core's live context had no Bane grant to read, so the re-roll never happened.
//! From `EPOCH_73_V36` the volley reads it (battle log: "Bane when Shooting: ... re-rolls N unmodified Defense 6s").
//! Replay row: gf_1000_net_037 act 10 (the harness half, carrying the cast's token into the act's `pre` block, is a
//! separate row).
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real Titan Lords shooter: two models, ten attacks each with a plain rifle (no Bane of its own).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "shooter":{"unit_id":"shooter","name":"Shooter","quality":4,"defense":4,"tough":1,"wounds_max":[1,1],"model_count":2,
    "caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"titan_lords",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":10,"count":2,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// One live ledger record on the shooter's own net: the granted rule name, once.
fn grant(rule: &str) -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from(rule),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from(rule),
    }
}

/// The shooter "a" (built the way the game builds it) and the target "b" 12" away, three models on a 4+ save.
fn line(epoch: u32, granted: Option<&str>) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    statics[0] = UnitStatic::build_for(&mut reg, header.profiles.get("shooter").expect("shooter"), epoch);
    // `ah` off the firing line so nothing else joins the volley.
    st.positions[1] = vec![[-2.0 * IN2M, 5.0 * IN2M, 0.0]];
    if let Some(rule) = granted {
        st.buffs[0].push(grant(rule));
    }
    (st, statics)
}

fn volley(st: &State, statics: &[UnitStatic], epoch: u32, seed: i64) -> ShootResult {
    let seams = Seams { sighting: true, rules_epoch: epoch, ..Default::default() };
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(statics, st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray).unwrap().1
}

/// The first seed whose plain volley saves at least one unmodified 6 (the Bane window's only trigger).
fn seed_with_a_saved_six(st: &State, statics: &[UnitStatic], epoch: u32) -> i64 {
    (0..200)
        .find(|&s| volley(st, statics, epoch, s).rolls.iter().find(|r| r.kind == "defense").is_some_and(|r| r.faces.contains(&6)))
        .expect("a seed with a saved 6")
}

fn defense_rolls(shot: &ShootResult) -> usize {
    shot.rolls.iter().filter(|r| r.kind == "defense").count()
}

/// The row: with the grant the defender re-rolls its saved 6s (a second Defense roll), and the log names the rule.
/// RED on main: the grant is on the ledger but nothing in the live context reads it, so there is no re-roll.
#[test]
fn a_granted_bane_when_shooting_makes_the_defender_re_roll_its_sixes_at_73() {
    let (st, statics) = line(EPOCH_73_V36, Some("Bane when Shooting"));
    let seed = seed_with_a_saved_six(&st, &statics, EPOCH_73_V36);
    let shot = volley(&st, &statics, EPOCH_73_V36, seed);
    assert_eq!(defense_rolls(&shot), 2, "the saves and the Bane re-roll of the saved 6s: {:?}", shot.rolls);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Bane when Shooting:") && l.contains("re-rolls")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// CONTROL: the same volley without the grant has no re-roll.
#[test]
fn without_the_grant_the_defender_keeps_its_sixes() {
    let (st, statics) = line(EPOCH_73_V36, None);
    let seed = seed_with_a_saved_six(&st, &statics, EPOCH_73_V36);
    assert_eq!(defense_rolls(&volley(&st, &statics, EPOCH_73_V36, seed)), 1);
}

/// CONTROL: a granted rule that is no Bane (the Furious record of the other grant tests) adds no re-roll.
#[test]
fn a_grant_that_is_no_bane_adds_no_re_roll() {
    let (st, statics) = line(EPOCH_73_V36, Some("Furious"));
    let seed = seed_with_a_saved_six(&st, &statics, EPOCH_73_V36);
    assert_eq!(defense_rolls(&volley(&st, &statics, EPOCH_73_V36, seed)), 1);
}

/// CONTROL: below 73 the grant stays inert, byte for byte.
#[test]
fn below_73_the_grant_adds_no_re_roll() {
    let (st, statics) = line(EPOCH_72_PLAYTEST_RULES, Some("Bane when Shooting"));
    let seed = seed_with_a_saved_six(&st, &statics, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(defense_rolls(&volley(&st, &statics, EPOCH_72_PLAYTEST_RULES, seed)), 1);
}
