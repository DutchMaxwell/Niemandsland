//! Rules 3.6 row BG-03a2 tests (the core centre-line probe stops treating a ruin as a wall); owned by lane core.
use super::*;

    // ---- BG-03a2: the core centre-line LINE-OF-SIGHT probe reads the rules epoch ----
    //
    // `terrain::Terrain::los_blocked` is the centre-to-centre probe `los_pairs` and the moved-shooter gate ask.
    // BG-03a3 made the per-model sight stop treating a ruin as a sight volume at epoch 73; this row gives the
    // probe the same reading: the ruin cell still gives cover but no longer BLOCKS the line. A container and a
    // forest keep blocking, and at 72 and below the probe answers exactly as before.

    /// A 6x4 board (30x30 grid of 3" cells, school cell 15 = world cell 0) with ONE `kind` cell in school column
    /// 14 (x -3..0") on school row 15 (z 0..3") — strictly between the two centres below.
    fn bg_03a2_board(kind: i32) -> crate::terrain::Terrain {
        use crate::terrain::{CellParams, PlainTerrain};
        crate::terrain::Terrain::build(&PlainTerrain {
            cells: vec![[14.0, 15.0, kind as f64]],
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

    /// Two unit centres 18" apart on the z = 0 line (x = -6" and x = 12").
    fn bg_03a2_endpoints() -> ([f32; 3], [f32; 3]) {
        ([(-6.0 * IN2M) as f32, 0.0, 0.0], [(12.0 * IN2M) as f32, 0.0, 0.0])
    }

    /// The old leg: a ruin between the centres still blocks the probe at epoch 72.
    #[test]
    fn the_core_los_probe_treats_a_ruin_as_a_wall_at_epoch_72() {
        let (a, b) = bg_03a2_endpoints();
        assert!(
            bg_03a2_board(crate::terrain::RUINS).los_blocked_at(a, b, crate::acts::EPOCH_72_PLAYTEST_RULES),
            "epoch 72 keeps the ruin as a wall"
        );
    }

    /// RED on main: the ruin still blocks the centre line at epoch 73.
    #[test]
    fn the_core_los_probe_sees_through_a_ruin_at_epoch_73() {
        let (a, b) = bg_03a2_endpoints();
        assert!(
            !bg_03a2_board(crate::terrain::RUINS).los_blocked_at(a, b, crate::acts::EPOCH_73_V36),
            "the ruin is no wall for the centre line at 73 (RED on main: true)"
        );
    }

    /// Control: a container and a forest still block the centre line at epoch 73.
    #[test]
    fn a_container_and_a_forest_still_block_the_core_los_probe_at_epoch_73() {
        let (a, b) = bg_03a2_endpoints();
        assert!(
            bg_03a2_board(crate::terrain::CONTAINER).los_blocked_at(a, b, crate::acts::EPOCH_73_V36),
            "a container stays a wall at 73"
        );
        assert!(
            bg_03a2_board(crate::terrain::FOREST).los_blocked_at(a, b, crate::acts::EPOCH_73_V36),
            "a forest stays a wall at 73"
        );
    }
