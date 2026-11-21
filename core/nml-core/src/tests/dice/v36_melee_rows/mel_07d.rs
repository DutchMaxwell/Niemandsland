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

/// Lines audit: the door's tray says the Parry event of the strike and of its follow-up, and the Bloodthirsty line with the weapon
/// (the table's words); both were in `ShootResult.log` only. RED on main: no tray line.
#[test]
fn the_door_tray_says_the_parry_and_bloodthirsty_lines() {
    let carrier = built("carrier", EPOCH_73_V36);
    let seeded = strike(&carrier, EPOCH_73_V36, true);
    let profiles = [carrier.melee[0].clone()];
    let att = Ctx { quality: 4, models: 1, rules_epoch: EPOCH_73_V36, ..Default::default() };
    let def = Ctx { models: 2, ..built("defender", EPOCH_73_V36).ctx };
    let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
    tray.set_zero_draws(true);
    resolve_melee_leg(&[striker(&profiles, &[0], &[12], &att)], &def, "Defender",
        false, true, true, false, 0.0, false, false, true, false, false, &mut tray);
    let said: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert_eq!(said.iter().filter(|l| l.starts_with("Parry: Defender rolls ") && l.contains(" dice and cancels ")).count(), 2, "{said:?}");
    assert!(said.iter().any(|l| l.starts_with("Bloodthirsty Fighter: ") && l.contains(" blocked 1") && (l.ends_with(" extra attacks with Blade") || l.ends_with(" extra attack with Blade"))), "{said:?}");
}

/// Lines audit: the strike fold asks the Regeneration bypass once per weapon with hits and says its name on the door tray (the table's
/// words): `<rule>: Regeneration ignored` for a registry bypass rule, `Unstoppable: Regeneration ignored` for the printed rule.
/// RED on main: the registry line was `ShootResult.log` only and the printed Unstoppable said nothing anywhere.
#[test]
fn the_door_tray_says_the_regeneration_bypass_of_a_strike() {
    let said = |rules: Vec<&str>, bypass_rule: &str| {
        let blade = ShootProfile { name: "Blade".into(), attacks: 12, count: 1, unstoppable: rules.contains(&"Unstoppable"), bypass_regen: !bypass_rule.is_empty(),
            rules: rules.iter().map(|r| r.to_string()).collect(), regen_bypass_rule: bypass_rule.into(), ..Default::default() };
        let profiles = [blade];
        let att = Ctx { quality: 4, models: 1, rules_epoch: EPOCH_73_V36, v36_rules: true, ..Default::default() };
        let def = Ctx { models: 2, regeneration: true, regen_target: 5, ..built("defender", EPOCH_73_V36).ctx };
        let run = |tray: &mut Tray| resolve_melee_leg(&[striker(&profiles, &[0], &[12], &att)], &def, "Defender",
            false, true, true, false, 0.0, false, false, true, false, false, tray);
        let seeded = run(&mut Tray::seeded(214));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
        run(&mut tray);
        tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>()
    };
    let named = said(vec!["Anti-Regen"], "Anti-Regen");
    assert_eq!(named.iter().filter(|l| *l == "Anti-Regen: Regeneration ignored").count(), 1, "{named:?}");
    let printed = said(vec!["Unstoppable"], "");
    assert_eq!(printed.iter().filter(|l| *l == "Unstoppable: Regeneration ignored").count(), 1, "{printed:?}");
    assert!(said(vec![], "").iter().all(|l| !l.contains("Regeneration ignored")), "a plain strike says nothing");
}

/// Lines audit: a Pierce strike names what it ignores on the door tray (the table's `_solo_resolve_saves` says it for strikes too: the
/// weapon and the target's positive Defense parts, no Cover in melee). RED on main: the melee fold said no Pierce line anywhere.
#[test]
fn a_pierce_strike_names_what_it_ignores_on_the_door_tray() {
    let said = |rules: Vec<&str>| {
        let blade = ShootProfile { name: "Blade".into(), attacks: 12, count: 1, rules: rules.iter().map(|r| r.to_string()).collect(), ..Default::default() };
        let profiles = [blade];
        let att = Ctx { quality: 4, models: 1, rules_epoch: EPOCH_73_V36, ..Default::default() };
        let def = Ctx { models: 2, shielded: true, in_cover: true, ..built("defender", EPOCH_73_V36).ctx };
        let run = |tray: &mut Tray| resolve_melee_leg(&[striker(&profiles, &[0], &[12], &att)], &def, "Defender",
            false, true, true, false, 0.0, false, false, true, false, false, tray);
        let seeded = run(&mut Tray::seeded(214));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
        run(&mut tray);
        tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>()
    };
    assert_eq!(said(vec!["Pierce"]).iter().filter(|l| *l == "Pierce: Blade ignores Shielded +1").count(), 1, "{:?}", said(vec!["Pierce"]));
    assert!(said(vec![]).iter().all(|l| !l.starts_with("Pierce:")), "a plain strike says nothing");
}
