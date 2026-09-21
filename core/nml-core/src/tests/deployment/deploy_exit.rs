use super::*;

    // ---- PR #1032 (`fix/deploy-exit-veto`): the table's deploy exit veto.
    // A spot whose walls box the unit's base in — no straight 12" exit
    // (`DEPLOY_EXIT_REACH_M` 0.3048 m) at the base's clearance
    // (base_r + 0.005 m pad) — is marked occupied and re-searched. The core
    // mirrors the table spot-for-spot, so `footprint_boxed` must answer the
    // table's own fixture exactly: a 20 cm wall box with a doorway in the
    // front wall.

    /// The table's fixture: walls at x=±0.10 for y∈[-0.10, 0.10], back wall
    /// y=0.10, front wall y=-0.10 with a `2*door_half` doorway (stubs from
    /// x=-0.10 to -door_half and door_half to 0.10).
    fn box_walls(door_half: f64) -> Vec<crate::deployment::WallSeg> {
        let (d, s) = (door_half as f32, 0.10_f32);
        vec![
            [[-s, -s], [-s, s]],  // left
            [[s, -s], [s, s]],    // right
            [[-s, s], [s, s]],    // back
            [[-s, -s], [-d, -s]], // front left stub
            [[d, -s], [s, -s]],   // front right stub
        ]
    }

    /// The four fixture verdicts: the 8 cm base (clearance 4.5 cm > the 3 cm
    /// half-doorway) cannot leave — boxed; the 32 mm base walks straight out;
    /// a 12 cm doorway lets the 8 cm base out; empty walls never box.
    #[test]
    fn deploy_exit_veto_mirrors_the_table_fixture() {
        let boxed = crate::deployment::footprint_boxed;
        assert!(boxed((0.0, 0.0), &[], 0.04, &box_walls(0.03)), "8 cm base boxed in");
        assert!(!boxed((0.0, 0.0), &[], 0.016, &box_walls(0.03)), "32 mm base walks out");
        assert!(!boxed((0.0, 0.0), &[], 0.04, &box_walls(0.06)), "12 cm doorway: 8 cm base out");
        assert!(!boxed((0.0, 0.0), &[], 0.04, &[]), "no walls, never boxed");
    }
