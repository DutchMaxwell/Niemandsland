use super::*;

    // ------------- sweep B 2026-09-14, row `Screened`: the CHARGE leg ---------

    // The book (gf/aof army-book data, originalName "Screened", aliased to the
    // Stealth primitive with `applies_charged: true`): "When units where all
    // models have this rule are shot or charged from over 9\" away, enemy
    // units get -1 to hit rolls." The core folds the alias pair on the
    // SHOOTING path only (dice.rs's volley, `stealth_alias_penalty`/
    // `stealth_alias_over_in`); `melee_hit_modifier` takes no stealth-alias
    // argument at all, so a charge launched from 10" rolls unpenalised hits in
    // every core-simulated game while the same charge at the table costs 1.

    /// The board: a single-model charger (Quality 4, one 8-attack Blade) 10.5"
    /// unit-centre to unit-centre from a single-model Screened target (Defense
    /// 4) — `vr_charge_line(8.5)`: base-EDGE gap 8.5", inside the 12" charge
    /// band, so the charge connects. `geom::centre_dist_in` is the NML-1152
    /// over-9" modifier measure — the same distance the table stamps into
    /// `report["charge_from_in"]` (solo_controller.gd:2329, pre-move).
    fn screened_charge_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = vr_charge_line(8.5);
        statics[1].ctx.stealth_alias_penalty = 1;
        statics[1].ctx.stealth_alias_over_in = 9.0;
        statics[1].ctx.stealth_alias_applies_charged = true;
        (st, statics)
    }

    fn run_screened_charge(
        st: &State,
        statics: &[UnitStatic],
        rules_epoch: u32,
    ) -> ShootResult {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics,
            st,
            &vr_charge(),
            &small_board(),
            Seams { movement: true, rules_epoch, ..Seams::default() },
            &mut rng,
            &mut tray,
        )
        .unwrap()
        .1
    }

    /// THE GATE'S OLD SIDE: at `rules_epoch: 19` the charge replays exactly as
    /// every recorded corpus does — the to-hit target stays the bare Quality
    /// 4+, unpenalised. This is the leg a gate nobody tests on the old side
    /// would silently re-date.
    #[test]
    fn at_epoch_19_a_charge_from_over_nine_into_screened_still_rolls_unpenalised() {
        let (st, statics) = screened_charge_line();
        let shot = run_screened_charge(&st, &statics, 19);
        assert_eq!(
            shot.rolls[0].target, 4,
            "epoch 19 corpus leg: the charge from 10.5\" is unpenalised: {:?}",
            shot.rolls
        );
    }

    /// THE DEFECT (RED): the same charge at the new epoch must cost the
    /// attacker 1 — Quality 4+ becomes 5+ — because Screened's printed text
    /// covers the charged-from-over-9" leg and the registry entry carries
    /// `applies_charged: true`. The core folds the alias on the shooting path
    /// only, so today this rolls unpenalised.
    #[test]
    fn at_epoch_22_a_charge_from_over_nine_into_screened_costs_the_hit() {
        let (st, statics) = screened_charge_line();
        let shot = run_screened_charge(&st, &statics, 22);
        assert_eq!(
            shot.rolls[0].target, 5,
            "the book: charged from over 9\" into Screened is -1 to hit: {:?}",
            shot.rolls
        );
    }
