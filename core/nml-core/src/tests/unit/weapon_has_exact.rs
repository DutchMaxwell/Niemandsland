use super::*;

fn weapon_with(rules: &[&str]) -> Weapon {
    Weapon {
        name: "Blade".to_string(),
        range: 0.0,
        attacks: 2,
        count: 1,
        ap: 0,
        rules: rules.iter().map(|s| (*s).to_string()).collect(),
    }
}

#[test]
fn scoped_alias_names_do_not_match_base_weapon_rule() {
    let cases = [
        ("Shred in Melee", "Shred"),
        ("Shred when Shooting", "Shred"),
        ("Shred Mark", "Shred"),
        ("Shred in Melee Aura", "Shred"),
        ("Shred in Melee (spell)", "Shred"),
        ("Surge when Shooting", "Surge"),
        ("Surge Mark", "Surge"),
        ("Surge when Shooting Aura", "Surge"),
        ("Rending in Melee Aura", "Rending"),
        ("Rending Mark", "Rending"),
        ("Rending in Melee", "Rending"),
        ("Rending when Shooting", "Rending"),
        ("Bane in Melee", "Bane"),
        ("Bane when Shooting", "Bane"),
        ("Bane Mark", "Bane"),
        ("Counter-Attack", "Counter"),
        ("Counter in Melee", "Counter"),
        ("Unstoppable in Melee", "Unstoppable"),
        ("Unstoppable Mark", "Unstoppable"),
        ("Takedown Strike", "Takedown"),
        ("Takedown Shot", "Takedown"),
        ("Brace in Melee", "Brace"),
        ("Unwieldy Debuff", "Unwieldy"),
        ("Ignores Cover when Shooting", "Ignores Cover"),
        ("Indirect when Shooting", "Indirect"),
        ("Relentless Aura", "Relentless"),
        ("Thrust in Melee", "Thrust"),
        ("Crossing Strike Aura", "Crossing Strike"),
    ];
    for (candidate, base) in cases {
        let w = weapon_with(&[candidate]);
        assert!(
            !weapon_has(&w, base),
            "scoped alias '{candidate}' must not match base weapon rule '{base}'"
        );
    }
}

#[test]
fn exact_and_parameterised_weapon_rules_still_match() {
    let w = weapon_with(&[
        "AP(1)",
        "Deadly(3)",
        "Blast(3)",
        "Brace(2)",
        "Rending (spell)",
        "  Shred  ",
        "Surge",
        "Crossing Strike",
    ]);
    assert!(weapon_has(&w, "AP"));
    assert!(weapon_has(&w, "Deadly"));
    assert!(weapon_has(&w, "Blast"));
    assert!(weapon_has(&w, "Brace"));
    assert!(weapon_has(&w, "Rending"));
    assert!(weapon_has(&w, "Shred"));
    assert!(weapon_has(&w, "Surge"));
    assert!(weapon_has(&w, "Crossing Strike"));

    let sp = base_profile(&w, 2, 0);
    assert_eq!(sp.ap, 1);
    assert_eq!(sp.deadly, 3);
    assert_eq!(sp.blast, 3);
    assert!(sp.rending);
    assert!(sp.shred);
    assert!(sp.surge);
    assert!(sp.strafing);
}

