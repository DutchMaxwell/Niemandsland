//! `nml_core::boardgen` (heightfield stage): determinism, budgets, reachability, mirror symmetry, 48 x 48 in.
//! The reachability and ascent checks are written here from scratch, not taken from the module.
use std::collections::{BTreeSet, HashSet, VecDeque};
use nml_core::boardgen::{budget, generate, generate_themed, ConnectorKind, Landmark, LandmarkKind, Layout, Symmetry, Theme, BOARD_IN, DEPLOY_DEPTH_CELLS, GRID, HIGH_PERMILLE, RAISED_PERMILLE};

/// Two cells as (x, z) pairs: one sight line.
type CellPair = ((usize, usize), (usize, usize));
const BOTH: [Symmetry; 2] = [Symmetry::Point180, Symmetry::BalancedFree];

fn nbrs(i: usize) -> Vec<usize> {
    let (x, z) = (i % GRID, i / GRID);
    let mut v = Vec::new();
    if x > 0 { v.push(i - 1); }
    if x + 1 < GRID { v.push(i + 1); }
    if z > 0 { v.push(i - GRID); }
    if z + 1 < GRID { v.push(i + GRID); }
    v
}

/// The cells a tank cluster or a crane base fills: nobody walks there.
fn solid(l: &Layout) -> Vec<bool> {
    let mut s = vec![false; GRID * GRID];
    for lm in l.landmarks.iter().filter(|lm| matches!(lm.kind, LandmarkKind::TankCluster | LandmarkKind::Crane)) {
        for z in lm.z..lm.z + lm.h { for x in lm.x..lm.x + lm.w { s[z * GRID + x] = true; } }
    }
    for c in l.cells.iter().filter(|c| matches!(c.lot_kind, nml_core::boardgen::LotKind::Roofed | nml_core::boardgen::LotKind::Tower)) { s[c.z * GRID + c.x] = true; }   // intact houses, tall towers
    s
}

/// Walkable graph: neighbours at the same level, plus every connector, minus the solid cells. Returns what a walk from
/// `player`'s band reaches.
fn reach(l: &Layout, player: u8) -> Vec<bool> {
    let sol = solid(l);
    let mut adj: Vec<Vec<usize>> = (0..GRID * GRID).map(|i| nbrs(i).into_iter().filter(|&j| l.cells[j].level == l.cells[i].level && !sol[j] && !sol[i]).collect()).collect();
    for c in &l.connectors {
        adj[usize::from(c.low)].push(usize::from(c.high));
        adj[usize::from(c.high)].push(usize::from(c.low));
    }
    let mut seen = vec![false; GRID * GRID];
    let mut q: VecDeque<usize> = (0..GRID * GRID).filter(|&i| l.cells[i].deploy == player).collect();
    q.iter().for_each(|&i| seen[i] = true);
    while let Some(u) = q.pop_front() {
        for &v in &adj[u] { if !seen[v] { seen[v] = true; q.push_back(v); } }
    }
    seen
}

#[test]
fn determinism_over_100_seeds() {
    let mut distinct = HashSet::new();
    for seed in 1..=100 {
        for sym in BOTH {
            let (a, b) = (generate(seed, sym), generate(seed, sym));
            assert_eq!(a.to_json(), b.to_json(), "seed {seed} {sym:?}: not byte-identical");
            if sym == Symmetry::Point180 { distinct.insert(a.to_json()); }
        }
    }
    assert!(distinct.len() >= 99, "100 seeds gave {} distinct boards", distinct.len());
}

#[test]
fn board_is_48_by_48_with_24_in_between_the_bands() {
    for sym in BOTH {
        let l = generate(7, sym);
        assert_eq!((l.board_in, l.nx, l.nz, l.cell_in), (BOARD_IN, 16, 16, 3));
        assert_eq!(l.cells.len(), 256);
        let rows = |p: u8| (0..GRID).filter(|&z| (0..GRID).all(|x| l.cell(x, z).deploy == p)).count();
        assert_eq!((rows(1), rows(2), l.deploy_depth_cells), (4, 4, DEPLOY_DEPTH_CELLS), "bands are 4 cells = 12 in deep");
        assert_eq!((0..GRID).filter(|&z| l.cell(0, z).deploy == 0).count() * 3, 24, "24 in between the bands");
    }
}

#[test]
fn arteries_are_wide_flat_and_staggered() {
    for seed in 1..=100 {
        for sym in BOTH {
            let l = generate(seed, sym);
            for a in &l.arteries {
                assert!(a.width_in * 2 >= 9, "artery {a:?} narrower than 4.5 in");
                for z in a.z..a.z + a.h { for x in a.x..a.x + a.w {
                    assert!(l.cell(x, z).level == 0 && l.cell(x, z).street, "seed {seed}: artery cell ({x},{z}) is not flat street");
                }}
            }
            let straight = (0..GRID).filter(|&x| l.cells.iter().filter(|c| c.x == x).all(|c| c.street)).count();
            assert_eq!(straight, 0, "seed {seed} {sym:?}: a street runs edge to edge");
        }
    }
}

#[test]
fn budgets_hold_and_sheer_height_stays_within_9_in_over_1000_seeds() {
    let (r, h) = (budget(RAISED_PERMILLE), budget(HIGH_PERMILLE));
    let (mut retried, t0) = (0, std::time::Instant::now());
    for seed in 1..=500 {
        for sym in BOTH {
            let l = generate(seed, sym);
            retried += usize::from(l.attempt > 0);
            assert!(l.problems().is_empty(), "seed {seed} {sym:?} attempt {}: {:?}\n{}", l.attempt, l.problems(), l.to_ascii());
            assert!((r.0..=r.1).contains(&l.raised()), "seed {seed}: raised {}", l.raised());
            assert!((h.0..=h.1).contains(&l.high()), "seed {seed}: high {}", l.high());
            assert!(l.cells.iter().all(|c| c.level <= 3 && (c.level < 2 || c.deploy == 0)), "level 2 or 3 in a band, or above 3");
            assert!(l.max_drop_in() <= 9, "seed {seed}: sheer drop {} in", l.max_drop_in());
        }
    }
    eprintln!("1000 boards in {:?}, {retried} needed a later sub-seed", t0.elapsed());
    assert!(retried <= 300, "{retried} of 1000 boards needed a retry: the first draw is too often wrong");
}

#[test]
fn every_cell_is_reachable_from_both_bands_by_climbing_only_through_connectors() {
    for seed in 1..=200 {
        for sym in BOTH {
            let l = generate(seed, sym);
            for c in &l.connectors {
                let (lo, hi) = (usize::from(c.low), usize::from(c.high));
                assert!(nbrs(lo).contains(&hi) && l.cells[lo].level + 1 == l.cells[hi].level, "seed {seed}: {c:?} is no one-level step between neighbours");
            }
            for p in [1, 2] {
                let seen = reach(&l, p);
                let sol = solid(&l);
                assert!(seen.iter().zip(&sol).all(|(&s, &x)| s || x), "seed {seed} {sym:?}: {} cells unreachable from player {p}\n{}", seen.iter().zip(&sol).filter(|(&s, &x)| !s && !x).count(), l.to_ascii());
            }
        }
    }
}

#[test]
fn every_raised_island_has_two_ascents_where_it_has_room_for_two() {
    for seed in 1..=200 {
        for sym in BOTH {
            let l = generate(seed, sym);
            let mut island = vec![usize::MAX; 256];
            for s in 0..256 {
                if island[s] != usize::MAX { continue; }
                let mut q = VecDeque::from([s]);
                island[s] = s;
                while let Some(i) = q.pop_front() {
                    for j in nbrs(i) { if island[j] == usize::MAX && l.cells[j].level == l.cells[s].level { island[j] = s; q.push_back(j); } }
                }
            }
            for root in (0..256).filter(|&s| island[s] == s && l.cells[s].level >= 1) {
                let mut room = 0;
                for h in (0..256).filter(|&h| island[h] == root) {
                    room += nbrs(h).into_iter().filter(|&n| l.cells[n].level + 1 == l.cells[h].level).count();
                }
                let have = l.connectors.iter().filter(|c| island[usize::from(c.high)] == root).count();
                assert!(have >= room.min(2), "seed {seed} {sym:?}: island {root} has {have} ascents, room for {room}");
            }
        }
    }
}

#[test]
fn point180_is_an_exact_half_turn() {
    for seed in 1..=100 {
        let l = generate(seed, Symmetry::Point180);
        for i in 0..256 {
            let (a, b) = (&l.cells[i], &l.cells[255 - i]);
            assert_eq!((a.level, a.lot_kind, a.street, a.deploy), (b.level, b.lot_kind, b.street, [0, 2, 1][usize::from(b.deploy)]), "seed {seed}: cell {i}");
        }
        let set: BTreeSet<_> = l.connectors.iter().map(|c| (c.kind, c.low, c.high)).collect();
        for c in &l.connectors {
            assert!(set.contains(&(c.kind, 255 - c.low, 255 - c.high)), "seed {seed}: {c:?} has no mirror");
        }
    }
}

#[test]
fn a_town_is_an_exact_half_turn_too() {
    for seed in 1..=200 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        for i in 0..256 {
            let (a, b) = (&l.cells[i], &l.cells[255 - i]);
            assert_eq!((a.level, a.lot_kind, a.street, a.deploy), (b.level, b.lot_kind, b.street, [0, 2, 1][usize::from(b.deploy)]), "seed {seed}: cell {i}");
        }
        let set: BTreeSet<_> = l.connectors.iter().map(|c| (c.kind, c.low, c.high)).collect();
        assert!(l.connectors.iter().all(|c| set.contains(&(c.kind, 255 - c.low, 255 - c.high))), "seed {seed}: a ladder has no mirror");
    }
}

#[test]
fn balanced_free_has_equal_halves_but_is_not_a_mirror() {
    let mut mirrored = 0;
    for seed in 1..=100 {
        let l = generate(seed, Symmetry::BalancedFree);
        let half = |lo: usize, f: &dyn Fn(u8) -> bool| l.cells[lo..lo + 128].iter().filter(|c| f(c.level)).count();
        assert_eq!(half(0, &|v| v >= 1), half(128, &|v| v >= 1), "seed {seed}: raised area per half");
        assert_eq!(half(0, &|v| v >= 2), half(128, &|v| v >= 2), "seed {seed}: level-2 area per half");
        assert_eq!(half(0, &|v| v == 3), half(128, &|v| v == 3), "seed {seed}: tower area per half");
        mirrored += usize::from((0..256).all(|i| l.cells[i].level == l.cells[255 - i].level));
    }
    assert!(mirrored <= 10, "{mirrored} of 100 free boards are mirror images");
}

