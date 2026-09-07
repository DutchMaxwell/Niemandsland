use super::*;

    // --------------------- wave 4 follow-up: Reckless Piercing (round AP stamp) ---

    /// The registry-built bearer: an aof/rift_daemons_of_war profile whose
    /// rules come straight off the book ("Reckless Piercing" itself, or the
    /// "Reckless Piercing Aura" grant the Chainrend item "Pilfered Relics"
    /// carries). The REAL `build_for` product, read at `epoch`.
    fn rp_bearer(rules_epoch: u32, rules: &[&str]) -> UnitStatic {
        let p = crate::state::Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: rules.iter().map(|r| r.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: "rift_daemons_of_war".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" vs a single-model Defense-4 target "b" 12" away: the
    /// `storm_line` shape, one model per side.
    fn rp_line(rules_epoch: u32, rules: &[&str]) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        let bearer = rp_bearer(rules_epoch, rules);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.quality = 4;
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        (st, vec![bearer, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    fn run_rp(st: &State, statics: &[UnitStatic], seed: i64, rules_epoch: u32) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(
            statics, st, &storm_action(), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// Consumption runs need their OWN action: the stamp tests ride HOLD
    /// (the pre-attack slot fires on every kind), the volley leg shoots "b",
    /// the melee leg charges it.
    fn run_action(st: &State, statics: &[UnitStatic], action: &Action, seed: i64, rules_epoch: u32) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, movement: true, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// The stamp: the REAL registry entry (self-named primitive, params
    /// `roll_target: 2, ap_bonus: 1, backfire_ap: 1`) lands on the statics
    /// behind the FROZEN `EPOCH_7_TABLE_RULES` — present at 7, absent at 6.
    #[test]
    fn the_real_registry_stamps_reckless_piercing_at_epoch_seven_not_six() {
        let on = rp_bearer(7, &["Reckless Piercing"]);
        assert_eq!(on.reckless_piercing.len(), 1, "epoch 7: the entry is stamped");
        let s = &on.reckless_piercing[0];
        assert_eq!(s.name, "Reckless Piercing");
        assert_eq!(s.roll_target, 2);
        assert_eq!(s.ap_bonus, 1);
        assert_eq!(s.backfire_ap, 1);
        let off = rp_bearer(6, &["Reckless Piercing"]);
        assert!(off.reckless_piercing.is_empty(), "epoch 6: the record predates the wave");
    }

    /// The two-hop chain: the Chainrend item "Pilfered Relics" carries the
    /// AURA rule, whose `grants: "Reckless Piercing"` the epoch-6 Aura
    /// Channel fold expands BEFORE the epoch-7 read — so the granted base is
    /// stamped through the aura, and no unit ever prints the base itself.
    #[test]
    fn the_aura_grant_reaches_the_stamp_through_the_item_hop() {
        let on = rp_bearer(7, &["Reckless Piercing Aura"]);
        assert_eq!(on.reckless_piercing.len(), 1, "aura → base, expanded at build");
        assert_eq!(on.reckless_piercing[0].name, "Reckless Piercing");
        let off = rp_bearer(5, &["Reckless Piercing Aura"]);
        assert!(off.reckless_piercing.is_empty(), "epoch 5: the fold never ran");
    }

    /// The handler: ONE die at the once-per-round before-attacking slot. A
    /// face at or over `roll_target` stamps the bearer's chain with the
    /// round AP buff; the epoch-6 control rolls nothing and stamps nothing.
    #[test]
    fn a_passing_roll_stamps_the_chain_ap_until_round_end() {
        let (st, statics) = rp_line(7, &["Reckless Piercing"]);
        let seed = (0..200).find(|&s| Tray::seeded(s).roll(1)[0] >= 2).expect("some seed passes") as i64;
        let (next, shot) = run_rp(&st, &statics, seed, 7);
        let die = shot.rolls.iter().find(|r| r.owner == "a" && r.count == 1).expect("one tray die");
        assert!(die.faces[0] >= 2, "this seed must PASS: {die:?}");
        assert_eq!(next.reckless_ap_round[0], 0, "the buff stamp, round-scoped");
        assert_eq!(next.reckless_backfire_round[0], -1, "no backfire on a pass");
        assert!(
            shot.log.iter().any(|l| l.contains("Reckless Piercing") && l.contains("AP(+1)")),
            "rules-must-log: the buff line names the rule — got {:#?}",
            shot.log
        );

        let (next6, shot6) = run_rp(&st, &statics, seed, 6);
        assert!(!shot6.rolls.iter().any(|r| r.owner == "a" && r.count == 1), "epoch 6: no die");
        assert_eq!(next6.reckless_ap_round[0], -1);
        assert!(shot6.log.iter().all(|l| !l.contains("Reckless Piercing")));
    }

    /// The backfire: a 1 stamps the chain so ENEMIES get AP(+1) against it
    /// until the end of the round (main.gd:16961-16966).
    #[test]
    fn a_failing_roll_stamps_the_backfire() {
        let (st, statics) = rp_line(7, &["Reckless Piercing"]);
        let seed = (0..200).find(|&s| Tray::seeded(s).roll(1)[0] < 2).expect("some seed fails") as i64;
        let (next, shot) = run_rp(&st, &statics, seed, 7);
        let die = shot.rolls.iter().find(|r| r.owner == "a" && r.count == 1).expect("one tray die");
        assert!(die.faces[0] < 2, "this seed must FAIL: {die:?}");
        assert_eq!(next.reckless_backfire_round[0], 0, "the backfire stamp, round-scoped");
        assert_eq!(next.reckless_ap_round[0], -1, "no buff on a fail");
        assert!(
            shot.log.iter().any(|l| l.contains("Reckless Piercing") && l.contains("against it")),
            "the backfire line names the rule — got {:#?}",
            shot.log
        );
    }

    /// Consumption, shooting leg: the buff stamp lowers every save against
    /// the stamped attacker's volley by the AP(+1) — Defense 4 saves on 3+,
    /// not 4+ (main.gd:9877's `_solo_reckless_ap` fold).
    #[test]
    fn the_ap_stamp_lowers_the_volley_save_target() {
        let (mut st, _) = rp_line(7, &[]);
        st.reckless_ap_round[0] = 0;
        let mut a = UnitStatic {
            name: "a".into(),
            model_count: 1,
            shoot: vec![gun("Rifle", 6, 24)],
            ..Default::default()
        };
        a.wounds_max = vec![1];
        a.ctx.quality = 4;
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        let statics = vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }];
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()),
            charge: None, patient: false, split: None, traced: None,
        };
        let (_, shot) = run_action(&st, &statics, &action, 11, 7);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 3),
            "stamped attacker: the saves run at AP(1) — got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
        assert!(
            !shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 4),
            "no unstamped save window survives"
        );

        // No stamp: the plain Defense-4 window.
        let (mut st0, _) = rp_line(7, &[]);
        st0.reckless_ap_round[0] = -1;
        let (_, shot0) = run_action(&st0, &statics, &action, 11, 7);
        assert!(
            shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 4)
                && !shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 3),
            "unstamped: the plain save"
        );
    }

    /// Consumption, melee leg: the BACKFIRE stamp on the target hands every
    /// enemy AP(+1) — the charge's saves run at Defense-3 too
    /// (main.gd:6017's fold).
    #[test]
    fn the_backfire_stamp_hands_the_enemy_ap_in_melee() {
        let (mut st, _) = rp_line(7, &[]);
        st.reckless_backfire_round[2] = 0;
        let mut a = UnitStatic {
            name: "a".into(),
            model_count: 1,
            melee: vec![gun("Blade", 6, 0)],
            ..Default::default()
        };
        a.wounds_max = vec![1];
        a.ctx.quality = 4;
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        // Movement reads every unit's base profile: all four roster slots
        // must exist (the `buff_line` fixture's own note).
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(); 4],
            index: HashMap::new(),
        });
        let statics = vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }];
        // A CHARGE needs contact: the fixture line sits 12" apart, the charge
        // move brings the charger in (the `movement` seam is on in
        // `run_action`, the table's own M4 port).
        st.positions[1] = vec![];
        st.positions[2] = vec![[3.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.positions[3] = vec![];
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let (_, shot) = run_action(&st, &statics, &charge, 11, 7);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 3),
            "backfire: the melee saves run at AP(1) — got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
    }
