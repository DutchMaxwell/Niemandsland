//! The generated board as a header's `terrain` block: `Layout` -> `PlainTerrain` (heightfield plan step 3).
//! Core-only and pure; nothing reads it yet (the table-facing call is step 16). The board is materialised ONCE, here:
//! every other reader gets this object back and never re-derives it from the seed.
//!
//! [`GENERATOR_VERSION`] names the generator's output. Whoever changes what `generate(seed)` returns for a seed
//! bumps it and re-pins the hash test below, so a stored board is never taken for the output of a newer generator.
use crate::terrain::{CellParams, PlainTerrain, TierGrid, DANGEROUS, NONE};
use super::levels::LotKind;
use super::{Layout, LEVEL_IN};

pub const GENERATOR_VERSION: u32 = 1;

/// Cells between the board edge and the edge of the terrain overlay's grid: that grid is the table diagonal in cells,
/// rounded up to even (`Terrain::build`), so a 48 in board sits in a 24 x 24 grid and its cell (0, 0) is grid cell (4, 4).
fn grid_margin(l: &Layout) -> i64 {
    let diag = f64::from(l.board_in[0]).hypot(f64::from(l.board_in[1])) / f64::from(l.cell_in);
    let grid = diag.ceil() as i64;
    (grid + grid % 2 - l.nx as i64) / 2
}

/// The board as the core reads it: Hazard lots become DANGEROUS cells in the overlay's grid and landmark footprints take
/// the terrain class of their kind (`LandmarkKind::terrain_class`), the table is the board
/// (4 x 4 ft, 3 in cells, yaw 0), and `tiers` carries every level (inches) and every ladder. No stairs exist.
pub fn to_plain(l: &Layout) -> PlainTerrain {
    let m = grid_margin(l);
    // one class per cell, row-major: a Hazard lot is DANGEROUS, a landmark's footprint carries the class of its kind
    // (a classless pump house leaves the cell as it was)
    let mut classes: std::collections::BTreeMap<(usize, usize), i32> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Hazard)
        .map(|c| ((c.z, c.x), DANGEROUS)).collect();
    for lm in l.landmarks.iter().filter(|lm| lm.kind.terrain_class() != NONE) {
        for i in lm.cells() {
            classes.insert((i / l.nx, i % l.nx), lm.kind.terrain_class());
        }
    }
    let cells = classes.into_iter().map(|((z, x), class)| [(x as i64 + m) as f64, (z as i64 + m) as f64, f64::from(class)]).collect();
    let tiers = TierGrid {
        nx: l.nx as u16, nz: l.nz as u16, cell_in: f64::from(l.cell_in),
        level_in: l.cells.iter().map(|c| f64::from(LEVEL_IN[usize::from(c.level)])).collect(),
        ladders: l.connectors.iter().map(|c| [c.low, c.high]).collect(),
        stairs: Vec::new(),
    };
    let cell_params = CellParams {
        table_size_feet: [f64::from(l.board_in[0]) / 12.0, f64::from(l.board_in[1]) / 12.0],
        grid_rotation_degrees: 0.0, grid_size_inches: f64::from(l.cell_in), inches_to_meters: crate::IN2M,
    };
    PlainTerrain { cells, tiers: Some(tiers), cell_params, ..Default::default() }
}