#[test]
fn the_checks_can_fail() {
    let good = generate(3, Symmetry::Point180);
    assert!(good.problems().is_empty());
    let mut flat = good.clone();
    flat.cells.iter_mut().for_each(|c| c.level = 0);
    assert!(!flat.problems().is_empty(), "a flat board must miss both budgets");
    let mut no_ways = good.clone();
    no_ways.connectors.clear();
    assert!(no_ways.problems().contains(&"board is not one connected walkable area"));
    assert!(reach(&no_ways, 1).iter().any(|&s| !s), "the test's own walk must see the cut too");
    let mut flat_towers = good.clone();
    flat_towers.cells.iter_mut().filter(|c| c.level == 3).for_each(|c| c.level = 2);
    assert!(flat_towers.problems().contains(&"level-3 area outside its budget"), "a board without towers misses the tower budget");
    let mut cut_towers = good.clone();
    let tower_cells: Vec<_> = (0..256).filter(|&i| good.cells[i].level == 3).collect();
    cut_towers.connectors.retain(|c| !tower_cells.contains(&usize::from(c.high)));
    assert!(reach(&cut_towers, 1).iter().zip(&cut_towers.cells).any(|(&s, c)| !s && c.level == 3), "the test's own walk must see towers without a ladder");
    let mut gutted = generate_themed(41, Symmetry::Point180, Theme::RuinTown);
    assert!(gutted.problems().is_empty());
    gutted.lots.iter_mut().filter(|l| l.kind == nml_core::boardgen::LotKind::Roofed).for_each(|l| l.kind = nml_core::boardgen::LotKind::Block);
    assert!(gutted.problems().contains(&"too few intact houses"), "a town whose houses are all ruins misses the intact floor");
    let mut on_a_foot = good.clone();
    let foot = usize::from(good.connectors[0].low);
    on_a_foot.landmarks.push(Landmark { kind: LandmarkKind::Sump, x: foot % GRID, z: foot / GRID, w: 1, h: 1, turn: 0 });
    assert!(on_a_foot.problems().contains(&"a landmark stands on a ladder foot"));
    let mut walled = good.clone();
    walled.landmarks = (0..GRID).map(|x| Landmark { kind: LandmarkKind::Crane, x, z: 8, w: 1, h: 1, turn: 0 }).collect();
    assert!(walled.problems().contains(&"board is not one connected walkable area"), "a solid wall across the board must cut it");
    assert!(reach(&walled, 1).iter().zip(&walled.cells).any(|(&s, c)| !s && c.deploy == 2), "the test's own walk must see the cut too");
    let mut none = good.clone();
    none.landmarks.clear();
    assert!(none.problems().contains(&"landmark count outside its budget"));
    let mut no_ascents = good.clone();
    let ground = |l: &Layout, c: &nml_core::boardgen::Connector| l.cells[usize::from(c.low)].level == 0;
    let kept: Vec<_> = no_ascents.connectors.iter().filter(|c| !ground(&good, c)).copied().collect();
    no_ascents.connectors = kept;
    assert!(no_ascents.problems().contains(&"an island has fewer ascents than it could have (max 2)"));
    assert!(reach(&no_ascents, 1).iter().any(|&s| !s), "the test's own walk must see the missing ascents too");
}

#[test]
fn every_connector_is_a_ladder_and_no_stair_exists_over_1000_seeds() {
    // Maintainer decision 20.11.: models cannot stand on stairs and stair steps are not 3 in units, so every level change is a ladder.
    let mut ladders = 0;
    for seed in 1..=500 {
        for sym in BOTH {
            let l = generate(seed, sym);
            assert!(l.connectors.iter().all(|c| c.kind == ConnectorKind::Ladder), "seed {seed} {sym:?}: a connector is not a ladder");
            assert!(!l.to_json().contains("Stair"), "seed {seed} {sym:?}: the JSON still names a stair");
            ladders += l.connectors.len();
        }
    }
    assert!(ladders >= 1000, "only {ladders} ladders over 1000 boards: the generator stopped wiring");
}

#[test]
fn json_round_trips_and_ascii_has_one_line_per_row() {
    let l = generate(11, Symmetry::Point180);
    let back: Layout = serde_json::from_str(&l.to_json()).unwrap();
    assert_eq!(l, back);
    let art = l.to_ascii();
    assert_eq!(art.lines().count(), 16);
    assert!(art.lines().all(|r| r.chars().count() == 16));
}

/// Share of eye-to-eye rays a tier stops, over the cell pairs given. Eyes are 1.25 in above the floor they stand on;
/// `cap` flattens every level above it (3 -> 2 gives the board as it was before the towers); `solids` lets a tank cluster
/// or crane base stop a ray like the 2.5 in container the core knows.
fn blocked_share(l: &Layout, cap: u8, pairs: &[CellPair], solids: bool) -> f64 {
    blocked_share_roofs(l, cap, pairs, solids, nml_core::terrain::CONTAINER_HEIGHT_IN)
}

/// `blocked_share` with the roofed houses stopping a ray at `roof_in` (the core reads a house as 2.5 in; the look draws the ridge at 4.0-5.2 in).
fn blocked_share_roofs(l: &Layout, cap: u8, pairs: &[CellPair], solids: bool, roof_in: f64) -> f64 {
    let sol = solid(l);
    let h = |x: f64, z: f64| {
        let (cx, cz) = ((x / 3.0) as usize, (z / 3.0) as usize);
        let floor = f64::from(nml_core::boardgen::LEVEL_IN[usize::from(l.cell(cx, cz).level.min(cap))]);
        let top = match l.cell(cx, cz).lot_kind { nml_core::boardgen::LotKind::Roofed => roof_in, nml_core::boardgen::LotKind::Tower => nml_core::boardgen::plain::TOWER_IN, _ => nml_core::terrain::CONTAINER_HEIGHT_IN };
        if solids && sol[cz * GRID + cx] { floor.max(top) } else { floor }
    };
    let blocked = pairs.iter().filter(|&&((x1, z1), (x2, z2))| {
        let (a, b) = ((x1 as f64 * 3.0 + 1.5, z1 as f64 * 3.0 + 1.5), (x2 as f64 * 3.0 + 1.5, z2 as f64 * 3.0 + 1.5));
        let (ya, yb) = (h(a.0, a.1) + 1.25, h(b.0, b.1) + 1.25);
        (1..100).any(|k| { let t = f64::from(k) / 100.0; h(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t) > ya + (yb - ya) * t })
    }).count();
    blocked as f64 / pairs.len().max(1) as f64
}

/// Band 1 row 1 against band 2 row 14, every column pair: the sight lines of the opening turn.
fn band_pairs() -> Vec<CellPair> { (0..GRID).flat_map(|x1| (0..GRID).map(move |x2| ((x1, 1), (x2, 14)))).collect() }
/// Every pair of level-2 roof cells (the towers themselves are no endpoints): the roof-top duels.
fn roof_pairs(l: &Layout) -> Vec<CellPair> {
    let roofs: Vec<_> = l.cells.iter().filter(|c| c.level == 2).map(|c| (c.x, c.z)).collect();
    roofs.iter().enumerate().flat_map(|(i, &a)| roofs[i + 1..].iter().map(move |&b| (a, b))).collect()
}

#[test]
fn census_of_towers_and_sight() {
    let (mut towers, mut tiers, mut n) = (Vec::new(), [0usize; 4], 0.0);
    let (mut band, mut roof) = ([0.0, 0.0, 0.0], [0.0, 0.0]);
    for seed in 1..=500 {
        for sym in BOTH {
            let l = generate(seed, sym);
            towers.push(l.towers());
            for c in &l.cells { tiers[usize::from(c.level)] += 1; }
            n += 1.0;
            for (k, cap) in [3u8, 2].into_iter().enumerate() {
                band[k] += blocked_share(&l, cap, &band_pairs(), true);
                roof[k] += blocked_share(&l, cap, &roof_pairs(&l), true);
            }
            band[2] += blocked_share(&l, 3, &band_pairs(), false);
        }
    }
    let share = tiers.map(|t| t as f64 / (n * 256.0));
    eprintln!("tier shares {share:?}, tower cells {:?}..{:?}, band rays blocked {:.4} (before towers {:.4}, before landmarks {:.4}), roof rays blocked {:.4} (before towers {:.4})",
        towers.iter().min(), towers.iter().max(), band[0] / n, band[1] / n, band[2] / n, roof[0] / n, roof[1] / n);
    assert!((0.008..=0.03).contains(&share[3]), "towers are rare: {:.4} of all cells", share[3]);
    assert!(towers.iter().all(|&t| (2..=6).contains(&t)), "a board has 2 to 6 tower cells");
    assert!(band[0] / n <= band[1] / n + 0.01, "towers must not dim the opening-turn sight lines: {:.4} vs {:.4}", band[0] / n, band[1] / n);
    assert!(band[0] / n <= band[2] / n + 0.03, "landmarks must not dim the opening-turn sight lines much: {:.4} vs {:.4}", band[0] / n, band[2] / n);
    assert!(roof[0] / n <= 0.30, "towers hide at most 30 % of roof-to-roof pairs: {:.4}", roof[0] / n);
}

#[test]
fn a_tower_is_nine_inches_up_a_ladder_chain_from_the_ground_and_never_in_a_band() {
    let mut boards_with_a_tower_ladder = 0;
    for seed in 1..=200 {
        for sym in BOTH {
            let l = generate(seed, sym);
            let lv = |i: u16| l.cells[usize::from(i)].level;
            assert!((1..=3).contains(&(l.towers() / 2)), "seed {seed} {sym:?}: {} tower cells", l.towers());
            assert!(l.cells.iter().filter(|c| c.level == 3).all(|c| c.deploy == 0), "seed {seed}: a tower in a deployment band");
            let top: Vec<_> = l.connectors.iter().filter(|c| lv(c.high) == 3).collect();
            assert!(top.iter().all(|c| lv(c.low) == 2), "seed {seed}: a 9 in ladder must start at 6 in");
            boards_with_a_tower_ladder += usize::from(!top.is_empty());
            assert!((0..2).all(|p| reach(&l, p + 1).iter().zip(&l.cells).all(|(&seen, c)| seen || c.level < 3)), "seed {seed}: a tower is cut off");
        }
    }
    assert_eq!(boards_with_a_tower_ladder, 400, "every board with towers has a ladder up to them");
}

/// The cells of one landmark, written out here (not taken from the module).
fn footprint(lm: &Landmark) -> Vec<usize> { (lm.z..lm.z + lm.h).flat_map(|z| (lm.x..lm.x + lm.w).map(move |x| z * GRID + x)).collect() }

