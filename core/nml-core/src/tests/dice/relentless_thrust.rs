use super::*;

    // --- TEST WAVE (2026-09-14, D-PROOF) — the two weapon-tag families'
    // NUMBER pins: Relentless (a bonus hit per unmodified 6, over 9" only)
    // and Thrust (a charging weapon hits one better and saves one harder).
    // Each test reads the rule BY ITS EXACT NAME off the weapon (the
    // `weapon_has` stamps) through `UnitStatic::build_for` at
    // `CURRENT_RULES_EPOCH`, then walks the REAL dice folds.

    /// The family's carrier template: one rifle (AP 0) and one blade whose
    /// AP(5) prints as the weapon's own "AP(5)" rule (the field the AP stamp
    /// reads), `weapon` printed on BOTH weapons (the books' own shape for
    /// weapon rules), so the volley uses `shoot[0]` and the strike `melee[0]`.
    const PIN_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":["AP(5)"]}]}}}"#;

    /// The REAL `build_for` product: `weapon` printed on both weapons.
    fn pin_unit(weapon: &str) -> UnitStatic {
        let mut tpl = PIN_HEADER.replace("\"rules\":[]", &format!("\"rules\":[\"{weapon}\"]"));
        if !weapon.is_empty() {
            tpl = tpl.replace(
                "\"rules\":[\"AP(5)\"]",
                &format!("\"rules\":[\"AP(5)\",\"{weapon}\"]"),
            );
        }
        let header = read_act_header(&tpl).expect("PIN_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, crate::acts::CURRENT_RULES_EPOCH)
    }

    /// A plain Defense-4 target of `models` models, Tough(1) each.
    fn pin_target(models: i64) -> Ctx {
        Ctx { defense: 4, models, tough: 1, ..Default::default() }
    }

    /// One 64-attack rifle volley by `us` at centre distance `dist_in`.
    fn volley(us: &UnitStatic, def: &Ctx, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, def, "def", dist_in, dist_in, true, false, false, false, &mut tray,
        )
    }

    /// One 64-attack blade strike phase by `us` against `def`.
    fn strike(us: &UnitStatic, def: &Ctx, charging: bool) -> crate::dice::ShootResult {
        let profiles = [us.melee[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_melee_with_tray(&strikers, def, "def", charging, true, false, &mut tray)
    }

    /// The save-target count every "defense" batch of `out` rolled.
    fn save_counts(out: &crate::dice::ShootResult) -> Vec<i64> {
        out.rolls.iter().filter(|r| r.kind == "defense" && r.count > 0).map(|r| r.count).collect()
    }

    /// "Relentless" (gf/aof common, bonus_hits_per_six 1, over_in 9): over
    /// 9" every unmodified 6 of the volley is ONE BONUS hit on top of its
    /// own, so the save batch count is `hits + sixes`; at 6" (and on a
    /// rule-less carrier) the batch is the plain hits alone.
    #[test]
    fn relentless_rolls_one_bonus_hit_per_six_only_over_nine_inches() {
        let us = pin_unit("Relentless");
        assert!(us.shoot[0].relentless, "the weapon tag stamps the flag");

        let on = volley(&us, &pin_target(8), 12.0);
        let atk = on.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        let plain = atk.faces.iter().filter(|&&f| f >= 4).count() as i64;
        let sixes = atk.faces.iter().filter(|&&f| f == 6).count() as i64;
        assert_eq!(
            save_counts(&on),
            vec![plain + sixes],
            "over 9\": every unmodified 6 is one bonus hit on the same save batch"
        );

        let close = volley(&us, &pin_target(8), 6.0);
        let atk_c = close.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        let plain_c = atk_c.faces.iter().filter(|&&f| f >= 4).count() as i64;
        assert_eq!(
            save_counts(&close),
            vec![plain_c],
            "at 6\": the over-9 gate is shut — the sixes count nothing"
        );

        let bare = pin_unit("");
        assert!(!bare.shoot[0].relentless, "no tag, no flag");
        let off = volley(&bare, &pin_target(8), 12.0);
        let atk_o = off.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        let plain_o = atk_o.faces.iter().filter(|&&f| f >= 4).count() as i64;
        assert_eq!(save_counts(&off), vec![plain_o], "no rule: plain hits only");
    }

    /// "Thrust" (gf/aof common, hit_bonus 1, ap_bonus 1, charge_only): a
    /// CHARGING blade hits one better (Quality 4 -> 3+) and saves one harder
    /// (the blade's AP(5) becomes AP(6) -> Defense 4 saves at 10); the same
    /// blade NOT charging rolls plain Quality 4 at plain AP(5).
    #[test]
    fn a_charging_thrust_weapon_hits_one_better_and_saves_one_harder() {
        let us = pin_unit("Thrust");
        assert!(us.melee[0].thrust, "the weapon tag stamps the melee flag");

        let on = strike(&us, &pin_target(1), true);
        let atk = on.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        assert_eq!(atk.target, 3, "charging: Quality 4 - Thrust's +1 = hit on 3+");
        assert_eq!(
            on.rolls.iter().filter(|r| r.kind == "defense" && r.count > 0).map(|r| r.target).collect::<Vec<i64>>(),
            vec![10],
            "charging: the blade's AP(5) + Thrust's AP(+1) -> Defense 4 saves at 10"
        );

        let idle = strike(&us, &pin_target(1), false);
        let atk_i = idle.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        assert_eq!(atk_i.target, 4, "not charging: plain Quality 4");
        assert_eq!(
            idle.rolls.iter().filter(|r| r.kind == "defense" && r.count > 0).map(|r| r.target).collect::<Vec<i64>>(),
            vec![9],
            "not charging: the blade's plain AP(5)"
        );
    }
