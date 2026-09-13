use super::*;

    // ------------------- epoch 12: Great Musician (the move-only Utility-Buff knob) ---

    /// The registry-built bearer: an aof/ogres profile whose ONLY rule is
    /// "Great Musician", read off the REAL registry
    /// (`assets/solo/rules_mechanics_aof.json`, params move_mod 1 / target
    /// friendly / max_targets 1 / range_in 12 / once). The REAL `build_for`
    /// product, read at `epoch`.
    fn great_musician_bearer(rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Great Musician".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: "ogres".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" at 0", friend "b" at 5", SAME player, inside the printed
    /// 12" pick. `b`'s Tough outranks the bearer's own (the pick is
    /// `alive + Tough`, best first, sim.rs::utility_targets), so the
    /// pre-attack pick lands on "b" and nowhere else.
    fn great_musician_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Great Musician", "ogres", rules_epoch);
        st.player = vec![0, 0, 0, 0];
        st.positions[2] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.wounds[2] = vec![1];
        st.alive = vec![1, 0, 1, 0];
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.defense = 4;
        b.ctx.tough = 2;
        (
            st,
            vec![
                great_musician_bearer(rules_epoch),
                UnitStatic { name: "ah".into(), ..Default::default() },
                b,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    /// The bearer's activation — the pre-attack Utility-Buff pick runs.
    fn run_hold(st: &State, statics: &[UnitStatic], unit: &str, rules_epoch: u32) -> State {
        let action = Action {
            kind: HOLD, unit: unit.into(), dest: None, shoot: None,
            charge: None, patient: false, split: None, traced: None, teleport: None, };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// One move on the tray path — the seed never matters (a plain move
    /// draws no die). The `feat_speed.rs` shape, unit taken from the action.
    fn run_move(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    fn advance_of(unit: &str, x_in: f64) -> Action {
        Action {
            kind: ADVANCE,
            unit: unit.into(),
            dest: Some([x_in * IN2M, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        }
    }

    /// RED: the bearer's Utility-Buff pick lands NOTHING on its friend today
    /// (record_buff drops the all-zero row, sim.rs:935), so the friend
    /// advances its bare 6" band. At `EPOCH_12_MOVE_BUFF` the +1" must ride.
    /// The expectation is written as `base_band + move_mod` (never a magic
    /// inch constant) so a later band change cannot silently re-bless it.
    #[test]
    fn great_musician_extends_the_buffed_advance_at_epoch_12() {
        let base_band = 6.0;
        let move_mod = 1.0;
        let (st, statics) = great_musician_line(12); // bearer "a" at 0", friend "b" at 5", same player
        let after_pick = run_hold(&st, &statics, "a", 12); // the bearer activates: the pick lands
        assert_eq!(
            after_pick.buffs[2].len(),
            1,
            "the move-only row reaches the ledger at epoch 12"
        );
        let (landed, _) = run_move(&after_pick, &statics, &advance_of("b", 20.0), 12);
        let x = landed.positions[2][0][0];
        assert!(
            (x - (5.0 + base_band + move_mod) * IN2M).abs() < 1e-6,
            "the buffed ADVANCE rides +1\" (6\" band + 1\"): {x}"
        );
    }

    /// The epoch twin: a record stamped 11 (every corpus recorded up to
    /// today's live epoch) keeps replaying byte-exact — the row is not
    /// recorded (the parse stays 0, the all-zero row keeps being dropped)
    /// and the band is bare.
    #[test]
    fn an_epoch_11_record_sees_no_move_buff() {
        let base_band = 6.0;
        let (st, statics) = great_musician_line(11);
        let after_pick = run_hold(&st, &statics, "a", 11);
        assert!(
            after_pick.buffs[2].is_empty(),
            "an epoch-11 record carries no move row"
        );
        let (landed, _) = run_move(&after_pick, &statics, &advance_of("b", 20.0), 11);
        let x = landed.positions[2][0][0];
        assert!(
            (x - (5.0 + base_band) * IN2M).abs() < 1e-6,
            "an epoch-11 record replays at the plain band: {x}"
        );
    }
