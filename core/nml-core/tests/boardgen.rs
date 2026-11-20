//! `nml_core::boardgen` (heightfield stage): determinism, budgets, reachability, mirror symmetry, 48 x 48 in.
//! The reachability and ascent checks are written here from scratch, not taken from the module.
use std::collections::{BTreeSet, HashSet, VecDeque};
use nml_core::boardgen::{budget, generate, ConnectorKind, Layout, Symmetry, BOARD_IN, DEPLOY_DEPTH_CELLS, GRID, HIGH_PERMILLE, RAISED_PERMILLE};

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

/// Walkable graph: neighbours at the same level, plus every connector. Returns what a walk from `player`'s band reaches.
fn reach(l: &Layout, player: u8) -> Vec<bool> {
    let mut adj: Vec<Vec<usize>> = (0..GRID * GRID).map(|i| nbrs(i).into_iter().filter(|&j| l.cells[j].level == l.cells[i].level).collect()).collect();
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
fn budgets_hold_and_sheer_height_stays_within_6_in_over_1000_seeds() {
    let (r, h) = (budget(RAISED_PERMILLE), budget(HIGH_PERMILLE));
    let (mut retried, t0) = (0, std::time::Instant::now());
    for seed in 1..=500 {
        for sym in BOTH {
            let l = generate(seed, sym);
            retried += usize::from(l.attempt > 0);
            assert!(l.problems().is_empty(), "seed {seed} {sym:?} attempt {}: {:?}\n{}", l.attempt, l.problems(), l.to_ascii());
            assert!((r.0..=r.1).contains(&l.raised()), "seed {seed}: raised {}", l.raised());
            assert!((h.0..=h.1).contains(&l.high()), "seed {seed}: high {}", l.high());
            assert!(l.cells.iter().all(|c| c.level <= 2 && (c.level < 2 || c.deploy == 0)), "level 2 in a band or above 2");
            assert!(l.max_drop_in() <= 6, "seed {seed}: sheer drop {} in", l.max_drop_in());
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
                assert!(seen.iter().all(|&s| s), "seed {seed} {sym:?}: {} cells unreachable from player {p}\n{}", seen.iter().filter(|&&s| !s).count(), l.to_ascii());
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
        assert_eq!(half(0, &|v| v == 2), half(128, &|v| v == 2), "seed {seed}: level-2 area per half");
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
