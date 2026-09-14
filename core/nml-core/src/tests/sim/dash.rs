use super::*;

    // ---- RULE_FIDELITY_WAVE2 2026-09-13 2B.4, row `Dash` (ledger
    //      proven_vs_read_part2.tsv, family "move bands", proof_kind "none"):
    //      the gf/custodian_brothers entry rides the `Bounding` primitive with
    //      `{place_d3_plus: 1, timing: "end_of_activation", per_round: true}`.
    //      Two legs pin its band number: the FRESH arm rolls 1d3 and adds the
    //      entry's own +1 (`place_d3_plus`, read off the alias arm of
    //      `unit.rs::bounding_place_of`) to the carrier's reach before the
    //      move, naming the rule and the rolled distance (rules-must-log); the
    //      RECORDED arm replays the table's `bounding_d3` trace as "+N\" every
    //      move band this activation" (sim.rs's band fold). The exact name is
    //      the #489 lesson; the legs run at the build's current rules epoch.

    /// The carrier: a gf/custodian_brothers profile whose only rule is "Dash",
    /// read off the REAL registry — the REAL `build_for` product, at `epoch`.
    fn dash_carrier(epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Dash".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "custodian_brothers".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands { advance: 6.0, rush: 12.0, charge: None },
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// One Dash carrier "a" (at the origin, 1\" radius) with an objective 10"
    /// up +x; the other roster slots leave the board so the hop's scan has a
    /// clear corridor toward it (`place_d3`'s own hop-line fixture).
    fn dash_line(epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = dangerous_line();
        for j in 1..4 {
            st.positions[j] = vec![];
            st.radii[j] = vec![];
            st.wounds[j] = vec![];
            st.alive[j] = 0;
        }
        st.objectives = vec![crate::state::Objective {
            pos: [10.0 * IN2M, 0.0, 0.0],
            owner: 0,
        }];
        (st, vec![dash_carrier(epoch), UnitStatic { name: "ah".into(), ..Default::default() },
            UnitStatic { name: "b".into(), ..Default::default() },
            UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// One fresh-sim activation on the REAL small board, the seeded streams
    /// live (`place_d3`'s own harness).
    fn run_dash(st: &State, statics: &[UnitStatic], act: &Action) -> (State, ShootResult) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, act, &small_board(),
            Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// The FRESH arm: the hop's die is the seeded stream's FIRST draw (the
    /// only `randi_range` on this activation's path), so the probe draws the
    /// same face and the log must name the rolled reach — the faces PLUS the
    /// entry's own `place_d3_plus: 1` — under the rule's exact name.
    #[test]
    fn a_dash_activation_hops_the_rolled_d3_plus_one_before_the_move() {
        let (st, statics) = dash_line(crate::acts::CURRENT_RULES_EPOCH);
        let face = {
            let mut probe = crate::rng::GodotRng::new(0);
            probe.randi_range(1, 3)
        };
        let (next, shot) = run_dash(&st, &statics, &advance_to(20.0));
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!(
            moved_in > 6.5 && moved_in < 11.0,
            "band 6\" + the rolled D3 + the entry's +1: {moved_in}\""
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Dash") && l.contains(&format!("rolled {}\"", face + 1))),
            "rules-must-log: the hop names the rule and the rolled reach (faces + place_d3_plus 1), got {:?}",
            shot.log
        );
    }

    /// The RECORDED arm: the table's own `bounding_d3` trace — faces 2, plus
    /// the entry's `place_d3_plus` 1 — widens the ADVANCE 6" band to 9" and
    /// the RUSH 12" band to 15", the one +3" logged per leg.
    #[test]
    fn a_recorded_dash_trace_widens_the_advance_and_rush_bands_by_faces_plus_one() {
        use crate::io::TracedRoll;
        let (st, statics) = dash_line(crate::acts::CURRENT_RULES_EPOCH);
        let traced = vec![TracedRoll { tag: "bounding_d3".into(), faces: vec![2], plus: 1 }];
        let advance = crate::io::Action { traced: Some(traced.clone()), ..advance_to(20.0) };
        let (next, shot) = run_dash(&st, &statics, &advance);
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!((moved_in - 9.0).abs() < 1e-6, "advance band 6\" + the recorded 3\": {moved_in}\"");
        assert!(
            shot.log.iter().any(|l| l.contains("Bounding") && l.contains("+3")),
            "the table's own band model logs: {:?}",
            shot.log
        );
        let rush = crate::io::Action {
            kind: RUSH,
            traced: Some(traced),
            dest: Some([20.0 * IN2M, 0.0, 0.0]),
            ..advance_to(20.0)
        };
        let (next2, shot2) = run_dash(&st, &statics, &rush);
        let rushed_in = (next2.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!((rushed_in - 15.0).abs() < 1e-6, "rush band 12\" + the same 3\": {rushed_in}\"");
        assert!(
            shot2.log.iter().any(|l| l.contains("Bounding") && l.contains("+3")),
            "the rush leg logs the same band bonus: {:?}",
            shot2.log
        );
    }
