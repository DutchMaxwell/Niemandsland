use super::*;

    // --- Wave 4 "unregistered renames" family (rules-wave4-renames, epoch 7) ---
    //
    // Word-for-word renames of rules the core already resolves: "Piercing
    // Warrior" prints Havocbound's text (gf/havoc_brothers, aof/havoc_dwarves,
    // aof/havoc_warriors) and "Takedown when Shooting" prints Takedown's
    // ranged facet (aof/saurians). One RED/GREEN test per name through the
    // REAL registry (each name's own (system, faction) block), plus one
    // epoch test per name: a record below 7 sees the old behaviour exactly.
    // The epoch literals here are 7/6, never `CURRENT_RULES_EPOCH`, so a
    // wave-5 bump cannot re-date what these assertions mean.

    /// The family's carrier template: one rifle and one blade, so both
    /// stamped arrays are non-empty and every facet gate has both sides.
    const RENAMES_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product of a carrier printing `rules` in
    /// `<system>/<faction>`, read at `epoch`.
    fn rename_unit(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = RENAMES_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace(
                "\"faction_folder\":\"robot_legions\"",
                &format!("\"faction_folder\":\"{faction}\""),
            )
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("RENAMES_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// Every stamped conditional-AP spec NAMED `name` whose condition is
    /// `cond`, across the ranged and melee arrays.
    fn named_forms<'a>(us: &'a UnitStatic, name: &str, cond: &str) -> Vec<&'a CondAp> {
        us.shoot
            .iter()
            .chain(us.melee.iter())
            .flat_map(|sp| sp.cond_ap.iter())
            .filter(|c| c.name == name && c.condition == cond)
            .collect()
    }

    /// A plain Defense-4 target of one Tough(1) model.
    fn target() -> Ctx {
        Ctx { defense: 4, models: 1, tough: 1, ..Default::default() }
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

    /// The save targets every "defense" batch of `out` rolled at.
    fn save_targets(out: &crate::dice::ShootResult) -> Vec<i64> {
        out.rolls.iter().filter(|r| r.kind == "defense" && r.count > 0).map(|r| r.target).collect()
    }

    fn logged(out: &crate::dice::ShootResult, needle: &str) -> bool {
        out.log.iter().any(|l| l.contains(needle))
    }

    /// "Piercing Warrior" (gf/havoc_brothers, aof/havoc_dwarves,
    /// aof/havoc_warriors): "When this model shoots at enemies over 9\" away,
    /// or when it charges, its weapons get AP(+1)" — Havocbound's text word
    /// for word. The entry's own `ranged_over_or_charge` spelling is INERT on
    /// the shared match (exactly like Havocbound's), so the epoch-7 named arm
    /// states the two printed legs BY NAME: on_charge and ranged_over at the
    /// entry's own over_in, on both stamped arrays, in every faction block
    /// that prints the name. PRESENT at 7 (RED before the fix).
    #[test]
    fn piercing_warrior_stamps_havocbounds_two_legs_by_name_at_epoch_7() {
        for (system, faction) in [("gf", "havoc_brothers"), ("aof", "havoc_dwarves"), ("aof", "havoc_warriors")] {
            let us = rename_unit(system, faction, &["Piercing Warrior"], 7);
            let charge = named_forms(&us, "Piercing Warrior", "on_charge");
            assert_eq!(
                charge.len(),
                2,
                "{system}/{faction} epoch 7: the charge leg on both profiles, stated by name (RED before the fix)"
            );
            assert_eq!(charge[0].ap_bonus, 1, "{system}/{faction}: AP(+1)");
            let over = named_forms(&us, "Piercing Warrior", "ranged_over");
            assert_eq!(
                over.len(),
                2,
                "{system}/{faction} epoch 7: the ranged leg on both profiles (RED before the fix)"
            );
            assert_eq!(over[0].ap_bonus, 1, "{system}/{faction}: AP(+1)");
            assert!((over[0].over_in - 9.0).abs() < 1e-9, "{system}/{faction}: at the entry's own over_in");
        }
        let none = rename_unit("gf", "havoc_brothers", &[], 7);
        assert!(named_forms(&none, "Piercing Warrior", "on_charge").is_empty(), "no rule, no legs");
        assert!(named_forms(&none, "Piercing Warrior", "ranged_over").is_empty(), "no rule, no legs");
    }

    /// The two legs END TO END on the tray at epoch 7: the charge folds AP(+1)
    /// into the strike's save target and the volley past 9\" into the
    /// volley's, both naming the rule (rules-must-log); an unhurried strike
    /// and a 5\" volley stay at the printed AP and log nothing.
    #[test]
    fn a_piercing_warrior_charge_and_far_volley_fold_ap_and_log_at_epoch_7() {
        let us = rename_unit("gf", "havoc_brothers", &["Piercing Warrior"], 7);
        let charge = strike(&us, &target(), true);
        assert_eq!(save_targets(&charge), vec![5], "epoch 7: AP(+1) on the charge (RED before the fix)");
        assert!(
            logged(&charge, "Piercing Warrior: AP(+1) on att's strike"),
            "rules-must-log: the strike names the rule (RED before the fix): {:?}",
            charge.log
        );
        let far = volley(&us, &target(), 12.0);
        assert_eq!(save_targets(&far), vec![5], "epoch 7: AP(+1) past 9\" (RED before the fix)");
        assert!(
            logged(&far, "Piercing Warrior: AP(+1) on att's volley"),
            "rules-must-log: the volley names the rule (RED before the fix): {:?}",
            far.log
        );
        let still = strike(&us, &target(), false);
        assert_eq!(save_targets(&still), vec![4], "not charging: the printed AP");
        assert!(!logged(&still, "Piercing Warrior"), "nothing fired, nothing logs");
        let close = volley(&us, &target(), 5.0);
        assert_eq!(save_targets(&close), vec![4], "5\": under the gate, the printed AP");
        assert!(!logged(&close, "Piercing Warrior"), "nothing fired, nothing logs");
    }

    /// EPOCH TEST: a record stamped 6 sees the old behaviour exactly — the
    /// generic pass still stamps the entry's inert `ranged_over_or_charge`
    /// spelling (unnamed, on both profiles, as at every epoch since
    /// NML-1103), no named leg exists, and neither the charge nor the far
    /// volley moves off the printed AP or logs the name.
    #[test]
    fn piercing_warrior_is_inert_below_epoch_7() {
        for epoch in [7u32, 6] {
            let us = rename_unit("gf", "havoc_brothers", &["Piercing Warrior"], epoch);
            let inert = named_forms(&us, "", "ranged_over_or_charge");
            assert_eq!(inert.len(), 2, "epoch {epoch}: the generic pass's inert spelling never re-dates");
        }
        let us6 = rename_unit("gf", "havoc_brothers", &["Piercing Warrior"], 6);
        assert!(named_forms(&us6, "Piercing Warrior", "on_charge").is_empty(), "epoch 6: no charge leg");
        assert!(named_forms(&us6, "Piercing Warrior", "ranged_over").is_empty(), "epoch 6: no ranged leg");
        let charge = strike(&us6, &target(), true);
        assert_eq!(save_targets(&charge), vec![4], "epoch 6: the charge stays at the printed AP");
        assert!(!logged(&charge, "Piercing Warrior"), "epoch 6: nothing fires, nothing logs");
        let far = volley(&us6, &target(), 12.0);
        assert_eq!(save_targets(&far), vec![4], "epoch 6: 12\" stays at the printed AP");
        assert!(!logged(&far, "Piercing Warrior"), "epoch 6: nothing fires, nothing logs");
    }

    /// "Takedown when Shooting" (aof/saurians): "This model gets Takedown when
    /// shooting" — the table's `AiEv.takedown_rule_for_profile` flags every
    /// RANGED profile of the bearer (`shooting_only`), never the melee one,
    /// and the flag routes to the existing Takedown consumers. PRESENT at 7
    /// (RED before the fix), ABSENT without the rule.
    #[test]
    fn takedown_when_shooting_flags_only_the_ranged_profiles_at_epoch_7() {
        let us = rename_unit("aof", "saurians", &["Takedown when Shooting"], 7);
        assert!(us.shoot[0].takedown, "epoch 7: the rifle gets Takedown (RED before the fix)");
        assert_eq!(
            us.shoot[0].takedown_rule, "Takedown when Shooting",
            "epoch 7: the rifle carries the NAME for the log (RED before the fix)"
        );
        assert!(!us.melee[0].takedown, "shooting only: the blade never gets Takedown");
        assert!(us.melee[0].takedown_rule.is_empty(), "shooting only: no name on the blade");

        let none = rename_unit("aof", "saurians", &[], 7);
        assert!(!none.shoot[0].takedown, "no rule, no Takedown");
        assert!(none.shoot[0].takedown_rule.is_empty(), "no rule, no name");
    }

    /// END TO END on the tray at epoch 7: the bearer's volley reaches the
    /// existing Takedown consumers — the `unported` mark the core keeps for
    /// the unit-of-[1] pick it does not reproduce — and names the rule on the
    /// rules-must-log line; the strike (melee) does neither.
    #[test]
    fn a_takedown_when_shooting_volley_marks_takedown_and_logs_at_epoch_7() {
        let us = rename_unit("aof", "saurians", &["Takedown when Shooting"], 7);
        let shot = volley(&us, &target(), 12.0);
        assert!(
            shot.unported.contains(&"takedown"),
            "epoch 7: the volley reaches the Takedown consumer (RED before the fix): {:?}",
            shot.unported
        );
        assert!(
            logged(&shot, "Takedown when Shooting: Takedown on att's volley"),
            "rules-must-log: the volley names the rule (RED before the fix): {:?}",
            shot.log
        );
        let blade = strike(&us, &target(), true);
        assert!(!blade.unported.contains(&"takedown"), "melee: never Takedown");
        assert!(!logged(&blade, "Takedown when Shooting"), "melee: nothing fires, nothing logs");
    }

    /// EPOCH TEST: a record stamped 6 sees the old behaviour exactly — no
    /// flag, no name, no mark, no log line, on either array.
    #[test]
    fn takedown_when_shooting_is_inert_below_epoch_7() {
        let us6 = rename_unit("aof", "saurians", &["Takedown when Shooting"], 6);
        assert!(!us6.shoot[0].takedown, "epoch 6: the rifle stays plain");
        assert!(us6.shoot[0].takedown_rule.is_empty(), "epoch 6: no name");
        assert!(!us6.melee[0].takedown, "epoch 6: the blade stays plain");
        let shot = volley(&us6, &target(), 12.0);
        assert!(!shot.unported.contains(&"takedown"), "epoch 6: no Takedown consumer reached");
        assert!(!logged(&shot, "Takedown when Shooting"), "epoch 6: nothing fires, nothing logs");
    }
