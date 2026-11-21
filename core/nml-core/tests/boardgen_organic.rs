//! Organic plan C4 + K4 (plan level): measurements of the free-solid town on REAL sight zones (`sight::zones_of_at`), not the
//! cell-ray helper of tests/boardgen.rs, and the share of the drawn plan outline that is off the table axes.
//! `NML_N=1000 NML_ORGANIC_OUT=<file> cargo test --release --test boardgen_organic -- --ignored --nocapture`
use nml_core::acts::CURRENT_RULES_EPOCH;
use nml_core::boardgen::plain::to_plain;
use nml_core::boardgen::solids::{free_solids, FreeSolid};
use nml_core::boardgen::{generate_themed, LandmarkKind, Layout, LotKind, Symmetry, Theme, GRID, LEVEL_IN};
use nml_core::sight::{has_los, zones_of_at, Cyl, Zone};
use nml_core::terrain::{ContainerObb, Obb, PlainTerrain, Terrain, CONTAINER};
use nml_core::IN2M;

type CellPair = ((usize, usize), (usize, usize));
fn band_pairs() -> Vec<CellPair> { (0..GRID).flat_map(|a| (0..GRID).map(move |b| ((a, 1), (b, 14)))).collect() }
fn mid_pairs() -> Vec<CellPair> { (0..GRID).flat_map(|a| (0..GRID).map(move |b| ((a, 4), (b, 11)))).collect() }

/// The houses as their whole lots at yaw 0 (the C1 encoding): today's blocking with free boxes.
fn flat(l: &Layout, s: &[FreeSolid]) -> Vec<FreeSolid> {
    s.iter().map(|b| {
        let lot = l.lots.iter().find(|o| o.id == b.lot).expect("lot");
        FreeSolid { c_in: [(lot.x as f64 + lot.w as f64 * 0.5) * 3.0 - 24.0, (lot.z as f64 + lot.h as f64 * 0.5) * 3.0 - 24.0], he_in: [lot.w as f64 * 1.5, lot.h as f64 * 1.5], yaw: 0.0, lot: b.lot }
    }).collect()
}

fn with_solids(p: &PlainTerrain, s: &[FreeSolid]) -> PlainTerrain {
    let m = |v: [f64; 2]| [v[0] * IN2M, v[1] * IN2M];
    PlainTerrain {
        sandbox: s.iter().map(|b| Obb { c: m(b.c_in), he: m(b.he_in), yaw: b.yaw, kind: CONTAINER, slabs: Vec::new() }).collect(),
        containers: s.iter().map(|b| ContainerObb { c: m(b.c_in), he: m(b.he_in), yaw: b.yaw }).collect(),
        ..p.clone()
    }
}

/// Share of eye-to-eye rays (1.25 in above the floor of each end cell) that the real sight zones stop.
fn zone_share(l: &Layout, zones: &[Zone], pairs: &[CellPair]) -> f64 {
    let eye = |(x, z): (usize, usize)| {
        let floor = f64::from(LEVEL_IN[usize::from(l.cell(x, z).level)]) * IN2M;
        Cyl { c: [(x as f64 * 3.0 + 1.5 - 24.0) * IN2M, (z as f64 * 3.0 + 1.5 - 24.0) * IN2M], r: 0.0, y0: floor, y1: floor + 1.25 * IN2M }
    };
    pairs.iter().filter(|&&(a, b)| !has_los(&eye(a), &eye(b), false, zones, &[])).count() as f64 / pairs.len() as f64
}

/// Plan-level outline: inches of footprint edge off the table axes by more than 5 deg / all footprint edge. Raised mass and solid
/// landmarks are cell outlines (edges between cells of different height or solidity, and at the board rim); a house is its box.
fn edge_share(l: &Layout, s: &[FreeSolid]) -> (f64, f64) {
    let solid_lm: Vec<bool> = (0..GRID * GRID).map(|i| l.landmarks.iter().any(|m| matches!(m.kind, LandmarkKind::TankCluster | LandmarkKind::Crane) && m.cells().any(|j| j == i))).collect();
    let key = |x: i64, z: i64| -> i32 {
        if x < 0 || z < 0 || x >= GRID as i64 || z >= GRID as i64 { return 0; }
        let i = z as usize * GRID + x as usize;
        if solid_lm[i] { 10 } else { i32::from(l.cells[i].level) }
    };
    let mut axis = 0.0;
    for z in -1..GRID as i64 { for x in -1..GRID as i64 {
        if key(x, z) != key(x + 1, z) && z >= 0 { axis += 3.0; }
        if key(x, z) != key(x, z + 1) && x >= 0 { axis += 3.0; }
    }}
    let mut off = 0.0;
    for b in s {
        let per = 4.0 * (b.he_in[0] + b.he_in[1]);
        let deg = b.yaw.to_degrees().rem_euclid(90.0);
        if deg.min(90.0 - deg) > 5.0 { off += per } else { axis += per }
    }
    (off, axis + off)
}

