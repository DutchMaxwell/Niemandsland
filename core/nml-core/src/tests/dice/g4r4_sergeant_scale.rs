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

// ------ The bearer's strike is said on the tray, as the table says it (`_solo_resolve_saves`) ------

/// The whole squad strikes with 10 of 20 dice hitting: one Sergeant hit. The supplied replay of a seeded run says the
/// table's line right before the bearer's save batch (the one at AP 1), on the volley leg and on the melee leg alike.
/// RED on main: the line is only in the resolve's own `log`, never on the tray, so nothing reaches the battle log.
#[test]
fn the_bearers_strike_is_said_before_its_save_batch_on_the_volley_and_the_melee_leg() {
    let us = squad(EPOCH_73_V36);
    let n = effective_attacks(us.shoot[0].attacks, MODELS, MODELS);
    let att = Ctx { quality: 4, models: MODELS, side: 1, ..Default::default() };
    let seed = (0..5000i64)
        .find(|&s| faces_to_hits(&Tray::seeded(s).roll(n as usize), 4) as i64 == 10)
        .expect("a seed with the wanted hits");
    let shoot = [us.shoot[0].clone()];
    let melee = [ShootProfile { range: 0, ..us.shoot[0].clone() }];
    for (leg, rule) in [("volley", "shoot"), ("melee", "melee")] {
        let run = |tray: &mut Tray| match leg {
            "volley" => resolve_volley_with_tray(&[striker(&shoot, &[0], &[n], &att)], &defender(4, 5), "Target", 12.0, 12.0, true, true, true, false, tray),
            _ => resolve_melee_with_tray(&[striker(&melee, &[0], &[n], &att)], &defender(4, 5), "Target", true, true, true, tray),
        };
        let seeded = run(&mut Tray::seeded(seed));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
        let again = run(&mut tray);
        assert_eq!(again.rolls, seeded.rolls, "{leg}: the same dice either way");
        let lines = tray.all_lines();
        let at = lines.iter().position(|l| l.text == "Sergeant: Striker strikes 1 hit with AP(+1)")
            .unwrap_or_else(|| panic!("{leg}: no Sergeant line on the tray: {lines:?}"));
        assert_eq!((lines[at].rule, lines[at].category, lines[at].side), (rule, crate::logline::Category::Combat, 1), "{leg}");
        assert_eq!(lines[at + 1].text, "Target saves on 5+ (Def 4+, AP 1)", "{leg}: the bearer's own save batch follows");
        assert_eq!(lines.iter().filter(|l| l.text.starts_with("Sergeant:")).count(), 1, "{leg}: said once");
    }
}
