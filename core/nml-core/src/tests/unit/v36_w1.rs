//! Rules 3.6 lane w1 tests for the unit module; owned by lane w1.
use crate::acts::{rule_on, CURRENT_RULES_EPOCH, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// D-EPOCH: the whole rules 3.6 wave shares one epoch, and it is the live one, so a fresh
/// `play_game()` stamps it and every 3.6 gate written against `EPOCH_73_V36` is on.
#[test]
fn the_rules_3_6_wave_is_the_live_epoch_73() {
    assert_eq!(EPOCH_73_V36, 73, "the rules 3.6 wave's one frozen epoch");
    assert_eq!(CURRENT_RULES_EPOCH, EPOCH_73_V36, "the live epoch is EPOCH_73_V36");
    assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_73_V36), "a fresh record gets the 3.6 gates");
}

/// The old leg: the play-test fixes keep their own frozen gate, and a record stamped with it
/// gets none of the rules 3.6 behaviour.
#[test]
fn a_record_at_epoch_72_gets_no_rules_3_6_gate() {
    assert_eq!(EPOCH_72_PLAYTEST_RULES, 72, "the play-test fixes' gate stays frozen at 72");
    assert!(rule_on(EPOCH_72_PLAYTEST_RULES, EPOCH_72_PLAYTEST_RULES), "72 keeps its own rules");
    assert!(!rule_on(EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36), "72 is below every 3.6 gate");
    assert!(rule_on(EPOCH_73_V36, EPOCH_72_PLAYTEST_RULES), "73 keeps the play-test fixes");
}

/// D-MOST: one row of the "most models" case table. test/v36/w1_4_test.gd carries the same
/// rows under the same names, so both engines answer every row alike.
struct MostCase {
    name: &'static str,
    host_rules: &'static [&'static str],
    host_models: i64,
    host_dead: i64,
    /// Each joined hero: its own rules, and whether it still lives.
    heroes: &'static [(&'static [&'static str], bool)],
    solo: bool,
    want: bool,
}

const PLAIN_HERO: (&[&str], bool) = (&["Hero"], true);
const FEARLESS_HERO: (&[&str], bool) = (&["Hero", "Fearless"], true);

#[rustfmt::skip]
const MOST_CASES: &[MostCase] = &[
    MostCase { name: "three host models with it, two joined heroes without: 3 of 5, on", host_rules: &["Fearless"], host_models: 3, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: true },
    MostCase { name: "one host model with it, one joined hero without: an exact half, off", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO], solo: false, want: false },
    MostCase { name: "one host model without it, a joined hero with it: 1 of 2, off", host_rules: &[], host_models: 1, host_dead: 0, heroes: &[FEARLESS_HERO], solo: false, want: false },
    MostCase { name: "two host models without it, a joined hero with it: 1 of 3, off", host_rules: &[], host_models: 2, host_dead: 0, heroes: &[FEARLESS_HERO], solo: false, want: false },
    MostCase { name: "a Tough(6) joined hero without it is one model, not six wounds: 2 of 3, on", host_rules: &["Fearless"], host_models: 2, host_dead: 0, heroes: &[(&["Hero", "Tough(6)"], true)], solo: false, want: true },
    MostCase { name: "a Tough(6) joined hero with it is one model, not six wounds: 1 of 3, off", host_rules: &[], host_models: 2, host_dead: 0, heroes: &[(&["Hero", "Fearless", "Tough(6)"], true)], solo: false, want: false },
    MostCase { name: "a Tough(3) host model with it is one model, not three wounds: 1 of 3, off", host_rules: &["Fearless", "Tough(3)"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: false },
    MostCase { name: "a lone hero keeps its own rule", host_rules: &["Hero", "Fearless"], host_models: 1, host_dead: 0, heroes: &[], solo: false, want: true },
    MostCase { name: "a lone hero without the rule stays off", host_rules: &["Hero"], host_models: 1, host_dead: 0, heroes: &[], solo: false, want: false },
    MostCase { name: "dead host models without it do not count: 2 of 3 living, on", host_rules: &[], host_models: 3, host_dead: 2, heroes: &[FEARLESS_HERO, FEARLESS_HERO], solo: false, want: true },
    MostCase { name: "dead host models with it do not count: 1 of 3 living, off", host_rules: &["Fearless"], host_models: 3, host_dead: 2, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: false },
    MostCase { name: "a fallen joined hero without it does not count: 1 of 1, on", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[(&["Hero"], false)], solo: false, want: true },
    MostCase { name: "a wiped-out unit has no majority", host_rules: &["Fearless"], host_models: 2, host_dead: 2, heroes: &[], solo: false, want: false },
    MostCase { name: "solo: the picked host model answers from its own unit, on", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: true, want: true },
    MostCase { name: "solo: the collapse never borrows the heroes' rule, off", host_rules: &[], host_models: 1, host_dead: 0, heroes: &[FEARLESS_HERO, FEARLESS_HERO], solo: true, want: false },
    MostCase { name: "solo: a host with no living model is off", host_rules: &["Fearless"], host_models: 1, host_dead: 1, heroes: &[], solo: true, want: false },
];

