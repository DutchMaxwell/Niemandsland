//! MEL-07d tests (rules 3.6, lane melee): the Bloodthirsty Fighter follow-up strike is its own
//! strike, so the defender's Parry(X) event that sits between hit rolls and saves fires for it
//! too, with the same dice count as the strike it continues. A carrier without the rule keeps one
//! Parry event, and below epoch 73 no Parry die is drawn at all.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// The carrier, a plain carrier and the Parry(1) defender, all through the REAL registry
/// (`UnitStatic::build_for`), so `bloodthirsty_rule` and `parry_dice` are the live stamps.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"war_disciples",
    "special_rules":["Bloodthirsty Fighter"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":12,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"war_disciples",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":12,"count":1,"ap":0,"rules":[]}]},
  "defender":{"unit_id":"defender","name":"Defender","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":2,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"",
    "special_rules":["Parry(1)"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]}}}"#;

fn built(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get(id).expect(id), epoch)
}

/// One 12-attack strike by `carrier` into the 2-model Parry defender, tray seed 214: the
/// attacker's faces leave 7 hits, the first Parry cuts one, the six saves include two
/// unmodified 1s, and the two follow-up dice both hit.
fn strike(carrier: &UnitStatic, epoch: u32, gated: bool) -> ShootResult {
    let profiles = [carrier.melee[0].clone()];
    let att = Ctx { quality: 4, models: 1, rules_epoch: epoch, ..Default::default() };
    let def = Ctx { models: 2, ..built("defender", epoch).ctx };
    let mut tray = Tray::seeded(214);
    tray.set_zero_draws(true);
    resolve_melee_leg(&[striker(&profiles, &[0], &[12], &att)], &def, "Defender",
        false, true, true, false, 0.0, false, false, gated, false, false, &mut tray)
}

fn parry_count(r: &ShootResult) -> usize {
    r.rolls.iter().filter(|x| x.kind == "parry").count()
}

/// RED before the row: the follow-up's hits are saved without a second Parry event. GREEN:
/// the strike and its follow-up each draw one Parry event with the same dice count.
#[test]
fn the_follow_up_strike_keeps_its_parry_event_at_epoch_73() {
    let carrier = built("carrier", EPOCH_73_V36);
    assert!(!carrier.melee[0].bloodthirsty_rule.is_empty(), "the live stamp carries the rule");
    let def = built("defender", EPOCH_73_V36);
    assert_eq!(def.ctx.parry_dice, 1, "the live stamp carries Parry(1)");
    let r = strike(&carrier, EPOCH_73_V36, true);
    assert_eq!(parry_count(&r), 2, "the strike and its follow-up are one Parry event each: {:?}", r.rolls);
    let parry: Vec<&Roll> = r.rolls.iter().filter(|x| x.kind == "parry").collect();
    let attacks: Vec<&Roll> = r.rolls.iter().filter(|x| x.kind == "attack").collect();
    assert_eq!(attacks.len(), 2, "the blocked 1s pay a second attack slot: {:?}", r.rolls);
    let bt_hits = faces_to_hits(&attacks[1].faces, attacks[1].target as u8) as i64;
    assert_eq!(parry[1].count, bt_hits.min(2), "the follow-up keeps the strike's Parry dice count");
    assert!(r.log.iter().any(|l| l.contains("Bloodthirsty Fighter")), "{:?}", r.log);
}

/// CONTROL: a carrier without Bloodthirsty never makes a follow-up, so it keeps exactly one
/// Parry event for the strike.
#[test]
fn a_carrier_without_bloodthirsty_gets_one_parry_event() {
    let plain = built("plain", EPOCH_73_V36);
    let r = strike(&plain, EPOCH_73_V36, true);
    assert!(plain.melee[0].bloodthirsty_rule.is_empty(), "the plain carrier has no rule");
    assert_eq!(parry_count(&r), 1, "{:?}", r.rolls);
}

/// EPOCH CONTROL: below 73 the Parry stamp is off, so neither the strike nor the follow-up
/// draws a Parry die; the follow-up itself still fires.
#[test]
fn no_parry_events_are_drawn_at_epoch_72() {
    let carrier = built("carrier", EPOCH_72_PLAYTEST_RULES);
    let r = strike(&carrier, EPOCH_72_PLAYTEST_RULES, false);
    assert_eq!(parry_count(&r), 0, "{:?}", r.rolls);
    assert_eq!(r.rolls.iter().filter(|x| x.kind == "attack").count(), 2, "{:?}", r.rolls);
}
