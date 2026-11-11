//! W31-F5a1 tests (release 0.3.15): rules the registry-gated readers dropped in books that field them without a
//! mechanics row. The "is it automated?" test reads the static `modeled` list for every book, so these rules
//! neither applied nor told the player to do them by hand. Every carrier is built the way the game builds it (a
//! header profile with the book's slug and system, then `UnitStatic::build_for` at the live epoch) and read
//! through the stamp the rule uses. Each rule has a control book that already had its row.
//! Table twin: `test/v36/f5a1_silent_rows_test.gd`.
use super::super::*;

/// One unit of `book` carrying `rules` (a JSON array: the unit's own rules, as the army import writes them), with a
/// rifle and a melee blade.
fn f5_carrier(system: &str, book: &str, rules: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}},
          {{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("carrier").expect("carrier").clone()
}

fn f5_built(system: &str, book: &str, rules: &str) -> UnitStatic {
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &f5_carrier(system, book, rules), CURRENT_RULES_EPOCH)
}

/// The range half of the Royal Legion family: a book with the aura + its granted base (control: gf alien_hives)
/// and the two books whose base alone is fielded without a row.
#[test]
fn f5a1_increased_shooting_range_reaches_six_inches_where_the_book_fields_it() {
    let both = r#"["Increased Shooting Range Aura","Increased Shooting Range"]"#;
    assert_eq!(f5_built("gf", "alien_hives", both).royal_legion_range_in, 6.0, "the control book keeps its rows");
    assert_eq!(f5_built("gf", "elven_jesters", "[]").royal_legion_range_in, 0.0, "no rule, no reach");
    let mut dropped: Vec<String> = Vec::new();
    for (book, rules) in [("elven_jesters", both), ("elven_jesters", r#"["Increased Shooting Range"]"#),
                          ("blessed_sisters", r#"["Increased Shooting Range"]"#)] {
        let us = f5_built("gf", book, rules);
        let lifted = us.shoot.iter().filter(|sp| sp.range > 0).all(|sp| sp.reach_bonus_in == 6.0);
        if us.royal_legion_range_in != 6.0 || !lifted || !us.shoot[0].reach_bonus_rule.starts_with("Increased Shooting Range") {
            dropped.push(format!("gf/{book} {rules}"));
        }
    }
    assert!(dropped.is_empty(), "Increased Shooting Range silently dropped in: {dropped:?}");
}

#[test]
fn f5a1_piercing_target_places_its_token_where_the_book_fields_it() {
    let marks = |us: &UnitStatic| us.piercing_tags.iter().map(|t| (t.name.clone(), t.range_in)).collect::<Vec<_>>();
    let want = vec![("Piercing Target".to_string(), 18.0)];
    assert_eq!(marks(&f5_built("gf", "custodian_brothers", r#"["Piercing Target"]"#)), want, "control book");
    assert!(marks(&f5_built("gf", "alien_hives", "[]")).is_empty(), "no rule, no token");
    assert_eq!(marks(&f5_built("gf", "alien_hives", r#"["Piercing Target"]"#)), want,
        "gf/alien_hives: Piercing Target silently dropped");
}

#[test]
fn f5a1_takedown_shot_adds_its_extra_attack_where_the_book_fields_it() {
    let extra = |us: &UnitStatic| us.shoot.iter().filter(|sp| sp.name == "Takedown Shot").count();
    assert_eq!(extra(&f5_built("gf", "human_inquisition", r#"["Takedown Shot"]"#)), 1, "control book");
    assert_eq!(extra(&f5_built("gf", "elven_jesters", "[]")), 0, "no rule, no extra attack");
    assert_eq!(extra(&f5_built("gf", "elven_jesters", r#"["Takedown Shot"]"#)), 1,
        "gf/elven_jesters: Takedown Shot silently dropped");
}

/// Melee Slayer is one of the unit's own rules: the strike's AP spec exists only when the registry has its row.
#[test]
fn f5a1_melee_slayer_names_its_ap_spec_where_the_book_fields_it() {
    let named = |us: &UnitStatic| us.melee.iter().flat_map(|sp| sp.cond_ap.iter()).filter(|c| c.name == "Melee Slayer").count();
    let slayer = r#"["Melee Slayer"]"#;
    assert_eq!(named(&f5_built("gf", "blood_prime_brothers", slayer)), 1, "control book");
    assert_eq!(named(&f5_built("gf", "lust_disciples", "[]")), 0, "no rule, no AP spec");
    assert_eq!(named(&f5_built("gf", "lust_disciples", slayer)), 1, "gf/lust_disciples: Melee Slayer silently dropped");
}

#[test]
fn f5a1_hit_and_run_is_active_where_the_book_fields_it() {
    assert!(f5_built("gf", "custodian_brothers", r#"["Hit & Run"]"#).hit_and_run_active, "control book");
    assert!(!f5_built("aof", "high_elves", "[]").hit_and_run_active, "no rule, no step");
    assert!(f5_built("aof", "high_elves", r#"["Hit & Run"]"#).hit_and_run_active,
        "aof/high_elves: Hit & Run silently dropped");
}

/// Primeborn is the Fortified family's ungated spelling: the incoming AP is cut by one on every save batch.
#[test]
fn f5a1_primeborn_cuts_incoming_ap_where_the_book_fields_it() {
    let cut = |us: &UnitStatic| us.ctx.fortified_boost_ap + us.ctx.fortified_alias_ap;
    assert_eq!(cut(&f5_built("gf", "prime_brothers", r#"["Primeborn"]"#)), 1, "control book");
    assert_eq!(cut(&f5_built("gf", "wolf_prime_brothers", "[]")), 0, "no rule, no cut");
    assert_eq!(cut(&f5_built("gf", "wolf_prime_brothers", r#"["Primeborn"]"#)), 1,
        "gf/wolf_prime_brothers: Primeborn silently dropped");
}
