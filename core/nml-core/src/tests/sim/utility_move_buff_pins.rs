use super::*;

    // --- TEST WAVE (part 2, chunk 3 of 4; D-PROOF) — the three move-grant
    // UTILITY BUFF rows the 14.09. sweep found only `mentioned`: "Speed Buff"
    // grants "Fast", "Rapid Rush Buff" grants "Rapid Rush", "Speed Debuff"
    // grants "Slow" (enemy). Each is pinned through the REAL registry at
    // `CURRENT_RULES_EPOCH` (no epoch bump, no behaviour change): the record
    // lands by the rule's EXACT NAME on the in-range pick (and never on the
    // out-of-range one), and the granted base's own inches move the
    // recipient's band at the EPOCH_19 move spend. The reads' own trace lines
    // fire only under NML_TRACE_RULES=1, which no core test asserts today
    // (utility_buff_family's standing note).

    /// The row's carrier: a single-model unit whose ONLY printed rule is the
    /// REAL registry entry, one 24" rifle (silent on a HOLD). A `rule` of ""
    /// builds the bare recipient twin — a real `build_for` product, so its
    /// `solo_move_grant_mods` stamp exists and the fold can read it.
    fn buff_carrier(system: &str, faction: &str, rule: &str) -> UnitStatic {
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
        UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH)
    }

    /// The friendly board: bearer "a" at the origin, friend "b" 5" away
    /// (inside the printed 12" pick range, Tough 2 — value 3 beats the
    /// bearer's own, so the pick lands on IT), friend "bh" 15" away and OFF
    /// the rush lane (beyond the pick range, Tough 9 — a value that would win
    /// the pick if the range gate leaked). ah is dead. All one player.
    fn friendly_line(system: &str, faction: &str, rule: &str) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(); 4],
            index: HashMap::new(),
        });
        st.player = vec![0, 0, 0, 0];
        st.alive = vec![1, 0, 1, 1];
        st.wounds = vec![vec![1], vec![], vec![1], vec![1]];
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0]],
            vec![[15.0 * IN2M, 4.0 * IN2M, 0.0]],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]];
        let mut inside = buff_carrier(system, faction, "");
        inside.ctx.tough = 2;
        let mut outside = buff_carrier(system, faction, "");
        outside.ctx.tough = 9;
        (
            st,
            vec![
                buff_carrier(system, faction, rule),
                UnitStatic { name: "ah".into(), ..Default::default() },
                inside,
                outside,
            ],
        )
    }

    /// The enemy-side board for "Speed Debuff": bearer "a" at the origin
    /// (player 0), enemies "b" 6" and "bh" 25" away (player 1, Tough 2 / 9 —
    /// the far one would win the pick if the 18" gate leaked).
    fn enemy_line(system: &str, faction: &str, rule: &str) -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = friendly_line(system, faction, rule);
        st.player = vec![0, 0, 1, 1];
        st.positions[3] = vec![[25.0 * IN2M, 0.0, 0.0]];
        (st, statics)
    }

    /// One HOLD activation of the bearer at the current epoch — the pre-attack
    /// slot the utility tray occupies, dice-free.
    fn run_hold(st: &State, statics: &[UnitStatic]) -> State {
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

    /// One move of unit key `who` at the current epoch — the seed never
    /// matters (a plain move draws no die); the move_grants.rs shape.
    fn run_move(st: &State, statics: &[UnitStatic], kind: i64, unit: &str, dest_in: f64) -> State {
        let action = Action {
            kind, unit: unit.into(), dest: Some([dest_in * IN2M, 0.0, 0.0]),
            shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// "Speed Buff" (gf/soul_snatcher_cults, grants "Fast", friendly 12",
    /// once): the record lands on the in-range friend by the exact name, and
    /// the granted Fast rides the rush band (+4": 12 -> 16) at the move spend.
    #[test]
    fn a_speed_buff_records_fast_and_the_pick_gains_four_rush_inches() {
        let (st, statics) = friendly_line("gf", "soul_snatcher_cults", "Speed Buff");
        let next = run_hold(&st, &statics);
        assert!(
            next.buffs[3].is_empty(),
            "the 15\" friend is beyond the printed 12\" pick range: {:?}",
            next.buffs[3]
        );
        assert_eq!(next.buffs[2].len(), 1, "one record on the in-range pick");
        let rec = &next.buffs[2][0];
        assert_eq!(&*rec.name, "Speed Buff", "the record names the rule exactly");
        assert_eq!(&*rec.grants_rule, "Fast", "the record carries the printed grant");
        assert!(rec.once, "the once-per-activation promise rides the record");
        let landed = run_move(&next, &statics, RUSH, "b", 40.0);
        let x = landed.positions[2][0][0];
        assert!(
            (x - (5.0 + 12.0 + 4.0) * IN2M).abs() < 1e-6,
            "the granted Fast rides +4\" on the recipient's rush band (12 -> 16 from 5\"): {x}"
        );
    }

    /// "Rapid Rush Buff" (aof/human_empire, grants "Rapid Rush", friendly
    /// 12", once): the record carries the printed grant and the granted base
    /// rides +6" onto the recipient's rush band.
    #[test]
    fn a_rapid_rush_buff_records_rapid_rush_and_the_pick_gains_six_rush_inches() {
        let (st, statics) = friendly_line("aof", "human_empire", "Rapid Rush Buff");
        let next = run_hold(&st, &statics);
        assert!(
            next.buffs[3].is_empty(),
            "the 15\" friend is beyond the printed 12\" pick range: {:?}",
            next.buffs[3]
        );
        assert_eq!(next.buffs[2].len(), 1, "one record on the in-range pick");
        let rec = &next.buffs[2][0];
        assert_eq!(&*rec.name, "Rapid Rush Buff", "the record names the rule exactly");
        assert_eq!(&*rec.grants_rule, "Rapid Rush", "the record carries the printed grant");
        let rushed = run_move(&next, &statics, RUSH, "b", 40.0);
        assert!(
            (rushed.positions[2][0][0] - (5.0 + 12.0 + 6.0) * IN2M).abs() < 1e-6,
            "the granted Rapid Rush rides +6\" on the recipient's rush band (12 -> 18): {}",
            rushed.positions[2][0][0]
        );
    }

    /// "Speed Debuff" (aof/dwarves, grants "Slow", ENEMY 18", `needs_los`,
    /// once): the record lands on the in-range enemy and the granted Slow
    /// shrinks ITS bands (-2 advance / -4 rush); the 25" enemy is never
    /// picked.
    #[test]
    fn a_speed_debuff_brakes_the_enemy_picks_bands_at_the_current_epoch() {
        let (st, statics) = enemy_line("aof", "dwarves", "Speed Debuff");
        let next = run_hold(&st, &statics);
        assert!(
            next.buffs[3].is_empty(),
            "the 25\" enemy is beyond the printed 18\" pick range: {:?}",
            next.buffs[3]
        );
        assert_eq!(next.buffs[2].len(), 1, "one record on the in-range enemy");
        let rec = &next.buffs[2][0];
        assert_eq!(&*rec.name, "Speed Debuff", "the record names the rule exactly");
        assert_eq!(&*rec.grants_rule, "Slow", "the record carries the printed grant");
        let advanced = run_move(&next, &statics, ADVANCE, "b", 20.0);
        assert!(
            (advanced.positions[2][0][0] - (5.0 + 6.0 - 2.0) * IN2M).abs() < 1e-6,
            "the granted Slow rides -2\" on the enemy's advance band (6 -> 4 from 5\"): {}",
            advanced.positions[2][0][0]
        );
        let rushed = run_move(&next, &statics, RUSH, "b", 40.0);
        assert!(
            (rushed.positions[2][0][0] - (5.0 + 12.0 - 4.0) * IN2M).abs() < 1e-6,
            "the granted Slow rides -4\" on the enemy's rush band (12 -> 8 from 5\"): {}",
            rushed.positions[2][0][0]
        );
    }
