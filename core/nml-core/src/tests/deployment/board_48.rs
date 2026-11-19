    // ---- FIREFIGHT step 8: the deployment catalogue gains a per-board-size
    // key. 48x48 carries the standard family only; the 72x48 polygons are
    // refused on a 48-in board (their x reaches +-36, past the +-24 edge).

    fn catalogue() -> serde_json::Value {
        serde_json::from_str(include_str!("../../../../../assets/solo/deployments.json"))
            .expect("deployments.json parses")
    }

    #[test]
    fn board_48x48_deployment_zones_and_72x48_refusal() {
        let cat = catalogue();
        // The old 72x48 geometry is legal on its own table and not on a 4x4 ft.
        let wide = crate::objectives::zones_of_style(&cat["styles"]["front_line"]);
        assert!(crate::deployment::zones_fit_board(&wide, [72.0, 48.0]));
        assert!(!crate::deployment::zones_fit_board(&wide, [48.0, 48.0]));
        assert_eq!(crate::deployment::board_size_key([48.0, 48.0]), Some("48x48"));
        assert_eq!(crate::deployment::board_size_key([72.0, 48.0]), None);

        // G: both zones 12 in deep, 24 in apart, 48 in wide.
        let zones = crate::deployment::catalog_zones_for_board(&cat, "front_line", [48.0, 48.0])
            .expect("48x48 front_line");
        assert_eq!(zones.len(), 2);
        let (p1, p2) = (&zones[0], &zones[1]);
        assert!(crate::objectives::in_zone(0, -13, p1), "12 in deep");
        assert!(!crate::objectives::in_zone(0, -11, p1), "front edge at -12");
        assert!(crate::objectives::in_zone(0, 13, p2), "12 in deep");
        assert!(!crate::objectives::in_zone(0, 11, p2), "front edge at +12");
        assert!(!crate::objectives::in_zone(0, 0, p1) && !crate::objectives::in_zone(0, 0, p2), "24 in apart");
        assert!(crate::objectives::in_zone(23, -13, p1) && !crate::objectives::in_zone(25, -13, p1), "48 wide");
        assert!(crate::objectives::in_zone(-23, 13, p2) && !crate::objectives::in_zone(-25, 13, p2), "48 wide");

        // R: a 72x48 zone dropped under the 48x48 key is still refused.
        let mut wrong = cat.clone();
        wrong["boards"]["48x48"]["front_line"] = cat["styles"]["front_line"].clone();
        assert!(crate::deployment::catalog_zones_for_board(&wrong, "front_line", [48.0, 48.0]).is_none());

        // Standard family only on a 48x48 board; unknown ids are refused.
        assert!(crate::deployment::catalog_zones_for_board(&cat, "centre_disc_12", [48.0, 48.0]).is_none());
        assert!(crate::deployment::catalog_zones_for_board(&cat, "no_such_style", [48.0, 48.0]).is_none());

        // 72x48 keeps reading "styles" unchanged.
        assert_eq!(
            crate::deployment::catalog_zones_for_board(&cat, "front_line", [72.0, 48.0]),
            Some(wide)
        );
    }
