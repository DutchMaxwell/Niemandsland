use super::*;

    // ------------- Dead-parameter recount 2026-09-15, families 1+3: the
    // Counter strike-phase mark's own `strikes_first` switch and the
    // Artillery entry's `shooter_hit_bonus` / `target_hit_penalty` READS
    // ---
    //
    // The mark pays a hard-coded "always" and the over-9" artillery legs
    // hard-code +1/-2 while the registry entries carry all three unread.
    // These tests build FIXTURE registries whose entries switch/retune them
    // and hold the folds to the entry's own numbers; on main the constants
    // win, so both RED. The shipped books all print true/1/2 — exactly the
    // constants — so a real-book run cannot tell the read apart, and no
    // recorded game changes (the stamps ride the EXISTING frozen gates
    // EPOCH_7_TABLE_RULES / EPOCH_13_WHO_WINS).

    /// A fixture registry with ONE entry: `name` aliasing `primitive` under
    /// `faction`, carrying `params` verbatim (the surge_param wave's
    /// temp-repo shape — a whole temp repo root, not a cache override).
    fn counter_registry(
        tag: &str, system: &str, faction: &str, name: &str, primitive: &str, params: &str,
    ) -> String {
        let dir = std::env::temp_dir()
            .join(format!("nml_counterfam_{}_{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let map_dir = dir.join("assets/solo");
        std::fs::create_dir_all(&map_dir).expect("temp map dir");
        let body = format!(
            r#"{{"common":{{}},"factions":{{"{faction}":{{"{name}":{{"primitive":"{primitive}","rated":false,"book_version":"3.5.3","params":{params}}}}}}}}}"#
        );
        std::fs::write(map_dir.join(format!("rules_mechanics_{system}.json")), body)
            .expect("write temp mechanics map");
        dir.to_string_lossy().into_owned()
    }

    /// One Blade (8 attacks) — the counter mark reads the melee array, the
    /// stamp rides the profile's own "Counter-Attack" alias.
    const CTR_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"testfac",
        "special_rules":["Counter-Attack"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One Rifle (24", 8 attacks) + the Artillery rule — the over-9" legs
    /// read the shoot array and the ctx's own stamped hit params.
    const ART_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"testfac",
        "special_rules":["Artillery"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn art_static(root: &str, header: &str) -> UnitStatic {
        let parsed = read_act_header(header).expect("header parses");
        let mut reg = Registries::new(root);
        let p = parsed.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, 7)
    }

    /// The entry's `strikes_first` is stamped onto every Counter melee profile — the switch the
    /// charge's strike-first gate reads (`sim::tray_charge`) — and the strike LEG never marks
    /// `counter_strikes_first`: it cannot tell a charger from a defender, a charger's Counter weapon
    /// strikes in its normal slot at the table, and the charge flags the cases the core cannot play
    /// (a joined hero's Counter without `Seams::tray_exact`, epochs below 13).
    #[test]
    fn a_counter_entrys_strikes_first_is_stamped_and_the_strike_leg_never_marks() {
        let strike = |us: &UnitStatic| {
            let profiles = [us.melee[0].clone()];
            let att = Ctx { quality: 4, ..Default::default() };
            let strikers = [Shooter {
                profiles: &profiles, keep: &[0], attacks: &[8], att: &att, owner: "att",
            }];
            let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
            let mut tray = Tray::seeded(9);
            resolve_melee_with_tray(&strikers, &def, "def", false, false, false, &mut tray)
        };
        let on = art_static(
            &counter_registry("ctr_on", "gf", "testfac", "Counter", "Counter", "{}"),
            CTR_HEADER,
        );
        let off = art_static(
            &counter_registry(
                "ctr_off", "gf", "testfac", "Counter", "Counter", r#"{"strikes_first":false}"#,
            ),
            CTR_HEADER,
        );
        assert_eq!((on.melee[0].counter_strikes_first, off.melee[0].counter_strikes_first), (Some(true), Some(false)));
        assert!(!strike(&on).unported.contains(&"counter_strikes_first"), "the leg is no gap");
        assert!(!strike(&off).unported.contains(&"counter_strikes_first"), "the leg is no gap");
    }

    /// The over-9" artillery legs: the entry's `shooter_hit_bonus: 0` drops
    /// the shooter's +1 (a die at exactly 3 flips from hit to miss) and the
    /// entry's `target_hit_penalty: 1` softens the -2 to -1 (a die at
    /// exactly 5 flips the other way). On main both constants win and
    /// neither seed flips anything (RED). Seed 17 carries the 3, seed 27
    /// the 5 (fixture-guarded below).
    #[test]
    fn an_artillery_entrys_hit_params_pay_the_entry_numbers_not_the_constants() {
        let volley = |us: &UnitStatic, def: &Ctx| {
            let p = [us.shoot[0].clone()];
            let mut tray = Tray::seeded(17);
            resolve_volley_with_tray(
                &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att: &us.ctx, owner: "" }],
                def, "Target", 12.0, 12.0, true, true, true, true, &mut tray,
            )
        };
        let faces = Tray::seeded(17).roll(8);
        assert!(faces.contains(&3), "fixture: seed 17 must roll a 3 or the shooter leg is blind");
        let base =
            art_static(&counter_registry("art1", "gf", "testfac", "Artillery", "Artillery", "{}"), ART_HEADER);
        let no_bonus = art_static(
            &counter_registry(
                "art0", "gf", "testfac", "Artillery", "Artillery", r#"{"shooter_hit_bonus":0}"#,
            ),
            ART_HEADER,
        );
        let plain_def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
        let with_bonus = volley(&base, &plain_def).rolls[1].count;
        let without = volley(&no_bonus, &plain_def).rolls[1].count;
        assert!(
            with_bonus > without,
            "the entry's shooter_hit_bonus:0 must drop the constant +1 — on main it cannot (RED)"
        );
        let target_faces = Tray::seeded(27).roll(8);
        assert!(target_faces.contains(&5), "fixture: seed 27 must roll a 5 or the target leg is blind");
        let soft = art_static(
            &counter_registry(
                "art2", "gf", "testfac", "Artillery", "Artillery", r#"{"target_hit_penalty":1}"#,
            ),
            ART_HEADER,
        );
        let mut tray = Tray::seeded(27);
        let hard_hits = resolve_volley_with_tray(
            &[Shooter {
                profiles: &[base.shoot[0].clone()], keep: &[0], attacks: &[8], att: &base.ctx,
                owner: "",
            }],
            &base.ctx, "Target", 12.0, 12.0, true, true, true, true, &mut tray,
        )
        .rolls[1].count;
        let mut tray = Tray::seeded(27);
        let soft_hits = resolve_volley_with_tray(
            &[Shooter {
                profiles: &[base.shoot[0].clone()], keep: &[0], attacks: &[8], att: &base.ctx,
                owner: "",
            }],
            &soft.ctx, "Target", 12.0, 12.0, true, true, true, true, &mut tray,
        )
        .rolls[1].count;
        assert!(
            soft_hits > hard_hits,
            "the entry's target_hit_penalty:1 must soften the constant -2 — on main it cannot (RED)"
        );
    }
