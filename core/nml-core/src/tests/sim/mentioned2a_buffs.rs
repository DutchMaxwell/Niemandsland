use super::*;

    // ---------------- MENTIONED wave 2, chunk 1: the board-fold rows ---------
    //
    // The three MENTIONED rows whose numbers only resolve on the LIVE board:
    // "Entrenched Buff" and "Hold the Line Boost Buff" stamp their Utility
    // Buff record through the #985 seam (tray_utility_buff -> utility_targets
    // -> record_buff), and "Hit & Run Fighter Aura" hands the Fighter half's
    // 3-inch post-attack band to its carrier through the core's own stamp.
    // Every row by its EXACT NAME at `CURRENT_RULES_EPOCH`; no epoch bump.

    /// The row's bearer: a single-model unit whose ONLY printed rule is the
    /// REAL registry entry, one 24" rifle (silent on a HOLD), the REAL
    /// `build_for` product at `epoch`.
    fn bearer(system: &str, faction: &str, rule: &str, epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![crate::state::Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 2,
                count: 1,
                ap: 0,
                rules: vec![],
            }],
            special_rules: vec![rule.into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: system.into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// The board: bearer "a" at the origin, friend "in" 5" away (inside the
    /// printed 12" pick range, Tough 2 — value 3 beats the bearer's own, so
    /// the pick lands on IT), friend "out" 15" away (beyond the pick range,
    /// Tough 9 — a value that would win the pick if the range gate leaked).
    /// All one player.
    fn ub_line(system: &str, faction: &str, rule: &str) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.player = vec![0, 0, 0, 0];
        st.alive = vec![1, 0, 1, 1];
        st.wounds = vec![vec![1], vec![], vec![1], vec![1]];
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0]],
            vec![[15.0 * IN2M, 0.0, 0.0]],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]];
        let mut inside = UnitStatic { name: "in".into(), ..Default::default() };
        inside.ctx.tough = 2;
        let mut outside = UnitStatic { name: "out".into(), ..Default::default() };
        outside.ctx.tough = 9;
        (
            st,
            vec![
                bearer(system, faction, rule, crate::acts::CURRENT_RULES_EPOCH),
                UnitStatic { name: "ah".into(), ..Default::default() },
                inside,
                outside,
            ],
        )
    }

    /// One HOLD activation of the bearer — the pre-attack slot the utility
    /// tray occupies, dice-free.
    fn run_line(st: &State, statics: &[UnitStatic]) -> State {
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: None,
            charge: None, patient: false, split: None, traced: None, teleport: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// BOTH rows, one table: the record lands on the in-range pick with the
    /// printed grant, never beyond the 12" pick range, never on the bearer;
    /// the build stamp carries the entry's own numbers.
    #[test]
    fn the_entrenched_and_hold_the_line_buff_rows_stamp_their_records_at_current_epoch() {
        let rows = [
            ("gf", "human_defense_force", "Entrenched Buff", "Entrenched"),
            ("aof", "human_empire", "Hold the Line Boost Buff", "Hold the Line Boost"),
        ];
        for (system, faction, rule, grants) in rows {
            let us = bearer(system, faction, rule, crate::acts::CURRENT_RULES_EPOCH);
            let ub = us.utility_buffs.first().expect("the row IS read off the registry");
            assert_eq!(ub.name, rule, "{}: the stamp reads the entry by its exact name", rule);
            assert_eq!(&*ub.grants_rule, grants, "{}: the entry's printed grant", rule);
            assert_eq!(ub.max_targets, 1, "{}: the entry's max_targets", rule);
            assert_eq!(ub.range_in, 12.0, "{}: the entry's printed pick range", rule);
            assert!(ub.once, "{}: the once promise", rule);
            let (st, statics) = ub_line(system, faction, rule);
            let next = run_line(&st, &statics);
            assert!(
                next.buffs[3].is_empty(),
                "{}: the 15\" friend is beyond the printed 12\" pick range -- got {:?}",
                rule, next.buffs[3]
            );
            assert_eq!(next.buffs[2].len(), 1, "{}: one record on the in-range pick", rule);
            let rec = &next.buffs[2][0];
            assert_eq!(&*rec.name, rule, "{}: the record names the rule exactly", rule);
            assert_eq!(&*rec.grants_rule, grants, "{}: the record carries the printed grant", rule);
            assert!(rec.once, "{}: the once-per-activation promise rides the record", rule);
            assert!(
                next.buffs[0].is_empty(),
                "{}: the in-range friend outranks the bearer, the bearer stays unstamped",
                rule
            );
        }
    }

    /// "Hold the Line Boost Buff" grants "Hold the Line Boost", and the
    /// granted Boost's own number in the morale net is the +2 the core folds
    /// at the rolled morale test (sim.rs's tray_morale, epoch-gated).
    #[test]
    fn a_hold_the_line_boost_buffs_grant_joins_the_morale_net_at_plus_two() {
        assert_eq!(
            crate::combat::HOLD_THE_LINE_BOOST_MORALE_BONUS, 2,
            "the granted Boost's morale_bonus"
        );
    }

    /// "Hit & Run Fighter Aura" hands the Fighter half to its carrier: the
    /// core-stamped flag fires the 3-inch post-attack step on the melee leg —
    /// a declared charge that falls short of contact still counts as the
    /// attack (main.gd's own hnr_attacked quirk, ported as found).
    #[test]
    fn a_hit_and_run_fighter_aura_steps_three_inches_after_a_declared_charge() {
        let (st, mut statics) = buff_line();
        let fighter = bearer(
            "gf",
            "wormhole_daemons_of_lust",
            "Hit & Run Fighter Aura",
            crate::acts::CURRENT_RULES_EPOCH,
        );
        statics[0] = fighter;
        let terrain = crate::terrain::Terrain::default();
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty(), "the charge fell short — no melee, no dice at all");
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!(
                (got[0] - (before[0] - 3.0 * IN2M)).abs() < 1e-9,
                "the Fighter half steps exactly 3 inches away, got {got:?}"
            );
        }
    }
