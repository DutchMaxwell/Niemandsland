//! The generated board as a header's `terrain` block: `Layout` -> `PlainTerrain` (heightfield plan step 3).
//! Core-only and pure; nothing reads it yet (the table-facing call is step 16). The board is materialised ONCE, here:
//! every other reader gets this object back and never re-derives it from the seed.
//!
//! [`GENERATOR_VERSION`] names the generator's output. Whoever changes what `generate(seed)` returns for a seed
//! bumps it and re-pins the hash test below, so a stored board is never taken for the output of a newer generator.
use crate::terrain::{CellParams, PlainTerrain, TierGrid, CONTAINER, DANGEROUS, FOREST, NONE, RUINS};
use super::levels::LotKind;
use super::{Layout, Theme, LEVEL_IN};

pub const GENERATOR_VERSION: u32 = 1;
/// Height of a tall scenery tower (`LotKind::Tower`) to the core, inches: above every eye on a board (9 in + 1.25 in), so nobody sees over it.
pub const TOWER_IN: f64 = 12.0;

/// Cells between the board edge and the edge of the terrain overlay's grid: that grid is the table diagonal in cells,
/// rounded up to even (`Terrain::build`), so a 48 in board sits in a 24 x 24 grid and its cell (0, 0) is grid cell (4, 4).
fn grid_margin(l: &Layout) -> i64 {
    let diag = f64::from(l.board_in[0]).hypot(f64::from(l.board_in[1])) / f64::from(l.cell_in);
    let grid = diag.ceil() as i64;
    (grid + grid % 2 - l.nx as i64) / 2
}