/// The core reads a unit's living model count off the live state, and its per-activation
/// profile lists only the living joined heroes (a fallen hero drops out of
/// `attached_hero_rules`), so the fixture hands the reader exactly that.
fn most_of(c: &MostCase) -> bool {
    let mut p: crate::state::Profile =
        serde_json::from_str(r#"{"unit_id":"host","name":"Host"}"#).unwrap();
    p.special_rules = c.host_rules.iter().map(|r| r.to_string()).collect();
    p.attached_hero_rules = c
        .heroes
        .iter()
        .filter(|(_, alive)| *alive)
        .map(|(rules, _)| rules.iter().map(|r| r.to_string()).collect())
        .collect();
    crate::unit::rule_on_most_models(&p, c.host_models - c.host_dead, "Fearless", c.solo)
}

#[test]
fn rule_on_most_models_answers_the_shared_case_table() {
    for c in MOST_CASES {
        assert_eq!(most_of(c), c.want, "{}", c.name);
    }
}

/// The one majority test the morale rows count live state with: strictly more than half.
#[test]
fn most_models_of_needs_a_strict_majority() {
    assert!(!crate::unit::most_models_of(1, 2), "an exact half is not most");
    assert!(crate::unit::most_models_of(2, 3), "2 of 3 is most");
    assert!(!crate::unit::most_models_of(0, 0), "an empty unit has no majority");
    assert!(crate::unit::most_models_of(1, 1), "1 of 1 is most");
    assert!(!crate::unit::most_models_of(2, 5), "2 of 5 is not most");
}

/// W1.3: a named hero carries "Unique Hero" in place of a separate "Hero" rule, and the profile's
/// hero stamp answers it like "Hero" (wound order, the relay's hero clause, the net's hero token).
/// test/v36/w1_3_test.gd pins the same rows on GameUnit.is_hero(). A rule that only contains the
/// word stays no hero.
#[test]
fn a_unique_hero_is_stamped_a_hero() {
    const HERO_TEMPLATE: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;
    let cases: &[(&[&str], bool)] = &[
        (&["Unique Hero"], true),
        (&["Unique Hero", "Tough(3)"], true),
        (&["Hero"], true),
        (&["Fearless"], false),
        (&["Hero Hunter Made-Up"], false),
    ];
    let mut reg = crate::rules::Registries::new(&super::repo_root());
    for (rules, want) in cases {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let text = HERO_TEMPLATE.replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = crate::acts::read_act_header(&text).expect("HERO_TEMPLATE parses");
        let p = header.profiles.get("carrier").expect("carrier");
        let us = crate::unit::UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH);
        assert_eq!(us.is_hero, *want, "{rules:?}: want is_hero {want}");
    }
}