#[test]
fn landmarks_are_mirrored_pairs_on_the_right_ground_and_never_on_a_ladder_foot() {
    for seed in 1..=300 {
        for sym in BOTH {
            let l = generate(seed, sym);
            let lms = &l.landmarks;
            assert!(lms.len().is_multiple_of(2) && (2..=4).contains(&lms.len()), "seed {seed} {sym:?}: {} pieces", lms.len());
            let feet: HashSet<usize> = l.connectors.iter().flat_map(|c| [usize::from(c.low), usize::from(c.high)]).collect();
            let mut used = HashSet::new();
            for lm in lms {
                let cells = footprint(lm);
                assert!(cells.iter().all(|i| l.cells[*i].deploy == 0 && !feet.contains(i) && used.insert(*i)), "seed {seed} {sym:?}: {lm:?} sits in a band, on a ladder foot or on another piece");
                let level = l.cells[cells[0]].level;
                match lm.kind {
                    LandmarkKind::PumpHouse => assert!((1..=2).contains(&level) && cells.iter().all(|&i| l.cells[i].level == level), "seed {seed}: a pump house needs one raised level"),
                    k => assert!(cells.iter().all(|&i| l.cells[i].level == 0 && !l.cells[i].street), "seed {seed}: {k:?} needs open level-0 ground"),
                }
                assert_eq!(cells.iter().all(|&i| l.cells[i].lot_kind == nml_core::boardgen::LotKind::Hazard), lm.kind == LandmarkKind::Sump, "seed {seed}: a sump is hazard ground");
                let twin = if sym == Symmetry::Point180 { Some(Landmark { x: 16 - lm.x - lm.w, z: 16 - lm.z - lm.h, turn: (lm.turn + 2) % 4, ..*lm }) } else { None };
                if let Some(t) = twin { assert!(lms.contains(&t), "seed {seed}: {lm:?} has no half-turn twin"); }
            }
            let kinds: BTreeSet<_> = lms.iter().map(|lm| lm.kind).collect();
            assert_eq!(kinds.len() * 2, lms.len(), "seed {seed} {sym:?}: every pair has its own kind");
            for k in kinds {
                let half = |top: bool| lms.iter().filter(|lm| lm.kind == k && ((lm.z + lm.h <= 8) == top)).map(|lm| lm.w * lm.h).sum::<usize>();
                assert!(half(true) > 0 && half(true) == half(false), "seed {seed} {sym:?}: {k:?} is not equal in both halves");
            }
        }
    }
}

#[test]
fn each_landmark_maps_to_a_terrain_class_the_core_already_has() {
    use nml_core::terrain::{is_dangerous, is_forbidden_rest, NONE};
    assert!(is_forbidden_rest(LandmarkKind::TankCluster.terrain_class()) && is_forbidden_rest(LandmarkKind::Crane.terrain_class()));
    assert!(is_dangerous(LandmarkKind::Sump.terrain_class()));
    assert_eq!(LandmarkKind::PumpHouse.terrain_class(), NONE);
    assert!(LandmarkKind::TankCluster.is_solid() && LandmarkKind::Crane.is_solid() && !LandmarkKind::Sump.is_solid() && !LandmarkKind::PumpHouse.is_solid());
}

#[test]
fn census_of_landmarks() {
    let (mut kinds, mut pieces, mut retried) = (std::collections::BTreeMap::new(), [0usize; 5], 0);
    for seed in 1..=500 {
        for sym in BOTH {
            let l = generate(seed, sym);
            retried += usize::from(l.attempt > 0);
            pieces[l.landmarks.len()] += 1;
            for lm in &l.landmarks { *kinds.entry(lm.kind).or_insert(0usize) += 1; }
        }
    }
    eprintln!("landmark pieces per board {pieces:?}, kinds {kinds:?}, retried {retried}");
    assert_eq!(pieces[0] + pieces[1] + pieces[3], 0, "a board has one or two pairs");
    assert!(pieces[2] >= 300 && pieces[4] >= 300, "one pair and two pairs both occur: {pieces:?}");
    assert!(kinds.len() == 4 && kinds.values().all(|&n| n >= 400), "every kind turns up often enough: {kinds:?}");
    assert!(retried <= 300, "landmarks must not add retries: {retried}");
}

/// The Deepworks board as JSON, seeds 1..=200 under both symmetries, FNV-1a 64 over the concatenation. Pinned on main
/// before the theme existed: a theme must never move a Deepworks board (the layout JSON itself, not only its plain form).
fn deepworks_json_pin() -> String {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for seed in 1..=200 { for sym in BOTH { for b in generate(seed, sym).to_json().bytes() { h = (h ^ u64::from(b)).wrapping_mul(0x0000_0100_0000_01b3); } } }
    format!("{h:016x}")
}

#[test]
fn deepworks_layouts_stay_byte_identical_over_200_seeds() {
    assert_eq!(deepworks_json_pin(), "ec25eb2d0382236f", "a theme (or any stage change) moved a Deepworks board");
    for seed in [3, 42] { assert_eq!(generate(seed, Symmetry::Point180).to_json(), generate_themed(seed, Symmetry::Point180, Theme::Deepworks).to_json()); }
}

