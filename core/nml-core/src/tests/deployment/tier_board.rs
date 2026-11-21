use super::*;

    // Heightfield plan step 14: deployment on a generated tier board. A spot keeps off the cliffs and a base never stands
    // partly over a tier edge (R10); a unit that arrives (Reinforcement, Spawn) stands on the surface (the arrival tests
    // in reinforcement.rs / below). `p` are board-centred inches turned into world metres.

    /// A 4 x 4 board of 3 in cells (x, z from -6 to 6 in): the columns at x >= 0 are a 3 in tier, one ladder in the row
    /// z -3..0, the rest of the border at x = 0 is a cliff.
    fn laddered() -> Terrain {
        crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { 3.0 } else { 0.0 }).collect(), vec![[5, 6]])
    }

    fn at(x_in: f64, z_in: f64) -> (f64, f64) {
        (x_in * crate::IN2M, z_in * crate::IN2M)
    }

    #[test]
    fn a_deployment_spot_keeps_off_the_cliffs_and_a_base_stays_inside_one_tier() {
        let (t, flat) = (laddered(), crate::terrain::tier_board_for_test(4, 4, vec![0.0; 16], Vec::new()));
        // the wall veto: 0.4 in from the cliff is inside the 2 cm clearance, 2 in away is not, the ladder is no wall
        assert!(wall_blocked(&t, at(-0.4, 3.0)));
        assert!(!wall_blocked(&t, at(-2.0, 3.0)));
        assert!(!wall_blocked(&t, at(-0.4, -1.5)));
        assert!(!wall_blocked(&flat, at(-0.4, 3.0)), "a flat board has no such wall");
        // the straddle: a 0.5 in base beside the ladder but across the tier line stands on two levels
        let r = 0.5 * crate::IN2M;
        assert!(spot_blocked(&t, at(-0.2, -1.5), false, r, &[], r), "the base spans the ground and the tier");
        assert!(!spot_blocked(&t, at(-2.0, -1.5), false, r, &[], r), "wholly on the ground");
        assert!(!spot_blocked(&t, at(2.0, -1.5), false, r, &[], r), "wholly on the tier");
        assert!(!spot_blocked(&flat, at(-0.2, -1.5), false, r, &[], r), "a flat board has no tier line");
        // a model grid is tested per model
        assert!(spot_blocked(&t, at(-2.0, -1.5), false, r, &[(1.9 * crate::IN2M, 0.0)], r), "the second model straddles");
    }
