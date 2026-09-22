use super::*;

    // ---- The objective token's reach columns t[10]/t[11] (token vocab 3).
    // RESIDUALS_ERLKOENIG_2026-09-19: 58.6 % of the reference net's losses to
    // the hand planner are LATE FLIPS — ahead on objectives after round 2,
    // behind at the end; the late surprises flipped an objective owner in
    // round 4. The token carried who is INSIDE the 3" contest range
    // (t[8]/t[9]) but not who could ENTER it this round with a rush. A unit
    // REACHES a marker when its base-edge gap is within
    // `OBJECTIVE_CONTROL_IN + live rush` (`sim::live_bands_of` — the same
    // seam the unit token's band columns ride); reach INCLUDES the units
    // already in contest range (reach ⊇ contest), so t[10] >= t[8] and
    // t[11] >= t[9] always. ----

    /// A neutral marker at the origin and up to four units at chosen
    /// base-edge gaps, `(player, gap_in)` per slot in roster order — a 1"
    /// radius base centred `gap_in + 1"` out leaves exactly `gap_in` of edge
    /// gap (`control_gap_in`'s own measure). Unused slots stay dead (the
    /// `storm_line` shape): empty positions, wounds and radii. Bands stay the
    /// line fixture's defaults, advance 6" / rush 12" — the live bands of a
    /// grant-less profile.
    fn reach_line(units: &[(i64, f64)]) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.objectives = vec![crate::state::Objective { pos: [0.0, 0.0, 0.0], owner: 0 }];
        let mut player = vec![0; 4];
        let mut alive = vec![0; 4];
        let mut positions: Vec<Vec<[f64; 3]>> = vec![vec![]; 4];
        let mut radii: Vec<Vec<f64>> = vec![vec![]; 4];
        let mut wounds: Vec<Vec<i64>> = vec![vec![]; 4];
        for (slot, &(pl, gap)) in units.iter().enumerate() {
            player[slot] = pl;
            alive[slot] = 1;
            positions[slot] = vec![[(gap + 1.0) * IN2M, 0.0, 0.0]];
            radii[slot] = vec![IN2M];
            wounds[slot] = vec![1];
        }
        st.player = player;
        st.alive = alive;
        st.positions = positions;
        st.radii = radii;
        st.wounds = wounds;
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None; 4]);
        (st, vec![UnitStatic::default(); 4])
    }

    /// The viewer-side row of marker 0 through the full `tokens::build` export
    /// (the `ev_move_grants.rs` call shape: empty candidate menu, seam off).
    fn objective_row(st: &State, statics: &[UnitStatic]) -> [f32; crate::tokens::F_O] {
        let terrain = crate::terrain::Terrain::default();
        let mut enc = crate::rows::RowEncoder::new(&repo_root());
        crate::tokens::build(st, 0, statics, &terrain, &mut enc, &[], -1, false, false,
            crate::acts::CURRENT_RULES_EPOCH)
            .unwrap()
            .objs[0]
    }

    /// (d) The pin: the reach PR touches only t[10]/t[11] — columns t[0..10]
    /// of the (a) fixture are bit-identical to main (pinned 2026-09-19 on
    /// main 4629574e with the pre-PR pin dump; t[6] 33.3 = the no-own-units
    /// INFINITY clamped to 999, /30; t[7] 0.3 = the 9" centre distance /30).
    #[test]
    fn the_first_ten_objective_columns_are_bit_identical_to_main() {
        let (st, statics) = reach_line(&[(1, 8.0)]);
        let t = objective_row(&st, &statics);
        let pinned: [f32; 10] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 33.3, 0.3, 0.0, 0.0];
        assert_eq!(&t[0..10], &pinned[..], "t[0..10] must not move with the reach splice");
    }

    /// (a) The flip the old token could not see: one enemy unit with an 8"
    /// edge gap — outside the 3" contest range (t[9] stays 0.0) but inside the
    /// 3" + 12" live rush band, so the enemy reach column fires.
    #[test]
    fn an_enemy_in_rush_band_but_out_of_contest_fires_the_reach_column() {
        let (st, statics) = reach_line(&[(1, 8.0)]);
        let t = objective_row(&st, &statics);
        assert_eq!(t[9], 0.0, "8\" edge gap is outside the 3\" contest range");
        assert_eq!(t[11], 0.1, "3\" contest + 12\" live rush covers the 8\" gap");
    }

    /// (b) The same unit 20" out — past contest AND rush band: both enemy
    /// columns stay 0.0.
    #[test]
    fn an_enemy_past_the_rush_band_reaches_nothing() {
        let (st, statics) = reach_line(&[(1, 20.0)]);
        let t = objective_row(&st, &statics);
        assert_eq!(t[9], 0.0);
        assert_eq!(t[11], 0.0, "20\" is past the 15\" reach band");
    }

    /// (c) Contest implies reach: an own unit 2" out sits inside the 3"
    /// contest range AND inside its own reach band — both own columns fire.
    #[test]
    fn contest_also_counts_as_reach() {
        let (st, statics) = reach_line(&[(0, 2.0)]);
        let t = objective_row(&st, &statics);
        assert_eq!(t[8], 0.1, "2\" edge gap is inside the 3\" contest range");
        assert_eq!(t[10], 0.1, "reach includes the units already in contest");
    }

    /// (e) The stamp: the reach columns are a vocabulary change — every
    /// exporter (and the trainer's stamp check on `build_info`) reads 3.
    #[test]
    fn the_token_vocab_stamp_is_3() {
        assert_eq!(crate::tokens::TOKEN_VOCAB_VERSION, 3);
    }
