use super::*;

    // -------------------------------- block C1: the two half-primitives ---

    /// (a) solo_controller.gd:9667 — a "Hit & Run Shooter" carrier that SHOT
    /// (`after_shoot = true`) kites 3" away from the nearest enemy and takes
    /// the shared per-round stamp (:9685), though the full "Hit & Run" gate
    /// would refuse it (no full-rule name on the profile).
    #[test]
    fn a_shooter_carrier_that_shot_steps_3_inches_and_stamps_the_round() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
        assert_eq!(st.hit_and_run_round[0], st.round);
    }

    /// (b) THE RED — the same Shooter carrier after a CHARGE is on the WRONG
    /// half (the table's pick is `"Hit & Run Shooter" if after_shoot else
    /// "Hit & Run Fighter"`, :9667): no step, no stamp. This is the test that
    /// fails the moment the `after_shoot` gate is dropped.
    #[test]
    fn a_shooter_carrier_after_a_charge_is_on_the_wrong_half() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }

    /// (c) the mirror: a "Hit & Run Fighter" carrier moves after a CHARGE
    /// (the melee leg, `after_shoot = false`) and does NOT after a shot —
    /// each half fires on its own trigger and its own EXACT name only.
    #[test]
    fn a_fighter_carrier_moves_after_a_charge_never_after_a_shot() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);

        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }

    // --- TEST WAVE (2026-09-14, D-PROOF) — the two half-primitives' NUMBER
    // pins: the EXACT name read (`unit_rule_active`'s own literal, gf
    // alien_hives / custodian_brothers) stamps its flag through the REAL
    // `build_for`, and the flag steps the shared 3" band on its own trigger
    // only, naming itself in the battle-log line.

    /// "Hit & Run Fighter" (gf/alien_hives): after a CHARGE the carrier steps
    /// EXACTLY 3" away from the nearest enemy, stamps the per-round token and
    /// logs the base line; after a SHOT (the wrong half) it stays put.
    #[test]
    fn a_hit_and_run_fighter_read_by_name_steps_three_inches_after_a_charge() {
        let terrain = crate::terrain::Terrain::default();
        let (st, statics) =
            boost_line("gf", "alien_hives", &["Hit & Run Fighter"], crate::acts::CURRENT_RULES_EPOCH);
        assert!(statics[0].hit_and_run_fighter_active, "the exact name is registry-backed");
        assert!(
            !statics[0].hit_and_run_shooter_active && !statics[0].hit_and_run_active,
            "each half fires on its own literal only"
        );
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None, };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M)).abs() < 1e-9, "got {got:?}");
        }
        assert_eq!(next.hit_and_run_round[0], next.round, "the once-per-round token");
        assert!(
            shot.log.iter().any(|l| l.contains("Hit & Run: a steps up to 3\"")),
            "rules-must-log: {:?}",
            shot.log
        );

        // The wrong half: after a SHOT the fighter stays put, unstamped.
        let (st2, statics2) =
            boost_line("gf", "alien_hives", &["Hit & Run Fighter"], crate::acts::CURRENT_RULES_EPOCH);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next2, _) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next2.positions[0], st2.positions[0]);
        assert_eq!(next2.hit_and_run_round[0], -1);
    }

    /// "Hit & Run Shooter" (gf/custodian_brothers): after a SHOT the carrier
    /// steps EXACTLY 3" away, stamps the token and logs the base line; after
    /// a (falls-short) CHARGE — the wrong half — it stays put.
    #[test]
    fn a_hit_and_run_shooter_read_by_name_steps_three_inches_after_a_shot() {
        let terrain = crate::terrain::Terrain::default();
        let (st, statics) =
            boost_line("gf", "custodian_brothers", &["Hit & Run Shooter"], crate::acts::CURRENT_RULES_EPOCH);
        assert!(statics[0].hit_and_run_shooter_active, "the exact name is registry-backed");
        assert!(
            !statics[0].hit_and_run_fighter_active && !statics[0].hit_and_run_active,
            "each half fires on its own literal only"
        );
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M)).abs() < 1e-9, "got {got:?}");
        }
        assert_eq!(next.hit_and_run_round[0], next.round, "the once-per-round token");
        assert!(
            shot.log.iter().any(|l| l.contains("Hit & Run: a steps up to 3\"")),
            "rules-must-log: {:?}",
            shot.log
        );

        // The wrong half: after a CHARGE the shooter stays put, unstamped.
        let (st2, statics2) =
            boost_line("gf", "custodian_brothers", &["Hit & Run Shooter"], crate::acts::CURRENT_RULES_EPOCH);
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None, };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next2, _) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next2.positions[0], st2.positions[0]);
        assert_eq!(next2.hit_and_run_round[0], -1);
    }