/// The board as the core reads it: Hazard lots become DANGEROUS cells in the overlay's grid and landmark footprints take
/// the terrain class of their kind (`LandmarkKind::terrain_class`); on a ruin town also the level-0 rest of a Terrace lot reads RUINS (cover, sight in and
/// out, Unstable), a garden plot and a wall breach FOREST (Difficult + cover) and an intact house CONTAINER (solid, 2.5 in); the table is the board
/// (4 x 4 ft, 3 in cells, yaw 0), and `tiers` carries every level (inches) and every ladder. No stairs exist.
pub fn to_plain(l: &Layout) -> PlainTerrain {
    let m = grid_margin(l);
    // one class per cell, row-major: a Hazard lot is DANGEROUS, a landmark's footprint carries the class of its kind
    // (a classless pump house leaves the cell as it was)
    let town = |c: &&super::Cell| -> Option<i32> {
        if l.theme != Theme::RuinTown { return None; }
        match (c.lot_kind, c.level) {
            (LotKind::Terrace, 0) if !c.street => Some(RUINS),
            (LotKind::Rough | LotKind::Wall, 0) => Some(FOREST),
            (LotKind::Roofed | LotKind::Tower, _) => Some(CONTAINER),
            _ => None,
        }
    };
    let mut classes: std::collections::BTreeMap<(usize, usize), i32> = l.cells.iter().filter_map(|c| town(&c).map(|k| ((c.z, c.x), k))).collect();
    classes.extend(l.cells.iter().filter(|c| c.lot_kind == LotKind::Hazard).map(|c| ((c.z, c.x), DANGEROUS)));
    for lm in l.landmarks.iter().filter(|lm| lm.kind.terrain_class() != NONE) {
        for i in lm.cells() {
            classes.insert((i / l.nx, i % l.nx), lm.kind.terrain_class());
        }
    }
    let cells = classes.into_iter().map(|((z, x), class)| [(x as i64 + m) as f64, (z as i64 + m) as f64, f64::from(class)]).collect();
    let tiers = TierGrid {
        nx: l.nx as u16, nz: l.nz as u16, cell_in: f64::from(l.cell_in),
        level_in: l.cells.iter().map(|c| if c.lot_kind == LotKind::Tower { TOWER_IN } else { f64::from(LEVEL_IN[usize::from(c.level)]) }).collect(),
        ladders: l.connectors.iter().map(|c| [c.low, c.high]).collect(),
        stairs: Vec::new(),
    };
    let cell_params = CellParams {
        table_size_feet: [f64::from(l.board_in[0]) / 12.0, f64::from(l.board_in[1]) / 12.0],
        grid_rotation_degrees: 0.0, grid_size_inches: f64::from(l.cell_in), inches_to_meters: crate::IN2M,
    };
    // L-RF1: an intact house is Impassable - its cells are solid (cliffs all round, nobody on the roof). Town only; the
    // solid landmarks (wells, crane feet, Deepworks tanks) are D-F2's own step.
    let solid_cells = if l.theme == Theme::RuinTown { (0..l.cells.len()).filter(|&i| matches!(l.cells[i].lot_kind, LotKind::Roofed | LotKind::Tower)).map(|i| i as u16).collect() } else { Vec::new() };
    PlainTerrain { cells, tiers: Some(tiers), solid_cells, cell_params, ..Default::default() }
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
    use crate::boardgen::{generate, generate_themed, Symmetry};
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

    /// Towers plan T1: a `Tower` cell is a tall solid - listed solid, `TOWER_IN` to the core, CONTAINER class, a Cliff on every face to a
    /// non-solid cell and none between two tower cells, a block no eye on the board (at most 9 + 1.25 in) sees over, and no ladder ends on it.
    /// Planted: the same cells at 9 in would be seen over (the sight assert can fail).
    #[test]
    fn a_tower_cell_is_a_tall_solid_nobody_climbs_or_sees_over() {
        let mut l = generate_themed(41, Symmetry::Point180, Theme::RuinTown);
        let free = |c: &crate::boardgen::Cell| c.level == 0 && !c.street && c.lot_kind == LotKind::Street;
        let i = (0..l.cells.len() - 1).find(|&i| i % 16 < 15 && free(&l.cells[i]) && free(&l.cells[i + 1])).expect("two free ground cells");
        let pick = [i, i + 1];
        for &k in &pick { l.cells[k].lot_kind = LotKind::Tower; }
        let p = to_plain(&l);
        let tiers = p.tiers.as_ref().unwrap();
        let board = Terrain::build(&p);
        for &k in &pick {
            assert!(p.solid_cells.contains(&(k as u16)), "a tower cell is solid");
            assert_eq!(tiers.level_in[k], TOWER_IN);
            assert_eq!(board.type_at(ground(l.cells[k].x, l.cells[k].z)), CONTAINER);
        }
        let solid: Vec<bool> = (0..256).map(|k| p.solid_cells.contains(&(k as u16))).collect();
        let v = |a: usize| (a as f64 - 8.0) * 3.0;
        let face = |a: [f64; 2], b: [f64; 2]| board.tier_edges().iter().any(|e| e.kind == crate::mv::tier::TierKind::Cliff
            && ((e.a[0] == a[0] && e.b[0] == a[0] && a[0] == b[0] && e.a[1].min(e.b[1]) <= a[1] && e.a[1].max(e.b[1]) >= b[1])
                || (e.a[1] == a[1] && e.b[1] == a[1] && a[1] == b[1] && e.a[0].min(e.b[0]) <= a[0] && e.a[0].max(e.b[0]) >= b[0])));
        let (x, z) = (i % 16, i / 16);
        assert!(!face([v(x + 1), v(z)], [v(x + 1), v(z + 1)]), "no edge between the two tower cells");
        for (k, dx, dz) in [(i, -1i64, 0i64), (i, 0, -1), (i, 0, 1), (i + 1, 1, 0), (i + 1, 0, -1), (i + 1, 0, 1)] {
            let (cx, cz) = ((k % 16) as i64, (k / 16) as i64);
            let (nx, nz) = (cx + dx, cz + dz);
            if !(0..16).contains(&nx) || !(0..16).contains(&nz) || solid[(nz * 16 + nx) as usize] { continue; }
            let (gx, gz) = ((cx + dx.max(0)) as usize, (cz + dz.max(0)) as usize);
            let (a, b) = if dx != 0 { ([v(gx), v(cz as usize)], [v(gx), v(cz as usize + 1)]) } else { ([v(cx as usize), v(gz)], [v(cx as usize + 1), v(gz)]) };
            assert!(face(a, b), "cell {k}: no cliff on the face toward ({nx}, {nz})");
        }
        let eye = 9.0 + 1.25;
        let top = |t: &TierGrid| t.boxes().iter().filter(|b| b.lo[0] <= v(x) && b.hi[0] >= v(x + 2) && b.lo[1] <= v(z) && b.hi[1] >= v(z + 1)).map(|b| b.top_in).fold(0.0, f64::max);
        assert!(top(tiers) > eye, "an eye on a 9 in tower top sees over the tall tower ({} in)", top(tiers));
        let mut planted = tiers.clone();
        for &k in &pick { planted.level_in[k] = 9.0; }
        assert!(top(&planted) < eye, "planted: a 9 in block must be seen over, or the assert above proves nothing");
        let feet: Vec<usize> = crate::boardgen::connect::wire(41, Symmetry::Point180, &l.cells).iter().flat_map(|c| [usize::from(c.low), usize::from(c.high)]).collect();
        assert!(pick.iter().all(|k| !feet.contains(k)), "a ladder ends on a tower cell");
    }

    #[test]
    fn fnv1a64_matches_the_published_vectors() {
        // test vectors of the FNV reference page (64-bit, FNV-1a)
        assert_eq!(fnv1a64(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a64(b"a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_f739_67e8);
    }

    #[test]
    fn a_town_yard_reads_ruins_a_plot_and_a_breach_read_forest_and_an_intact_house_reads_container() {
        let (mut ruins, mut forest, mut container) = (0, 0, 0);
        for seed in 1..=60 {
            let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
            let p = to_plain(&l);
            let roofed: Vec<u16> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).map(|c| (c.z * l.nx + c.x) as u16).collect();
            assert_eq!(p.solid_cells, roofed, "seed {seed}: every intact house cell and nothing else is solid");
            let board = Terrain::build(&p);
            let landmark = |c: &crate::boardgen::Cell| l.landmarks.iter().find(|m| m.cells().any(|i| i == c.z * 16 + c.x)).map(|m| m.kind.terrain_class()).filter(|&k| k != NONE);
            for c in &l.cells {
                let want = match (landmark(c), c.lot_kind, c.level) {
                    (Some(k), _, _) => k,
                    (_, LotKind::Hazard, _) => DANGEROUS,
                    (_, LotKind::Terrace, 0) if !c.street => RUINS,
                    (_, LotKind::Rough | LotKind::Wall, 0) => FOREST,
                    (_, LotKind::Roofed, _) => CONTAINER,
                    _ => NONE,
                };
                ruins += usize::from(want == RUINS);
                forest += usize::from(want == FOREST);
                container += usize::from(want == CONTAINER && c.lot_kind == LotKind::Roofed);
                assert_eq!(board.type_at(ground(c.x, c.z)), want, "seed {seed} cell ({}, {}) {:?} level {}", c.x, c.z, c.lot_kind, c.level);
            }
            // the same cells on a Deepworks layout of the same seed never read the town classes
            let d = generate(seed, Symmetry::Point180);
            let deep_plain = to_plain(&d);
            assert!(deep_plain.solid_cells.is_empty(), "seed {seed}: a Deepworks board writes no solid cells (D-F2 is its own step)");
            let deep = Terrain::build(&deep_plain);
            assert!(d.cells.iter().all(|c| ![RUINS, FOREST].contains(&deep.type_at(ground(c.x, c.z)))), "seed {seed}: a Deepworks board reads a town class");
        }
        assert!(ruins > 0 && forest > 0 && container > 0, "the class mapping proved nothing: {ruins} ruins, {forest} forest, {container} container cells");
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

    #[test]
    fn the_town_hash_pins_seed_42_and_a_class_change_moves_it() {
        let l = generate_themed(42, Symmetry::Point180, Theme::RuinTown);
        let p = to_plain(&l);
        assert_eq!(format!("{:016x}", board_hash(&p)), PINNED_TOWN_42, "the town generator or its class mapping changed: re-pin on purpose");
        let mut moved = p.clone();
        moved.cells.pop();
        assert_ne!(board_hash(&moved), board_hash(&p), "a changed class must change the hash");
    }

    // re-pinned 21.11. (silhouette round): slender 2 x 1 town towers, one tower per wall run, 65 % intact houses;
    // re-pinned 21.11. (L-RF1 F3, 593b1257da9d696f -> df767026f7ddebdd): the town writes its intact houses as solid_cells
    // re-pinned 22.11. (roofs plan K2, df767026f7ddebdd -> 719d45f5c81b7df2): the town raised minimum 23 -> 15 % (fewer filler slabs)
    // re-pinned 22.11. (roofs plan K3, 719d45f5c81b7df2 -> c35f70fddda0af2c): infill houses between the bands
    const PINNED_TOWN_42: &str = "c35f70fddda0af2c";
    const PINNED_SEED_42: &str = "cbcd64fada596527";
}