/// W1.6 (D-ENH): rules 3.6 books print "Enhanced <X>" where 3.5 books printed "<X> Boost"
/// ("Enhanced <X> Aura" / "Enhanced <X> Buff" for the carried forms). The 3.6 name stamps
/// exactly the effect the 3.5 name stamped; the 3.5 name is gone (no alias). Every carrier is
/// the REAL `build_for` product through the real registry, read at the 3.6 epoch.
mod enhanced_renames {
    use super::super::*;
    use crate::acts::EPOCH_73_V36;

    /// One rifle and one blade, so both stamped arrays are non-empty.
    const ENHANCED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// A carrier printing `rules` in `<system>/<faction>`, read at `EPOCH_73_V36`.
    fn enhanced_unit(system: &str, faction: &str, rules: &[&str]) -> UnitStatic {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = ENHANCED_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("ENHANCED_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), EPOCH_73_V36)
    }

    /// W1.6a, code literal (unit.rs Bane stamp): the widened save re-roll window over 9", and
    /// the volley log names the 3.6 rule.
    #[test]
    fn enhanced_bestial_widens_the_bane_window_like_its_3_5_boost() {
        let us = enhanced_unit("aof", "beastmen", &["Bestial", "Enhanced Bestial"]);
        assert!(us.shoot[0].bane, "the base still banes");
        assert_eq!(us.shoot[0].bane_low, 5, "the entry's reroll_save_low");
        assert_eq!(us.shoot[0].bane_over_in, 9.0, "the entry's over_in");
        assert_eq!(us.shoot[0].bane_rule, "Enhanced Bestial", "the window names the 3.6 rule");
        let p = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
        let mut tray = crate::dice::Tray::seeded(27);
        let shot = crate::dice::resolve_volley_with_tray(
            &strikers, &def, "Target", 12.0, 12.0, true, false, false, false, &mut tray,
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Enhanced Bestial")),
            "rules-must-log: the volley log prints the 3.6 name"
        );
        let old = enhanced_unit("aof", "beastmen", &["Bestial", "Bestial Boost"]);
        assert_eq!(old.shoot[0].bane_rule, "", "the 3.5 name is gone (no alias)");
    }

    /// W1.6a, code literals (unit.rs aura channel list + Shot Modifier names): the aura hands
    /// its base to the carrier, a flat +1 to hit when shooting.
    #[test]
    fn an_enhanced_buccaneer_aura_hands_its_flat_plus_one_like_its_3_5_boost_aura() {
        let us = enhanced_unit("aof", "sky_city_dwarves", &["Enhanced Buccaneer Aura"]);
        assert_eq!(us.shoot[0].hit_bonus, 1, "the granted base's flat hit_bonus");
        assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no over_in on the base");
        assert_eq!(us.melee[0].hit_bonus, 0, "shooting only");
    }

    /// W1.6a, map-only name (no code literal): the Shred upgrade stamps from its entry alone.
    /// Carried bare, so the stamp is its own (with the base carried too, the base entry comes
    /// first at the same amount and names the shred, exactly as with the 3.5 name).
    #[test]
    fn enhanced_destroyer_shreds_like_its_3_5_boost() {
        let us = enhanced_unit("aof", "ogres", &["Enhanced Destroyer"]);
        assert!(us.shoot[0].shred_alias, "a Shred carrier");
        assert_eq!(us.shoot[0].shred_low, 1, "carried bare: its own 1s window");
        assert_eq!(us.shoot[0].shred_ones_wound_bonus, 1, "the entry's extra_wound_per_save_one");
        assert_eq!(us.shoot[0].shred_ones_rule, "Enhanced Destroyer", "the stamp names the 3.6 rule");
        let full = enhanced_unit("aof", "ogres", &["Destroyer", "Enhanced Destroyer"]);
        assert_eq!(full.shoot[0].shred_low, 2, "with the base: the entry's save_fail_max window");
    }
}