#[test]
fn base_profile_ignores_scoped_aliases_on_weapons() {
    let w = weapon_with(&[
        "Shred in Melee",
        "Shred when Shooting",
        "Surge when Shooting",
        "Surge Mark",
        "Rending in Melee Aura",
        "Bane in Melee",
        "Counter-Attack",
        "Unstoppable in Melee",
        "Takedown Strike",
        "Ignores Cover when Shooting",
        "Indirect when Shooting",
        "Relentless Aura",
        "Thrust in Melee",
        "Crossing Strike Aura",
    ]);
    let sp = base_profile(&w, 2, 0);
    assert!(!sp.shred, "Shred scoped aliases must not stamp sp.shred");
    assert!(!sp.surge, "Surge scoped aliases must not stamp sp.surge");
    assert!(!sp.rending, "Rending aura must not stamp sp.rending");
    assert!(!sp.bane, "Bane scoped alias must not stamp sp.bane");
    assert!(!sp.bypass_regen, "Bane scoped alias must not stamp sp.bypass_regen");
    assert!(!sp.counter, "Counter-Attack must not stamp sp.counter");
    assert!(!sp.unstoppable, "Unstoppable in Melee must not stamp sp.unstoppable");
    assert!(!sp.takedown, "Takedown Strike must not stamp sp.takedown");
    assert!(!sp.ignores_cover, "Ignores Cover when Shooting must not stamp sp.ignores_cover");
    assert!(!sp.indirect, "Indirect when Shooting must not stamp sp.indirect");
    assert!(!sp.relentless, "Relentless Aura must not stamp sp.relentless");
    assert!(!sp.thrust, "Thrust in Melee must not stamp sp.thrust");
    assert!(!sp.strafing, "Crossing Strike Aura must not stamp sp.strafing");
    assert_eq!(strafing_rule_name([&sp]), "Strafing");
}

#[test]
fn strafing_rule_name_matches_exact_crossing_strike_only() {
    let sp_alias = base_profile(&weapon_with(&["Crossing Strike Aura"]), 2, 0);
    assert_eq!(strafing_rule_name([&sp_alias]), "Strafing");

    let sp_exact = base_profile(&weapon_with(&["Crossing Strike"]), 2, 0);
    assert_eq!(strafing_rule_name([&sp_exact]), "Crossing Strike");

    let sp_param = base_profile(&weapon_with(&["Crossing Strike (spell)"]), 2, 0);
    assert_eq!(strafing_rule_name([&sp_param]), "Crossing Strike");
}

#[test]
fn unit_static_ignores_scoped_aliases_on_melee_weapons() {
    let raw = r#"{"kind":"header","knobs":{},"profiles":{
      "alias_w":{"unit_id":"alias_w","name":"Alias Weapon","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":["Shred in Melee","Surge Mark","Rending in Melee Aura","Brace in Melee","Unwieldy Debuff","Counter-Attack"]}]},
      "plain_w":{"unit_id":"plain_w","name":"Plain Weapon","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":["AP(1)","Deadly(3)","Blast(3)","Brace(2)","Unwieldy","Shred","Surge","Rending"]}]}
    }}"#;
    let header = read_act_header(raw).expect("header");
    let mut reg = Registries::new(&repo_root());

    let us_alias = UnitStatic::build_for(
        &mut reg,
        header.profiles.get("alias_w").expect("alias_w"),
        crate::acts::CURRENT_RULES_EPOCH,
    );
    assert!(!us_alias.melee[0].shred);
    assert!(!us_alias.melee[0].surge);
    assert!(!us_alias.melee[0].rending);
    assert!(!us_alias.melee[0].counter);
    assert_eq!(us_alias.ctx.brace_models, 0, "Brace in Melee on a weapon must not grant Brace");
    assert_eq!(us_alias.ctx.brace_impact_per_model, None);
    assert!(!us_alias.ctx.unwieldy, "Unwieldy Debuff on a weapon must not make it Unwieldy");

    let us_plain = UnitStatic::build_for(
        &mut reg,
        header.profiles.get("plain_w").expect("plain_w"),
        crate::acts::CURRENT_RULES_EPOCH,
    );
    assert_eq!(us_plain.melee[0].ap, 1);
    assert_eq!(us_plain.melee[0].deadly, 3);
    assert_eq!(us_plain.melee[0].blast, 3);
    assert!(us_plain.melee[0].shred);
    assert!(us_plain.melee[0].surge);
    assert!(us_plain.melee[0].rending);
    assert_eq!(us_plain.ctx.brace_models, 1);
    assert_eq!(us_plain.ctx.brace_impact_per_model, Some(2), "Brace(2) on a weapon must keep its rating");
    assert!(us_plain.ctx.unwieldy, "plain Unwieldy on a melee weapon must still match");
}
