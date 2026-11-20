use super::*;

    /// `EPOCH_94_PARITY_BATCH` (soak game 23): a placement in which no model left its place (a joined-hero chain the planner clamped to zero) must not
    /// stamp the unit, the table stamps an EXECUTED move only. RED before the fix: the first assert. Controls: the pending epoch minus one replays the stamp, a
    /// model that really walked stamps at every epoch.
    #[test]
    fn an_advance_that_moved_nobody_does_not_stamp_the_unit_moved_from_the_pending_epoch() {
        use crate::acts::EPOCH_94_PARITY_BATCH as ZERO;
        let stamped = |epoch: u32, shift_in: f64| -> bool {
            let (st, statics) = buff_line();
            let mut at = st.positions[0].clone();
            at[0][0] += shift_in * IN2M;
            let mut tray = Tray::supplied(vec![]);
            tray.place(at, vec![vec![]; st.positions[0].len()]);
            let act = Action { kind: ADVANCE, ..buff_action(None) };
            let seams = Seams { rules_epoch: epoch, movement: true, moved_shoot: true, ..Default::default() };
            let (next, _) = resolve_stochastic_tray_on_board(&statics, &st, &act, &crate::terrain::Terrain::default(), seams,
                &mut crate::rng::GodotRng::new(0), &mut tray).expect("the activation resolves");
            next.moved_round[0] == next.round
        };
        assert!(!stamped(ZERO, 0.0), "nobody left their place: the unit stays not moved (RED before the fix)");
        assert!(stamped(ZERO - 1, 0.0), "below the pending epoch the placement stamps, the old reading");
        assert!(stamped(ZERO, 1.0), "a model that walked an inch stamps");
        assert!(stamped(ZERO - 1, 1.0), "and always did");
    }
