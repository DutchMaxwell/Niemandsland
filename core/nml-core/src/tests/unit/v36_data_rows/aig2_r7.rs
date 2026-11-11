//! AI-G2 row R7 (release 0.3.15, rules epoch 73): the Eternal Wardens' `Enhanced Warden` printed the same
//! `incoming_ap_reduction` as `Warden` (1), so the enhanced form changed nothing. The book gives the enhanced form a
//! LARGER cut (2 instead of 1) that REPLACES the base value; it never stacks on it (1 + 2). Below epoch 73 the
//! reading stays 1. Every carrier is the real `build_for` product through the real registry, and the save target
//! comes from the real melee dice path. Table twin: `test/v36/aig2_r7_enhanced_warden_test.gd`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One aof/eternal_wardens unit carrying `rules` (a JSON array, as the army import writes them) whose CCW is AP(2).
fn warden_unit(rules: &str, epoch: u32) -> UnitStatic {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Wardens","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"eternal_wardens",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Blade","range":0,"attacks":2,"count":1,"ap":2,"rules":["AP(2)"]}}]}}}}}}"#
    );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
}

/// The save target of one AP(2) strike phase (64 attacks) against the unit: the real melee dice path.
fn melee_save_target(us: &UnitStatic) -> (i64, bool) {
    let strikers = [crate::dice::Shooter { profiles: &us.melee, keep: &[0], attacks: &[64], att: &us.ctx, owner: "att" }];
    let mut tray = crate::dice::Tray::seeded(27);
    let out = crate::dice::resolve_melee_with_tray(&strikers, &us.ctx, "def", false, true, false, &mut tray);
    (out.rolls[1].target, out.fortified_fired)
}

#[test]
fn aig2_r7_enhanced_warden_cuts_two_ap_and_replaces_the_base_cut() {
    let both = warden_unit(r#"["Warden","Enhanced Warden"]"#, EPOCH_73_V36);
    assert_eq!(both.ctx.fortified_boost_ap, 2, "the enhanced form's cut REPLACES the base 1 (never 1 + 2)");
    assert_eq!(both.fortified_boost_name, "Enhanced Warden", "the log names the rule that supplies the cut");
    let (target, fired) = melee_save_target(&both);
    assert_eq!(target, 4, "AP(2) minus 2 = AP(0): Defense 4 saves on 4+");
    assert!(fired, "rules-must-log: the cut is reported");
}

#[test]
fn aig2_r7_the_base_and_the_aura_granted_form_read_their_own_value() {
    let base = warden_unit(r#"["Warden"]"#, EPOCH_73_V36);
    assert_eq!((base.ctx.fortified_boost_ap, base.fortified_boost_name.as_str()), (1, "Warden"));
    assert_eq!(melee_save_target(&base).0, 5, "control: Warden alone cuts one AP, AP(2) -> AP(1)");
    let plain = warden_unit("[]", EPOCH_73_V36);
    assert_eq!(melee_save_target(&plain).0, 6, "control: no rule, AP(2) stands");
    let aura = warden_unit(r#"["Warden","Enhanced Warden Aura"]"#, EPOCH_73_V36);
    assert_eq!(aura.ctx.fortified_boost_ap, 2, "the aura hands the enhanced form its own cut");
    assert_eq!(aura.fortified_boost_name, "Enhanced Warden");
}

#[test]
fn aig2_r7_below_epoch_73_the_enhanced_form_keeps_cutting_one() {
    let both = warden_unit(r#"["Warden","Enhanced Warden"]"#, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(both.ctx.fortified_boost_ap, 1, "epoch 72 replays byte-identical");
    assert_eq!(melee_save_target(&both).0, 5);
}
