//! `nml_core::boardgen` (heightfield stage): determinism, budgets, reachability, mirror symmetry, 48 x 48 in.
//! The reachability and ascent checks are written here from scratch, not taken from the module.
use std::collections::{BTreeSet, HashSet, VecDeque};
use nml_core::boardgen::{budget, generate, ConnectorKind, Landmark, LandmarkKind, Layout, Symmetry, BOARD_IN, DEPLOY_DEPTH_CELLS, GRID, HIGH_PERMILLE, RAISED_PERMILLE};

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
    let sol = solid(l);
    let h = |x: f64, z: f64| {
        let (cx, cz) = ((x / 3.0) as usize, (z / 3.0) as usize);
        let floor = f64::from(nml_core::boardgen::LEVEL_IN[usize::from(l.cell(cx, cz).level.min(cap))]);
        if solids && sol[cz * GRID + cx] { floor.max(nml_core::terrain::CONTAINER_HEIGHT_IN) } else { floor }
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
