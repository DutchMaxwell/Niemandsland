//! AIG-G2 R4 (release 0.3.15): "Increased Shooting Range" on a JOINED HERO. The table's shooting gate used to read the
//! host's bonus for the whole chain, so a hero carrying the rule printed "weapon reach 12"" for his own 12" gun. The core
//! carries a joined hero as his own roster row with his own profile, so the stamp is per row: the hero's gun reaches 18",
//! the host's own guns stay at 12" (the rule is the hero's), and below epoch 73 nothing reads the grant. The header shape
//! below is the one a recorded ratmen act carries (host with `attached_hero_rules`, the hero as his own profile).
//! Table twin: `test/v36/aig2_r4_isr_hero_test.gd`.
use super::super::*;

fn r4_profiles() -> (Profile, Profile) {
    let hero_rules = r#"["Tough(3)","Scurry","Unique Hero","Quick Throw","Tinkering Inventor","Increased Shooting Range"]"#;
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "grenadiers":{{"unit_id":"grenadiers","name":"Grenadiers","quality":5,"defense":5,"tough":1,"wounds_max":[1],
        "model_count":10,"caster_value":0,"base_radius":0.0125,"game_system":"aof","faction_folder":"ratmen",
        "special_rules":["Quick Throw","Scurry"],"item_grants":[],"attached_hero_rules":[{hero_rules}],
        "move_bands":{{"advance":7.0,"rush":14.0}},
        "weapons":[{{"name":"Toxin Bombs","range":12,"attacks":1,"count":10,"ap":0,"rules":[]}},
          {{"name":"Strike","range":0,"attacks":1,"count":10,"ap":0,"rules":[]}}]}},
      "getrie":{{"unit_id":"getrie","name":"Getrie Veikasip","quality":5,"defense":5,"tough":3,"wounds_max":[3],
        "model_count":1,"caster_value":0,"base_radius":0.0125,"game_system":"aof","faction_folder":"ratmen",
        "special_rules":{hero_rules},"item_grants":[],"attached_hero_rules":[],
        "move_bands":{{"advance":7.0,"rush":14.0}},
        "weapons":[{{"name":"Artificer Bombs","range":12,"attacks":1,"count":1,"ap":0,"rules":[]}},
          {{"name":"Overtuned Halberd","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    let h = read_act_header(&tpl).expect("header");
    (h.profiles.get("grenadiers").expect("host").clone(), h.profiles.get("getrie").expect("hero").clone())
}

/// The longest reach a row's ranged guns have: printed range plus the stamped bonus (the table's `range + bonus`).
fn r4_reach(us: &UnitStatic) -> f64 {
    us.shoot.iter().filter(|p| p.range > 0).map(|p| p.range as f64 + p.reach_bonus_in).fold(0.0_f64, f64::max)
}

#[test]
fn aig2_r4_a_joined_heros_own_gun_reaches_18_and_the_hosts_stays_12_from_epoch_73() {
    let (host, hero) = r4_profiles();
    let mut reg = Registries::new(&repo_root());
    let (h, g) = (
        UnitStatic::build_for(&mut reg, &host, crate::acts::EPOCH_73_V36),
        UnitStatic::build_for(&mut reg, &hero, crate::acts::EPOCH_73_V36),
    );
    assert_eq!(r4_reach(&g), 18.0, "Getrie's 12\" Artificer Bombs + his own Increased Shooting Range");
    assert!(g.shoot.iter().filter(|p| p.range > 0).all(|p| p.reach_bonus_rule == "Increased Shooting Range"),
        "the log names the BOOK rule, got {:?}", g.shoot.iter().map(|p| p.reach_bonus_rule.clone()).collect::<Vec<_>>());
    assert_eq!(r4_reach(&h), 12.0, "the hero's rule is not the host's: the Toxin Bombs keep their printed 12\"");
    assert_eq!(r4_reach(&h).max(r4_reach(&g)), 18.0, "the chain's gate reach is the longest member reach");
}

#[test]
fn aig2_r4_below_epoch_73_a_joined_heros_gun_keeps_its_printed_reach() {
    let (_, hero) = r4_profiles();
    let mut reg = Registries::new(&repo_root());
    let g = UnitStatic::build_for(&mut reg, &hero, crate::acts::EPOCH_73_V36 - 1);
    assert_eq!(r4_reach(&g), 12.0, "below 73 the core never read the grant");
}
