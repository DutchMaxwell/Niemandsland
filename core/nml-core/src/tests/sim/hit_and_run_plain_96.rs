use super::*;

    // ------------------- PENDING_EPOCH_HIT_AND_RUN_PLAIN: the ported step without the movement seam ---

    /// Runs unit 0's shot + Hit & Run on `board` at `epoch` with the shadow's and the door's seams (`movement` OFF).
    fn kite(st: &State, statics: &[UnitStatic], board: &crate::terrain::Terrain, epoch: u32, movement: bool) -> State {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, &buff_action(Some("b")), board,
            Seams { movement, rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
        .0
    }

    /// shootpos (gate 12, game 3, 9 Harassing rows): the shadow and the door run with `movement` OFF, so the core took the rigid
    /// 3" kite (board edge only) where the table walks its `_move_away` fallback through the move executor. From the pending
    /// epoch the step on a real board is the port whatever the seam says: on the kiting forest it lands exactly where the
    /// movement seam's port lands, and away from the rigid answer. One epoch below: the rigid answer to the digit.
    /// RED: the gate ignored (the rigid kite at the pending epoch).
    #[test]
    fn the_hit_and_run_step_takes_the_ported_move_on_a_board_from_the_pending_epoch() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        statics[1].hit_and_run_active = true;   // from 3.6 every model of the formation carries it (its joined hero "ah")
        let t = kiting_forest_board();
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let rigid = kite(&st, &statics, &t, e - 1, false);
        let seam = kite(&st, &statics, &t, e, true);
        let plain = kite(&st, &statics, &t, e, false);
        assert_eq!(plain.positions[0], seam.positions[0], "the pending step is the movement seam's port");
        assert_eq!(plain.hit_and_run_round[0], plain.round);
        let gap_in = plain.positions[0].iter().zip(rigid.positions[0].iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() / IN2M)
            .fold(0.0f64, f64::max);
        assert!(gap_in > 0.5, "the pending step landed on the rigid answer, gap {gap_in}\"");
        // Below the epoch nothing changes: the old seam-off path, the rigid 3" translation.
        for (got, before) in rigid.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M)).abs() < 1e-6 && (got[2] - before[2]).abs() < 1e-9, "rigid {got:?}");
        }
    }

    /// The anchor (shootpos sub-cause A, 2 rows): with an ACTIVATED enemy at 6" and an un-activated one at 12" the table steps
    /// away from the nearest (`_nearest_enemy_of`); from the pending epoch so does the core with `movement` OFF. Below it the
    /// rigid kite keeps its not-activated preference and steps the other way. RED: the gate ignored.
    #[test]
    fn the_pending_step_kites_away_from_the_plain_nearest_enemy_without_the_seam() {
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        statics[1].hit_and_run_active = true;   // from 3.6 every model of the formation carries it (its joined hero "ah")
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.alive[3] = 1;
        st.positions[2] = vec![[6.0 * IN2M, 0.0, 0.0], [6.02 * IN2M, 0.0, 0.0], [6.04 * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[-12.0 * IN2M, 0.0, 0.0]];
        st.activated[2] = true;
        let board = small_board();
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let old = kite(&st, &statics, &board, e - 1, false);
        let new = kite(&st, &statics, &board, e, false);
        assert!((old.positions[0][0][0] - (st.positions[0][0][0] + 3.0 * IN2M)).abs() < 1e-6, "old {:?}", old.positions[0]);
        assert!((new.positions[0][0][0] - (st.positions[0][0][0] - 3.0 * IN2M)).abs() < 1e-6, "new {:?}", new.positions[0]);
    }
