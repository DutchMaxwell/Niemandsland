//! Rules 3.6 lane morale tests for the dice module; owned by lane morale.
use super::*;

// ---- Row MOR-03 (ruling D-MOST): the Stealth family counts MOST models ----

/// A squad of `models` models carrying `special` (a JSON list) with the joined heroes `heroes` (a
/// JSON list of rule lists), built at `epoch` for (gf, `faction`) through the real registry.
fn mor03_squad(faction: &str, special: &str, heroes: &str, models: i64, epoch: u32) -> UnitStatic {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "st":{"unit_id":"st","name":"Stealth Squad","quality":4,
        "defense":4,"tough":1,"wounds_max":WOUNDS,"model_count":MODELS,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"FACTION",
        "special_rules":SPECIAL,"item_grants":[],
        "attached_hero_rules":HEROES,"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
        .replace("WOUNDS", &format!("{:?}", vec![1; models as usize]))
        .replace("MODELS", &models.to_string())
        .replace("FACTION", faction)
        .replace("SPECIAL", special)
        .replace("HEROES", heroes);
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("st").expect("st"), epoch)
}

/// One Quality 4+ rifle shot at `us` from `dist_in` inches.
fn mor03_shot(us: &UnitStatic, dist_in: f64) -> ShootResult {
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&[rifle(1)], &[0], &[1], &shooter(4), &us.ctx, dist_in, &mut tray)
}

fn mor03_names_most_models(out: &ShootResult) -> bool {
    out.log.iter().any(|l| l.contains("Stealth") && l.contains("most models"))
}

const MOR03_PLAIN_HERO: &str = r#"[["Hero"]]"#;

/// Three Stealth models and a joined hero without it are most models: the shot past 9" takes the
/// -1 and the log says the majority carried it. One Stealth model plus that hero is an exact half
/// (off), and a squad where every model has Stealth logs nothing extra.
#[test]
fn a_stealth_squad_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() {
    let us = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_73_V36);
    let far = mor03_shot(&us, 12.0);
    assert_eq!(far.rolls[0].target, 5, "3 of 4 models carry Stealth: Quality 4+ reads 5+ past 9\"");
    assert!(mor03_names_most_models(&far), "the log names the most-models read: {:?}", far.log);
    assert_eq!(mor03_shot(&us, 6.0).rolls[0].target, 4, "within 9\" Stealth does nothing");
    let tie = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 1, crate::acts::EPOCH_73_V36);
    assert_eq!(mor03_shot(&tie, 12.0).rolls[0].target, 4, "1 of 2 models is an exact half: no -1");
    let all = mor03_squad("robot_legions", r#"["Stealth"]"#, "[]", 3, crate::acts::EPOCH_73_V36);
    let all_far = mor03_shot(&all, 12.0);
    assert_eq!(all_far.rolls[0].target, 5, "every model carries Stealth");
    assert!(!mor03_names_most_models(&all_far), "no most-models line when all carry it: {:?}", all_far.log);
}

/// Control: below the 3.6 epoch a joined hero without Stealth still takes it away.
#[test]
fn a_stealth_squad_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() {
    let us = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_72_PLAYTEST_RULES);
    let far = mor03_shot(&us, 12.0);
    assert_eq!(far.rolls[0].target, 4, "at 72 the hero withholds Stealth");
    assert!(!mor03_names_most_models(&far), "{:?}", far.log);
}