#[test]
fn a_town_differs_from_the_deepworks_of_the_same_seed() {
    for seed in [3, 7, 25, 42] { for sym in BOTH {
        let (d, t) = (generate(seed, sym), generate_themed(seed, sym, Theme::RuinTown));
        assert_eq!((d.theme, t.theme), (Theme::Deepworks, Theme::RuinTown));
        assert_ne!(d.cells, t.cells, "seed {seed} {sym:?}: the town is the Deepworks board");
        assert!(!d.to_json().contains("theme") && t.to_json().contains(r#""theme":"RuinTown""#), "only a town names its theme");
        assert_eq!(serde_json::from_str::<Layout>(&t.to_json()).unwrap(), t, "a town survives its JSON");
        assert_eq!(serde_json::from_str::<Layout>(&d.to_json()).unwrap().theme, Theme::Deepworks, "an old layout without the key reads as Deepworks");
    }}
}

#[test]
fn town_budgets_hold_over_200_seeds() {
    let b = Theme::RuinTown.budgets();
    let (r, h, retried) = (budget(b.raised), budget(b.high), std::cell::Cell::new(0));
    let sym = Symmetry::Point180;   // the town is a Point180 board: its tower stage may find no site under BalancedFree
    for seed in 1..=200 {
        let l = generate_themed(seed, sym, Theme::RuinTown);
        retried.set(retried.get() + usize::from(l.attempt > 0));
        assert!((r.0..=r.1).contains(&l.raised()), "seed {seed} {sym:?}: raised {} outside {r:?}", l.raised());
        assert!((h.0..=h.1).contains(&l.high()), "seed {seed} {sym:?}: high {} outside {h:?}", l.high());
        assert_eq!(l.towers(), 4, "seed {seed} {sym:?}: the town has exactly one pair of slender 2 x 1 towers");
        assert!((b.landmark_pieces.0..=b.landmark_pieces.1).contains(&l.landmarks.len()));
        assert!(l.cells.iter().all(|c| c.level < 2 || c.deploy == 0), "level 2 or 3 in a band");
        assert!(l.max_drop_in() <= 9, "seed {seed}: sheer drop {} in", l.max_drop_in());
    }
    eprintln!("200 town boards, {} needed a later sub-seed", retried.get());
}

#[test]
fn town_boards_are_accepted_and_connected_over_200_seeds() {
    let sym = Symmetry::Point180;
    for seed in 1..=200 {
        let l = generate_themed(seed, sym, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed} {sym:?} attempt {}: {:?}\n{}", l.attempt, l.problems(), l.to_ascii());
        let sol = solid(&l);
        for p in [1, 2] {
            let seen = reach(&l, p);
            assert!(seen.iter().zip(&sol).all(|(&s, &x)| s || x), "seed {seed} {sym:?}: a cell is unreachable from player {p}\n{}", l.to_ascii());
        }
    }
}

/// What one batch of boards looks like: means over the boards, the shares the plan's census asks for.
#[derive(Default, Debug)]
struct Census {
    boards: f64, retried: f64, failed: f64,
    tier: [f64; 4],                       // mean cells per level
    lots: f64, lot_area: f64, open_lot_area: f64, lot_kinds: [f64; 8],     // mean count, lot cells, level-0 lot cells, count per LotKind
    ground: [f64; 5],                     // level-0 cells: street, hazard, yard (Terrace rest), other lot ground, empty ground
    ladders: f64, towers: f64, tower_blob: usize,
    band_blocked: f64, edge_lanes: f64, longest_lane_in: f64,
    kinds: [f64; 4],                      // boards carrying a TankCluster / Crane / Sump / PumpHouse
    dangerous_cells: f64, solid_cells: f64,
    pieces: f64, sight_pieces: f64, dangerous_pieces: f64,   // lots + landmark pieces; those with a raised cell or a solid; Hazard lots + pools
}

fn census(theme: Theme, sym: Symmetry, seeds: std::ops::RangeInclusive<i64>) -> Census {
    use nml_core::boardgen::LotKind;
    let mut c = Census::default();
    for seed in seeds {
        let l = generate_themed(seed, sym, theme);
        c.boards += 1.0;
        c.retried += f64::from(u8::from(l.attempt > 0));
        c.failed += f64::from(u8::from(!l.problems().is_empty()));
        let sol = solid(&l);
        for cell in &l.cells {
            c.tier[usize::from(cell.level)] += 1.0;
            if cell.level == 0 {
                let i = cell.z * GRID + cell.x;
                let k = if cell.lot_kind == LotKind::Hazard { 1 } else if cell.street { 0 } else if cell.lot_kind == LotKind::Terrace { 2 } else if cell.lot_kind != LotKind::Street { 3 } else { 4 };
                c.ground[if sol[i] { 4 } else { k }] += 1.0;
            }
        }
        c.lots += l.lots.len() as f64;
        for lot in &l.lots {
            c.lot_area += (lot.w * lot.h) as f64;
            c.lot_kinds[lot.kind as usize] += 1.0;
            c.open_lot_area += (0..lot.h).flat_map(|dz| (0..lot.w).map(move |dx| (lot.x + dx, lot.z + dz))).filter(|&(x, z)| l.cell(x, z).level == 0).count() as f64;
        }
        let raised_lot = |lot: &nml_core::boardgen::Lot| (0..lot.h).any(|dz| (0..lot.w).any(|dx| l.cell(lot.x + dx, lot.z + dz).level > 0));
        c.pieces += (l.lots.len() + l.landmarks.len()) as f64;
        c.sight_pieces += (l.lots.iter().filter(|lot| raised_lot(lot)).count() + l.landmarks.iter().filter(|lm| lm.kind.is_solid()).count()) as f64;
        c.dangerous_pieces += (l.lots.iter().filter(|lot| lot.kind == LotKind::Hazard).count() + l.landmarks.iter().filter(|lm| lm.kind == LandmarkKind::Sump).count()) as f64;
        c.ladders += l.connectors.len() as f64;
        c.towers += l.towers() as f64;
        c.band_blocked += blocked_share(&l, 3, &band_pairs(), true);
        let open = |x: usize, z: usize| l.cell(x, z).level == 0 && !sol[z * GRID + x];
        let (mut edge, mut longest) = (0, 0);
        for line in 0..GRID { for along_x in [true, false] {
            let (mut run, mut full) = (0, true);
            for k in 0..GRID {
                if if along_x { open(k, line) } else { open(line, k) } { run += 1; longest = longest.max(run) } else { run = 0; full = false }
            }
            edge += usize::from(full);
        }}
        c.edge_lanes += f64::from(u8::from(edge > 0));
        c.longest_lane_in += longest as f64 * 3.0;
        for lm in &l.landmarks { c.kinds[lm.kind as usize] += 0.0; }
        for (k, kind) in [LandmarkKind::TankCluster, LandmarkKind::Crane, LandmarkKind::Sump, LandmarkKind::PumpHouse].into_iter().enumerate() {
            c.kinds[k] += f64::from(u8::from(l.landmarks.iter().any(|lm| lm.kind == kind)));
        }
        c.dangerous_cells += l.cells.iter().filter(|x| x.lot_kind == LotKind::Hazard).count() as f64;
        c.solid_cells += sol.iter().filter(|&&s| s).count() as f64;
        // the largest connected blob of level-3 cells
        let mut seen = vec![false; GRID * GRID];
        for s in 0..GRID * GRID {
            if seen[s] || l.cells[s].level != 3 { continue }
            let (mut stack, mut n) = (vec![s], 0);
            seen[s] = true;
            while let Some(i) = stack.pop() { n += 1; for j in nbrs(i) { if !seen[j] && l.cells[j].level == 3 { seen[j] = true; stack.push(j) } } }
            c.tower_blob = c.tower_blob.max(n);
        }
    }
    c
}

fn census_report(name: &str, c: &Census) -> String {
    let n = c.boards;
    let g = |v: f64| v / n;
    let pct = |v: f64| 100.0 * v / n / 256.0;
    let ground: f64 = c.ground.iter().sum();
    format!("| {name} | {:.1} | {:.1} | {:.1} / {:.1} / {:.1} / {:.1} | {:.1} ({:.1} cells) | {:.1} / {:.1} / {:.1} / {:.1} / {:.1} / {:.1} / {:.1} | {:.1} % | {:.1} / {:.1} / {:.1} / {:.1} / {:.1} % | {:.1} | {:.1} (blob {}) | {:.1} % | {:.2} | {:.1} in | {:.0} / {:.0} / {:.0} / {:.0} % | {:.1} | {:.1} | {:.1} pieces: {:.0} % sight-blocking, {:.1} dangerous |",
        100.0 * c.retried / n, 100.0 * c.failed / n, pct(c.tier[0]), pct(c.tier[1]), pct(c.tier[2]), pct(c.tier[3]), g(c.lots), g(c.lot_area),
        g(c.lot_kinds[0]), g(c.lot_kinds[1]), g(c.lot_kinds[2]), g(c.lot_kinds[3]), g(c.lot_kinds[4]), g(c.lot_kinds[5]), g(c.lot_kinds[7]), 100.0 * c.open_lot_area / c.lot_area,
        100.0 * c.ground[0] / ground, 100.0 * c.ground[1] / ground, 100.0 * c.ground[2] / ground, 100.0 * c.ground[3] / ground, 100.0 * c.ground[4] / ground,
        g(c.ladders), g(c.towers), c.tower_blob, 100.0 * g(c.band_blocked), g(c.edge_lanes), g(c.longest_lane_in),
        100.0 * g(c.kinds[0]), 100.0 * g(c.kinds[1]), 100.0 * g(c.kinds[2]), 100.0 * g(c.kinds[3]), g(c.dangerous_cells), g(c.solid_cells), g(c.pieces), 100.0 * c.sight_pieces / c.pieces, g(c.dangerous_pieces))
}

#[test]
#[ignore = "measurement: NML_CENSUS_OUT=<file> cargo test --test boardgen census_of_a_town -- --ignored"]
fn census_of_a_town() {
    let mut out = String::from("| set | retried % | failed % | level 0/3/6/9 in % of cells | lots (area cells) | lots Street/Block/Terrace/Deck/Hazard/Rough/Roofed | open (level-0) share of lot cells | level-0 cells street/hazard/yard/other lot/empty-or-solid % | ladders | tower cells | opening-turn rays blocked | boards with an edge-to-edge lane | longest open lane | boards with fountain/statue/pool/hall % | hazard cells | solid cells | terrain pieces |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n");
    for (theme, name) in [(Theme::Deepworks, "Deepworks"), (Theme::RuinTown, "RuinTown")] {
        for sym in if theme == Theme::RuinTown { &BOTH[..1] } else { &BOTH[..] } {   // the town is a Point180 board
            out += &census_report(&format!("{name} {sym:?}"), &census(theme, *sym, 1..=1000));
            out.push('\n');
        }
    }
    eprintln!("{out}");
    if let Ok(path) = std::env::var("NML_CENSUS_OUT") { std::fs::write(path, &out).expect("census file"); }
}

/// Ruin-town windows of the lane's census (ds/ruintown_census.md): many small buildings, no straight open lane across the board.
#[test]
fn a_town_is_many_small_buildings_and_no_open_lane_runs_edge_to_edge() {
    let (mut lots, mut min_lots, mut retried, mut blocked, n) = (0, usize::MAX, 0, 0.0, 300);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
        lots += l.lots.len();
        min_lots = min_lots.min(l.lots.len());
        retried += usize::from(l.attempt > 0);
        blocked += blocked_share(&l, 3, &band_pairs(), true);
        assert!(l.lots.iter().all(|lot| lot.w * lot.h <= 6 && lot.w.max(lot.h) <= 3), "seed {seed}: a lot bigger than 3 x 2 cells");
        let sol = solid(&l);
        let open = |x: usize, z: usize| l.cell(x, z).level == 0 && !sol[z * GRID + x];   // written here, not taken from the module
        let lane = (0..GRID).any(|a| (0..GRID).all(|k| open(k, a)) || (0..GRID).all(|k| open(a, k)));
        assert!(!lane, "seed {seed}: an open lane runs from edge to edge\n{}", l.to_ascii());
    }
    let (mean, share, rays) = (lots as f64 / n as f64, retried as f64 / n as f64, blocked / n as f64);
    eprintln!("town lots mean {mean:.1} min {min_lots}, retried {share:.3}, opening-turn rays blocked {rays:.3}");
    assert!(mean >= 13.0 && min_lots >= 6, "lots per board: mean {mean:.1}, min {min_lots}");   // rows: fewer, deeper lots than the scatter (ds/ruintown_growth_census.md)
    assert!(share <= 0.97, "{share:.2} of the town boards needed a later sub-seed");
    assert!(rays >= 0.70, "the opening-turn sight lines are {rays:.2} blocked");
}

#[test]
fn only_the_town_asks_for_a_lane_free_board() {
    assert!(Theme::RuinTown.budgets().lane_free && !Theme::Deepworks.budgets().lane_free);
    let with_lane = (1..=200).filter(|&seed| generate(seed, Symmetry::Point180).has_edge_to_edge_lane()).count();
    assert!(with_lane > 0, "the Deepworks boards are left as they were: some still have a lane");
}

#[test]
fn a_town_tower_is_a_slender_2_by_1_block_nine_inches_up_with_a_ladder_from_six() {
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let tops: Vec<usize> = (0..GRID * GRID).filter(|&i| l.cells[i].level == 3 && l.cells[i].lot_kind != nml_core::boardgen::LotKind::Wall).collect();
        assert_eq!(tops.len(), 4, "seed {seed}: {} tower cells", tops.len());
        // two blocks of two (a cell and its right or lower neighbour), a half turn apart (silhouette round 21.11.: slender, not a 2 x 2 cube)
        let origins: Vec<usize> = tops.iter().copied().filter(|&i| (i % GRID + 1 < GRID && tops.contains(&(i + 1))) || tops.contains(&(i + GRID))).collect();
        assert_eq!(origins.len(), 2, "seed {seed}: the towers are not two 2 x 1 blocks\n{}", l.to_ascii());
        assert!(tops.iter().all(|&i| tops.contains(&(GRID * GRID - 1 - i))), "seed {seed}: the towers are not a half turn apart");
        assert!(tops.iter().all(|&i| l.cells[i].deploy == 0), "seed {seed}: a tower in a band");
        for o in origins {
            // the level-3 island the block belongs to (a wall tower may touch it) is reached by a ladder from a 6 in cell
            let mut seen = HashSet::from([o]);
            let mut queue = VecDeque::from([o]);
            while let Some(i) = queue.pop_front() { for j in nbrs(i) { if l.cells[j].level == 3 && seen.insert(j) { queue.push_back(j); } } }
            let ladders: Vec<_> = l.connectors.iter().filter(|c| seen.contains(&usize::from(c.high))).collect();
            assert!(!ladders.is_empty() && ladders.iter().all(|c| l.cells[usize::from(c.low)].level == 2), "seed {seed}: a tower block has no 6 in ladder up: {ladders:?}");
        }
    }
}

#[test]
#[ignore = "dev aid: NML_SHOW=3,7 cargo test --test boardgen show_town -- --ignored --nocapture"]
fn show_town() {
    for seed in std::env::var("NML_SHOW").unwrap_or_else(|_| "3".into()).split(',').filter_map(|s| s.parse::<i64>().ok()) {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        eprintln!("seed {seed} attempt {} problems {:?}\n{}", l.attempt, l.problems(), l.to_ascii());
    }
}

#[test]
fn a_town_has_garden_plots_that_stay_flat_and_the_deepworks_has_none() {
    use nml_core::boardgen::LotKind;
    let (mut total, mut least) = (0, usize::MAX);
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let plots: Vec<_> = l.lots.iter().filter(|lot| lot.kind == LotKind::Rough).collect();
        total += plots.len();
        least = least.min(plots.len());
        assert!(plots.iter().all(|lot| lot.w * lot.h == 1), "seed {seed}: a plot of more than one cell");
        assert!(l.cells.iter().filter(|c| c.lot_kind == LotKind::Rough).all(|c| c.level == 0 && !c.street), "seed {seed}: a raised or street plot cell");
        let on_plot = |lm: &Landmark| footprint(lm).iter().any(|&i| l.cells[i].lot_kind == LotKind::Rough);
        assert!(!l.landmarks.iter().any(on_plot), "seed {seed}: a landmark stands on a plot");
        assert!(!generate(seed, Symmetry::Point180).lots.iter().any(|lot| lot.kind == LotKind::Rough), "seed {seed}: a Deepworks plot");
    }
    let mean = total as f64 / 300.0;
    eprintln!("garden plots per town board: mean {mean:.1}, least {least}");
    assert!(mean >= 4.0 && least >= 4, "plots per board: mean {mean:.1}, least {least}");
}

#[test]
fn a_town_has_a_four_wide_six_deep_market_square_in_the_middle_and_the_deepworks_none() {
    let plaza: Vec<(usize, usize)> = (5..11).flat_map(|z| (6..10).map(move |x| (x, z))).collect();
    let mut deep_squares = 0;
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(plaza.iter().all(|&(x, z)| l.cell(x, z).street && l.cell(x, z).level == 0), "seed {seed}: the square is not open street\n{}", l.to_ascii());
        assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
        deep_squares += usize::from(plaza.iter().all(|&(x, z)| generate(seed, Symmetry::Point180).cell(x, z).street));
    }
    assert!(deep_squares < 60, "the Deepworks board has no reserved square ({deep_squares} of 300 have street there by chance)");
}

