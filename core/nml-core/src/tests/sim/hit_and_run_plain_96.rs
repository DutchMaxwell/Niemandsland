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

    // ------------------- review follow-ups (#3396): legality, the board-less split, the after-melee leg, the anchor ---

    /// `buff_line` with the joined hero detached (unit 1 "ah" a lone friendly), the host's two models side by side on z, the enemy
    /// "b" 6" off on +x, so the kite runs toward -x.
    fn lone_kiter(fighter: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        if fighter { statics[0].hit_and_run_fighter_active = true; } else { statics[0].hit_and_run_active = true; }
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.0, 0.0, 2.2 * IN2M]];
        st.positions[1] = vec![[30.0 * IN2M, 0.0, 20.0 * IN2M]];
        st.positions[2] = vec![[6.0 * IN2M, 0.0, -1.1 * IN2M], [6.0 * IN2M, 0.0, 1.1 * IN2M], [6.0 * IN2M, 0.0, 3.3 * IN2M]];   // centred on the host's z
        (st, statics)
    }

    fn step(st: &State, statics: &[UnitStatic], board: &crate::terrain::Terrain, epoch: u32, movement: bool, after_shoot: bool) -> State {
        let mut next = st.clone();
        tray_hit_and_run(statics, &mut next, 0, Seams { movement, rules_epoch: epoch, ..Seams::default() }, Cover::Board(board), after_shoot);
        next
    }

    /// Why unit 0's end spots are illegal ("" = legal): a base inside another unit's base, or a base resting where none may rest
    /// (`mv::gate::rest_forbidden`: a container cell, a wall band) or on a solid cell.
    fn illegal(st: &State, t: &crate::terrain::Terrain) -> String {
        let mut why = Vec::new();
        for (k, p) in st.positions[0].iter().enumerate() {
            let r = st.radii[0][k];
            for u in 1..st.units() {
                if st.alive[u] <= 0 { continue; }
                for (j, q) in st.positions[u].iter().enumerate() {
                    if (p[0] - q[0]).hypot(p[2] - q[2]) < r + st.radii[u][j] - 0.0005 { why.push(format!("m{k} inside u{u}.{j}")); }
                }
            }
            let c = t.to_inch([p[0] as f32, 0.0, p[2] as f32]);
            if crate::mv::gate::rest_forbidden([f64::from(c[0]), f64::from(c[1])], r / IN2M, t) { why.push(format!("m{k} rests on forbidden ground")); }
            if t.solid_at(p[0] / t.in2m(), p[2] / t.in2m()) { why.push(format!("m{k} on a solid cell")); }
        }
        why.join(", ")
    }

    /// The fix's own point (shootpos: Dark Shooters r4 ended 0.75" inside another unit): a lone friendly stands exactly where the rigid
    /// kite lands. At 95 the rigid step ends inside it; at the pending epoch the ported step ends clear and legal. RED: the gate ignored.
    #[test]
    fn the_rigid_kite_ends_inside_a_friendly_at_95_and_the_ported_step_ends_clear() {
        let (mut st, statics) = lone_kiter(false);
        st.positions[1] = vec![[-3.0 * IN2M, 0.0, 0.0]];   // the rigid landing of model 0
        let board = small_board();
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let old = step(&st, &statics, &board, e - 1, false, true);
        assert!(illegal(&old, &board).contains("inside u1"), "the fixture: the rigid kite lands on the friendly: {:?}", old.positions[0]);
        let new = step(&st, &statics, &board, e, false, true);
        assert_eq!(new.hit_and_run_round[0], new.round);
        assert_ne!(new.positions[0], st.positions[0], "the ported step moved");
        assert_eq!(illegal(&new, &board), "", "end spots {:?}", new.positions[0]);
    }

    /// The same with forbidden ground: a container block covers the rigid kite's landing. At 95 a base rests on it; at the pending epoch
    /// the ported step ends legal. RED: the gate ignored.
    #[test]
    fn the_rigid_kite_rests_on_a_container_at_95_and_the_ported_step_does_not() {
        let (st, statics) = lone_kiter(false);
        let t = crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![[13.0, 14.0, crate::terrain::CONTAINER as f64], [13.0, 15.0, crate::terrain::CONTAINER as f64]],   // x in [-6", -3"), z in [-3", 3")
            sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![],
            cell_params: crate::terrain::CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M },
            ..Default::default()
        });
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let old = step(&st, &statics, &t, e - 1, false, true);
        assert!(illegal(&old, &t).contains("forbidden"), "the fixture: the rigid kite rests on the block: {:?} -> {}", old.positions[0], illegal(&old, &t));
        let new = step(&st, &statics, &t, e, false, true);
        assert_eq!(new.hit_and_run_round[0], new.round);
        assert_ne!(new.positions[0], st.positions[0], "the ported step moved (a step that stays put is no legal kite)");
        assert_eq!(illegal(&new, &t), "", "end spots {:?}", new.positions[0]);
    }

    /// No real board (`Terrain::default()`, the benches' and the python calls' case): at the pending epoch the step stays the rigid 3"
    /// translation, now away from the plain nearest enemy (the table's anchor). The split is pinned so a change shows.
    #[test]
    fn without_a_board_the_pending_step_stays_rigid() {
        let (st, statics) = lone_kiter(false);
        let none = crate::terrain::Terrain::default();
        let new = step(&st, &statics, &none, crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN, false, true);
        for (got, before) in new.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M)).abs() < 1e-6 && (got[2] - before[2]).abs() < 1e-9, "rigid {got:?}");
        }
        assert_eq!(new.hit_and_run_round[0], new.round);
    }

    /// The after-melee leg (Hit & Run Fighter, `after_shoot = false`) passes the same gate: at the pending epoch it is the movement seam's
    /// port, one epoch below the rigid kite. RED: the gate ignored.
    #[test]
    fn the_after_melee_step_takes_the_ported_move_from_the_pending_epoch() {
        let (st, statics) = lone_kiter(true);
        let t = kiting_forest_board();
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let seam = step(&st, &statics, &t, e, true, false);
        let plain = step(&st, &statics, &t, e, false, false);
        let rigid = step(&st, &statics, &t, e - 1, false, false);
        assert_eq!(plain.positions[0], seam.positions[0], "the after-melee step is the port");
        assert_ne!(plain.positions[0], rigid.positions[0], "and not the rigid kite");
        assert_eq!(plain.hit_and_run_round[0], plain.round);
    }

    /// The early outs read the table's anchor too: with only an ACTIVATED enemy near and an un-activated one far, the board-less rigid
    /// step at the pending epoch kites away from the near one (the plain nearest); at 95 it keeps the not-activated pick. RED: the
    /// anchor switch ignored.
    #[test]
    fn the_board_less_kite_reads_the_plain_nearest_enemy_from_the_pending_epoch() {
        let (mut st, statics) = lone_kiter(false);
        st.alive[3] = 1;
        st.positions[3] = vec![[-12.0 * IN2M, 0.0, 1.1 * IN2M]];
        st.radii = Rc::new(vec![vec![IN2M; 2], vec![IN2M], vec![IN2M; 3], vec![IN2M]]);
        st.activated[2] = true;
        let none = crate::terrain::Terrain::default();
        let e = crate::acts::PENDING_EPOCH_HIT_AND_RUN_PLAIN;
        let old = step(&st, &statics, &none, e - 1, false, true);
        let new = step(&st, &statics, &none, e, false, true);
        assert!((old.positions[0][0][0] - 3.0 * IN2M).abs() < 1e-6, "old {:?}", old.positions[0]);
        assert!((new.positions[0][0][0] + 3.0 * IN2M).abs() < 1e-6, "new {:?}", new.positions[0]);
    }
