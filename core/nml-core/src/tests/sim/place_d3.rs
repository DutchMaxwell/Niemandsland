use super::*;

    // ---- epoch 24 (STANDALONE_SWEEP_C 2026-09-14: Wave-Step / Wolfborn / Rapid Blink) ----
    //
    // The `Bounding {place_d3 ..}` primitive's activation placement: "When this
    // unit is activated, you may place all models with this rule in it anywhere
    // fully within D3\" of their position." The table rolls the die at the
    // activation's head on its seeded RNG (solo_controller.gd:1688-1710); a
    // fresh core sim never rolled it and never hopped, so the carrier's reach
    // ran short by up to the roll. From epoch 24 the core rolls its own D3 from
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
    /// past the destination, so band and hop both spend fully.
    fn run_hop(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> (State, ShootResult) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, &advance_to(20.0), &crate::terrain::Terrain::default(),
            Seams { rules_epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// RED first: at the NEW epoch a fresh-sim Wolfborn activation hops the
    /// unit toward the objective BEFORE the move — the ADVANCE lands past the
    /// plain 6\" band (band + the rolled D3 inches), and the hop names its
    /// rule and the rolled distance (rules-must-log). Any face passes: the
    /// roll is 1..=3, the scan only takes a strictly closer legal spot.
    #[test]
    fn at_epoch_24_a_wolfborn_activation_hops_before_the_move() {
        let (st, statics) = hop_line(24);
        let (next, shot) = run_hop(&st, &statics, 24);
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!(
            moved_in > 6.0 && moved_in < 9.5,
            "the hop joined the move: {moved_in}\" (band 6\" + up to 3\" of D3)"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Wolfborn") && l.contains("rolled")),
            "rules-must-log: one trace line naming the rule and the rolled distance, got {:?}",
            shot.log
        );
    }