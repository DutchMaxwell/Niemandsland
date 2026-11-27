//! `NmlCore.boardgen_layout`: the seeded 48 x 48 in heightfield board (`nml_core::boardgen`) as plain data.
//! Pure Rust (a `serde_json::Value`), so `cargo test` covers it without an engine; `lib.rs` only converts the
//! value to a `VarDictionary`.
use nml_core::boardgen::{self, Symmetry, Theme, CELL_IN, LEVEL_IN};
use serde_json::{json, Value};

/// The layout's own JSON plus what a reader should not recompute: `level_in` (inches for level 0/1/2/3), `problems`
/// (what the accepted-board check still finds; empty = accepted) and, per connector, its cell coordinates and the
/// midpoint of the edge it crosses in board inches (origin at the board corner, x right, z down).
pub fn layout_value(seed: i64) -> Value { layout_value_themed(seed, "") }

/// The theme a flag value names: `ruintown`, `deepworks` or empty (= the original board), case-insensitive; anything else is unknown.
fn theme_of(id: &str) -> Option<Theme> {
    match id.trim().to_ascii_lowercase().as_str() { "" | "deepworks" => Some(Theme::Deepworks), "ruintown" => Some(Theme::RuinTown), _ => None }
}

/// [`layout_value`] for a theme. A town layout names itself (`theme`: "RuinTown"); a Deepworks layout carries no `theme` key, so it is
/// byte-identical to the one before themes. An unknown theme id gives the Deepworks board and an extra `problems` entry.
pub fn layout_value_themed(seed: i64, theme: &str) -> Value {
    let known = theme_of(theme);
    let layout = boardgen::generate_themed(seed, Symmetry::Point180, known.unwrap_or_default());
    let mut v = serde_json::to_value(&layout).expect("layout JSON");
    let nx = layout.nx;
    v["level_in"] = json!(LEVEL_IN);
    if layout.theme == Theme::RuinTown { v["tower_in"] = json!(boardgen::plain::TOWER_IN); }   // a tall scenery tower's height to the core (towers plan T1); a Deepworks layout stays byte-identical
    v["problems"] = json!(layout.problems().into_iter().chain(known.is_none().then_some("unknown theme")).collect::<Vec<_>>());
    // Each landmark also names the core terrain class of its footprint (0 = none) and whether it is solid.
    v["landmarks"] = Value::Array(layout.landmarks.iter().map(|l| { let mut o = serde_json::to_value(l).expect("landmark JSON"); o["terrain"] = json!(l.kind.terrain_class()); o["solid"] = json!(l.kind.is_solid()); o }).collect());
    v["connectors"] = Value::Array(layout.connectors.iter().map(|c| {
        let ((lx, lz), (hx, hz)) = ((usize::from(c.low) % nx, usize::from(c.low) / nx), (usize::from(c.high) % nx, usize::from(c.high) / nx));
        let mid = |a: usize, b: usize| (a + b + 1) as f64 * f64::from(CELL_IN) / 2.0;
        json!({ "kind": c.kind, "low": c.low, "high": c.high, "low_xz": [lx, lz], "high_xz": [hx, hz], "edge_in": [mid(lx, hx), mid(lz, hz)] })
    }).collect());
    v
}