#[test]
fn every_town_has_a_fountain_in_the_middle_and_a_statue_pool_and_hall_as_mirrored_pairs() {
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
        let of = |k: LandmarkKind| l.landmarks.iter().filter(move |lm| lm.kind == k).collect::<Vec<_>>();
        let fountain = of(LandmarkKind::TankCluster);
        assert_eq!(fountain.len(), 1, "seed {seed}: {} fountains", fountain.len());
        assert_eq!((fountain[0].x, fountain[0].z, fountain[0].w, fountain[0].h), (7, 7, 2, 2), "seed {seed}: the fountain is not on the centre");
        for k in [LandmarkKind::Crane, LandmarkKind::Sump, LandmarkKind::PumpHouse] {
            let v = of(k);
            assert_eq!(v.len(), 2, "seed {seed}: {k:?} x {}", v.len());
            let (a, b) = (v[0], v[1]);
            assert_eq!((a.x + b.x + a.w, a.z + b.z + a.h, a.w, a.h), (GRID, GRID, b.w, b.h), "seed {seed}: the {k:?} pair is not a half turn");
        }
    }
}

#[test]
#[ignore = "measurement: where a city-wall column (x in 2..=5, rows 4..=11) could go on the town boards"]
fn census_of_wall_columns() {
    let (mut counts, mut gates) = ([0usize; 5], [0usize; 6]);
    for seed in 1..=1000 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let ok: Vec<usize> = (2..=5).filter(|&x| {
            let rows: Vec<usize> = (4..=11).filter(|&z| l.cell(x, z).street).collect();
            let runs_ok = rows.windows(2).all(|w| w[1] != w[0] + 1 || (w[0] == 7 && w[1] == 8)) && !rows.windows(3).any(|w| w[1] == w[0] + 1 && w[2] == w[1] + 1);
            !rows.is_empty() && runs_ok
        }).collect();
        counts[ok.len()] += 1;
        if let Some(&x) = ok.first() { gates[(4..=11).filter(|&z| l.cell(x, z).street).count().min(5)] += 1; }
    }
    eprintln!("boards by number of usable wall columns {counts:?}; gates (street cells crossed) on the first usable column {gates:?}");
}

#[test]
fn a_town_has_two_half_turn_city_walls_with_a_gate_a_breach_towers_and_a_ladder_up() {
    use nml_core::boardgen::LotKind;
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed}: {:?}\n{}", l.problems(), l.to_ascii());
        let wall: Vec<&nml_core::boardgen::Cell> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Wall).collect();
        let ridge: Vec<&nml_core::boardgen::Cell> = wall.iter().copied().filter(|c| c.level >= 2).collect();
        let (west, east): (Vec<&nml_core::boardgen::Cell>, Vec<&nml_core::boardgen::Cell>) = ridge.iter().copied().partition(|c| c.x < GRID / 2);
        assert!(!west.is_empty() && west.len() == east.len(), "seed {seed}: the walls are not twins ({} / {})", west.len(), east.len());
        // the wall runs in one column, or - with the KINK (ruintown AAA step G5b) - in two neighbouring ones that share a step row
        let cols: BTreeSet<usize> = west.iter().map(|c| c.x).collect();
        assert!(cols.len() <= 2 && cols.iter().max().unwrap() - cols.iter().min().unwrap() < 2, "seed {seed}: the wall leaves its column(s) {cols:?}");
        let col = *cols.iter().next().unwrap();
        assert!(wall.iter().all(|c| cols.contains(&c.x) || cols.contains(&(GRID - 1 - c.x)) || c.level == 1), "seed {seed}: the wall leaves its column");
        // in a band the wall is the 3 in low wall: nothing of it is 6 or 9 in up
        assert!(wall.iter().filter(|c| c.deploy != 0).all(|c| c.level <= 1), "seed {seed}: a 6 in wall or a tower in a deployment band");
        assert!((0..GRID).any(|z| l.cell(col, z).deploy != 0 && l.cell(col, z).lot_kind == LotKind::Wall && l.cell(col, z).level == 1) || (0..GRID).all(|z| l.cell(col, z).street || l.cell(col, z).deploy == 0 || l.cell(col, z).lot_kind != LotKind::Wall), "seed {seed}: no low wall in the bands");
        // a gate (a street cell in the line), a breach (a level-0 wall cell) and a wall tower on each twin
        let line: Vec<_> = cols.iter().flat_map(|&cc| (0..GRID).map(move |z| (cc, z))).map(|(cc, z)| l.cell(cc, z)).collect();
        assert!(line.iter().any(|c| c.street && c.level == 0), "seed {seed}: no gate");
        assert!(line.iter().any(|c| c.lot_kind == LotKind::Wall && c.level == 0), "seed {seed}: no breach");
        let two_in_a_row = cols.iter().any(|&cc| (0..GRID).map(|z| l.cell(cc, z)).collect::<Vec<_>>().windows(2).any(|w| w.iter().all(|c| c.lot_kind == LotKind::Wall && c.level >= 2)));
        assert!(!two_in_a_row || wall.iter().any(|c| c.level == 3 && cols.contains(&c.x)), "seed {seed}: a wall run of two or more has no tower");
        // every wall ridge cell sits on a level-2 island that a ladder reaches from below (or touches a 9 in tower, which has its own ladder)
        for c in ridge.iter().filter(|c| c.level == 2 && cols.contains(&c.x)) {
            let mut seen = HashSet::from([c.z * GRID + c.x]);
            let mut queue = VecDeque::from([c.z * GRID + c.x]);
            while let Some(i) = queue.pop_front() { for j in nbrs(i) { if l.cells[j].level == 2 && seen.insert(j) { queue.push_back(j); } } }
            let up = l.connectors.iter().any(|k| seen.contains(&usize::from(k.high)) && l.cells[usize::from(k.low)].level == 1);
            let tower = seen.iter().any(|&i| nbrs(i).iter().any(|&j| l.cells[j].level == 3));
            assert!(up || tower, "seed {seed}: the wall cell {} has no way up\n{}", c.z * GRID + c.x, l.to_ascii());
        }
    }
}

/// Silhouette round (21.11.): a wall run carries ONE tower, at its end nearer the board's middle row (a tower at both ends made the wall a row of keeps).
#[test]
fn a_town_wall_run_has_one_tower_at_its_end_nearer_the_middle() {
    use nml_core::boardgen::LotKind;
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        for x in 0..GRID / 2 {
            let col: Vec<_> = (0..GRID).map(|z| l.cell(x, z)).collect();
            let mut z = 0;
            while z < GRID {
                if !(col[z].lot_kind == LotKind::Wall && col[z].level >= 2) { z += 1; continue; }
                let start = z;
                while z < GRID && col[z].lot_kind == LotKind::Wall && col[z].level >= 2 { z += 1; }
                let towers: Vec<usize> = (start..z).filter(|&k| col[k].level == 3).collect();
                assert!(towers.len() <= 1, "seed {seed}: the wall run {start}..{z} in column {x} has {} towers\n{}", towers.len(), l.to_ascii());
                if let Some(&t) = towers.first() { assert!(t == start || t == z - 1, "seed {seed}: a wall tower inside its run {start}..{z} col {x} at {t}\n{}", l.to_ascii()); }
            }
        }
    }
}

#[test]
fn two_thirds_of_the_town_houses_are_intact_solid_roofs_and_the_rest_ruined_walkable_ones() {
    use nml_core::boardgen::LotKind;
    let (mut intact, mut ruined) = (0, 0);
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        for lot in &l.lots {
            let lref = &l;
            let cells: Vec<_> = (0..lot.h).flat_map(|dz| (0..lot.w).map(move |dx| lref.cell(lot.x + dx, lot.z + dz))).collect();
            match lot.kind {
                LotKind::Roofed => { intact += 1; assert!(cells.iter().all(|c| c.level == 0 && !c.street), "seed {seed}: a raised or street roofed cell"); }
                LotKind::Block | LotKind::Terrace | LotKind::Deck => ruined += 1,
                _ => {}
            }
        }
        let solid = solid(&l);
        assert!(l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).all(|c| solid[c.z * GRID + c.x]), "seed {seed}: an intact house is not solid");
        let feet: HashSet<usize> = l.connectors.iter().flat_map(|c| [usize::from(c.low), usize::from(c.high)]).collect();
        assert!(feet.iter().all(|&i| l.cells[i].lot_kind != LotKind::Roofed), "seed {seed}: a ladder foot on an intact house");
        assert!(!generate(seed, Symmetry::Point180).lots.iter().any(|lot| lot.kind == LotKind::Roofed), "seed {seed}: a Deepworks roofed lot");
    }
    let share = intact as f64 / (intact + ruined) as f64;
    eprintln!("intact {intact}, ruined {ruined}: {share:.2}");
    assert!((0.59..=0.75).contains(&share), "{share:.2} of the houses are intact");   // roofs plan K3: the infill houses lift the share to 0.67 (was 0.40 - 0.60, silhouette round 21.11.)
}

/// What "grown" means in numbers (ruintown AAA step G1): per town board the shares the growth stage has to move.
#[derive(Default)]
struct Growth {
    boards: f64, houses: f64, with_street_face: f64, party_walls: f64, boards_with_party: f64, with_yard_behind: f64, with_sealed_yard: f64, backyard_only: f64,
    longest_run_cells: f64, widths: f64, width_hist: [f64; 5], roof_run_lots: f64, roof_run_max: usize, boards_roof_run_over_2: f64, any_level_run_lots: f64, blocked: f64,
}

