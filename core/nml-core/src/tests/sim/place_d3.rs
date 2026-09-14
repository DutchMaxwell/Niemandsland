use super::*;

    // ---- epoch 26 (STANDALONE_SWEEP_C 2026-09-14: Wave-Step / Wolfborn / Rapid Blink) ----
    //
    // The `Bounding {place_d3 ..}` primitive's activation placement: "When this
    // unit is activated, you may place all models with this rule in it anywhere
    // fully within D3\" of their position." The table rolls the die at the
    // activation's head on its seeded RNG (solo_controller.gd:1688-1710); a
    // fresh core sim never rolled it and never hopped, so the carrier's reach
    // ran short by up to the roll. From epoch 26 the core rolls its own D3 from
    // the seeded stream and re-places the carrier BEFORE the move, reusing
    // #930's free-placement scan (`deployment::vanguard_free_place`).

    /// The carrier: a gf/wolf_brothers profile whose ONLY rule is "Wolfborn"
    /// (the `Bounding {place_d3_plus: 0}` alias, gf 2 books), read off the REAL
    /// registry. The REAL `build_for` product, at `epoch`.
    fn wolfborn(epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Wolfborn".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "wolf_brothers".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands { advance: 6.0, rush: 12.0, charge: None },
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// One Wolfborn carrier "a" (4 models at the origin, 1\" radii) with an
    /// objective 10\" up +x; the other roster slots leave the board so the
    /// hop's scan has a clear corridor toward it.
    fn hop_line(epoch: u32) -> (State, Vec<UnitStatic>) {
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
        (st, vec![wolfborn(epoch), UnitStatic { name: "ah".into(), ..Default::default() },
            UnitStatic { name: "b".into(), ..Default::default() },
            UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// One fresh-sim ADVANCE (no recorded trace, the seeded stream live) far
    /// past the destination, on the REAL small board — a placement needs a
    /// table (an absent board refuses the hop, the `is_valid` law).
    fn run_hop(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> (State, ShootResult) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, &advance_to(20.0), &small_board(),
            Seams { rules_epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// At the NEW epoch a fresh-sim Wolfborn activation hops the unit toward
    /// the objective BEFORE the move — the ADVANCE lands past the plain 6\"
    /// band (band + the rolled D3 inches), and the hop names its rule and the
    /// rolled distance (rules-must-log). The roll is 1..=3, the scan takes a
    /// strictly closer legal spot only, so 6.5\"-9.5\" covers every face.
    #[test]
    fn at_epoch_26_a_wolfborn_activation_hops_before_the_move() {
        let (st, statics) = hop_line(crate::acts::EPOCH_26_PLACE_D3);
        let (next, shot) = run_hop(&st, &statics, crate::acts::EPOCH_26_PLACE_D3);
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!(
            moved_in > 6.5 && moved_in < 9.5,
            "the hop joined the move: {moved_in}\" (band 6\" + up to 3\" of D3)"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Wolfborn") && l.contains("rolled")),
            "rules-must-log: one trace line naming the rule and the rolled distance, got {:?}",
            shot.log
        );
    }

    /// The OLD leg, pinned to the epoch immediately below the bump —
    /// EPOCH_25_ETHEREAL_BANDS (#941 landed mid-flight; the reserved 24 was
    /// renumbered to 26 at rebase): a fresh-sim Wolfborn activation does NOT
    /// hop — the ADVANCE is the plain 6\" band to the digit (every recorded
    /// corpus's reading), and nothing logs. Below the gate the stamp is
    /// `None`, the trace replay stays the whole effect.
    #[test]
    fn at_epoch_25_a_wolfborn_activation_stays_on_its_plain_band() {
        let (st, statics) = hop_line(crate::acts::EPOCH_25_ETHEREAL_BANDS);
        let (next, shot) = run_hop(&st, &statics, crate::acts::EPOCH_25_ETHEREAL_BANDS);
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!((moved_in - 6.0).abs() < 1e-6, "plain band only: {moved_in}\"");
        assert!(
            !shot.log.iter().any(|l| l.contains("placed")),
            "no hop below the gate: {:?}",
            shot.log
        );
    }

    /// The replay law at the NEW epoch: a RECORDED act (the table's own
    /// `bounding_d3` trace) replays the table's band-bonus model byte-exact —
    /// the trace's faces grow the band (6\" + 2\"), there is NO second hop and
    /// no placement log, exactly what every recorded table game printed.
    #[test]
    fn a_recorded_trace_replays_the_band_bonus_at_epoch_26_without_a_hop() {
        use crate::io::TracedRoll;
        let (st, statics) = hop_line(crate::acts::EPOCH_26_PLACE_D3);
        let act = crate::io::Action {
            traced: Some(vec![TracedRoll { tag: "bounding_d3".into(), faces: vec![2], plus: 0 }]),
            ..advance_to(20.0)
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &act, &small_board(),
            Seams { rules_epoch: crate::acts::EPOCH_26_PLACE_D3, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!((moved_in - 8.0).abs() < 1e-6, "band 6\" + the recorded 2\": {moved_in}\"");
        assert!(
            shot.log.iter().any(|l| l.contains("+2")),
            "the table's own band model logs: {:?}",
            shot.log
        );
        assert!(
            !shot.log.iter().any(|l| l.contains("placed")),
            "a recorded act never hops: {:?}",
            shot.log
        );
    }
