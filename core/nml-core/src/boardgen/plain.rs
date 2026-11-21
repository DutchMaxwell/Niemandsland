//! The generated board as a header's `terrain` block: `Layout` -> `PlainTerrain` (heightfield plan step 3).
//! Core-only and pure; nothing reads it yet (the table-facing call is step 16). The board is materialised ONCE, here:
//! every other reader gets this object back and never re-derives it from the seed.
//!
//! [`GENERATOR_VERSION`] names the generator's output. Whoever changes what `generate(seed)` returns for a seed
//! bumps it and re-pins the hash test below, so a stored board is never taken for the output of a newer generator.
use crate::terrain::{CellParams, ContainerObb, Obb, PlainTerrain, TierGrid, CONTAINER, DANGEROUS, FOREST, NONE, RUINS};
use super::levels::LotKind;
use super::{Layout, Theme, LEVEL_IN};

pub const GENERATOR_VERSION: u32 = 1;

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
    // organic C1: on a board with free solids an intact house is a box (`solids::free_solids`), never painted cells
    let free = l.theme.budgets().free_solids;
    // one class per cell, row-major: a Hazard lot is DANGEROUS, a landmark's footprint carries the class of its kind
    // (a classless pump house leaves the cell as it was)
    let town = |c: &&super::Cell| -> Option<i32> {
        if l.theme != Theme::RuinTown { return None; }
        match (c.lot_kind, c.level) {
            (LotKind::Terrace, 0) if !c.street => Some(RUINS),
            (LotKind::Rough | LotKind::Wall, 0) => Some(FOREST),
            (LotKind::Roofed, _) if !free => Some(CONTAINER),
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
        level_in: l.cells.iter().map(|c| f64::from(LEVEL_IN[usize::from(c.level)])).collect(),
        ladders: l.connectors.iter().map(|c| [c.low, c.high]).collect(),
        stairs: Vec::new(),
    };
    let cell_params = CellParams {
        table_size_feet: [f64::from(l.board_in[0]) / 12.0, f64::from(l.board_in[1]) / 12.0],
        grid_rotation_degrees: 0.0, grid_size_inches: f64::from(l.cell_in), inches_to_meters: crate::IN2M,
    };
    let solids = super::solids::free_solids(l);
    let m_of = |v: [f64; 2]| [v[0] * crate::IN2M, v[1] * crate::IN2M];
    let sandbox = solids.iter().map(|s| Obb { c: m_of(s.c_in), he: m_of(s.he_in), yaw: s.yaw, kind: CONTAINER, slabs: Vec::new() }).collect();
    let containers = solids.iter().map(|s| ContainerObb { c: m_of(s.c_in), he: m_of(s.he_in), yaw: s.yaw }).collect();
    PlainTerrain { cells, sandbox, containers, tiers: Some(tiers), cell_params, ..Default::default() }
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
            let board = Terrain::build(&to_plain(&l));
            let landmark = |c: &crate::boardgen::Cell| l.landmarks.iter().find(|m| m.cells().any(|i| i == c.z * 16 + c.x)).map(|m| m.kind.terrain_class()).filter(|&k| k != NONE);
            // organic C3: a turned house box may leave a corner of its lot open - the cell centre reads its box
            let boxes = super::super::solids::free_solids(&l);
            let covered = |c: &crate::boardgen::Cell| boxes.iter().any(|b| {
                let (sn, cs) = b.yaw.sin_cos();
                let d = [3.0 * c.x as f64 - 22.5 - b.c_in[0], 3.0 * c.z as f64 - 22.5 - b.c_in[1]];
                (d[0] * cs - d[1] * sn).abs() <= b.he_in[0] && (d[0] * sn + d[1] * cs).abs() <= b.he_in[1]
            });
            for c in &l.cells {
                let want = match (landmark(c), c.lot_kind, c.level) {
                    (Some(k), _, _) => k,
                    (_, LotKind::Hazard, _) => DANGEROUS,
                    (_, LotKind::Terrace, 0) if !c.street => RUINS,
                    (_, LotKind::Rough | LotKind::Wall, 0) => FOREST,
                    (_, LotKind::Roofed, _) if covered(c) => CONTAINER,
                    _ => NONE,
                };
                ruins += usize::from(want == RUINS);
                forest += usize::from(want == FOREST);
                container += usize::from(want == CONTAINER && c.lot_kind == LotKind::Roofed);
                assert_eq!(board.type_at(ground(c.x, c.z)), want, "seed {seed} cell ({}, {}) {:?} level {}", c.x, c.z, c.lot_kind, c.level);
            }
            // the same cells on a Deepworks layout of the same seed never read the town classes
            let d = generate(seed, Symmetry::Point180);
            let deep = Terrain::build(&to_plain(&d));
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

    /// The free board with its houses painted back as CONTAINER cells (the encoding before organic C1).
    fn painted_back(l: &crate::boardgen::Layout, p: &PlainTerrain) -> PlainTerrain {
        let m = grid_margin(l) as f64;
        let mut q = PlainTerrain { sandbox: Vec::new(), containers: Vec::new(), ..p.clone() };
        q.cells.extend(l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).map(|c| [c.x as f64 + m, c.z as f64 + m, f64::from(CONTAINER)]));
        q
    }

    /// The free board with every house box widened back to its whole lot at yaw 0 (the C1 encoding).
    fn unturned(l: &crate::boardgen::Layout, p: &PlainTerrain) -> PlainTerrain {
        let lot = |id: u16| l.lots.iter().find(|o| o.id == id).expect("lot");
        let boxes: Vec<_> = super::super::solids::free_solids(l).iter().map(|b| {
            let o = lot(b.lot);
            ([((o.x as f64 + o.w as f64 * 0.5) * 3.0 - 24.0) * crate::IN2M, ((o.z as f64 + o.h as f64 * 0.5) * 3.0 - 24.0) * crate::IN2M], [o.w as f64 * 1.5 * crate::IN2M, o.h as f64 * 1.5 * crate::IN2M])
        }).collect();
        PlainTerrain {
            sandbox: boxes.iter().map(|&(c, he)| Obb { c, he, yaw: 0.0, kind: CONTAINER, slabs: Vec::new() }).collect(),
            containers: boxes.iter().map(|&(c, he)| ContainerObb { c, he, yaw: 0.0 }).collect(),
            ..p.clone()
        }
    }

    #[test]
    fn a_turned_house_blocks_exactly_its_box() {
        use crate::sight::{has_los, zones_of_at, Cyl};
        let (mut turned, mut planted) = (0, 0);
        for seed in 1..=60 {
            let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
            let p = to_plain(&l);
            let t = Terrain::build(&p);
            let zones = zones_of_at(&t, crate::acts::CURRENT_RULES_EPOCH);
            let bare = zones_of_at(&Terrain::build(&PlainTerrain { containers: Vec::new(), ..p.clone() }), crate::acts::CURRENT_RULES_EPOCH);
            let eye = |q: [f64; 2]| Cyl { c: q, r: 0.0, y0: 0.0, y1: 1.25 * crate::IN2M };
            for s in p.sandbox.iter().filter(|s| s.yaw != 0.0) {
                turned += 1;
                let (sn, cs) = s.yaw.sin_cos();
                // a point in the box's own frame (u along local +X, v along local +Z), back to the world
                let at = |u: f64, v: f64| [s.c[0] + u * cs + v * sn, s.c[1] - u * sn + v * cs];
                let w = |q: [f64; 2]| [q[0] as f32, 0.0, q[1] as f32];
                for (u, v) in [(0.0, 0.0), (0.9, 0.9), (-0.9, 0.9), (0.9, -0.9), (-0.9, -0.9)] {
                    assert_eq!(t.type_at(w(at(u * s.he[0], v * s.he[1]))), CONTAINER, "seed {seed}: inside the turned house reads open");
                }
                let out = 0.05 * crate::IN2M;
                for q in [at(s.he[0] + out, 0.0), at(-s.he[0] - out, 0.0), at(0.0, s.he[1] + out), at(0.0, -s.he[1] - out)] {
                    assert_ne!(t.type_at(w(q)), CONTAINER, "seed {seed}: just outside the turned house reads solid");
                }
                // an eye line across the box's middle is stopped; with the sight boxes omitted (planted) it is not
                let (a, b) = (eye(at(-s.he[0] - 4.0 * crate::IN2M, 0.0)), eye(at(s.he[0] + 4.0 * crate::IN2M, 0.0)));
                assert!(!has_los(&a, &b, false, &zones, &[]), "seed {seed}: an eye line through the turned house is clear");
                planted += usize::from(has_los(&a, &b, false, &bare, &[]));
            }
        }
        assert!(turned >= 100 && planted > 0, "the check proved too little: {turned} turned houses, {planted} lines the planted fault opened");
    }

    /// Movement and sight disagreements between the free board `p` and the painted board `q`: `type_at` at 9 interior
    /// points per house cell, and eye rays (1.25 in) across each house cell, through it and 0.3 in beside it.
    fn disagreements(l: &crate::boardgen::Layout, p: &PlainTerrain, q: &PlainTerrain) -> usize {
        use crate::sight::{has_los, zones_of_at, Cyl};
        let (a, b) = (Terrain::build(p), Terrain::build(q));
        let (za, zb) = (zones_of_at(&a, crate::acts::CURRENT_RULES_EPOCH), zones_of_at(&b, crate::acts::CURRENT_RULES_EPOCH));
        let w = |x: f64, z: f64| [((-24.0 + x) * crate::IN2M) as f32, 0.0, ((-24.0 + z) * crate::IN2M) as f32];
        let eye = |x: f64, z: f64| Cyl { c: [(-24.0 + x) * crate::IN2M, (-24.0 + z) * crate::IN2M], r: 0.0, y0: 0.0, y1: 1.25 * crate::IN2M };
        let mut bad = 0;
        for c in l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed) {
            let (x0, z0) = (3.0 * c.x as f64, 3.0 * c.z as f64);
            for (fx, fz) in [0.25, 1.5, 2.75].into_iter().flat_map(|u| [0.25, 1.5, 2.75].map(move |v| (u, v))) {
                bad += usize::from(a.type_at(w(x0 + fx, z0 + fz)) != b.type_at(w(x0 + fx, z0 + fz)));
            }
            for off in [1.5, -0.3, 3.3] {
                for (p0, p1) in [((x0 - 4.0, z0 + off), (x0 + 7.0, z0 + off)), ((x0 + off, z0 - 4.0), (x0 + off, z0 + 7.0))] {
                    let (e0, e1) = (eye(p0.0, p0.1), eye(p1.0, p1.1));
                    bad += usize::from(has_los(&e0, &e1, false, &za, &[]) != has_los(&e0, &e1, false, &zb, &[]));
                }
            }
        }
        bad
    }

    #[test]
    fn a_free_house_blocks_like_its_cells() {
        let (mut houses, mut planted) = (0, 0);
        for seed in 1..=60 {
            let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
            let p = to_plain(&l);
            let m = grid_margin(&l) as f64;
            let house = |c: &&[f64; 3]| l.cells.iter().any(|h| h.lot_kind == LotKind::Roofed && [h.x as f64 + m, h.z as f64 + m] == [c[0], c[1]]);
            assert!(!p.cells.iter().any(|c| house(&c)), "seed {seed}: a house was still painted");
            houses += p.sandbox.len();
            assert_eq!(p.sandbox.len(), p.containers.len());
            let p = unturned(&l, &p);   // the re-encoding check: each house as its whole lot at yaw 0 (C3 turns them; see a_turned_house_blocks_exactly_its_box)
            let q = painted_back(&l, &p);
            assert_eq!(disagreements(&l, &p, &q), 0, "seed {seed}: the free houses block other than their cells");
            // planted fault: the sight box omitted - the house must stop reading as a sight blocker
            planted += disagreements(&l, &PlainTerrain { containers: Vec::new(), ..p.clone() }, &q);
        }
        assert!(houses >= 120, "only {houses} free houses on 60 boards: the check proved too little");
        assert!(planted > 0, "omitting every sight box went unnoticed: the sight half of the check cannot fail");
    }

    #[test]
    fn a_free_board_is_an_exact_half_turn() {
        for seed in 1..=200 {
            let p = to_plain(&generate_themed(seed, Symmetry::Point180, Theme::RuinTown));
            for s in &p.sandbox {
                let twin = p.sandbox.iter().any(|t| t.c == [-s.c[0], -s.c[1]] && t.he == s.he && t.yaw == s.yaw && t.kind == s.kind);
                assert!(twin, "seed {seed}: the box at {:?} has no exact half-turn twin", s.c);
            }
            assert!(p.containers.iter().zip(&p.sandbox).all(|(c, s)| c.c == s.c && c.he == s.he && c.yaw == s.yaw), "seed {seed}: sight and movement boxes differ");
        }
    }

    #[test]
    fn the_cell_only_readers_see_a_free_house() {
        let (mut houses, mut pieces) = (0, 0);
        for seed in 1..=60 {
            let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
            let p = to_plain(&l);
            let t = Terrain::build(&p);
            let cells = crate::objectives::Cells::from_terrain(&t);
            for s in &p.sandbox {
                houses += 1;
                // the AI's centre line straight through the house, end to end 1 in outside it, reads blocked
                let (c, ext) = ([s.c[0] as f32, s.c[1] as f32], (s.he[0].hypot(s.he[1]) + crate::IN2M) as f32);
                let (a, b) = ([c[0] - ext, 0.0, c[1]], [c[0] + ext, 0.0, c[1]]);
                assert!(t.los_blocked_at(a, b, crate::acts::CURRENT_RULES_EPOCH), "seed {seed}: an AI line through the house at {:?} reads clear", s.c);
                // an objective marker at the house centre is illegal ground
                let (x_in, z_in) = ((s.c[0] / crate::IN2M).round() as i64, (s.c[1] / crate::IN2M).round() as i64);
                assert_eq!(cells.type_at_in(x_in, z_in), CONTAINER, "seed {seed}: a marker may land inside the house at {:?}", s.c);
            }
            // the net's tokens keep the painted yards, plots and pools AND get every house
            let got = t.pieces();
            assert!(p.sandbox.iter().all(|s| got.contains(s)), "seed {seed}: a house is missing from the net's pieces");
            assert!(got.iter().any(|q| q.kind != CONTAINER), "seed {seed}: the net lost the painted yards / plots / pools");
            pieces += got.len();
        }
        assert!(houses >= 120 && pieces > houses, "the check proved too little: {houses} houses, {pieces} pieces");
    }

    // re-pinned 21.11. (silhouette round): slender 2 x 1 town towers, one tower per wall run, 65 % intact houses
    // re-pinned 21.11. (organic C3): the free house boxes turn off the table axes, inscribed in their lots
    const PINNED_TOWN_42: &str = "8d88ebacc277f1c1";
    const PINNED_SEED_42: &str = "cbcd64fada596527";
}
