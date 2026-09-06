use super::*;

    // ------------------------------------------------- BLOCK B5: Hit & Run ---

    /// BLOCK B5 — a shot lands (`buff_line()`'s "a" vs "b" at 12"), and the
    /// bearer steps EXACTLY 3" directly AWAY from "b" (the only living enemy)
    /// on the SAME activation. Dice-free: the tray ends in the identical state
    /// whether the bearer carries the rule or not.
    #[test]
    fn hit_and_run_steps_three_inches_directly_away_from_the_nearest_enemy_after_a_shot_lands() {
        let (st, mut statics) = buff_line();
        let terrain = crate::terrain::Terrain::default();
        let action = buff_action(Some("b"));

        let mut base_tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut base_tray,
        )
        .unwrap();

        statics[0].hit_and_run_active = true;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(tray.state_i64(), base_tray.state_i64(), "Hit & Run draws no die");
        assert_eq!(next.hit_and_run_round[0], next.round);
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M as f64)).abs() < 1e-9, "got {got:?}");
            assert_eq!(got[2], before[2]);
        }
        // hero_attach is OFF by default: the attached "ah" is left behind.
        assert_eq!(next.positions[1], st.positions[1]);
    }

    /// The whole joined formation steps together when `hero_attach` is on —
    /// the same fold `resolve_with`'s own rigid move applies.
    #[test]
    fn hit_and_run_moves_the_joined_heros_formation_together_under_hero_attach() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let terrain = crate::terrain::Terrain::default();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, on, &mut rng, &mut tray,
        )
        .unwrap();
        assert!((next.positions[1][0][0] - (st.positions[1][0][0] - 3.0 * IN2M as f64)).abs() < 1e-9);
    }

    /// A DECLARED charge that falls short of contact (`buff_line`'s "b" stays
    /// 12" away, band 0) still fires Hit & Run: main.gd's own `hnr_attacked`
    /// is computed from `report["action"] == CHARGE` BEFORE `_run_ai_melee`
    /// runs, and never reset when the charge falls short — a table quirk,
    /// ported as found rather than silently tightened to "actually fought".
    #[test]
    fn hit_and_run_fires_after_a_declared_charge_that_falls_short_of_contact() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let terrain = crate::terrain::Terrain::default();
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty(), "the charge fell short — no melee, no dice at all");
        assert!((next.positions[0][0][0] - (st.positions[0][0][0] - 3.0 * IN2M as f64)).abs() < 1e-9);
        assert_eq!(next.hit_and_run_round[0], next.round);
    }