fn growth(seeds: std::ops::RangeInclusive<i64>) -> Growth {
    use nml_core::boardgen::LotKind::{Block, Deck, Roofed, Terrace, Wall};
    let mut g = Growth::default();
    let house = |k: nml_core::boardgen::LotKind| matches!(k, Block | Terrace | Deck | Roofed);
    for seed in seeds {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        g.boards += 1.0;
        let at = |x: i64, z: i64| if x < 0 || z < 0 || x >= GRID as i64 || z >= GRID as i64 { None } else { Some(l.cell(x as usize, z as usize)) };
        let dirs: [(i64, i64); 4] = [(0, -1), (1, 0), (0, 1), (-1, 0)];
        let mut party: HashSet<(u16, u16)> = HashSet::new();
        for lot in l.lots.iter().filter(|lot| house(lot.kind)) {
            g.houses += 1.0;
            // per face: the street cells beside it, and the cells beyond (a yard = ground that is neither street nor another house)
            let mut face = [(0usize, 0usize); 4];   // (street cells, yard cells)
            for dz in 0..lot.h { for dx in 0..lot.w {
                for (d, &(ox, oz)) in dirs.iter().enumerate() {
                    let (nx, nz) = ((lot.x + dx) as i64 + ox, (lot.z + dz) as i64 + oz);
                    let Some(nb) = at(nx, nz) else { continue };
                    if nb.lot_id == lot.id { continue }
                    if nb.street { face[d].0 += 1 } else if house(nb.lot_kind) { party.insert((lot.id.min(nb.lot_id), lot.id.max(nb.lot_id))); } else if nb.lot_kind != Wall { face[d].1 += 1 }
                }
            }}
            let front = (0..4).filter(|&d| face[d].0 > 0).max_by_key(|&d| face[d].0);
            match front {
                None => g.backyard_only += 1.0,
                Some(f) => {
                    g.with_street_face += 1.0;
                    g.with_yard_behind += f64::from(u8::from(face[(f + 2) % 4].1 > 0));
                    // a SEALED yard: every cell right behind the back face is ground (no street, no house, no wall) and no street touches it either - the back of a block
                    let (bx, bz) = dirs[(f + 2) % 4];
                    let back: Vec<(i64, i64)> = (0..lot.h).flat_map(|dz| (0..lot.w).map(move |dx| (dx, dz))).map(|(dx, dz)| ((lot.x + dx) as i64, (lot.z + dz) as i64))
                        .filter(|&(x, z)| at(x + bx, z + bz).is_some_and(|c| c.lot_id != lot.id) && at(x - bx, z - bz).is_none_or(|c| c.lot_id != lot.id)).map(|(x, z)| (x + bx, z + bz)).collect();
                    let sealed = !back.is_empty() && back.iter().all(|&(x, z)| {
                        let c = at(x, z).unwrap();
                        !c.street && !house(c.lot_kind) && c.lot_kind != Wall && dirs.iter().all(|&(ox, oz)| at(x + ox, z + oz).is_none_or(|n| !n.street))
                    });
                    g.with_sealed_yard += f64::from(u8::from(sealed));
                }
            }
        }
        g.party_walls += party.len() as f64;
        g.boards_with_party += f64::from(u8::from(!party.is_empty()));
        // longest straight street run and the street widths (across = the shorter of the two runs through a street cell, 4+ = junction or square)
        let street = |x: usize, z: usize| l.cell(x, z).street;
        let (mut longest, mut kinds) = (0, [false; 5]);
        for a in 0..GRID {
            for horizontal in [true, false] {
                let mut run = 0;
                for k in 0..GRID { if if horizontal { street(k, a) } else { street(a, k) } { run += 1; longest = longest.max(run) } else { run = 0 } }
            }
        }
        let run_through = |x: usize, z: usize, dx: usize, dz: usize| {
            let mut n = 1;
            let (mut a, mut b) = ((x, z), (x, z));
            while a.0 >= dx && a.1 >= dz && street(a.0 - dx, a.1 - dz) { a = (a.0 - dx, a.1 - dz); n += 1 }
            while b.0 + dx < GRID && b.1 + dz < GRID && street(b.0 + dx, b.1 + dz) { b = (b.0 + dx, b.1 + dz); n += 1 }
            n
        };
        for z in 0..GRID { for x in 0..GRID { if street(x, z) {
            let w = run_through(x, z, 1, 0).min(run_through(x, z, 0, 1)).min(4);
            g.width_hist[w] += 1.0;
            kinds[w] = true;
        }}}
        g.longest_run_cells += longest as f64;
        g.widths += kinds[1..4].iter().filter(|&&k| k).count() as f64;
        // roof runs: walkable raised building cells, edge-adjacent, counted in lots (same level; and any level)
        let sol = solid(&l);
        for same_level in [true, false] {
            let walk = |i: usize| l.cells[i].level > 0 && !sol[i] && !matches!(l.cells[i].lot_kind, Wall | nml_core::boardgen::LotKind::Street);
            let mut seen = vec![false; GRID * GRID];
            let mut best = 0;
            for s in (0..GRID * GRID).filter(|&i| walk(i)) {
                if seen[s] { continue }
                let (mut stack, mut lots) = (vec![s], HashSet::new());
                seen[s] = true;
                while let Some(i) = stack.pop() {
                    lots.insert(l.cells[i].lot_id);
                    for j in nbrs(i) { if !seen[j] && walk(j) && (!same_level || l.cells[j].level == l.cells[i].level) { seen[j] = true; stack.push(j) } }
                }
                best = best.max(lots.len());
            }
            if same_level { g.roof_run_lots += best as f64; g.roof_run_max = g.roof_run_max.max(best); g.boards_roof_run_over_2 += f64::from(u8::from(best > 2)) } else { g.any_level_run_lots += best as f64 }
        }
        g.blocked += blocked_share(&l, 3, &band_pairs(), true);
    }
    g
}

#[test]
#[ignore = "measurement: NML_GROWTH_OUT=<file> cargo test --test boardgen census_of_growth -- --ignored"]
fn census_of_growth() {
    let g = growth(1..=1000);
    let n = g.boards;
    let w: f64 = g.width_hist.iter().sum();
    let out = format!("| houses | with a street face | party walls / board (boards with any) | houses with a yard behind (of those with a front) | of those, a SEALED yard (ground, no street touching it) | backyard-only houses | longest straight street run | distinct street widths (1-3 cells) | street cells by width 1/2/3/4+ % | longest same-level walkable roof run in lots (mean, max, boards > 2) | longest any-level run in lots | opening-turn rays blocked |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n| {:.1} | {:.1} ({:.0} %) | {:.2} ({:.0} %) | {:.1} ({:.0} %) | {:.1} ({:.0} %) | {:.1} | {:.1} cells = {:.0} in | {:.2} | {:.0} / {:.0} / {:.0} / {:.0} | {:.2}, {}, {:.0} % | {:.2} | {:.1} % |",
        g.houses / n, g.with_street_face / n, 100.0 * g.with_street_face / g.houses, g.party_walls / n, 100.0 * g.boards_with_party / n, g.with_yard_behind / n, 100.0 * g.with_yard_behind / g.with_street_face.max(1.0), g.with_sealed_yard / n, 100.0 * g.with_sealed_yard / g.with_street_face.max(1.0), g.backyard_only / n,
        g.longest_run_cells / n, g.longest_run_cells / n * 3.0, g.widths / n, 100.0 * g.width_hist[1] / w, 100.0 * g.width_hist[2] / w, 100.0 * g.width_hist[3] / w, 100.0 * g.width_hist[4] / w,
        g.roof_run_lots / n, g.roof_run_max, 100.0 * g.boards_roof_run_over_2 / n, g.any_level_run_lots / n, 100.0 * g.blocked / n);
    eprintln!("{out}");
    if let Ok(path) = std::env::var("NML_GROWTH_OUT") { std::fs::write(path, &out).expect("growth census file"); }
}

/// Houses stand in ROWS (ruintown AAA step G2): neighbours share a party wall, a row is 2 to 4 houses with a passage after it, and nearly every house has a street at its door.
#[test]
fn a_town_has_party_walls_and_passages() {
    use nml_core::boardgen::LotKind::{Block, Deck, Roofed, Terrace};
    let house = |k| matches!(k, Block | Terrace | Deck | Roofed);
    let (mut party, mut with_party, mut houses, mut touching, mut longest, n) = (0, 0, 0, 0, 0, 300);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
        let mut walls: BTreeSet<(u16, u16)> = BTreeSet::new();
        for i in 0..GRID * GRID { for j in nbrs(i) {
            let (a, b) = (&l.cells[i], &l.cells[j]);
            if a.lot_id != 0 && b.lot_id != 0 && a.lot_id != b.lot_id && house(a.lot_kind) && house(b.lot_kind) { walls.insert((a.lot_id.min(b.lot_id), a.lot_id.max(b.lot_id))); }
        }}
        party += walls.len();
        with_party += usize::from(!walls.is_empty());
        // a row = the lots joined by party walls; none is longer than 4 houses (a passage follows every row)
        let ids: Vec<u16> = l.lots.iter().filter(|lot| house(lot.kind)).map(|lot| lot.id).collect();
        let mut seen: BTreeSet<u16> = BTreeSet::new();
        for &s in &ids {
            if !seen.insert(s) { continue; }
            let (mut stack, mut size) = (vec![s], 0);
            while let Some(a) = stack.pop() { size += 1; for &(p, q) in &walls { for (x, y) in [(p, q), (q, p)] { if x == a && seen.insert(y) { stack.push(y); } } } }
            longest = longest.max(size);
            assert!(size <= 4, "seed {seed}: a row of {size} houses\n{}", l.to_ascii());
        }
        houses += ids.len();
        touching += l.lots.iter().filter(|lot| house(lot.kind) && (lot.z..lot.z + lot.h).any(|z| (lot.x..lot.x + lot.w).any(|x| nbrs(z * GRID + x).iter().any(|&j| l.cells[j].street)))).count();
    }
    let (p, share, t) = (party as f64 / n as f64, with_party as f64 / n as f64, touching as f64 / houses as f64);
    eprintln!("town party walls {p:.2} per board, boards with one {share:.3}, longest row {longest}, houses touching a street {t:.3}");
    assert!(p >= 2.0 && share >= 0.80, "party walls {p:.2} per board, {share:.2} of the boards have one");
    assert!(t >= 0.85, "{t:.2} of the houses touch a street");
}

/// Mid-board sight lines: rows 4 and 11 (12 in from each edge, the turn-2 positions), every column pair.
fn mid_pairs() -> Vec<CellPair> { (0..GRID).flat_map(|x1| (0..GRID).map(move |x2| ((x1, 4), (x2, 11)))).collect() }

