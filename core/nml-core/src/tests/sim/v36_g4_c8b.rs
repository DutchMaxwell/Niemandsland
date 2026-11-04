//! Rules 3.6 row G4-C8b: the defender's PILE-IN. Once the charger has stood (charge move and snap), every
//! defender model without base contact moves up to 3" toward contact before any die is rolled — the table's
//! `SoloController.pile_in` (main.gd `_solo_resolve_ai_charge`, ahead of Counter, Impact and the strikes).
//! From `EPOCH_73_V36`; below it the defender stays where the charge left it. The fixtures run the real
//! charge on a board (`resolve_stochastic_tray_on_board` with the movement seam), never a hand-set flag.

mod g4_c8b {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    /// A 1-model charger "a" against a 3-model defender "b" in a line along x: the nearest model is
    /// 4" from the charger's edge, the other two stand behind it 0.5" apart (edge to edge), so once the
    /// charger has snapped onto the first, two defender models are out of contact.
    fn line_of_three() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = vr_charge_line(4.0);
        st.alive[1] = 3;
        st.positions[1] = [6.0, 8.5, 11.0].iter().map(|x| [x * IN2M, 0.0, 0.0]).collect();
        st.wounds[1] = vec![5, 5, 5];
        Rc::make_mut(&mut st.radii)[1] = vec![IN2M; 3];
        statics[1].ctx.models = 3;
        statics[1].ctx.tough = 5;
        statics[1].model_count = 3;
        statics[1].wounds_max = vec![5, 5, 5];
        (st, statics)
    }

    fn charge(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, Vec<String>) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { movement: true, rules_epoch: epoch, ..Seams::default() };
        let (next, shot) =
            resolve_stochastic_tray_on_board(statics, st, &vr_charge(), &small_board(), seams, &mut rng, &mut tray).unwrap();
        (next, shot.log)
    }

    /// The defender's models' summed centre distance to the point `to` - the charger's contact spot. From
    /// 73 the charger backs off 1" after the fight (G4R4-CONS), so its final spot is no longer the reference.
    fn spread(st: &State, to: [f64; 3]) -> f64 {
        st.positions[1].iter().map(|p| (p[0] - to[0]).hypot(p[2] - to[2])).sum()
    }

    #[test]
    fn the_two_models_out_of_contact_pile_in_and_the_line_names_the_rule_at_73() {
        let (st, statics) = line_of_three();
        let (_, log) = charge(&st, &statics, EPOCH_73_V36);
        assert!(log.iter().any(|l| l == "Pile In: Target: 2 models pile in up to 3\""), "{log:?}");
    }

    #[test]
    fn a_piled_in_model_ends_closer_to_the_charger_than_the_charge_left_it_at_73() {
        let (st, statics) = line_of_three();
        let (at72, _) = charge(&st, &statics, EPOCH_72_PLAYTEST_RULES);
        let (at73, _) = charge(&st, &statics, EPOCH_73_V36);
        let contact = at72.positions[0][0];
        assert!(spread(&at73, contact) < spread(&at72, contact) - 0.5 * IN2M, "{} vs {}", spread(&at73, contact) / IN2M, spread(&at72, contact) / IN2M);
    }

    #[test]
    fn below_73_the_defender_stays_and_nothing_is_logged() {
        let (st, statics) = line_of_three();
        let (_, log) = charge(&st, &statics, EPOCH_72_PLAYTEST_RULES);
        assert!(!log.iter().any(|l| l.starts_with("Pile In")), "{log:?}");
    }

    #[test]
    fn a_defender_already_in_base_contact_does_not_move_and_logs_nothing() {
        let (st, statics) = vr_charge_line(4.0);
        let (_, log) = charge(&st, &statics, EPOCH_73_V36);
        assert!(!log.iter().any(|l| l.starts_with("Pile In")), "{log:?}");
    }
}
