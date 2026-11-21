use super::*;
use crate::acts::EPOCH_94_PARITY_BATCH;
use crate::mv::reach::ReachQuery;

    // Heightfield plan step 11b: the walled reach index (the charge menu's path check) sees the cliffs of a tier board.

    /// A 4 x 4 board of 3 in cells, the columns at x >= 0 a 3 in tier, one ladder in the row z -3..0, the rest of the border
    /// a cliff. A model 2 in west of the cliff, in the row z 0..3 (no ladder), wants to be 2 in east of it with 6 in of
    /// arc: the straight 4 in is cut by the cliff, the way round through the ladder is longer than 6 in.
    #[test]
    fn the_walled_reach_index_stops_at_a_cliff_from_the_height_gate() {
        let t = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { 3.0 } else { 0.0 }).collect(), vec![[5, 6]]);
        let mut st = four_unit_line();
        for u in 0..st.units() {
            st.positions[u].clear();
            st.alive[u] = 0;
        }
        let q = ReachQuery { start: [4.0, 9.0], target: [8.0, 9.0], radius: 0.5, band: 6.0, cap_in: 0.0, mover: 1, foe: 0 };
        let reach = |epoch: u32| walled_reach_index_for_state(&st, &t, epoch).expect("a board").query(&q);
        assert!(reach(EPOCH_94_PARITY_BATCH - 1).reachable, "below the gate the board is flat: 4 in straight");
        let at_gate = reach(EPOCH_94_PARITY_BATCH);
        assert!(!at_gate.reachable && at_gate.end_centre[0] < 6.0, "the cliff stops it: {at_gate:?}");
    }
