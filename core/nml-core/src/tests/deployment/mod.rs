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
    use crate::rollout::{reinforcement_round_start, Rollout};    use crate::rules::Registries;
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

    mod reinforcement;
    mod spawn;

    /// The 6x4 ft board's own rectangle, world metres — the table a circle
    /// zone clamps its bounding square against (the driver's own read,
    /// `rollout::table_rect`).
    pub(crate) fn table_rect_of(board: &Terrain) -> crate::deployment::Rect {
        let [w_in, d_in] = board.board_in();
        assert!(w_in > 0.0 && d_in > 0.0, "the fixture board has a table");
        let (w, d) = (w_in * crate::IN2M, d_in * crate::IN2M);
        crate::deployment::Rect::new(-w / 2.0, -d / 2.0, w, d)
    }
