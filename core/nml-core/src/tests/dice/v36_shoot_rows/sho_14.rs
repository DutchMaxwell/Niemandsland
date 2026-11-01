//! SHO-14 (rules 3.6, lane shoot): a Pierce weapon's saves ignore the target's POSITIVE Defense
//! modifiers (Cover, Shielded and its Defense(X)/Grounded aliases, Guarded, the Defensive growth
//! ladder, a Defense Buff) while Armor, Fortified and a NEGATIVE modifier still apply. Its AP(+1)
//! beyond half the weapon's range is pure data on the conditional-AP hook.
use super::super::*;

use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;
use crate::unit::UnitStatic;

/// One unit with a 24" Pierce rifle (weapon 0) and an identical plain rifle (weapon 1), so the
/// control and the rule share every other stamp.
const PIERCE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "piercer":{"unit_id":"piercer","name":"Piercer","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Pierce Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":["Pierce"]},
      {"name":"Plain Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

fn piercer(epoch: u32) -> UnitStatic {
    let header = read_act_header(PIERCE_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("piercer").expect("piercer");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// The save target the volley's defense batch rolled against.
fn save_target_of(out: &ShootResult) -> i64 {
    out.rolls.iter().find(|r| r.kind == "defense").expect("a save batch").target
}

/// The defender's Ctx at a record's own epoch: `rules_epoch` gates Pierce, `modifier_sum` is the
/// table's one-sum clamp from 68.
fn at(epoch: u32) -> Ctx {
    Ctx { rules_epoch: epoch, modifier_sum: epoch >= 68, ..defender(4, 5) }
}

fn covered(epoch: u32) -> Ctx {
    Ctx { in_cover: true, ..at(epoch) }
}

/// One volley of weapon `keep` at `d` inches.
fn volley(us: &UnitStatic, keep: usize, d: f64, def: &Ctx) -> ShootResult {
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&us.shoot, &[keep], &[6], &us.ctx, def, d, &mut tray)
}

/// RED/GREEN: a Pierce shot at a unit in cover drops the cover +1 at 73, and the log names it.
#[test]
fn pierce_ignores_cover_at_epoch_73() {
    let us = piercer(EPOCH_73_V36);
    let out = volley(&us, 0, 12.0, &covered(EPOCH_73_V36));
    assert_eq!(save_target_of(&out), 4, "Pierce ignores the target's cover");
    assert!(
        out.log.iter().any(|l| l.contains("Pierce") && l.contains("Cover +1")),
        "one line per Pierce volley names the ignored part: {:?}",
        out.log
    );
}

/// OLD leg: at 72 the same weapon counts the cover — a 3.5 record has no Pierce entry and the gate
/// is off, so the fold is byte-identical to a weapon without the rule.
#[test]
fn pierce_counts_cover_at_epoch_72() {
    let us = piercer(EPOCH_72_PLAYTEST_RULES);
    let pierce = volley(&us, 0, 12.0, &covered(EPOCH_72_PLAYTEST_RULES));
    let plain = volley(&us, 1, 12.0, &covered(EPOCH_72_PLAYTEST_RULES));
    assert_eq!(save_target_of(&pierce), 3, "below 73 the recorded cover fold stands");
    assert_eq!(save_target_of(&pierce), save_target_of(&plain), "byte-identical without the rule");
    assert!(!pierce.log.iter().any(|l| l.contains("Pierce")), "no line below 73: {:?}", pierce.log);
}

/// CONTROL: a non-Pierce weapon keeps its cover +1 at 73.
#[test]
fn a_plain_weapon_keeps_its_cover_at_epoch_73() {
    let us = piercer(EPOCH_73_V36);
    assert_eq!(save_target_of(&volley(&us, 1, 12.0, &covered(EPOCH_73_V36))), 3);
}

/// Armor SETS the Defense and stays; Shielded is a positive modifier and goes.
#[test]
fn pierce_keeps_armor_and_drops_shielded_at_epoch_73() {
    let armored = Ctx { defense: 3, shielded: true, ..at(EPOCH_73_V36) };
    let pierce = ShootProfile { name: "Pierce".into(), attacks: 6, range: 24, rules: vec!["Pierce".into()], ..Default::default() };
    let plain = ShootProfile { name: "Plain".into(), ..pierce.clone() };
    let mut t1 = Tray::seeded(27);
    let out = resolve_shooting_with_tray(std::slice::from_ref(&pierce), &[0], &[6], &at(EPOCH_73_V36), &armored, 12.0, &mut t1);
    assert_eq!(save_target_of(&out), 3, "Armor(3) stands; Shielded +1 is ignored");
    let mut t2 = Tray::seeded(27);
    let ctrl = resolve_shooting_with_tray(std::slice::from_ref(&plain), &[0], &[6], &at(EPOCH_73_V36), &armored, 12.0, &mut t2);
    assert_eq!(save_target_of(&ctrl), 2, "a plain weapon keeps Shielded +1 on Armor(3)");
}

/// Fortified lowers the attacker's AP and is NOT a Defense modifier, so Pierce keeps it.
#[test]
fn pierce_keeps_fortified_at_epoch_73() {
    let fort = Ctx { fortified: true, ..at(EPOCH_73_V36) };
    let ap2 = ShootProfile { name: "Pierce".into(), attacks: 6, range: 24, ap: 2, rules: vec!["Pierce".into()], ..Default::default() };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(std::slice::from_ref(&ap2), &[0], &[6], &at(EPOCH_73_V36), &fort, 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 5, "Fortified takes AP(2) to AP(1), not to AP(0) and not off");
}

/// A NEGATIVE modifier (Defense Debuff's positive `defense_mod`) still applies; a Defense Buff
/// (negative `defense_mod`) is a positive modifier and is dropped.
#[test]
fn pierce_keeps_a_negative_defense_modifier_at_epoch_73() {
    let hexed = Ctx { defense_mod: 1, ..at(EPOCH_73_V36) };
    let buffed = Ctx { defense_mod: -1, ..at(EPOCH_73_V36) };
    let pierce = ShootProfile { name: "Pierce".into(), attacks: 6, range: 24, rules: vec!["Pierce".into()], ..Default::default() };
    for (def, want, why) in [(hexed, 5, "the debuff still applies"), (buffed, 4, "the buff is ignored")] {
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(std::slice::from_ref(&pierce), &[0], &[6], &at(EPOCH_73_V36), &def, 12.0, &mut tray);
        assert_eq!(save_target_of(&out), want, "{why}");
    }
}

/// Part (b), pure data: the map entry grants AP(+1) strictly beyond half the weapon's range.
#[test]
fn pierce_gains_ap_beyond_half_the_weapon_range_at_epoch_73() {
    let us = piercer(EPOCH_73_V36);
    let inside = volley(&us, 0, 12.0, &at(EPOCH_73_V36));
    let beyond = volley(&us, 0, 18.0, &at(EPOCH_73_V36));
    assert_eq!(save_target_of(&inside), 4, "exactly half the range is not beyond it");
    assert_eq!(save_target_of(&beyond), 5, "over half the 24\" range: AP(+1)");
    assert!(
        beyond.log.iter().any(|l| l.contains("Pierce") && l.contains("half the weapon's range")),
        "the conditional AP names itself: {:?}",
        beyond.log
    );
}
