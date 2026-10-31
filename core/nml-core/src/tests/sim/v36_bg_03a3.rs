//! Rules 3.6 row BG-03a3 tests (a ruin is no sight volume, core) for the sim module; owned by lane ux.
use super::*;

    // ---- BG-03a3: the per-model sight stops treating a ruin as a wall from rules 3.6 ----
    //
    // At epoch 73 a moved shooter's target gate asks the per-model 3D sight (`sight::unit_sees` over the board's
    // zones). Until now the zone list held a 6" volume for every ruin, so a ruin across the line of fire refused
    // the shot although the same ruin only gives cover. A forest and a container keep their volumes.

    /// A 6x4 board (30x30 grid of 3" cells, school cell 15 = world cell 0) with `kind` in school column 18
    /// (x 9..12") on the school rows 11..=18 (z -12..12"), wide enough that no model line passes beside it.
    fn bg_03a3_board(kind: i32) -> crate::terrain::Terrain {
        use crate::terrain::{CellParams, PlainTerrain};
        crate::terrain::Terrain::build(&PlainTerrain {
            cells: (11..=18).map(|r| [18.0, r as f64, kind as f64]).collect(),
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// "a" (two models 18" apart across the line of fire) advances 3" east to x = 0 and fires its rifles at "b",
    /// 18" further east, over the terrain column at x 9..12".
    fn bg_03a3_volley(terrain: &crate::terrain::Terrain, epoch: u32) -> ShootResult {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot[0].attacks = 2;
        st.positions[0] = vec![[-3.0 * IN2M, 0.0, 9.0 * IN2M], [-3.0 * IN2M, 0.0, -9.0 * IN2M]];
        st.positions[2] = vec![
            [18.0 * IN2M, 0.0, 9.0 * IN2M], [18.0 * IN2M, 0.0, 0.0], [18.0 * IN2M, 0.0, -9.0 * IN2M],
        ];
        let mut act = advance_shoot("b");
        act.dest = Some([0.0, 0.0, 0.0]);
        let seams = Seams { moved_shoot: true, rules_epoch: epoch, ..Default::default() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(&statics, &st, &act, terrain, seams, &mut rng, &mut tray)
            .expect("the moved volley resolves")
            .1
    }

    fn bg_03a3_attack_dice(shot: &ShootResult) -> i64 {
        shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "a").map(|r| r.count).sum()
    }

    /// The old leg: a ruin across every line blocks the moved shooter at epoch 72.
    #[test]
    fn a_moved_shooter_has_no_shot_through_a_ruin_at_epoch_72() {
        let shot = bg_03a3_volley(&bg_03a3_board(crate::terrain::RUINS), crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(shot.rolls.is_empty(), "epoch 72 keeps the ruin as a sight blocker: no shot");
    }

    /// RED on main: the ruin still stops the moved shooter at epoch 73.
    #[test]
    fn a_moved_shooter_fires_through_a_ruin_at_epoch_73() {
        let shot = bg_03a3_volley(&bg_03a3_board(crate::terrain::RUINS), crate::acts::EPOCH_73_V36);
        assert_eq!(bg_03a3_attack_dice(&shot), 2, "both rifles fire through the ruin (RED on main: 0); log {:?}", shot.log);
    }

    /// Control: a forest across every line still stops the moved shooter at epoch 73.
    #[test]
    fn a_moved_shooter_has_no_shot_through_a_forest_at_epoch_73() {
        let shot = bg_03a3_volley(&bg_03a3_board(crate::terrain::FOREST), crate::acts::EPOCH_73_V36);
        assert!(shot.rolls.is_empty(), "a forest keeps blocking sight at 73");
    }

    /// Control: so does a container.
    #[test]
    fn a_moved_shooter_has_no_shot_through_a_container_at_epoch_73() {
        let shot = bg_03a3_volley(&bg_03a3_board(crate::terrain::CONTAINER), crate::acts::EPOCH_73_V36);
        assert!(shot.rolls.is_empty(), "a container keeps blocking sight at 73");
    }

    /// The sight volumes of the last board are remembered per board; the memo must also know the epoch, or a
    /// board read at 72 serves its ruin to the next read at 73. (The resolve gate only asks from 73 on, so the
    /// memo is exercised directly.)
    #[test]
    fn the_board_zone_memo_is_keyed_on_the_epoch() {
        let board = bg_03a3_board(crate::terrain::RUINS);
        assert_eq!(board_zones(&board, false, crate::acts::EPOCH_72_PLAYTEST_RULES).len(), 1);
        assert!(board_zones(&board, false, crate::acts::EPOCH_73_V36).is_empty(), "the 72 entry is not served at 73");
        assert_eq!(board_zones(&board, false, crate::acts::EPOCH_72_PLAYTEST_RULES).len(), 1, "and back again");
    }

    /// The per-model sight matrix the trainer stamps (`restamp_los`) follows the same rule.
    #[test]
    fn the_sight_matrix_sees_through_a_ruin_at_epoch_73_only() {
        let (mut st, _) = buff_line();
        st.positions[0] = vec![[0.0, 0.0, 9.0 * IN2M], [0.0, 0.0, -9.0 * IN2M]];
        st.positions[2] = vec![
            [18.0 * IN2M, 0.0, 9.0 * IN2M], [18.0 * IN2M, 0.0, 0.0], [18.0 * IN2M, 0.0, -9.0 * IN2M],
        ];
        let board = bg_03a3_board(crate::terrain::RUINS);
        // m[0 * n + 2]: unit "a" looking at unit "b".
        assert!(!crate::sight::sight_matrix_at(&st, &board, crate::acts::EPOCH_72_PLAYTEST_RULES)[2]);
        assert!(crate::sight::sight_matrix_at(&st, &board, crate::acts::EPOCH_73_V36)[2], "RED on main: blocked");
    }
