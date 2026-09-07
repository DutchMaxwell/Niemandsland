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

    /// BISECT: the dice fold alone -- a shooter whose Ctx already carries
    /// `reckless_ap: 1` must raise the save target to 5.
    #[test]
    fn bisect_dice_fold_reckless_ap() {
        let profiles = [ShootProfile { name: "R".into(), attacks: 8, count: 1, range: 24, ..Default::default() }];
        let att = Ctx { quality: 2, reckless_ap: 1, ..Default::default() };
        let def = Ctx { defense: 4, tough: 1, models: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter { profiles: &profiles, keep: &[0], attacks: &[8], att: &att, owner: "a" }];
        let mut tray = Tray::seeded(11);
        let out = crate::dice::resolve_volley_with_tray(
            &strikers, &def, "b", 12.0, 12.0, false, false, false, false, &mut tray,
        );
        assert!(
            out.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "dice fold: {:#?}",
            out.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
    }

    /// Consumption, shooting leg -- the PROVEN `tag_volley` harness: a rifle
    /// carrier on the split line, the victim Defense 4. With the buff stamp
    /// on the shooter every spent save window runs at AP(1) (target 3), the
    /// unstamped control replays the plain Defense-4 window (main.gd:9877).
    #[test]
    fn the_ap_stamp_lowers_the_volley_save_target() {
        let (mut st, mut statics) = tag_line("Piercing Tag", 0, 24.0);
        statics[0].piercing_tags.clear();
        statics[0].shoot[0].attacks = 64;
        // The handler stamps the whole joined chain -- hero included.
        st.reckless_ap_round[0] = 0;
        st.reckless_ap_round[1] = 0;
        let (_, shot) = tag_volley(&statics, &st, Seams { rules_epoch: 7, ..Seams::default() });
        assert!(
            shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "stamped attacker: the saves run at AP(1) -- got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
        assert!(
            shot.rolls.iter().all(|r| r.kind != "defense" || r.target == 5 || r.count == 0),
            "every spent save window runs at AP(1)"
        );

        // No stamp: the plain Defense-4 window.
        let (st0, mut statics) = tag_line("Piercing Tag", 0, 24.0);
        statics[0].piercing_tags.clear();
        statics[0].shoot[0].attacks = 64;
        let (_, shot0) = tag_volley(&statics, &st0, Seams { rules_epoch: 7, ..Seams::default() });
        assert!(
            shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 4)
                && !shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "unstamped: the plain save -- got {:#?}",
            shot0.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
    }

    /// Consumption, melee leg -- `strike_phase` called directly on the
    /// four-unit line with the charger in contact: the BACKFIRE stamp on the
    /// target hands the attacker AP(+1), so the melee saves run at 3+
    /// (main.gd:6017's `_solo_reckless_ap` fold).
    #[test]
    fn the_backfire_stamp_hands_the_enemy_ap_in_melee() {
        let (mut st, mut statics) = rp_line(7, &[]);
        st.reckless_backfire_round[2] = 0;
        statics[0].melee = vec![gun("Blade", 64, 0)];
        // A consistent ONE-model target: the fixture line carries three.
        st.alive[2] = 1;
        st.wounds[2] = vec![1];
        st.positions[2] = vec![[1.2 * IN2M, 0.0, 0.0]]; // base-edge contact
        st.radii[2] = vec![IN2M];
        let mut tray = Tray::seeded(11);
        let mut shot = ShootResult::default();
        let seams = Seams { rules_epoch: 7, ..Seams::default() };
        strike_phase(&statics, &mut st, 0, 2, true, seams, &mut tray, &mut shot);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "backfire: the melee saves run at AP(1) -- got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );

        // No backfire stamp: the plain Defense-4 window.
        let (mut st0, mut statics) = rp_line(7, &[]);
        statics[0].melee = vec![gun("Blade", 64, 0)];
        st0.alive[2] = 1;
        st0.wounds[2] = vec![1];
        st0.radii[2] = vec![IN2M];
        st0.positions[2] = vec![[1.2 * IN2M, 0.0, 0.0]];
        let mut tray0 = Tray::seeded(11);
        let mut shot0 = ShootResult::default();
        strike_phase(&statics, &mut st0, 0, 2, true, seams, &mut tray0, &mut shot0);
        assert!(
            shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 4)
                && !shot0.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "unstamped melee: the plain save -- got {:#?}",
            shot0.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
    }