/// The numbers of the G2 acceptance (lead decision 21.11.), over `n` town seeds: opening rays blocked, mid rays blocked, party walls, houses touching a street, and how often the FIRST sub-seed
/// is already lane-free / valid. `NML_N=1000` for the real census.
#[test]
#[ignore = "measurement: NML_N=1000 cargo test --test boardgen g2_gate -- --ignored --nocapture"]
fn g2_gate() {
    use nml_core::boardgen::{generate_attempt, LotKind::{Block, Deck, Roofed, Terrace}};
    let n: i64 = std::env::var("NML_N").ok().and_then(|v| v.parse().ok()).unwrap_or(300);
    let house = |k| matches!(k, Block | Terrace | Deck | Roofed);
    let (mut open_r, mut mid_r, mut party, mut with_party, mut houses, mut touching, mut lane0, mut valid0, mut lots, mut failed, mut attempts) = (0.0, 0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    let (mut walk_up, mut walk_l3, mut intact) = (0, 0, 0);   // standing room above the ground (raised cells that are not an intact house), its 9 in part, intact houses
    for seed in 1..=n {
        let a0 = generate_attempt(seed, Symmetry::Point180, Theme::RuinTown, 0);
        lane0 += usize::from(!a0.has_edge_to_edge_lane());
        valid0 += usize::from(a0.problems().is_empty());
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        open_r += blocked_share(&l, 3, &band_pairs(), true);
        mid_r += blocked_share(&l, 3, &mid_pairs(), true);
        lots += l.lots.len();
        walk_up += l.cells.iter().filter(|c| c.level >= 1 && c.lot_kind != Roofed).count();
        walk_l3 += l.cells.iter().filter(|c| c.level == 3).count();
        intact += l.lots.iter().filter(|lot| lot.kind == Roofed).count();
        failed += usize::from(!l.problems().is_empty());
        attempts += usize::from(l.attempt);
        let mut walls: BTreeSet<(u16, u16)> = BTreeSet::new();
        for i in 0..GRID * GRID { for j in nbrs(i) {
            let (a, b) = (&l.cells[i], &l.cells[j]);
            if a.lot_id != 0 && b.lot_id != 0 && a.lot_id != b.lot_id && house(a.lot_kind) && house(b.lot_kind) { walls.insert((a.lot_id.min(b.lot_id), a.lot_id.max(b.lot_id))); }
        }}
        party += walls.len();
        with_party += usize::from(!walls.is_empty());
        houses += l.lots.iter().filter(|lot| house(lot.kind)).count();
        touching += l.lots.iter().filter(|lot| house(lot.kind) && (lot.z..lot.z + lot.h).any(|z| (lot.x..lot.x + lot.w).any(|x| nbrs(z * GRID + x).iter().any(|&j| l.cells[j].street)))).count();
    }
    let f = n as f64;
    eprintln!("G2 over {n}: lots {:.1}, opening rays blocked {:.1} % (<= 95), mid rays blocked {:.1} % (60-85), party walls {:.2} per board ({:.0} % of boards), houses touching a street {:.1} % (>= 85), first sub-seed lane-free {:.1} % (>= 99), first sub-seed valid {:.1} %, mean sub-seed {:.1}, boards still failing after all sub-seeds {failed}, walkable raised cells {:.1} per board (9 in: {:.1}), intact houses {:.1}",
        lots as f64 / f, 100.0 * open_r / f, 100.0 * mid_r / f, party as f64 / f, 100.0 * with_party as f64 / f, 100.0 * touching as f64 / houses as f64, 100.0 * lane0 as f64 / f, 100.0 * valid0 as f64 / f, attempts as f64 / f, walk_up as f64 / f, walk_l3 as f64 / f, intact as f64 / f);
}


/// Roofs plan K3: the infill stage (the last step of `levels::stack`) puts small intact houses only between the bands, each with a street at its door, as half-turn
/// twins, solid, never a ladder foot. The infill lots are the ones a run with `infill_pairs: 0` does not have (same graph, same seed).
#[test]
fn a_town_has_infill_houses_only_between_the_bands_with_a_street_at_the_door() {
    use nml_core::boardgen::{connect, graph, levels, LotKind};
    let (b, mut infill) = (Theme::RuinTown.budgets(), 0);
    let b0 = nml_core::boardgen::Budgets { infill_pairs: 0, ..b };
    for seed in 1..=300 {
        let g = graph::build(seed * 7919, Symmetry::Point180, &b);
        let ((lots0, _), (lots, cells)) = (levels::stack(seed, &g, &b0), levels::stack(seed, &g, &b));
        assert_eq!(lots[..lots0.len()], lots0[..], "seed {seed}: the infill stage changed an earlier lot");
        let new = &lots[lots0.len()..];
        assert!(new.len() % 2 == 0 && new.len() <= 2 * b.infill_pairs, "seed {seed}: {} infill lots", new.len());
        let feet: HashSet<usize> = connect::wire(seed, Symmetry::Point180, &cells).iter().flat_map(|c| [usize::from(c.low), usize::from(c.high)]).collect();
        for (k, lot) in new.iter().enumerate() {
            let idx: Vec<usize> = (lot.z..lot.z + lot.h).flat_map(|z| (lot.x..lot.x + lot.w).map(move |x| z * GRID + x)).collect();
            assert!(lot.kind == LotKind::Roofed && idx.iter().all(|&i| cells[i].lot_kind == LotKind::Roofed && cells[i].lot_id == lot.id && cells[i].level == 0), "seed {seed}: infill lot {} is not a solid house", lot.id);
            assert!(idx.iter().all(|&i| cells[i].deploy == 0), "seed {seed}: infill lot {} stands in a deployment band", lot.id);
            assert!(idx.iter().any(|&i| nbrs(i).iter().any(|&j| cells[j].street)), "seed {seed}: infill lot {} has no street at its door", lot.id);
            assert!(idx.iter().all(|i| !feet.contains(i)), "seed {seed}: a ladder foot on infill lot {}", lot.id);
            let twin = &new[k ^ 1];
            assert_eq!((twin.x, twin.z, twin.w, twin.h), (GRID - lot.x - lot.w, GRID - lot.z - lot.h, lot.w, lot.h), "seed {seed}: infill lot {} has no half-turn twin", lot.id);
        }
        infill += new.len();
    }
    eprintln!("infill houses per board over 300 seeds: {:.2}", infill as f64 / 300.0);
    assert!(infill >= 300 * 4, "the infill stage placed only {infill} houses on 300 boards");
}

/// Towers plan T2: one half-turn pair of tall towers in the outer columns between the bands (rows 4-11), level 0, solid, no ladder, no street, no wall. A board
/// tries the 2 x 2 pair for its first `max_attempts` sub-seeds, then a 1 x 2 pair, then none (lead 22.11.); the sub-seed says which. The Deepworks has none.
#[test]
fn a_town_has_one_half_turn_pair_of_tall_towers_outside_the_bands_and_the_wall() {
    use nml_core::boardgen::LotKind;
    let (b, mut shares) = (Theme::RuinTown.budgets(), [0usize; 3]);
    for seed in 1..=300 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let step = usize::from(l.attempt / b.max_attempts);
        let (w, h) = [b.tall_towers, (1, 2), (0, 0)][step];
        shares[step] += 1;
        let t: Vec<usize> = (0..GRID * GRID).filter(|&i| l.cells[i].lot_kind == LotKind::Tower).collect();
        assert_eq!(t.len(), 2 * w * h, "seed {seed} (sub-seed {}): {} tower cells\n{}", l.attempt, t.len(), l.to_ascii());
        if t.is_empty() { continue; }
        let west: Vec<usize> = t.iter().copied().filter(|&i| i % GRID < GRID / 2).collect();
        let z0 = west[0] / GRID;
        assert_eq!(west, (z0..z0 + h).flat_map(|z| (0..w).map(move |x| z * GRID + x)).collect::<Vec<_>>(), "seed {seed}: the west tower is no {w} x {h} block at the west edge");
        assert!(z0 >= 4 && z0 + h <= 12, "seed {seed}: the west tower leaves rows 4-11 (row {z0})");
        assert!(t.iter().all(|&i| t.contains(&(GRID * GRID - 1 - i))), "seed {seed}: the towers are no half turn");
        let feet: HashSet<usize> = l.connectors.iter().flat_map(|c| [usize::from(c.low), usize::from(c.high)]).collect();
        let sol = solid(&l);
        for &i in &t { let c = &l.cells[i]; assert!(c.deploy == 0 && c.level == 0 && !c.street && c.lot_id == 0 && !feet.contains(&i) && sol[i], "seed {seed}: tower cell {i} is in a band, raised, street, a lot or a ladder foot"); }
        assert!(!generate(seed, Symmetry::Point180).cells.iter().any(|c| c.lot_kind == LotKind::Tower), "seed {seed}: a Deepworks tower");
    }
    eprintln!("tall towers over 300 town boards: 2 x 2 {}, 1 x 2 {}, none {}", shares[0], shares[1], shares[2]);
    assert!(shares[0] >= 285, "only {} of 300 boards carry the 2 x 2 tower pair", shares[0]);
}

/// Roofs plan K4: every town board has at least four intact (roofed) houses - a skyline on every board, not only on the average one.
#[test]
fn every_town_has_at_least_four_intact_houses() {
    let mut few = Vec::new();
    for seed in 1..=1000 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let houses = l.lots.iter().filter(|lot| lot.kind == nml_core::boardgen::LotKind::Roofed).count();
        if houses < 4 { few.push((seed, houses)); }
    }
    assert!(few.is_empty(), "{} of 1000 town boards have fewer than 4 intact houses: {:?}", few.len(), &few[..few.len().min(20)]);
}

/// Roofs plan K2: the town's raised minimum is 15 %, so the generator grows few filler slabs (raised cells on free earth: no lot, not the wall).
/// Before K2 (minimum 23 %) the mean over 200 seeds was ~38 cells per board.
#[test]
fn a_town_grows_few_filler_slabs() {
    use nml_core::boardgen::LotKind;
    let n = 200;
    let filler: usize = (1..=n).map(|seed| generate_themed(seed, Symmetry::Point180, Theme::RuinTown).cells.iter()
        .filter(|c| c.level >= 1 && c.lot_id == 0 && c.lot_kind != LotKind::Wall).count()).sum();
    let mean = filler as f64 / n as f64;
    eprintln!("filler slab cells per town board over {n} seeds: {mean:.1}");
    assert!(mean <= 26.0, "a town grows too many filler slabs on free earth: {mean:.1} cells per board (cap 26)");
}

/// BASELINE of PLAN_RUINTOWN_ROOFS step K0: origin/main 6a2972697, town theme, Point180, seeds 1..=1000 (means per board, sq in, percent).
/// Re-pinned by K2 (raised minimum 23 -> 15 %), K3 (infill houses), K4 (at least 4 houses) and towers T2 (a tall tower pair, read at 12 in), 1000 seeds. The roofs steps K2+ move these numbers ON PURPOSE: each re-pins the entries it changes, in the same commit, with the old -> new values in its message.
const ROOFS_BASELINE: [(&str, f64); 19] = [
    ("intact houses", 8.27), ("boards with <= 2 houses %", 0.0), ("roofed cells", 19.37), ("raised cells in house plots", 13.07), ("raised cells on free earth", 22.64), ("raised cells in the city wall", 34.25),
    ("roof share of footprints %", 35.17), ("walkable sq in 0 in", 1374.21), ("walkable sq in 3 in", 352.48), ("walkable sq in 6 in", 207.58), ("walkable sq in 9 in", 69.53), ("ladders", 44.27),
    ("opening rays blocked %", 95.58), ("mid rays blocked %", 78.39), ("tier-to-tier rays blocked, house 2.5 in %", 53.4), ("tier-to-tier rays blocked, ridge 4.5 in %", 58.07),
    ("roofed cells in the bands", 8.88), ("raised cells in the bands", 30.17), ("asymmetric cells", 0.0),
];

