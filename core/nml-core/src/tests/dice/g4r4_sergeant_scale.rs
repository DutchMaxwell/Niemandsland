use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::effective_attacks;

// ------ G4R4 C-SERGEANT-SCALE: the Sergeant bearer's share is a share of the FULL attack pool ------
//
// The table stamps the bearer's share on the member's profile BEFORE the sighted scaling (`AiEv.stamp_sergeant`
// on the full-strength profile) and strikes `min(plain, round(plain * share / full attacks))` hits at AP(+1).
// The core read the SIGHTED dice count instead, so one sighted model of ten (2 dice of 20) was a 50 % chunk of
// the volley where the table's is about one in ten. Units are built the way the game builds them: a recorded
// header profile over the real registry, the dice count from the same pro-rata scaling the volley uses.

const MODELS: i64 = 10;

fn squad(epoch: u32) -> UnitStatic {
    let header = r#"{"kind":"header","knobs":{},"profiles":{"sgt":{"unit_id":"sgt","name":"Squad",
        "quality":4,"defense":4,"tough":1,"wounds_max":[1,1,1,1,1,1,1,1,1,1],"model_count":10,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres","special_rules":["Sergeant"],
        "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":10,"ap":0,"rules":[]}]}}}"#;
    let hdr = read_act_header(header).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, hdr.profiles.get("sgt").expect("sgt"), epoch)
}

/// The log of one volley of `sighted` models of the ten, seeded so the first roll is `want_hits` hits.
fn volley_log(us: &UnitStatic, sighted: i64, want_hits: i64) -> (Vec<String>, usize) {
    let p = [us.shoot[0].clone()];
    let n = effective_attacks(p[0].attacks, sighted, MODELS);
    let att = Ctx { quality: 4, models: MODELS, ..Default::default() };
    let seed = (0..5000i64)
        .find(|&s| faces_to_hits(&Tray::seeded(s).roll(n as usize), 4) as i64 == want_hits)
        .expect("a seed with the wanted hits");
    let mut tray = Tray::seeded(seed);
    let r = resolve_volley_with_tray(&[striker(&p, &[0], &[n], &att)], &defender(4, 5), "Target", 12.0, 12.0, true, true, true, false, &mut tray);
    let saves = r.rolls.iter().filter(|x| x.kind == "defense").count();
    (r.log, saves)
}

fn sergeant_lines(log: &[String]) -> Vec<&String> {
    log.iter().filter(|l| l.starts_with("Sergeant:")).collect()
}

/// (a) One sighted model of ten fires 2 of the 20 dice; both hit. The bearer's share is one model's 2 attacks of
/// the 20, so 2 hits give round(2 * 2 / 20) = 0 Sergeant hits and the volley saves as one plain batch.
/// RED on main: the share was read off the 2 sighted dice (1 of 2), so the log carries "Sergeant ... 1 hit".
#[test]
fn one_sighted_model_of_ten_gives_the_bearer_no_hit_at_73() {
    let us = squad(EPOCH_73_V36);
    let (log, saves) = volley_log(&us, 1, 2);
    assert!(sergeant_lines(&log).is_empty(), "no Sergeant strike on 2 hits of a 20-attack pool: {log:?}");
    assert_eq!(saves, 1, "one plain save batch: {log:?}");
}

/// (b) Two sighted models: 4 dice, all hit. round(4 * 2 / 20) = 0 again (the sighted-dice read struck 1).
#[test]
fn two_sighted_models_of_ten_still_give_the_bearer_no_hit_at_73() {
    let us = squad(EPOCH_73_V36);
    let (log, _) = volley_log(&us, 2, 4);
    assert!(sergeant_lines(&log).is_empty(), "round(4 * 2 / 20) = 0: {log:?}");
}

/// (c) Control: the whole squad sighted, 20 dice, 10 hit -> round(10 * 2 / 20) = 1 Sergeant hit. Both reads agree
/// at full strength, so this must stay green before and after.
#[test]
fn a_fully_sighted_squad_strikes_the_bearer_share_at_73() {
    let us = squad(EPOCH_73_V36);
    let (log, saves) = volley_log(&us, MODELS, 10);
    assert_eq!(sergeant_lines(&log), vec!["Sergeant: Striker strikes 1 hit with AP(+1)"], "{log:?}");
    assert_eq!(saves, 2, "the bearer's batch and the rest: {log:?}");
}

/// (d) Control: below 73 the rule is not played at all, sighted or not.
#[test]
fn below_73_the_sergeant_never_strikes() {
    let us = squad(EPOCH_72_PLAYTEST_RULES);
    let (log, _) = volley_log(&us, 1, 2);
    assert!(sergeant_lines(&log).is_empty(), "{log:?}");
}