/// Plan step 27-pre P1: the ledges the core plays on for the board of `seed` / `theme` - the `tiers` (per-cell height in
/// inches, ladders) and the `solid_cells` of `boardgen::plain::to_plain`, the same conversion every selfplay board takes,
/// for the table to put into the terrain line it hands the core. The same layout as [`layout_value_themed`] draws.
/// GEN-2: it also names the board - `cells` (`to_plain`'s cover classes in the overlay's grid), `version`
/// (`GENERATOR_VERSION`), `digest` (16 hex of `board_hash`, what a save and an MP peer compare) and the layout's `problems`
/// (empty = accepted; an unknown theme adds "unknown theme"), so the table can re-roll a rejected seed.
pub fn tiers_value_themed(seed: i64, theme: &str) -> Value {
    let known = theme_of(theme);
    let layout = boardgen::generate_themed(seed, Symmetry::Point180, known.unwrap_or_default());
    let plain = boardgen::plain::to_plain(&layout);
    let problems: Vec<&str> = layout.problems().into_iter().chain(known.is_none().then_some("unknown theme")).collect();
    json!({ "tiers": plain.tiers, "solid_cells": plain.solid_cells, "cells": plain.cells,
            "version": boardgen::plain::GENERATOR_VERSION, "digest": format!("{:016x}", boardgen::plain::board_hash(&plain)), "problems": problems })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 27-pre P1: the binding's ledges are `to_plain`'s for both themes, and each cell's height is the level the drawn
    /// layout gives that cell (a ground cell 0, a raised one its LEVEL_IN step), so the core's board is the one on the table.
    #[test]
    fn the_tiers_are_the_drawn_layouts_own() {
        for (seed, theme) in [(7, ""), (42, "ruintown")] {
            let v = tiers_value_themed(seed, theme);
            let layout = boardgen::generate_themed(seed, Symmetry::Point180, theme_of(theme).unwrap());
            let want = boardgen::plain::to_plain(&layout);
            assert_eq!(v["tiers"], serde_json::to_value(&want.tiers).unwrap(), "seed {seed} {theme}");
            assert_eq!(v["solid_cells"], serde_json::to_value(&want.solid_cells).unwrap());
            let drawn = layout_value_themed(seed, theme);
            let heights = v["tiers"]["level_in"].as_array().unwrap();
            assert_eq!(heights.len(), drawn["cells"].as_array().unwrap().len());
            let plain_cells = drawn["cells"].as_array().unwrap().iter().zip(heights)
                .filter(|(c, _)| matches!(c["lot_kind"].as_str(), Some(k) if k != "Roofed" && k != "Tower"));
            for (c, h) in plain_cells {
                assert_eq!(h.as_f64().unwrap(), f64::from(LEVEL_IN[c["level"].as_u64().unwrap() as usize]), "seed {seed} {theme}");
            }
            assert!(heights.iter().any(|h| h.as_f64().unwrap() > 0.0), "a board with ledges");
        }
    }

    /// GEN-2: the binding names the board - its `cells` (cover classes in the overlay's grid), the generator `version`,
    /// the `digest` (16 hex of `board_hash`) a save and an MP peer compare, and the layout's `problems` for the re-roll.
    #[test]
    fn the_binding_names_the_board() {
        for (seed, theme) in [(42, ""), (42, "ruintown"), (7, "deepworks")] {
            let v = tiers_value_themed(seed, theme);
            let layout = boardgen::generate_themed(seed, Symmetry::Point180, theme_of(theme).unwrap());
            let plain = boardgen::plain::to_plain(&layout);
            assert_eq!(v["cells"], serde_json::to_value(&plain.cells).unwrap(), "seed {seed} {theme}");
            assert_eq!(v["version"], json!(boardgen::plain::GENERATOR_VERSION));
            assert_eq!(v["digest"], json!(format!("{:016x}", boardgen::plain::board_hash(&plain))));
            assert_eq!(v["problems"], layout_value_themed(seed, theme)["problems"]);
        }
        assert_eq!(tiers_value_themed(42, "")["digest"], json!("cbcd64fada596527"), "PINNED_SEED_42 of plain.rs");
        assert_eq!(tiers_value_themed(42, "ruintown")["digest"], json!("acda780062931af3"), "PINNED_TOWN_42 of plain.rs");
        assert_eq!(tiers_value_themed(42, "castle")["problems"], json!(["unknown theme"]));
    }

    #[test]
    fn layout_is_a_full_board_with_heights_and_no_problems() {
        for seed in [1, 7, 42, 1000] {
            let v = layout_value(seed);
            assert_eq!(v["cells"].as_array().unwrap().len(), 256);
            assert_eq!(v["level_in"], json!([0, 3, 6, 9]));
            assert_eq!(v["board_in"], json!([48, 48]));
            assert_eq!(v["problems"], json!([]), "seed {seed}");
            assert!(v["cells"].as_array().unwrap().iter().all(|c| c["level"].as_u64().unwrap() <= 3));
        }
    }

    #[test]
    fn landmarks_carry_their_core_terrain_class() {
        let v = layout_value(42);
        let lms = v["landmarks"].as_array().unwrap();
        assert!(lms.len() == 2 || lms.len() == 4);
        for l in lms {
            let (kind, terrain) = (l["kind"].as_str().unwrap(), l["terrain"].as_i64().unwrap());
            let want = match kind { "TankCluster" | "Crane" => nml_core::terrain::CONTAINER, "Sump" => nml_core::terrain::DANGEROUS, _ => nml_core::terrain::NONE };
            assert_eq!((terrain, l["solid"].as_bool().unwrap()), (i64::from(want), matches!(kind, "TankCluster" | "Crane")), "{kind}");
        }
    }

    #[test]
    fn a_themed_layout_names_its_theme() {
        let town = layout_value_themed(7, "ruintown");
        assert_eq!((town["theme"].as_str(), &town["problems"]), (Some("RuinTown"), &json!([])));
        assert_ne!(town["cells"], layout_value(7)["cells"], "the town is another board");
        assert_eq!(layout_value_themed(7, " RuinTown ")["cells"], town["cells"], "ids are trimmed and case-insensitive");
        for id in ["", "deepworks"] { assert_eq!(layout_value_themed(42, id), layout_value(42)); }
        assert!(layout_value(42).get("theme").is_none(), "a Deepworks layout has no theme key (the recorded fixture stays byte-identical)");
    }

    #[test]
    fn an_unknown_theme_is_the_deepworks_board_with_a_problem() {
        let (v, plain) = (layout_value_themed(42, "castle"), layout_value(42));
        assert_eq!(v["problems"], json!(["unknown theme"]));
        assert_eq!((&v["cells"], v.get("theme")), (&plain["cells"], None));
    }

    #[test]
    fn layout_is_deterministic_per_seed_and_differs_between_seeds() {
        assert_eq!(layout_value(5), layout_value(5));
        assert_ne!(layout_value(5)["cells"], layout_value(6)["cells"]);
    }

    #[test]
    fn connectors_join_neighbours_one_level_apart_and_carry_their_edge() {
        let v = layout_value(42);
        let (cells, conns) = (v["cells"].as_array().unwrap(), v["connectors"].as_array().unwrap());
        assert!(!conns.is_empty());
        for c in conns {
            let (low, high) = (c["low"].as_u64().unwrap() as usize, c["high"].as_u64().unwrap() as usize);
            assert_eq!(cells[high]["level"].as_u64().unwrap(), cells[low]["level"].as_u64().unwrap() + 1);
            assert_eq!(c["kind"].as_str(), Some("Ladder"), "no stairs on a generated board");
            let (e, (lx, lz)) = (c["edge_in"].as_array().unwrap(), (low % 16, low / 16));
            let (ex, ez) = (e[0].as_f64().unwrap(), e[1].as_f64().unwrap());
            // The edge midpoint lies on the boundary of the low cell: half a cell from its centre along one axis only.
            let (dx, dz) = ((ex - (lx as f64 + 0.5) * 3.0).abs(), (ez - (lz as f64 + 0.5) * 3.0).abs());
            assert!((dx == 1.5 && dz == 0.0) || (dx == 0.0 && dz == 1.5), "edge {ex},{ez} of cell {lx},{lz}");
        }
    }
}
