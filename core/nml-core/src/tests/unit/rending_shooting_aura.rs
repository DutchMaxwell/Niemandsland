use super::*;

    // --- STANDALONE_SWEEP_G row `Rending when Shooting Aura` (epoch 47) ---
    //
    // The Utility-Buff aura ("Rending when Shooting Aura", gff machine_cults /
    // saurian_starhost, aof halflings / sky_city_dwarves) carries
    // `grants_rule: "Rending"`, `scope: "shooting"`: the bearer's SHOOTING
    // profiles gain Rending — wound-6 = AP(+4) and the Regeneration bypass —
    // the way the table stamps it (ai_ev.gd:330-341 granted-or-direct,
    // main.gd:7104's bypass). One file, the brief's whole red/green pair: the
    // aura is read at `EPOCH_47_RENDING_SHOOTING_AURA` and never below it.
    // The epoch literals here are 47/44, never `CURRENT_RULES_EPOCH`, so a
    // later wave bump cannot re-date what these assertions mean. The old leg
    // pins the epoch immediately below the bump at rebase time: 44, the
    // surge-mark leg's frozen `EPOCH_44_SURGE_MARK` (#958).

    /// The carrier template: one rifle and one blade, so both stamped arrays
    /// are non-empty and the scope gate has both sides (the condap shape).
    const RENDING_AURA_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gff","faction_folder":"machine_cults",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":64,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":64,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product of a gff carrier printing `rules` in
    /// `gff/<faction>`, read at `epoch`.
    fn aura_unit(rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = RENDING_AURA_HEADER.replace(
            "\"special_rules\":[]",
            &format!("\"special_rules\":[{printed}]"),
        );
        let header = read_act_header(&tpl).expect("RENDING_AURA_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// A plain Defense-4 target of `tough` per model.
    fn target(tough: i64) -> Ctx {
        Ctx { defense: 4, models: 1, tough, ..Default::default() }
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

    /// The aura carrier: the SHOOTING profiles rend (the volley's sixes save
    /// at AP(+4), the table's wound-6 shape) and the melee profiles do NOT —
    /// `scope: "shooting"`, never both arrays. PRESENT at 47
    /// (`EPOCH_47_RENDING_SHOOTING_AURA`), ABSENT at 46 (RED before the fix)
    /// and without the rule.
    #[test]
    fn rending_shooting_aura_rends_only_the_shooting_profiles_at_epoch_47() {
        let us = aura_unit(&["Rending when Shooting Aura"], 47);
        assert!(us.shoot[0].rending, "epoch 47: the rifle rends (RED before the fix)");
        assert!(
            save_targets(&volley(&us, &target(1), 12.0)).contains(&8),
            "epoch 47: the volley's sixes save at AP(+4) (RED before the fix)"
        );
        assert!(!us.melee[0].rending, "epoch 47: the blade does not — scope shooting, not melee");

        let us44 = aura_unit(&["Rending when Shooting Aura"], 44);
        assert!(
            !us44.shoot[0].rending && !us44.melee[0].rending,
            "epoch 44: stamped-but-unconsumed, byte-exact (the sweep's TABLE-ONLY row)"
        );
        assert!(
            !save_targets(&volley(&us44, &target(1), 12.0)).contains(&8),
            "epoch 44: no AP(+4) batch"
        );

        let plain = aura_unit(&[], 47);
        assert!(
            !plain.shoot[0].rending && !plain.melee[0].rending,
            "no rule, no rending"
        );
    }
