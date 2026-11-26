    //! Per-family tests that own a DEPLOYMENT seam — putting a unit onto the
    //! table and taking one off it, not one activation's resolve. Wired the
    //! `tests/sim` way (`#[path = "tests/deployment/mod.rs"]`), so the rule
    //! census never reads a test literal as a resolver arm
    //! (`rule_universe_census.py::core_src_files` excludes `src/tests/`).
    use super::*;
    // Tests exercise "the current epoch" generically (bumped forward each
    // wave); production reads the FROZEN `EPOCH_7_TABLE_RULES` instead.
    use crate::acts::{read_act_header, Knobs, CURRENT_RULES_EPOCH};
    use crate::io::{self, Seams};
    use crate::menu::Candidate;
    use crate::playout::Policy;
    use crate::rollout::{mint_template_slot, reinforcement_round_start, spawn_round_start, Rollout};
    use crate::rules::Registries;
    use crate::sim::Scratch;
    use crate::state::{ProfileCache, State};
    use crate::terrain::PlainTerrain;
    use crate::unit::UnitStatic;

    /// The checkout this crate lives in — mirrors `tests/rollout/mod.rs`.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// Index of a unit by its capture key, so a fixture asserts on names
    /// rather than on the JSON object's order.
    fn idx(st: &State, key: &str) -> usize {
        (0..st.units()).find(|&i| st.key(i) == key).unwrap_or_else(|| panic!("no unit {key}"))
    }

    /// Statics off the PRODUCTION path (`UnitStatic::build_for` over the
    /// header's own profile table), so a rule flag in a fixture is the one the
    /// shipped registry data resolves — never a hand-set field.
    fn statics_of(st: &State, epoch: u32) -> Vec<UnitStatic> {
        let mut reg = Registries::new(&repo_root());
        st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect()
    }

    /// A 6x4 ft board with no cells, no sandbox and no walls: `spot_blocked`
    /// answers false everywhere, so the ZONE decides the spot and nothing else
    /// does. The table extent is what the driver measures the 12" band
    /// against, so it cannot be `Terrain::default()`.
    fn empty_board() -> Terrain {
        let plain: PlainTerrain = serde_json::from_value(serde_json::json!({
            "cells": [], "sandbox": [], "walls": [],
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
                            "grid_size_inches": 6.0, "inches_to_meters": crate::IN2M},
        }))
        .expect("plain terrain");
        Terrain::build(&plain)
    }

    mod deploy_coherency;
    mod deploy_exit;
    mod deploy_large;
    mod reinforcement;
    mod spawn;
    mod tier_board;
    mod v36_ux;
    mod v36_ux_13;
    mod v36_ux_14;
    mod vanguard_free;
    mod skirmish_a_setup;

    /// The 6x4 ft board's own rectangle, world metres — the table a circle
    /// zone clamps its bounding square against (the driver's own read,
    /// `rollout::table_rect`).
    pub(crate) fn table_rect_of(board: &Terrain) -> crate::deployment::Rect {
        let [w_in, d_in] = board.board_in();
        assert!(w_in > 0.0 && d_in > 0.0, "the fixture board has a table");
        let (w, d) = (w_in * crate::IN2M, d_in * crate::IN2M);
        crate::deployment::Rect::new(-w / 2.0, -d / 2.0, w, d)
    }

    /// Firefight step 8 + switch step 18: 48x48 board zones (catalogue key per board size, six standard + three attack_defend styles).
    /// R: a 72x48 zone on a 48-in board is refused; G: both zones 12 in deep, 24 in apart.
    #[test]
    fn board_48x48_deployment_zones_and_72x48_refusal() {
        let cat: serde_json::Value =
            serde_json::from_str(include_str!("../../../../../assets/solo/deployments.json")).unwrap();
        // RED guard: a 72x48 zone does not fit on a 48x48 board and must be refused.
        let z72 = crate::objectives::zones_of_style(&cat["styles"]["front_line"]);
        assert!(zones_fit_board(&z72, [48.0, 48.0]).is_err(), "72x48 zone on 48x48 board must be refused");
        assert!(zones_fit_board(&z72, [72.0, 48.0]).is_ok(), "72x48 zone fits 72x48 board");

        // 48x48 catalogue: the six standard + three attack_defend styles; the unshipped families are refused.
        assert!(catalog_zones_for_board(&cat, "long_haul", [48.0, 48.0]).is_err(),
            "non-standard styles are not enabled on 48x48");
        // Every shipped 48x48 style resolves for both sides (`zones_fit_board` runs in the lookup).
        let ids: Vec<&String> = cat["boards"]["48x48"].as_object().unwrap().keys().collect();
        assert_eq!(ids.len(), 9, "six standard + three attack_defend: {ids:?}");
        for id in ids {
            let [a, b] = catalog_zones_for_board(&cat, id, [48.0, 48.0]).unwrap_or_else(|e| panic!("48x48/{id}: {e}"));
            assert!(!a.is_empty() && !b.is_empty(), "{id} has zones for both sides");
            if cat["boards"]["48x48"][id.as_str()]["family"] == "attack_defend" {
                assert_eq!(a, b, "{id} is role-agnostic: the same zone for both sides");
            }
        }
        // Planted faults: a vertex an inch past the half-extent, and a disc that spills over the edge, are refused.
        let mut bad = cat.clone();
        bad["boards"]["48x48"]["ground_war"]["zones"]["1"][0][0] = serde_json::json!([25, -24]);
        assert!(catalog_zones_for_board(&bad, "ground_war", [48.0, 48.0]).is_err(), "a vertex past the board is refused");
        bad["boards"]["48x48"]["centre_disc_12"]["zones"]["1"][0]["disc"]["r_in"] = serde_json::json!(25);
        assert!(catalog_zones_for_board(&bad, "centre_disc_12", [48.0, 48.0]).is_err(), "a disc past the board is refused");

        // 48x48 front_line: both zones 12 in deep, 24 in apart, spanning x in [-24, 24].
        let [p1, p2] = catalog_zones_for_board(&cat, "front_line", [48.0, 48.0]).unwrap();
        let bounds = |zones: &[Zone]| -> (i64, i64, i64, i64) {
            let (mut x0, mut x1, mut z0, mut z1) = (i64::MAX, i64::MIN, i64::MAX, i64::MIN);
            for z in zones {
                let Zone::Poly(pts) = z else { panic!("expected polygon zone") };
                for &[x, y] in pts {
                    x0 = x0.min(x); x1 = x1.max(x); z0 = z0.min(y); z1 = z1.max(y);
                }
            }
            (x0, x1, z0, z1)
        };
        let (p1x0, p1x1, p1z0, p1z1) = bounds(&p1);
        let (p2x0, p2x1, p2z0, p2z1) = bounds(&p2);
        assert_eq!((p1x0, p1x1, p1z0, p1z1), (-24, 24, -24, -12), "P1 zone is 48x12 along z=-24..-12");
        assert_eq!((p2x0, p2x1, p2z0, p2z1), (-24, 24, 12, 24), "P2 zone is 48x12 along z=12..24");
        assert_eq!(p1z1 - p1z0, 12, "P1 zone 12 in deep");
        assert_eq!(p2z1 - p2z0, 12, "P2 zone 12 in deep");
        assert_eq!(p2z0 - p1z1, 24, "zones 24 in apart");

        // 72x48 lookup continues to return the existing 72x48 front_line zones unchanged.
        let [g1, g2] = catalog_zones_for_board(&cat, "front_line", [72.0, 48.0]).unwrap();
        assert_eq!(bounds(&g1), (-36, 36, -24, -12));
        assert_eq!(bounds(&g2), (-36, 36, 12, 24));
    }
