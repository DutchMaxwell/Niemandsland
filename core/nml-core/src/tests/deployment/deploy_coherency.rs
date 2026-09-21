    // ---- PR #1038 (`large base may take a forward spot from the whole zone`)
    // and PR #1037 (`coherency repair stays inside the zone and off the table
    // edge`), mirrored UNGATED from the table (the core has no static
    // switches). The fixtures reuse the table's own geometry spot-for-spot:
    // the whole-zone respot fires only when the section scan had to land far
    // behind the forward edge, and the repair's ring walk skips candidates
    // outside the unit's zone or off the table edge — in FREE and in FORCED
    // mode alike.

    use super::empty_board;

    /// A round settle shape of radius `r` — the `shape_for_model` result for a
    /// round base at Tough scale 1.
    fn round_geom(r: f64) -> crate::deployment::SettleShapeGeom {
        crate::deployment::SettleShapeGeom {
            oval: false,
            radius: r,
            semi_x: 0.0,
            semi_z: 0.0,
            yaw: 0.0,
        }
    }

    /// A settle unit of `models` (x, y in metres), every model a round base of
    /// radius `r`, contained in `zone`.
    fn unit(models: &[(f64, f64)], r: f64, zone: crate::deployment::Rect) -> crate::deployment::SettleUnit {
        crate::deployment::SettleUnit {
            models: models.iter().map(|m| [m.0 as f32, m.1 as f32]).collect(),
            geoms: vec![round_geom(r); models.len()],
            zone,
            flying: false,
            footprint: vec![],
        }
    }

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

    // ---- DEPLOYCOH: the repair's zone and table-edge gates.

    /// The straggler ring walk: component {A(0.22,0), B(0.17,0)}, straggler
    /// S(0.42,0) — 8.4" out, past the 1" link. The first ring candidates
    /// (0deg..45deg around A) sit beyond the zone's right edge (x = 0.25), so
    /// the ZONE gate must skip them and land on the 60deg candidate.
    #[test]
    fn coherency_repair_stays_inside_the_zone() {
        let board = empty_board();
        let zone = crate::deployment::Rect::new(-0.25, -0.25, 0.5, 0.5);
        let mut units = vec![unit(&[(0.22, 0.0), (0.17, 0.0), (0.42, 0.0)], 0.016, zone)];
        let forced = crate::deployment::repair_deploy_coherency(&mut units, &board, &[], &[]);
        assert!(!forced, "a free repair never sets forced_any");
        let s = units[0].models[2];
        assert!(
            (s[0] as f64 - 0.24235).abs() <= 0.001 && (s[1] as f64 - 0.0387113).abs() <= 0.001,
            "the straggler lands on the first IN-ZONE ring candidate, got {s:?}"
        );
        assert!(
            s[0] < 0.25 && s[1] >= -0.25 && s[1] < 0.25,
            "the repaired model is inside its zone, got {s:?}"
        );
    }

    /// The same ring under six enemy discs parked on it (30deg-offset, 60deg
    /// spacing, radius 6 cm): every free candidate around BOTH component
    /// models fails the free spot check (worst gap 0.069 < 0.078), so the
    /// repair goes FORCED — and the zone gate must still hold there (the
    /// old forced-first-candidate spot at x = 0.2647 is outside the zone).
    #[test]
    fn forced_repair_still_respects_the_zone_gate() {
        let board = empty_board();
        let zone = crate::deployment::Rect::new(-0.25, -0.25, 0.5, 0.5);
        let ring = 0.0447_f64;
        let enemy: Vec<(f64, f64)> = (0..6)
            .map(|k| {
                let a = std::f64::consts::TAU * (k as f64 + 0.5) / 6.0;
                (0.22 + a.cos() * ring, a.sin() * ring)
            })
            .collect();
        let mut units = vec![
            unit(&[(0.22, 0.0), (0.17, 0.0), (0.42, 0.0)], 0.016, zone),
            unit(&enemy, 0.06, crate::deployment::Rect::new(-0.55, -0.6, 1.1, 0.3048)),
        ];
        let forced = crate::deployment::repair_deploy_coherency(&mut units, &board, &[], &[]);
        assert!(forced, "the packed ring forces the placement");
        let s = units[0].models[2];
        assert!(
            (s[0] as f64 - 0.24235).abs() <= 0.001 && (s[1] as f64 - 0.0387113).abs() <= 0.001,
            "the forced spot is the first IN-ZONE candidate, got {s:?}"
        );
   }

    /// The table-edge gate: the unit sits at y = 0.59, past the 6x4 board's
    /// bound (0.6096 - margin 0.0414 = 0.5682). The in-zone candidates in the
    /// +y half all fail the edge; the first edge-legal candidate (210deg) is
    /// blocked by B; the repair lands on 225deg — (0.76839, 0.55839).
    #[test]
    fn coherency_repair_stays_off_the_table_edge() {
        let board = empty_board(); // 6x4 ft: half extents (0.9144, 0.6096)
        let zone = crate::deployment::Rect::new(0.5, 0.30, 0.35, 0.40);
        let mut units = vec![unit(&[(0.80, 0.59), (0.75, 0.59), (1.02, 0.59)], 0.016, zone)];
        let forced = crate::deployment::repair_deploy_coherency(&mut units, &board, &[], &[]);
        assert!(!forced, "a free repair never sets forced_any");
        let s = units[0].models[2];
        assert!(
            (s[0] as f64 - 0.76839).abs() <= 0.001 && (s[1] as f64 - 0.55839).abs() <= 0.001,
            "the straggler lands on the first table-legal ring candidate, got {s:?}"
        );
        let (hx, hy) = (0.9144 - 0.016 - crate::IN2M, 0.6096 - 0.016 - crate::IN2M);
        assert!(
            s[0].abs() <= hx as f32 + 1e-4 && s[1].abs() <= hy as f32 + 1e-4,
            "the repaired straggler stays off the table edge, got {s:?}"
        );
        assert_eq!(
            units[0].models[0],
            [0.8f32, 0.59],
            "the in-coherency component models are untouched"
        );
    }
