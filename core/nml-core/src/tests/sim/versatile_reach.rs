use super::*;

    // ------------------------------------------- BLOCK C: Versatile Reach ---

    /// GF v3.5.1 p.9 "Consolidation Moves": a melee that wipes the enemy
    /// (`vr_charge_line`'s "a" vs the melee-less "b", already in contact) lets
    /// the survivor move up to 3" toward the nearest objective, stamped 10"
    /// due z of "a" so the whole band is spent and the delta is exact. RED
    /// without the seam: `consolidate="off"` (the default) never moves it.
    #[test]
    fn consolidate_table_moves_the_winner_three_inches_toward_the_nearest_marker() {
        let (mut st, statics) = vr_charge_line(0.0);
        st.objectives = vec![crate::state::Objective { pos: [0.0, 0.0, 10.0 * IN2M], owner: 1 }];
        let terrain = small_board();
        let action = vr_charge();

        let off = resolve_on_board(&statics, &st, &action, &terrain, Seams::default()).unwrap();
        assert_eq!(off.alive[1], 0, "the melee must wipe the target for this test to prove anything");
        assert_eq!(
            off.positions[0][0], [0.0, 0.0, 0.0],
            "consolidate=\"off\" (default): the winner never moves"
        );

        let on = resolve_on_board(
            &statics, &st, &action, &terrain, Seams { consolidate: true, ..Seams::default() },
        )
        .unwrap();
        assert_eq!(on.alive[1], 0);
        let moved_in = on.positions[0][0][2] / IN2M;
        assert!(
            (moved_in - 3.0).abs() < 1e-6,
            "consolidate=\"table\": the winner spends the whole 3\" band toward the marker, got {:.4}\"",
            moved_in
        );
    }

    /// (a) THE WITNESS POLICY — a CHARGE whose base-edge gap sits in the
    /// unlock ring `(band, band + 2"]` lands in contact: the action itself is
    /// the evidence the table's own judge took the charge half. RED without
    /// the port (the plain 12" band falls 1.5" short of the boundary).
    #[test]
    fn a_vr_charge_in_the_unlock_ring_lands_in_contact() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let next = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&next) < 0.3,
            "in the ring, the +2\" must land contact: gap {:.3}\"",
            vr_gap(&next)
        );
    }

    /// (b) THE UPPER BOUND — a gap of `band + 2.5"` is outside the closed
    /// ring: the band stays byte-identical to a non-carrier's and the charge
    /// falls 2.5" short. RED the moment the upper bound is loosened or lost.
    #[test]
    fn a_vr_charge_outside_the_ring_gets_no_bonus() {
        let (st, mut statics) = vr_charge_line(14.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let next = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&next) > 2.0,
            "outside the ring the plain band stands: gap {:.3}\"",
            vr_gap(&next)
        );
    }

    /// (c) THE LOWER BOUND — a charge that is already legal (`gap <= band`)
    /// gets NOTHING: on the rigid arm the carrier's translation is
    /// byte-identical to a non-carrier's, which is what keeps the port from
    /// over-granting on ordinary charges. RED the moment the `gap > band`
    /// guard is dropped — the band then reaches the target CENTRE one inch
    /// further on.
    #[test]
    fn an_ordinary_vr_charge_lands_exactly_like_a_non_carriers() {
        let (st, statics) = vr_charge_line(11.0);
        let action = Action { dest: Some(st.positions[1][0]), ..vr_charge() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (plain, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &small_board(), Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let (st2, mut statics2) = vr_charge_line(11.0);
        statics2[0].versatile_reach_charge_in = Some(2.0);
        let mut tray2 = Tray::seeded(11);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (carrier, _) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &action, &small_board(), Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert_eq!(
            carrier.positions[0], plain.positions[0],
            "inside the plain band the landing is byte-identical"
        );
    }

    /// (d) THE KIND GATE — the same carrier RUSHing at the same point draws no
    /// band. The act mirrors battle_sim.gd:649-650, which reads the charge key
    /// for EVERY move kind, so a recorded RUSH can carry one: without the
    /// `kind != CHARGE` gate the helper would grant the +2" here too and the
    /// rigid arm would spend 14". RED the moment the gate falls.
    #[test]
    fn a_vr_rush_draws_no_band_bonus() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let rush = Action {
            kind: RUSH, unit: "a".into(), dest: Some(st.positions[1][0]), shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let next = vr_resolve(&st, &statics, &rush);
        let moved = (next.positions[0][0][0] - st.positions[0][0][0]).abs() / IN2M as f64;
        assert!(
            (moved - 12.0).abs() < 1e-6,
            "the plain rush band, nothing more: moved {:.3}\"",
            moved
        );
    }

    /// The `versatile_reach` knob itself (`Knobs`/`Seams::versatile_reach`,
    /// INVESTIGATION_gen0_replay_drift_2026-09-03.md): PR #582 shipped this
    /// bonus with no legacy gate at all, so 45/2000 sampled Gen-0 games
    /// (recorded before #582) no longer replay byte-identical. OFF (the
    /// `Default`, every corpus recorded before #582) must replay the same gap
    /// a non-carrier gets — no bonus, band unchanged; ON (the shipped current
    /// engine) applies the same +2" ring bonus test (a) above proves. RED if
    /// the `!versatile_reach` guard in `versatile_reach_charge_in` is
    /// dropped: the "off" row would land in contact like the "on" row.
    #[test]
    fn the_versatile_reach_knob_off_replays_legacy_and_on_applies_the_bonus() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (legacy, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams { movement: true, versatile_reach: false, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            (vr_gap(&legacy) - 1.5).abs() < 1e-6,
            "knob OFF: the plain 12\" rush band alone, 1.5\" short of the 13.5\" gap, got {:.3}\"",
            vr_gap(&legacy)
        );

        let on = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&on) < 0.3,
            "knob ON: the +2\" ring bonus lands in contact, gap {:.3}\"",
            vr_gap(&on)
        );
    }

    /// The CLASS FIX (external review 03.09. item 3 / F9, `acts::rule_on`):
    /// the boolean's own OFF row above is `rules_epoch: 0`, the reading every
    /// pre-epoch corpus (including this test's own default) carries and must
    /// keep replaying unaffected. `rules_epoch: CURRENT_RULES_EPOCH` — what a
    /// fresh `play_game()` stamps — turns the SAME rule on even with the
    /// boolean left at its legacy `false`, exactly like a fresh recording
    /// that never sets `versatile_reach` itself. RED if `rule_on` is dropped
    /// from the `versatile_reach_charge_in` call site in `resolve_with`: the
    /// epoch row would land short like the legacy row.
    #[test]
    fn the_versatile_reach_epoch_gate_turns_the_bonus_on_without_the_knob() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);

        let mut off_tray = Tray::seeded(11);
        let mut off_rng = crate::rng::GodotRng::new(0);
        let (epoch_0, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams { movement: true, versatile_reach: false, rules_epoch: 0, ..Seams::default() },
            &mut off_rng, &mut off_tray,
        )
        .unwrap();
        assert!(
            (vr_gap(&epoch_0) - 1.5).abs() < 1e-6,
            "epoch 0, knob false: still the plain 12\" rush band, got {:.3}\"",
            vr_gap(&epoch_0)
        );

        let mut on_tray = Tray::seeded(11);
        let mut on_rng = crate::rng::GodotRng::new(0);
        let (epoch_current, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams {
                movement: true, versatile_reach: false,
                rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default()
            },
            &mut on_rng, &mut on_tray,
        )
        .unwrap();
        assert!(
            vr_gap(&epoch_current) < 0.3,
            "rules_epoch: CURRENT_RULES_EPOCH, knob false: the +2\" bonus still lands in contact, gap {:.3}\"",
            vr_gap(&epoch_current)
        );
    }
