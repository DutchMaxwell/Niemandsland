//! Rules 3.6 row W1.5b tests (AI charge estimate reads the edge-gap gate); owned by row W1.5b.
use super::*;

    // ---- W1.5b-rs (D-GATE6): the core's melee EV is handed the pre-charge edge gap from epoch 73 ----
    //
    // The EV only READS the distance through Versatile Attack's over-9" charge leg, so the observable
    // geometry is a charge from an edge gap of 10" (above the gate) next to the W1.5a geometry
    // (centres 7", edges 5": below every gate, nothing to read).

    const E72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;
    const E73: u32 = crate::acts::EPOCH_73_V36;

    /// The `vr_charge_line` duel (edge gap `edge_gap_in`, Quality 4 charger, one 8-attack Blade) with
    /// the charger's Blade carrying Versatile Attack.
    fn versatile_duel(edge_gap_in: f64) -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = vr_charge_line(edge_gap_in);
        statics[0].melee[0].versatile_attack = true;
        (st, statics)
    }

    /// Same duel, but the charger is weak enough (one Quality 5 attack, EV 1/6 against a 4+ Defense)
    /// to sit under the futile-charge bar until Versatile Attack's bonus is priced.
    fn weak_versatile_duel(edge_gap_in: f64) -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = versatile_duel(edge_gap_in);
        statics[0].melee[0].attacks = 1;
        statics[0].ctx.quality = 5;
        (st, statics)
    }

    /// The gate itself, both legs: the edge gap passes through from the wave, the record leg stays blind.
    #[test]
    fn the_charge_estimate_gap_is_the_edge_gap_at_epoch_73_and_zero_at_epoch_72() {
        assert_eq!(crate::combat::charge_estimate_gap_in(E72, 5.0), 0.0);
        assert_eq!(crate::combat::charge_estimate_gap_in(E73, 5.0), 5.0);
    }

    /// `melee_ev` hands its charge distance on to the profile EV: a charge from 10" prices Versatile
    /// Attack's bonus, a charge from 5" (the W1.5a geometry) and a blind 0.0 do not.
    #[test]
    fn melee_ev_reads_the_charge_distance_it_is_handed() {
        let (st, statics) = versatile_duel(10.0);
        let (att, def) = (statics[0].ctx, statics[1].ctx);
        let mut sc = Scratch::default();
        melee_profiles_of(&statics[0], st.alive[0], &mut sc);
        let ev = |gap: f64| crate::combat::melee_ev(&statics[0].melee, &sc.attacks, &att, &def, true, gap);
        assert!(ev(10.0) > ev(0.0), "10\" is over the gate: {} vs {}", ev(10.0), ev(0.0));
        assert_eq!(ev(5.0), ev(0.0), "5\" is under every gate");
    }

    /// `melee_threat_at_epoch`: below the wave the estimate stays blind to the gap, from the wave a
    /// 10" charge prices the bonus and the 5" W1.5a geometry still does not.
    #[test]
    fn melee_threat_reads_the_edge_gap_at_epoch_73_only() {
        let (far, statics) = versatile_duel(10.0);
        let (near, _) = versatile_duel(5.0);
        let threat = |st: &State, epoch: u32| melee_threat_at_epoch(&statics, st, 0, 1, epoch);
        assert_eq!(threat(&far, E72), threat(&near, E72), "epoch 72 reads no gap");
        assert!(threat(&far, E73) > threat(&far, E72), "epoch 73 reads the 10\" edge gap");
        assert_eq!(threat(&near, E73), threat(&near, E72), "5\" reads no gate at 73");
    }

    /// The charge menu's futile bar (`nearest_chargeable` and `best_charge`): the weak charger clears
    /// it from 10" only when the estimate reads the gap, i.e. at epoch 73.
    #[test]
    fn the_charge_menu_prices_the_edge_gap_at_epoch_73_only() {
        let board = small_board();
        let tuning = crate::menu::Tuning::default();
        let (far, statics) = weak_versatile_duel(10.0);
        let (near, near_statics) = weak_versatile_duel(5.0);
        let nearest = |st: &State, s: &[UnitStatic], epoch: u32| {
            crate::menu::nearest_chargeable(st, &board, s, 0, &mut Scratch::default(), tuning, epoch)
        };
        let best = |st: &State, s: &[UnitStatic], epoch: u32| {
            crate::menu::best_charge(st, &board, s, 0, &mut Scratch::default(), tuning, epoch, None)
        };
        assert_eq!((nearest(&far, &statics, E72), best(&far, &statics, E72)), (None, None));
        assert_eq!((nearest(&far, &statics, E73), best(&far, &statics, E73)), (Some(1), Some(1)));
        assert_eq!((nearest(&near, &near_statics, E73), best(&near, &near_statics, E73)), (None, None));
    }

    /// The EV-path resolver (`resolve_with`'s charge strike): the wound fraction the charge lands on the
    /// target is the estimate's EV, so it only grows from the wave.
    #[test]
    fn the_ev_charge_strike_reads_the_edge_gap_at_epoch_73_only() {
        let (st, statics) = weak_versatile_duel(10.0);
        let wounds = |epoch: u32| {
            let seams = Seams { movement: true, rules_epoch: epoch, ..Seams::default() };
            resolve_on_board(&statics, &st, &vr_charge(), &small_board(), seams).unwrap().wound_frac[1]
        };
        assert!(wounds(E72) > 0.0, "the charge must connect at 72");
        assert!(wounds(E73) > wounds(E72), "{} vs {}", wounds(E73), wounds(E72));
    }

    /// The spell menu's charge usage reads the live (current) epoch: a rush spell that brings a 13"
    /// target into reach is worth the charge's EV, and the weak charger's EV clears the futile bar only
    /// once the gap is priced.
    #[test]
    fn the_cast_movement_gain_prices_the_edge_gap_at_the_current_epoch() {
        let (st, statics) = weak_versatile_duel(13.0);
        let rush = crate::rules::SpellModifier { present: true, rush_in: 2.0, ..Default::default() };
        let gain = crate::cast_move_ev::movement_cast_gain(&statics, &st, 0, &rush);
        assert!(gain > 0.0, "a 13\" charge priced at the current epoch is worth something: {gain}");
    }
