    // ---- PR #1037 (`coherency repair stays inside the zone and off the table
    // edge`), mirrored UNGATED from the table: the repair's ring walk skips
    // candidates outside the unit's zone or off the table edge — in FREE and in
    // FORCED mode alike. Fixtures reuse the table's geometry spot-for-spot.

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