/// FNV-1a 64 over the serialised JSON of the board: the identity MP peers and a save compare (no hash crate needed).
pub fn board_hash(p: &PlainTerrain) -> u64 {
    fnv1a64(serde_json::to_string(p).expect("board JSON").as_bytes())
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |h, &b| (h ^ u64::from(b)).wrapping_mul(0x0000_0100_0000_01b3))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::boardgen::{generate, Symmetry};
    use crate::terrain::{Terrain, NONE};

    fn ground(x: usize, z: usize) -> [f32; 3] {
        // board centre = world origin, cell (x, z) spans [-24 + 3x, -24 + 3x + 3) in inches
        [((-24.0 + 3.0 * x as f64 + 1.5) * crate::IN2M) as f32, 0.0, ((-24.0 + 3.0 * z as f64 + 1.5) * crate::IN2M) as f32]
    }

    #[test]
    fn to_plain_keeps_every_level_and_connector() {
        let (mut with_hazard, mut with_landmark_class) = (0, 0);
        for seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 42, 1000] {
            for sym in [Symmetry::Point180, Symmetry::BalancedFree] {
                let l = generate(seed, sym);
                let p = to_plain(&l);
                let t = p.tiers.as_ref().expect("a generated board has tiers");
                assert_eq!((t.nx, t.nz, t.cell_in), (16, 16, 3.0));
                assert_eq!(p.cell_params.table_size_feet, [4.0, 4.0]);
                assert!(t.stairs.is_empty(), "there are no stairs");
                for (i, c) in l.cells.iter().enumerate() {
                    assert_eq!(t.level_in[i], f64::from(LEVEL_IN[usize::from(c.level)]), "seed {seed} {sym:?} cell {i}");
                }
                assert_eq!(t.ladders.len(), l.connectors.len());
                for (pair, c) in t.ladders.iter().zip(&l.connectors) {
                    assert_eq!(*pair, [c.low, c.high]);
                    assert_eq!(t.level_in[usize::from(pair[1])] - t.level_in[usize::from(pair[0])], 3.0, "a ladder is one tier");
                }
                // the overlay frame is right: a landmark footprint reads its kind's class, else a Hazard lot cell reads
                // DANGEROUS at its centre, every other cell reads NONE
                with_hazard += usize::from(l.cells.iter().any(|c| c.lot_kind == LotKind::Hazard));
                let board = Terrain::build(&p);
                for c in &l.cells {
                    let landmark = l.landmarks.iter().find(|m| m.cells().any(|i| i == c.z * 16 + c.x)).map(|m| m.kind.terrain_class());
                    with_landmark_class += usize::from(landmark.is_some_and(|k| k != NONE));
                    let want = match landmark {
                        Some(k) if k != NONE => k,
                        _ if c.lot_kind == LotKind::Hazard => DANGEROUS,
                        _ => NONE,
                    };
                    assert_eq!(board.type_at(ground(c.x, c.z)), want, "seed {seed} {sym:?} cell ({}, {})", c.x, c.z);
                }
            }
        }
        assert!(with_hazard >= 4, "only {with_hazard} boards had a Hazard lot: the frame check above proved too little");
        assert!(with_landmark_class >= 20, "only {with_landmark_class} classed landmark cells: the landmark mapping proved too little");
    }

    #[test]
    fn fnv1a64_matches_the_published_vectors() {
        // test vectors of the FNV reference page (64-bit, FNV-1a)
        assert_eq!(fnv1a64(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a64(b"a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_f739_67e8);
    }

    #[test]
    fn the_hash_pins_seed_42_version_1_and_sees_one_level() {
        let p = to_plain(&generate(42, Symmetry::Point180));
        assert_eq!(GENERATOR_VERSION, 1);
        assert_eq!(format!("{:016x}", board_hash(&p)), PINNED_SEED_42, "the generator or the plain mapping changed: bump GENERATOR_VERSION and re-pin");
        let again: PlainTerrain = serde_json::from_str(&serde_json::to_string(&p).unwrap()).unwrap();
        assert_eq!(board_hash(&again), board_hash(&p), "a board that went through JSON keeps its hash");
        let mut moved = p.clone();
        let level = &mut moved.tiers.as_mut().unwrap().level_in[100];
        *level = if *level == 6.0 { 3.0 } else { 6.0 };
        assert_ne!(board_hash(&moved), board_hash(&p), "one changed level must change the hash");
    }

    const PINNED_SEED_42: &str = "cbcd64fada596527";
}
