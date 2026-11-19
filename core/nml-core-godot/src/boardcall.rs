//! `NmlCore.boardgen_layout`: the seeded 48 x 48 in heightfield board (`nml_core::boardgen`) as plain data.
//! Pure Rust (a `serde_json::Value`), so `cargo test` covers it without an engine; `lib.rs` only converts the
//! value to a `VarDictionary`.
use nml_core::boardgen::{self, Symmetry, CELL_IN, LEVEL_IN};
use serde_json::{json, Value};

/// The layout's own JSON plus what a reader should not recompute: `level_in` (inches for level 0/1/2), `problems`
/// (what the accepted-board check still finds; empty = accepted) and, per connector, its cell coordinates and the
/// midpoint of the edge it crosses in board inches (origin at the board corner, x right, z down).
pub fn layout_value(seed: i64) -> Value {
    let layout = boardgen::generate(seed, Symmetry::Point180);
    let mut v = serde_json::to_value(&layout).expect("layout JSON");
    let nx = layout.nx;
    v["level_in"] = json!(LEVEL_IN);
    v["problems"] = json!(layout.problems());
    v["connectors"] = Value::Array(layout.connectors.iter().map(|c| {
        let ((lx, lz), (hx, hz)) = ((usize::from(c.low) % nx, usize::from(c.low) / nx), (usize::from(c.high) % nx, usize::from(c.high) / nx));
        let mid = |a: usize, b: usize| (a + b + 1) as f64 * f64::from(CELL_IN) / 2.0;
        json!({ "kind": c.kind, "low": c.low, "high": c.high, "low_xz": [lx, lz], "high_xz": [hx, hz], "edge_in": [mid(lx, hx), mid(lz, hz)] })
    }).collect());
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_is_a_full_board_with_heights_and_no_problems() {
        for seed in [1, 7, 42, 1000] {
            let v = layout_value(seed);
            assert_eq!(v["cells"].as_array().unwrap().len(), 256);
            assert_eq!(v["level_in"], json!([0, 3, 6]));
            assert_eq!(v["board_in"], json!([48, 48]));
            assert_eq!(v["problems"], json!([]), "seed {seed}");
            assert!(v["cells"].as_array().unwrap().iter().all(|c| c["level"].as_u64().unwrap() <= 2));
        }
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
            assert!(matches!(c["kind"].as_str(), Some("Stair" | "Ladder")));
            let (e, (lx, lz)) = (c["edge_in"].as_array().unwrap(), (low % 16, low / 16));
            let (ex, ez) = (e[0].as_f64().unwrap(), e[1].as_f64().unwrap());
            // The edge midpoint lies on the boundary of the low cell: half a cell from its centre along one axis only.
            let (dx, dz) = ((ex - (lx as f64 + 0.5) * 3.0).abs(), (ez - (lz as f64 + 0.5) * 3.0).abs());
            assert!((dx == 1.5 && dz == 0.0) || (dx == 0.0 && dz == 1.5), "edge {ex},{ez} of cell {lx},{lz}");
        }
    }
}
