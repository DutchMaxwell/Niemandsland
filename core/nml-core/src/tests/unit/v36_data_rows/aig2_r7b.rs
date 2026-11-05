//! AI-G2 row R7b (release 0.3.15, rules epoch 73), sibling of R7: the Custodian Brothers' `Enhanced Guardian` and the
//! Ossified Undead's `Enhanced Ossified` read the same `incoming_ap_reduction` as their base (1). Their 3.6 books give
//! the enhanced form a LARGER cut (2 instead of 1) that REPLACES the base value; it never stacks on it (1 + 2). Below
//! epoch 73 the reading stays 1. Every carrier is the real `build_for` product through the real registry, and the save
//! target comes from the real melee dice path. Table twin: `test/v36/aig2_r7b_enhanced_guardian_ossified_test.gd`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One unit of `faction` carrying `rules` (a JSON array, as the army import writes them) whose CCW is AP(2).
fn book_unit(system: &str, faction: &str, rules: &str, epoch: u32) -> UnitStatic {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Bearers","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{faction}",
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

/// (system, book, base rule, enhanced rule) of the two siblings.
const SIBLINGS: [(&str, &str, &str, &str); 2] = [
    ("gf", "custodian_brothers", "Guardian", "Enhanced Guardian"),
    ("aof", "ossified_undead", "Ossified", "Enhanced Ossified"),
];

#[test]
fn aig2_r7b_the_enhanced_form_cuts_two_ap_and_replaces_the_base_cut() {
    let mut wrong: Vec<String> = Vec::new();
    for (system, book, base, enhanced) in SIBLINGS {
        let both = book_unit(system, book, &format!(r#"["{base}","{enhanced}"]"#), EPOCH_73_V36);
        let (target, fired) = melee_save_target(&both);
        if (both.ctx.fortified_boost_ap, both.fortified_boost_name.as_str()) != (2, enhanced) || target != 4 || !fired {
            wrong.push(format!("{system}/{book}: cut {} name {} target {target} fired {fired}", both.ctx.fortified_boost_ap, both.fortified_boost_name));
        }
    }
    assert!(wrong.is_empty(), "the enhanced form must cut AP(2) to AP(0), replacing the base's cut of 1: {wrong:?}");
}

#[test]
fn aig2_r7b_the_base_and_the_aura_granted_form_read_their_own_value() {
    for (system, book, base, enhanced) in SIBLINGS {
        let alone = book_unit(system, book, &format!(r#"["{base}"]"#), EPOCH_73_V36);
        assert_eq!((alone.ctx.fortified_boost_ap, alone.fortified_boost_name.as_str()), (1, base), "{book}: control");
        assert_eq!(melee_save_target(&alone).0, 5, "{book}: control, the base alone cuts one AP, AP(2) -> AP(1)");
        assert_eq!(melee_save_target(&book_unit(system, book, "[]", EPOCH_73_V36)).0, 6, "{book}: no rule, AP(2) stands");
        let aura = book_unit(system, book, &format!(r#"["{base}","{enhanced} Aura"]"#), EPOCH_73_V36);
        assert_eq!((aura.ctx.fortified_boost_ap, aura.fortified_boost_name.as_str()), (2, enhanced), "{book}: the aura's grant");
    }
}

#[test]
fn aig2_r7b_below_epoch_73_the_enhanced_form_keeps_cutting_one() {
    for (system, book, base, enhanced) in SIBLINGS {
        let both = book_unit(system, book, &format!(r#"["{base}","{enhanced}"]"#), EPOCH_72_PLAYTEST_RULES);
        assert_eq!(both.ctx.fortified_boost_ap, 1, "{book}: epoch 72 replays byte-identical");
        assert_eq!(melee_save_target(&both).0, 5, "{book}: epoch 72");
    }
}
