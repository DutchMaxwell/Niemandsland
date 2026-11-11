use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// FAB-A4 (rules 3.6): the Unstoppable "own modifiers" fold must use the same
// GATED Artillery +1 the to-hit sum already uses. Today a moved Artillery
// shooter gets the ungated +1 back through the clamp. The shipped map's
// Artillery entry is the data under test; the weapon carries Unstoppable.

const ART_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Artillery"],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":["Unstoppable"]}]}}}"#;

fn art_at(epoch: u32) -> crate::unit::UnitStatic {
    let parsed = crate::acts::read_act_header(ART_HEADER).expect("header parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    crate::unit::UnitStatic::build_for(&mut reg, parsed.profiles.get("carrier").expect("carrier"), epoch)
}

/// One eight-shot Quality-4 volley at `dist_in`; returns the to-hit targets and the log.
fn volley(us: &crate::unit::UnitStatic, att: &Ctx, dist_in: f64) -> (Vec<i64>, Vec<String>) {
    let p = [us.shoot[0].clone()];
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let mut tray = Tray::seeded(17);
    let r = resolve_volley_with_tray(
        &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att, owner: "Carrier" }],
        &def, "Target", dist_in, dist_in, true, true, true, true, &mut tray,
    );
    (r.rolls.iter().filter(|x| x.kind == "attack").map(|x| x.target).collect(), r.log)
}

fn without_artillery(us: &crate::unit::UnitStatic) -> Ctx {
    Ctx { artillery: false, ..us.ctx }
}

fn keeps_own(log: &[String]) -> Option<String> {
    log.iter().find(|l| l.contains("Unstoppable") && l.contains("own")).cloned()
}

#[test]
fn moved_artillery_unstoppable_gets_no_phantom_plus_one_at_13in_at_epoch_73() {
    let us = art_at(EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let (targets, log) = volley(&us, &moved, 13.0);
    let (plain, _) = volley(&us, &without_artillery(&us), 13.0);
    assert_eq!(targets, plain, "RED on main: the ungated +1 rides the clamp: {log:?}");
    assert!(keeps_own(&log).is_none(), "no phantom own line: {log:?}");
}

#[test]
fn held_artillery_unstoppable_still_pays_the_plus_one_at_13in_at_epoch_73() {
    let us = art_at(EPOCH_73_V36);
    let held = Ctx { held: true, ..us.ctx };
    let (targets, _) = volley(&us, &held, 13.0);
    let (plain, _) = volley(&us, &without_artillery(&us), 13.0);
    assert_ne!(targets, plain, "a held gun over 12\" earns the +1");
}

#[test]
fn moved_artillery_unstoppable_stays_byte_identical_at_epoch_72() {
    let us = art_at(EPOCH_72_PLAYTEST_RULES);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let (targets, _) = volley(&us, &moved, 10.0);
    let (plain, _) = volley(&us, &without_artillery(&us), 10.0);
    assert_ne!(targets, plain, "epoch 72 keeps the older over-9\" +1");
}