#[test]
#[ignore = "measurement: NML_N=1000 NML_ORGANIC_OUT=<file> cargo test --release --test boardgen_organic -- --ignored --nocapture"]
fn organic_census() {
    let n: i64 = std::env::var("NML_N").ok().and_then(|v| v.parse().ok()).unwrap_or(100);
    let (mut open, mut mid) = ([0.0; 2], [0.0; 2]);
    let (mut off, mut all, mut turned, mut houses, mut area, mut walk) = ([0.0; 2], [0.0; 2], 0, 0, 0.0, 0);
    let mut best = (0.0, 0);
    for seed in 1..=n {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let s = free_solids(&l);
        let p = to_plain(&l);
        for (k, set) in [flat(&l, &s), s.clone()].iter().enumerate() {
            let zones = zones_of_at(&Terrain::build(&with_solids(&p, set)), CURRENT_RULES_EPOCH);
            open[k] += zone_share(&l, &zones, &band_pairs());
            mid[k] += zone_share(&l, &zones, &mid_pairs());
            let (o, a) = edge_share(&l, set);
            off[k] += o;
            all[k] += a;
        }
        turned += s.iter().filter(|b| b.yaw.abs() >= 5f64.to_radians()).count();
        houses += s.len();
        let a: f64 = l.lots.iter().filter(|o| o.kind == LotKind::Roofed).map(|o| (o.w * o.h) as f64 * 9.0).sum();
        area += a;
        if a > best.0 { best = (a, seed); }
        walk += l.cells.iter().filter(|c| c.level >= 1 && c.lot_kind != LotKind::Roofed).count();
    }
    let f = n as f64;
    let out = format!("| board | opening rays blocked (real zones) | mid rays blocked (real zones) | non-axis plan outline |\n|---|---|---|---|\n\
        | houses at yaw 0 (C1) | {:.1} % | {:.1} % | {:.1} % |\n| houses turned (C3) | {:.1} % | {:.1} % | {:.1} % |\n\n\
        {n} seeds: houses {:.2} per board, turned >= 5 deg {:.2} per board ({:.0} %), intact-house lot area {:.1} sq in per board, walkable raised cells {:.1} per board; most intact area: seed {} ({:.0} sq in)\n",
        100.0 * open[0] / f, 100.0 * mid[0] / f, 100.0 * off[0] / all[0], 100.0 * open[1] / f, 100.0 * mid[1] / f, 100.0 * off[1] / all[1],
        houses as f64 / f, turned as f64 / f, 100.0 * turned as f64 / houses.max(1) as f64, area / f, walk as f64 / f, best.1, best.0);
    eprintln!("{out}");
    for seed in std::env::var("NML_SEEDS").unwrap_or_default().split(',').filter_map(|v| v.parse::<i64>().ok()) {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let s = free_solids(&l);
        let (o0, a0) = edge_share(&l, &flat(&l, &s));
        let (o1, a1) = edge_share(&l, &s);
        let line = format!("seed {seed}: non-axis plan outline {:.1} % (yaw 0) -> {:.1} % (turned); houses {} turned {}; yaws {:?}\n", 100.0 * o0 / a0, 100.0 * o1 / a1, s.len(),
            s.iter().filter(|b| b.yaw.abs() >= 5f64.to_radians()).count(), s.iter().map(|b| (b.yaw.to_degrees() * 10.0).round() / 10.0).collect::<Vec<_>>());
        eprint!("{line}");
    }
    if let Ok(path) = std::env::var("NML_ORGANIC_OUT") { std::fs::write(path, &out).expect("census file"); }
}

/// C4 red: a free box planted across the board is seen by the real zones; the cell helper of tests/boardgen.rs reads cells only
/// and cannot see it. The board is emptied (no cells, no tiers) so every ray is clear before the plant.
#[test]
fn the_real_zone_census_sees_a_free_box() {
    let l = generate_themed(7, Symmetry::Point180, Theme::RuinTown);
    let flat = |l: &Layout| { let mut f = l.clone(); for c in &mut f.cells { c.level = 0; } f };
    let (lf, p) = (flat(&l), PlainTerrain { cells: Vec::new(), tiers: None, ..to_plain(&l) });
    let pairs = band_pairs();
    let base = zone_share(&lf, &zones_of_at(&Terrain::build(&with_solids(&p, &[])), CURRENT_RULES_EPOCH), &pairs);
    let wall = FreeSolid { c_in: [0.0, 0.0], he_in: [24.0, 0.5], yaw: 0.2, lot: 0 };   // a planted, turned box across the whole board
    let planted = zone_share(&lf, &zones_of_at(&Terrain::build(&with_solids(&p, &[wall])), CURRENT_RULES_EPOCH), &pairs);
    assert!(base == 0.0 && planted > 0.9, "the real-zone census missed a planted box: {base} -> {planted}");
}
