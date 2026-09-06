use super::*;

    // --- Wave 4 "conditional-AP live reads" family (rules-wave4-condap, epoch 7) ---
    //
    // One test per ported base, through the REAL registry (each name's own
    // (system, faction) block, the folder its book prints), plus one aura
    // riding its base's live handler and one corpus-floor test. The epoch
    // literals here are 7/6, never `CURRENT_RULES_EPOCH`, so a wave-5 bump
    // cannot re-date what these assertions mean.

    /// The family's carrier template: one rifle and one blade, so both
    /// stamped arrays are non-empty and every facet gate has both sides.
    const CONDAP_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product of a gf carrier printing `rules` in
    /// `gf/<faction>`, read at `epoch`.
    fn condap_unit(faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = CONDAP_HEADER
            .replace(
                "\"faction_folder\":\"robot_legions\"",
                &format!("\"faction_folder\":\"{faction}\""),
            )
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("CONDAP_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// A plain Defense-4 target of `tough` per model.
    fn target(tough: i64) -> Ctx {
        Ctx { defense: 4, models: 1, tough, ..Default::default() }
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

    /// "Piercing Fighter" (gf, common — orc_marauders prints its Aura): "This
    /// model gets AP(+1) in melee". The strike saves one step harder and the
    /// rule names itself; the volley is untouched (melee only). PRESENT at 7,
    /// ABSENT at 6 (the entry's `in_melee` spelling is inert on the shared
    /// match, byte-exact), ABSENT without the rule.
    #[test]
    fn piercing_fighter_adds_ap_one_in_melee_at_epoch_7() {
        let us = condap_unit("orc_marauders", &["Piercing Fighter"], 7);
        let on = strike(&us, &target(1), false);
        assert_eq!(save_targets(&on), vec![5], "epoch 7: AP(+1) in melee (RED before the fix)");
        assert!(
            logged(&on, "Piercing Fighter: AP(+1) on att's strike"),
            "rules-must-log: the strike names the rule (RED before the fix)"
        );
        assert_eq!(save_targets(&volley(&us, &target(1), 12.0)), vec![4], "shooting: untouched");

        let us6 = condap_unit("orc_marauders", &["Piercing Fighter"], 6);
        let off = strike(&us6, &target(1), false);
        assert_eq!(save_targets(&off), vec![4], "epoch 6: the in_melee spelling stays inert");
        assert!(!logged(&off, "Piercing Fighter"), "epoch 6: nothing fires, nothing logs");

        let plain = condap_unit("orc_marauders", &[], 7);
        assert_eq!(save_targets(&strike(&plain, &target(1), false)), vec![4], "no rule, no AP");
    }

    /// "Piercing Fighter Aura" (gf/orc_marauders): "This model and its unit
    /// get AP(+1) in melee" — the Aura-Channel fold grants the base and the
    /// base's live handler fires on the carrier's own strike. The grant was
    /// live at epoch 6 already (rules-wave3-aura1); the HANDLER is epoch-7
    /// born, so the aura carrier's strike moves only at 7.
    #[test]
    fn piercing_fighter_aura_reaches_its_live_base_at_epoch_7() {
        let us = condap_unit("orc_marauders", &["Piercing Fighter Aura"], 7);
        let on = strike(&us, &target(1), false);
        assert_eq!(save_targets(&on), vec![5], "epoch 7: the granted base fires (RED before the fix)");
        assert!(logged(&on, "Piercing Fighter: AP(+1) on att's strike"));
        let us6 = condap_unit("orc_marauders", &["Piercing Fighter Aura"], 6);
        assert_eq!(save_targets(&strike(&us6, &target(1), false)), vec![4], "epoch 6: granted, not read");
    }

    /// "Point-Blank Piercing" (gf/blessed_sisters): "This model gets AP(+1)
    /// when shooting enemies within 12\"". Inclusive at 12", shut past it,
    /// never in melee; the volley names the rule. PRESENT at 7, ABSENT at 6
    /// (the entry's `ranged_within` spelling carries no cap on the generic
    /// pass, byte-exact).
    #[test]
    fn point_blank_piercing_adds_ap_one_within_twelve_inches_at_epoch_7() {
        let us = condap_unit("blessed_sisters", &["Point-Blank Piercing"], 7);
        let close = volley(&us, &target(1), 6.0);
        assert_eq!(save_targets(&close), vec![5], "epoch 7, 6\": AP(+1) (RED before the fix)");
        assert!(
            logged(&close, "Point-Blank Piercing: AP(+1) on att's volley"),
            "rules-must-log: the volley names the rule (RED before the fix)"
        );
        assert_eq!(save_targets(&volley(&us, &target(1), 12.0)), vec![5], "exactly 12\" is within");
        let far = volley(&us, &target(1), 18.0);
        assert_eq!(save_targets(&far), vec![4], "18\": past the cap");
        assert!(!logged(&far, "Point-Blank Piercing"), "nothing fired, nothing logs");
        assert_eq!(save_targets(&strike(&us, &target(1), true)), vec![4], "melee: never");

        let us6 = condap_unit("blessed_sisters", &["Point-Blank Piercing"], 6);
        let off = volley(&us6, &target(1), 6.0);
        assert_eq!(save_targets(&off), vec![4], "epoch 6: the cap is not born yet");
        assert!(!logged(&off, "Point-Blank Piercing"));
    }

    /// The `ranged_within` arm itself, straight off the printed shape: fires
    /// only on a spec whose cap is SET (the generic pass stamps 0.0, so its
    /// registry-spelled specs stay inert at every epoch), inclusive at the
    /// cap, shut in melee and on an unknown distance.
    #[test]
    fn ranged_within_fires_only_on_a_capped_spec_within_the_cap() {
        use crate::combat::conditional_ap_bonus;
        let capped = CondAp {
            ap_bonus: 1, condition: "ranged_within".into(), within_in: 12.0, ..Default::default()
        };
        let generic = CondAp { within_in: 0.0, ..capped.clone() };
        assert_eq!(conditional_ap_bonus(&capped, 1, 4, false, 6.0, false), 1);
        assert_eq!(conditional_ap_bonus(&capped, 1, 4, false, 12.0, false), 1, "inclusive");
        assert_eq!(conditional_ap_bonus(&capped, 1, 4, false, 12.5, false), 0);
        assert_eq!(conditional_ap_bonus(&capped, 1, 4, false, -1.0, false), 0, "unknown distance");
        assert_eq!(conditional_ap_bonus(&capped, 1, 4, true, 0.0, true), 0, "melee");
        assert_eq!(conditional_ap_bonus(&generic, 1, 4, false, 6.0, false), 0, "generic pass: inert");
    }

    /// "Rending in Melee" (gf, common — rebel_guerrillas prints its Aura):
    /// "This model gets Rending in melee". The entry's own `melee_only` is
    /// the live read: the blade rends (its 6s save at AP(+4)), the rifle no
    /// longer does. At 6 the flat prefix read stamps BOTH arrays (the
    /// pre-wave reading, byte-exact).
    #[test]
    fn rending_in_melee_rends_only_the_melee_profiles_at_epoch_7() {
        let us = condap_unit("rebel_guerrillas", &["Rending in Melee"], 7);
        assert!(us.melee[0].rending, "epoch 7: the blade rends");
        assert!(!us.shoot[0].rending, "epoch 7: the rifle does not (RED before the fix)");
        assert!(
            save_targets(&strike(&us, &target(1), false)).contains(&8),
            "the strike's 6s save at AP(+4)"
        );
        assert!(
            !save_targets(&volley(&us, &target(1), 12.0)).contains(&8),
            "the volley has no AP(+4) batch (RED before the fix)"
        );

        let us6 = condap_unit("rebel_guerrillas", &["Rending in Melee"], 6);
        assert!(us6.melee[0].rending && us6.shoot[0].rending, "epoch 6: both arrays, byte-exact");
        assert!(save_targets(&volley(&us6, &target(1), 12.0)).contains(&8));

        // The aura carrier: the fold grants the base (epoch 6+), the facet
        // read scopes it; the aura's own spelling never rends by itself.
        let aura = condap_unit("rebel_guerrillas", &["Rending in Melee Aura"], 7);
        assert!(aura.melee[0].rending && !aura.shoot[0].rending, "aura carrier: melee only");
        let plain = condap_unit("rebel_guerrillas", &[], 7);
        assert!(!plain.melee[0].rending && !plain.shoot[0].rending, "no rule, no rending");
    }

    /// "Melee Slayer" (gf/blood_prime_brothers): "When this model charges,
    /// its weapons get AP(+2) if most models in the target have Tough(3) or
    /// higher". The ARITHMETIC is live at every epoch off the generic pass
    /// (charge_only + vs_tough_ge, fired with the real `charging`) — the
    /// wave adds the NAME: the strike logs it at 7, stays silent at 6.
    #[test]
    fn melee_slayer_names_its_charge_bonus_at_epoch_7() {
        let us = condap_unit("blood_prime_brothers", &["Melee Slayer"], 7);
        let on = strike(&us, &target(3), true);
        assert_eq!(save_targets(&on), vec![6], "charging vs Tough(3): AP(+2)");
        assert!(
            logged(&on, "Melee Slayer: AP(+2) on att's strike"),
            "rules-must-log: the strike names the rule (RED before the fix)"
        );
        let idle = strike(&us, &target(3), false);
        assert_eq!(save_targets(&idle), vec![4], "not charging: nothing");
        assert!(!logged(&idle, "Melee Slayer"));
        assert_eq!(save_targets(&strike(&us, &target(1), true)), vec![4], "vs Tough(1): nothing");
        assert_eq!(save_targets(&volley(&us, &target(3), 6.0)), vec![4], "shooting never charges");

        let us6 = condap_unit("blood_prime_brothers", &["Melee Slayer"], 6);
        let off = strike(&us6, &target(3), true);
        assert_eq!(save_targets(&off), vec![6], "epoch 6: the same AP(+2), byte-exact");
        assert!(!logged(&off, "Melee Slayer"), "epoch 6: unnamed, silent");
    }

    /// The corpus floor, in one place: a record stamped BELOW
    /// `EPOCH_7_TABLE_RULES` sees none of this wave's four bases — the exact
    /// reading it had before the wave existed.
    #[test]
    fn an_epoch_six_record_sees_none_of_the_four_wave_four_cond_ap_reads() {
        let fighter = condap_unit("orc_marauders", &["Piercing Fighter"], 6);
        assert!(fighter.melee[0].cond_ap.iter().all(|c| c.name.is_empty()), "epoch 6: unnamed");
        assert_eq!(save_targets(&strike(&fighter, &target(1), false)), vec![4]);
        let pbp = condap_unit("blessed_sisters", &["Point-Blank Piercing"], 6);
        assert!(pbp.shoot[0].cond_ap.iter().all(|c| c.within_in == 0.0), "epoch 6: no cap");
        assert_eq!(save_targets(&volley(&pbp, &target(1), 6.0)), vec![4]);
        let rending = condap_unit("rebel_guerrillas", &["Rending in Melee"], 6);
        assert!(rending.shoot[0].rending, "epoch 6: the flat prefix read, both arrays");
        let slayer = condap_unit("blood_prime_brothers", &["Melee Slayer"], 6);
        assert!(slayer.melee[0].cond_ap.iter().all(|c| c.name.is_empty()), "epoch 6: unnamed");
    }
