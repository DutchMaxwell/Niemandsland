    // ---- PR #1038 (`large base may take a forward spot from the whole zone`),
    // mirrored UNGATED from the table (the core has no static switches): the
    // whole-zone respot fires only when the section scan had to land far behind
    // the forward edge. Fixtures reuse the table's geometry spot-for-spot.

    use super::empty_board;

    // ---- DEPLOYLARGE: the whole-zone forward respot in `deploy_place_id`.

    /// The respot fixture's zone: a 1.1 x 1 ft band at the table's forward
    /// edge, forward y = end().1 = -0.2952.
    fn respot_zone() -> (crate::deployment::Rect, f64) {
        let zone = crate::deployment::Rect::new(-0.55, -0.6, 1.1, 0.3048);
        (zone, zone.end().1)
    }

    /// The three occupied discs straddle the middle section's forward rows, so
    /// the SECTION scan must land on its rearmost row (0.2188 m behind the
    /// forward edge) while the WHOLE-zone scan still finds a legal spot 0.0938
    /// m behind it — inside the table's `LARGE_ZONE_SPOT_BEHIND_M` (6").
    fn respot_blockers() -> Vec<crate::deployment::Occupied> {
        vec![
            crate::deployment::Occupied { pos: (-0.1833, -0.3524), radius: 0.08 },
            crate::deployment::Occupied { pos: (-0.0333, -0.3524), radius: 0.08 },
            crate::deployment::Occupied { pos: (0.1167, -0.3524), radius: 0.08 },
        ]
    }

    #[test]
    fn large_base_respotted_forward_when_the_section_spot_lags() {
        let board = empty_board();
        let (zone, forward_y) = respot_zone();
        let sec = crate::deployment::section_rect(&zone, 2);
        let base_r = 0.076; // 6" base — past the 1.5" trigger radius
        let radius = crate::deployment::deploy_footprint_radius(1, base_r);
        let objectives = vec![(-0.3667, -0.2952), (0.3667, -0.2952)];
        let mut occupied = respot_blockers();
        let out = crate::deployment::deploy_place_id(
            &zone, &sec, forward_y, &objectives, &mut occupied, &board, &[], radius, &[],
            base_r, false, false, 0.0, 15,
        );
        assert!(out.zone_forward_respotted, "the whole-zone respot must fire");
        assert!(
            (out.spot.1 - forward_y).abs() < 0.1524,
            "the respot must land within 6\" of the forward edge, got {:?}",
            out.spot
        );
        let end = zone.end();
        assert!(
            out.spot.0 >= zone.pos.0 && out.spot.0 <= end.0 && out.spot.1 >= zone.pos.1 && out.spot.1 <= end.1,
            "the respot stays inside the zone, got {:?}",
            out.spot
        );
        assert_eq!(out.rung, 0, "the respot rides the section scan's rung");
   }

    /// Negative: a 32 mm base is under the 1.5" trigger radius — same blocked
    /// section, no respot (the section spot is its answer even at 0.1638 m
    /// behind the edge).
    #[test]
    fn small_base_keeps_its_section_spot() {
        let board = empty_board();
        let (zone, forward_y) = respot_zone();
        let sec = crate::deployment::section_rect(&zone, 2);
        let base_r = 0.016;
        let radius = crate::deployment::deploy_footprint_radius(1, base_r);
        let objectives = vec![(-0.3667, -0.2952), (0.3667, -0.2952)];
        let mut occupied = respot_blockers();
        let out = crate::deployment::deploy_place_id(
            &zone, &sec, forward_y, &objectives, &mut occupied, &board, &[], radius, &[],
            base_r, false, false, 0.0, 15,
        );
        assert!(!out.zone_forward_respotted, "a small base never respots");
    }

    /// Negative: a large base whose SECTION spot is already forward (no
    /// blockers) never respots — the strict behind-margin gate.
    #[test]
    fn forward_section_spot_needs_no_respot() {
        let board = empty_board();
        let (zone, forward_y) = respot_zone();
        let sec = crate::deployment::section_rect(&zone, 2);
        let base_r = 0.076;
        let radius = crate::deployment::deploy_footprint_radius(1, base_r);
        let objectives = vec![(-0.3667, -0.2952), (0.3667, -0.2952)];
        let mut occupied = Vec::new();
        let out = crate::deployment::deploy_place_id(
            &zone, &sec, forward_y, &objectives, &mut occupied, &board, &[], radius, &[],
            base_r, false, false, 0.0, 15,
        );
        assert!(!out.zone_forward_respotted, "a forward section spot never respots");
    }