/// Roofs census over `NML_N` town seeds (default 1000, the baseline's size; the baseline is asserted only at 1000, within +-0.5 on every number). `NML_ROOFS_OUT=<file>` also writes the report.
#[test]
#[ignore = "measurement: NML_N=1000 cargo test --release --test boardgen census_of_roofs -- --ignored --nocapture"]
fn census_of_roofs() {
    use nml_core::boardgen::LotKind;
    let n: i64 = std::env::var("NML_N").ok().and_then(|v| v.parse().ok()).unwrap_or(1000);
    let (mut houses, mut roofed, mut raised, mut walk, mut ladders, mut band, mut asym) = (Vec::new(), 0, [0usize; 3], [0usize; 4], 0, [0usize; 2], 0);
    let (mut rays, mut failed, mut towers, mut subs) = ([0.0f64; 4], 0, [0usize; 3], 0usize);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        failed += usize::from(!l.problems().is_empty());
        towers[usize::from(l.attempt / Theme::RuinTown.budgets().max_attempts).min(2)] += 1;
        subs += usize::from(l.attempt) + 1;
        houses.push(l.lots.iter().filter(|lot| lot.kind == LotKind::Roofed).count());
        let sol = solid(&l);
        for (i, c) in l.cells.iter().enumerate() {
            let is_roof = c.lot_kind == LotKind::Roofed;
            roofed += usize::from(is_roof);
            band[0] += usize::from(is_roof && c.deploy != 0);
            if c.level > 0 && !is_roof {
                raised[if c.lot_kind == LotKind::Wall { 2 } else if c.lot_id != 0 { 0 } else { 1 }] += 1;
                band[1] += usize::from(c.deploy != 0);
            }
            walk[usize::from(c.level)] += usize::from(!sol[i]);
            let twin = &l.cells[GRID * GRID - 1 - i];
            asym += usize::from((twin.level, twin.lot_kind) != (c.level, c.lot_kind));
        }
        ladders += l.connectors.len();
        let tiers: Vec<(usize, usize)> = l.cells.iter().filter(|c| c.level >= 1 && c.lot_kind != LotKind::Roofed).map(|c| (c.x, c.z)).collect();
        let duels: Vec<CellPair> = tiers.iter().enumerate().flat_map(|(i, &a)| tiers[i + 1..].iter().map(move |&b| (a, b))).collect();
        rays[0] += blocked_share(&l, 3, &band_pairs(), true);
        rays[1] += blocked_share(&l, 3, &mid_pairs(), true);
        rays[2] += blocked_share(&l, 3, &duels, true);
        rays[3] += blocked_share_roofs(&l, 3, &duels, true, 4.5);
    }
    houses.sort_unstable();
    let f = n as f64;
    let got = [
        houses.iter().sum::<usize>() as f64 / f, 100.0 * houses.iter().filter(|&&h| h <= 2).count() as f64 / f, roofed as f64 / f,
        raised[0] as f64 / f, raised[1] as f64 / f, raised[2] as f64 / f, 100.0 * roofed as f64 / (roofed + raised[0] + raised[1]) as f64,
        walk[0] as f64 * 9.0 / f, walk[1] as f64 * 9.0 / f, walk[2] as f64 * 9.0 / f, walk[3] as f64 * 9.0 / f, ladders as f64 / f,
        100.0 * rays[0] / f, 100.0 * rays[1] / f, 100.0 * rays[2] / f, 100.0 * rays[3] / f, band[0] as f64 / f, band[1] as f64 / f, asym as f64,
    ];
    let mut out = format!("roofs census over {n} town seeds (Point180); houses min {} p10 {} median {} max {}; boards failing {failed}; tall towers 2 x 2 / 1 x 2 / none {towers:?}; mean sub-seed {:.2}\n", houses[0], houses[houses.len() / 10], houses[houses.len() / 2], houses[houses.len() - 1], subs as f64 / f);
    let mut off = Vec::new();
    for (&(name, base), g) in ROOFS_BASELINE.iter().zip(got) {
        out += &format!("{name}: {g:.2} (baseline {base})\n");
        if (g - base).abs() > 0.5 { off.push(format!("{name}: {g:.2} vs {base}")); }
    }
    eprintln!("{out}");
    if let Ok(path) = std::env::var("NML_ROOFS_OUT") { std::fs::write(path, &out).expect("roofs census file"); }
    if n == 1000 { assert!(off.is_empty(), "the town moved off the K0 baseline (re-pin ROOFS_BASELINE on purpose): {off:?}"); }
}


#[test]
#[ignore = "dev aid"]
fn one_attempt() {
    use nml_core::boardgen::generate_attempt;
    let seed: i64 = std::env::var("NML_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(2);
    let a0 = generate_attempt(seed, Symmetry::Point180, Theme::RuinTown, 0);
    eprintln!("{}\nproblems {:?} towers {} lots {:?}", a0.to_ascii(), a0.problems(), a0.towers(), a0.lots.iter().map(|l| (l.x, l.z, l.w, l.h, l.kind)).collect::<Vec<_>>());
}

#[test]
#[ignore = "dev aid"]
fn attempt0_problems() {
    use nml_core::boardgen::generate_attempt;
    let mut tally: std::collections::BTreeMap<&str, usize> = std::collections::BTreeMap::new();
    let n: i64 = std::env::var("NML_N").ok().and_then(|v| v.parse().ok()).unwrap_or(300);
    for seed in 1..=n { for p in generate_attempt(seed, Symmetry::Point180, Theme::RuinTown, 0).problems() { *tally.entry(p).or_default() += 1; } }
    let (mut lane_with_wall, mut lane_no_wall) = (0, 0);
    for seed in 1..=n {
        let l = generate_attempt(seed, Symmetry::Point180, Theme::RuinTown, 0);
        if l.has_edge_to_edge_lane() { if l.cells.iter().any(|c| c.lot_kind == nml_core::boardgen::LotKind::Wall && c.level == 2) { lane_with_wall += 1 } else { lane_no_wall += 1 } }
    }
    eprintln!("lanes with a wall {lane_with_wall}, without {lane_no_wall}");
    eprintln!("attempt 0 problems over {n} seeds: {tally:#?}");
}




/// Rows must not become a roof highway (ruintown AAA step G4): no walkable roof run touches more than two houses, and the validator says so when one does.
#[test]
fn a_town_has_no_walkable_roof_run_longer_than_two_houses() {
    use nml_core::boardgen::LotKind;
    let (mut forced_over, mut longest) = (0, 0);
    for seed in 1..=200 {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        assert!(l.problems().is_empty(), "seed {seed}: {:?}", l.problems());
        longest = longest.max(l.longest_roof_run());
        assert!(l.longest_roof_run() <= 2, "seed {seed}: a roof run over {} houses\n{}", l.longest_roof_run(), l.to_ascii());
        // planted: every house ruined and one level (all level 1) joins every party wall into one run - the validator must see it
        let mut all = l.clone();
        for c in all.cells.iter_mut().filter(|c| matches!(c.lot_kind, LotKind::Block | LotKind::Terrace | LotKind::Deck | LotKind::Roofed)) { c.lot_kind = LotKind::Block; c.level = 1; }
        if all.longest_roof_run() > 2 {
            forced_over += 1;
            assert!(all.problems().contains(&"a walkable roof run touches more houses than the cap"), "seed {seed}: the cap did not fire");
        }
    }
    eprintln!("longest real roof run {longest}; boards whose all-level-1 twin breaks the cap: {forced_over} of 200");
    assert!(forced_over > 20, "the planted all-level-1 boards should break the cap on many boards ({forced_over})");
}


/// Backyards (ruintown AAA step G3): behind most houses of a row there is a garden plot, so a block has a back.
#[test]
fn most_town_houses_have_a_garden_plot_behind_them() {
    use nml_core::boardgen::LotKind::{Block, Deck, Rough, Roofed, Terrace};
    let (mut fronted, mut with_plot, n) = (0, 0, 300);
    let b = Theme::RuinTown.budgets();
    let b0 = nml_core::boardgen::Budgets { infill_pairs: 0, ..b };
    for seed in 1..=n {
        // the houses of the plot stage only (roofs plan K3): the infill houses stand on bare earth by design, so the lots a run without infill has are counted, on the full board
        let g = nml_core::boardgen::graph::build(seed * 7919, Symmetry::Point180, &b);
        let ((lots0, _), (_, cells)) = (nml_core::boardgen::levels::stack(seed, &g, &b0), nml_core::boardgen::levels::stack(seed, &g, &b));
        for lot in lots0.iter().filter(|lot| matches!(lot.kind, Block | Terrace | Deck | Roofed)) {
            let side = |dx: i64, dz: i64| -> (usize, bool) {   // street cells and garden plots on the face looking (dx, dz)
                let (mut streets, mut plot) = (0, false);
                for z in lot.z..lot.z + lot.h { for x in lot.x..lot.x + lot.w {
                    let (nx, nz) = (x as i64 + dx, z as i64 + dz);
                    if nx < 0 || nz < 0 || nx >= GRID as i64 || nz >= GRID as i64 || (nx as usize >= lot.x && (nx as usize) < lot.x + lot.w && nz as usize >= lot.z && (nz as usize) < lot.z + lot.h) { continue; }
                    let c = &cells[nz as usize * GRID + nx as usize];
                    streets += usize::from(c.street);
                    plot |= c.lot_kind == Rough;
                }}
                (streets, plot)
            };
            let faces = [side(0, -1), side(1, 0), side(0, 1), side(-1, 0)];
            let Some(front) = (0..4).filter(|&d| faces[d].0 > 0).max_by_key(|&d| faces[d].0) else { continue };
            fronted += 1;
            with_plot += usize::from(faces[(front + 2) % 4].1);
        }
    }
    let share = with_plot as f64 / fronted as f64;
    eprintln!("houses with a street at the door that have a garden plot behind: {share:.3}");
    assert!(share >= 0.25, "only {share:.2} of the fronted houses have a garden plot behind them");
}


/// Streets that grew (ruintown AAA step G5): the north artery has a jog (it shifts a column) and a pinch (two rows one cell = 3 in wide), mirrored by the half turn.
#[test]
fn a_town_street_is_not_one_straight_line() {
    let (mut jogged, mut pinched, n) = (0, 0, 300);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let (mut lefts, mut one_wide) = (BTreeSet::new(), 0);
        for z in 0..GRID / 2 - 1 {
            let xs: Vec<usize> = (0..GRID).filter(|&x| l.cell(x, z).street).collect();
            if xs.is_empty() || xs.len() > 3 { continue; }   // the cross street's row has many street cells
            lefts.insert(xs[0]);
            one_wide += usize::from(xs.len() == 1);
            // the half turn twin has the same width on the opposite row
            assert_eq!((0..GRID).filter(|&x| l.cell(x, GRID - 1 - z).street).count(), xs.len(), "seed {seed}: the street is not a half turn");
        }
        jogged += usize::from(lefts.len() >= 2);
        pinched += usize::from(one_wide >= 1);
    }
    eprintln!("jogged {jogged} of {n}, pinched {pinched} of {n}");
    assert!(jogged as f64 >= 0.85 * n as f64 && pinched as f64 >= 0.5 * n as f64, "jog {jogged} / pinch {pinched} of {n}");   // the pinch is hidden on boards where a house or the cross street shares its rows
}

/// The city wall has a kink (ruintown AAA step G5b): on most boards its west twin runs in two neighbouring columns joined by a step row, and the twins stay an exact half turn.
#[test]
fn a_town_wall_is_not_one_ruler_line() {
    use nml_core::boardgen::LotKind;
    let (mut kinked, n) = (0, 300);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let cols: BTreeSet<usize> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Wall && c.level >= 2 && c.x < GRID / 2).map(|c| c.x).collect();
        kinked += usize::from(cols.len() == 2);
        for c in l.cells.iter().filter(|c| c.lot_kind == LotKind::Wall && c.level >= 2) {
            let twin = l.cell(GRID - 1 - c.x, GRID - 1 - c.z);
            assert!(twin.lot_kind == LotKind::Wall && twin.level == c.level, "seed {seed}: the wall is not a half turn at ({}, {})", c.x, c.z);
        }
    }
    eprintln!("kinked walls {kinked} of {n}");
    assert!(kinked as f64 >= 0.25 * n as f64, "only {kinked} of {n} walls have a kink");
}