/// Changebound is a "most models" alias of the family: its -1 past 9" holds with a plain hero.
#[test]
fn changebound_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() {
    let us = mor03_squad("change_disciples", r#"["Changebound"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_73_V36);
    assert_eq!(mor03_shot(&us, 12.0).rolls[0].target, 5, "3 of 4 models carry Changebound");
}

/// Control: below the 3.6 epoch the same hero withholds Changebound.
#[test]
fn changebound_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() {
    let us = mor03_squad("change_disciples", r#"["Changebound"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_72_PLAYTEST_RULES);
    assert_eq!(mor03_shot(&us, 12.0).rolls[0].target, 4);
}

mod mor_17a {
    //! MOR-17a: Warding, Knightborn and Angelic Blessing are one rule. From `EPOCH_73_V36` a non-spell
    //! wound is ignored on a 6+ only when the unit was shot from over 9" or charged from over 6"; a
    //! spell wound on a 2+. Below 73 the old map entry stands (6+ at any distance, 4+ vs spells).
    //! `Enhanced Knightborn` carries the same rule with its gate pinned open. The stamp lives in
    //! `unit::regen_targets`; the legs compare the distance gates here.
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::spell::{spell_damage_ev, spell_facets};

    /// A gf knight_brothers squad built through the REAL registry at `epoch`.
    fn knight_squad(special: &str, grants: &str, epoch: u32) -> crate::unit::UnitStatic {
        let tpl = r#"{"kind":"header","knobs":{},"profiles":{
          "kb":{"unit_id":"kb","name":"Knightborn Squad","quality":2,
            "defense":4,"tough":1,"wounds_max":[1,1,1,1],"model_count":4,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
            "special_rules":SPECIAL,"item_grants":GRANTS,
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
            {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
            .replace("SPECIAL", special)
            .replace("GRANTS", grants);
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        crate::unit::UnitStatic::build_for(&mut reg, header.profiles.get("kb").expect("kb"), epoch)
    }

    /// One 64-attack volley from a Quality 2 shooter at `d` inches.
    fn shot(us: &crate::unit::UnitStatic, d: f64) -> ShootResult {
        let profiles = [rifle(64)];
        let att = shooter(2);
        let squad = [Shooter { profiles: &profiles, keep: &[0], attacks: &[64], att: &att,
            owner: "Archers" }];
        let mut tray = Tray::seeded(27);
        resolve_volley_with_tray(&squad, &us.ctx, "Knightborn Squad", d, d, true, true, true, true,
            &mut tray)
    }

    /// One 64-attack melee strike from a Quality 2 striker; `charge_from_in` is the pre-charge gap.
    fn melee(us: &crate::unit::UnitStatic, charging: bool, charge_from_in: f64) -> ShootResult {
        let profiles = [blade(64)];
        let att = shooter(2);
        let strikers = [striker(&profiles, &[0], &[64], &att)];
        let mut tray = Tray::seeded(27);
        resolve_melee_leg(&strikers, &us.ctx, "Knightborn Squad", charging, false, false, false,
            charge_from_in, false, false, false, false, false, &mut tray)
    }

    /// The Regeneration-family dice this resolution actually rolled (`target == 6` is the 6+ ignore;
    /// the defender's saves run at its own Defense 4 here, so nothing else draws at 6).
    fn regen_dice(out: &ShootResult) -> i64 {
        out.rolls.iter().filter(|r| r.kind != "defense" && r.target == 6).map(|r| r.count).sum()
    }

    fn logged(out: &ShootResult, line: &str) -> bool {
        out.log.iter().any(|l| l == line)
    }

    #[test]
    fn knightborn_ignores_shot_wounds_from_over_nine_inches_at_epoch_73() {
        let us = knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_73_V36);
        let now = shot(&us, 12.0);
        assert!(regen_dice(&now) > 0, "12in: the 6+ ignore must roll: {:?}", now.rolls);
        assert!(logged(&now, "Warding: Knightborn Squad ignores wounds on 6+ (shot from over 9in)"));
    }

    #[test]
    fn knightborn_rolls_no_6_ignore_when_shot_from_within_nine_inches_at_epoch_73() {
        let now = shot(&knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_73_V36), 5.0);
        let before = shot(&knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES), 5.0);
        assert_eq!(regen_dice(&now), 0, "5in: no 6+ die of this kind at 73: {:?}", now.rolls);
        assert!(now.wounds > before.wounds, "the gate costs the ignore: {} vs {}", now.wounds, before.wounds);
        assert!(logged(&now, "Warding: no 6+ ignore, Knightborn Squad was shot from within 9in"));
    }

    #[test]
    fn knightborn_rolls_the_6_ignore_at_any_shot_distance_at_epoch_72() {
        let before = shot(&knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES), 5.0);
        assert!(regen_dice(&before) > 0, "72 keeps today's reading: {:?}", before.rolls);
        assert!(!before.log.iter().any(|l| l.starts_with("Warding")), "below 73 the rule is silent");
    }

    #[test]
    fn knightborn_ignores_charge_wounds_only_from_over_six_inches_at_epoch_73() {
        let us = knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_73_V36);
        let far = melee(&us, true, 8.0);
        assert!(regen_dice(&far) > 0, "charged from 8in: the 6+ ignore rolls: {:?}", far.rolls);
        assert!(logged(&far, "Warding: Knightborn Squad ignores wounds on 6+ (charged from over 6in)"));
        let near = melee(&us, true, 4.0);
        assert_eq!(regen_dice(&near), 0, "charged from 4in: no 6+ die: {:?}", near.rolls);
        assert!(logged(&near, "Warding: no 6+ ignore, Knightborn Squad was charged from within 6in"));
        let charged_us = melee(&us, false, 0.0);
        assert_eq!(regen_dice(&charged_us), 0, "we charged: the enemy was not charged from range");
    }

    #[test]
    fn knightborn_ignores_charge_wounds_at_any_distance_at_epoch_72() {
        let before = melee(&knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES), true, 4.0);
        assert!(regen_dice(&before) > 0, "72 keeps today's reading: {:?}", before.rolls);
    }

    #[test]
    fn a_spell_wound_is_ignored_on_2_at_73_and_on_4_at_72() {
        let f = spell_facets(&[]);
        let now = spell_damage_ev(10, &knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_73_V36).ctx, &f);
        let before = spell_damage_ev(10, &knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES).ctx, &f);
        assert!(now < before, "2+ vs 4+: {now} vs {before}");
        assert!((now - 5.0 / 6.0).abs() < 1e-9, "2+ ignores 5/6 of 5 unsaved: {now}");
    }

    /// The Enhanced Knightborn grant carries the same rule with its gate pinned open: inside 9" the
    /// 6+ still rolls at 73, and at 72 it reads exactly like the plain 3.5 entry.
    #[test]
    fn enhanced_knightborn_has_no_gate_at_epoch_73_but_does_nothing_new_at_72() {
        let now = shot(&knight_squad("[]", r#"["Enhanced Knightborn"]"#, EPOCH_73_V36), 5.0);
        assert!(regen_dice(&now) > 0, "no gate: the 6+ rolls inside 9in: {:?}", now.rolls);
        let f = spell_facets(&[]);
        let now_spell = spell_damage_ev(
            10, &knight_squad("[]", r#"["Enhanced Knightborn"]"#, EPOCH_73_V36).ctx, &f);
        assert!((now_spell - 5.0 / 6.0).abs() < 1e-9, "the spell leg is 2+ at 73: {now_spell}");
        let old = knight_squad("[]", r#"["Enhanced Knightborn"]"#, EPOCH_72_PLAYTEST_RULES);
        let plain = knight_squad(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES);
        assert_eq!(shot(&old, 5.0).wounds, shot(&plain, 5.0).wounds, "72 reads the old keys");
        assert!((spell_damage_ev(10, &old.ctx, &f) - spell_damage_ev(10, &plain.ctx, &f)).abs() < 1e-9);
    }

    /// CONTROL — a plain Regeneration unit (5+, no gate) is untouched by the row at either distance.
    #[test]
    fn plain_regeneration_is_unchanged_at_both_distances() {
        let us = knight_squad(r#"["Regeneration"]"#, "[]", EPOCH_73_V36);
        let near = shot(&us, 5.0);
        let far = shot(&us, 12.0);
        let faces_near: Vec<u8> = near.rolls.iter().flat_map(|r| r.faces.clone()).collect();
        let faces_far: Vec<u8> = far.rolls.iter().flat_map(|r| r.faces.clone()).collect();
        assert_eq!(faces_near, faces_far, "the same dice at either distance");
        assert!(!near.log.iter().any(|l| l.starts_with("Warding")), "a plain carrier never logs Warding");
    }
}
