//! Roofs plan step K1: no move passes through a roofed house. On generated town boards (seeds 7, 25, 41) a ground model
//! stands beside an intact house (`LotKind::Roofed`, terrain class CONTAINER) and the core's move planner is asked to
//! take it straight across to legal ground on the far side, along every lane through the house. The planner's route
//! (`Landing::trails`, the inch frame) must never enter a roofed cell; the end must never be one either.
//! The second test is the instrument check: the same lanes on a board whose houses carry no terrain class MUST cross.
//!
//! FIXED by L-RF1 F1-F3 (`PlainTerrain::solid_cells`: cliffs round every house cell, no roof exemption over it); the third
//! test adds the corner-to-corner lanes through every 2 x 2 house (the corner graze case) on seeds 1..=60.
//! WAS A KNOWN FAILURE (measured 21.11. on main 6a2972697): the first test was RED and `#[ignore]`d - 16 of 16 lanes cross a house and 5 end
//! inside one. `to_plain` writes no wall segments and a level-0 roofed cell has no tier edge, so the planner sees the house as open ground
//! (class CONTAINER only forbids a REST, and a centre over the footprint counts as standing on the roof, `gate::overlaps_block`).
//! Smallest repro: seed 7 (Point180, RuinTown), the 2 x 1 house at cell (4,5): from cell (5,4) to cell (5,6) the route is
//! [[16.5,13.5],[16.5,19.5]] in inches and ends on the far side. The look draws that house as a solid 2.5 in body under a roof.
//! The fix is the heightfield chain's (roofs plan L-RF1), not this step's; remove the `#[ignore]` with it.
use super::*;
use crate::boardgen::{generate_themed, plain::to_plain, Layout, LotKind, Symmetry, Theme};
use crate::mv::step::MoveRules;
use crate::terrain::CONTAINER;

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// One ground model at `(x, z)` metres, alone on the board.
fn state_at(x: f64, z: f64) -> State {
    let unit = format!(r#"{{"player":1,"alive":1,"wounds":[1],"radii":[0.016],"positions":[[{x},0.0,{z}]],"in_cover":false,
      "shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
      "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{{}},"mods_base":{{}},
      "bands":{{"advance":6.0,"rush":12.0}}}}"#);
    let plain = format!(r#"{{"round":1,"rounds_total":3,"scoring":"end","objectives":[],"units":{{"p1_0_a":{unit}}}}}"#);
    let mut cache = ProfileCache::new(read_act_header(HEADER).expect("header").profiles);
    io::state_from_json(&plain, &mut cache, &mut None).expect("state")
}

/// World metres of the centre of cell `(x, z)`.
fn centre_m(l: &Layout, (x, z): (usize, usize)) -> (f64, f64) {
    (((x as f64 + 0.5) - l.nx as f64 / 2.0) * f64::from(l.cell_in) * crate::IN2M, ((z as f64 + 0.5) - l.nz as f64 / 2.0) * f64::from(l.cell_in) * crate::IN2M)
}

/// A lane through a roofed house: `(lot x, lot z, from cell, to cell)`.
type Lane = (usize, usize, (usize, usize), (usize, usize));

/// Every straight lane through a roofed house with bare level-0 ground on both sides.
fn lanes(l: &Layout) -> Vec<Lane> {
    let ground = |x: i64, z: i64| (0..l.nx as i64).contains(&x) && (0..l.nz as i64).contains(&z)
        && { let c = l.cell(x as usize, z as usize); c.level == 0 && c.lot_kind != LotKind::Roofed && c.lot_kind != LotKind::Hazard };
    let mut out = Vec::new();
    for lot in l.lots.iter().filter(|lot| lot.kind == LotKind::Roofed) {
        let (x0, z0, x1, z1) = (lot.x as i64, lot.z as i64, (lot.x + lot.w) as i64, (lot.z + lot.h) as i64);
        let cell = |x: i64, z: i64| (x as usize, z as usize);
        for z in z0..z1 { if ground(x0 - 1, z) && ground(x1, z) { out.push((lot.x, lot.z, cell(x0 - 1, z), cell(x1, z))); out.push((lot.x, lot.z, cell(x1, z), cell(x0 - 1, z))); } }
        for x in x0..x1 { if ground(x, z0 - 1) && ground(x, z1) { out.push((lot.x, lot.z, cell(x, z0 - 1), cell(x, z1))); out.push((lot.x, lot.z, cell(x, z1), cell(x, z0 - 1))); } }
    }
    out
}

/// Both diagonals, both ways, through every house of at least 2 x 2 cells, corner cell to corner cell (ground on both).
fn diagonals(l: &Layout) -> Vec<Lane> {
    let ground = |x: i64, z: i64| (0..l.nx as i64).contains(&x) && (0..l.nz as i64).contains(&z)
        && { let c = l.cell(x as usize, z as usize); c.level == 0 && c.lot_kind != LotKind::Roofed && c.lot_kind != LotKind::Hazard };
    let mut out = Vec::new();
    for lot in l.lots.iter().filter(|lot| lot.kind == LotKind::Roofed && lot.w >= 2 && lot.h >= 2) {
        let (x0, z0, x1, z1) = (lot.x as i64 - 1, lot.z as i64 - 1, (lot.x + lot.w) as i64, (lot.z + lot.h) as i64);
        for (a, b) in [((x0, z0), (x1, z1)), ((x1, z0), (x0, z1))] {
            if ground(a.0, a.1) && ground(b.0, b.1) {
                let (a, b) = ((a.0 as usize, a.1 as usize), (b.0 as usize, b.1 as usize));
                out.push((lot.x, lot.z, a, b));
                out.push((lot.x, lot.z, b, a));
            }
        }
    }
    out
}

/// Does the route (inch frame, 0.25 in samples) enter a roofed cell?
fn enters_a_roof(l: &Layout, trail: &[[f32; 2]]) -> bool {
    let roofed = |p: [f32; 2]| p[0] >= 0.0 && p[1] >= 0.0 && ((p[0] / 3.0) as usize) < l.nx && ((p[1] / 3.0) as usize) < l.nz && l.cell((p[0] / 3.0) as usize, (p[1] / 3.0) as usize).lot_kind == LotKind::Roofed;
    trail.windows(2).any(|w| {
        let n = ((w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]) / 0.25).ceil().max(1.0) as usize;
        (0..=n).any(|k| { let f = k as f32 / n as f32; roofed([w[0][0] + (w[1][0] - w[0][0]) * f, w[0][1] + (w[1][1] - w[0][1]) * f]) })
    })
}

/// The lanes over the seeds, as `(lanes asked, one line per lane whose route enters a roof)`; `classed` false strips CONTAINER from the terrain.
fn crossings(classed: bool) -> (usize, Vec<String>) {
    crossings_on(&[7, 25, 41], classed, lanes)
}

/// `crossings` over `seeds` along the lanes `lanes_of` names.
fn crossings_on(seeds: &[i64], classed: bool, lanes_of: fn(&Layout) -> Vec<Lane>) -> (usize, Vec<String>) {
    let (mut asked, mut crossed) = (0, Vec::new());
    for &seed in seeds {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let mut plain = to_plain(&l);
        if !classed { plain.cells.retain(|c| c[2] as i32 != CONTAINER); plain.solid_cells.clear(); }
        let t = Terrain::build(&plain);
        for (lx, lz, a, b) in lanes_of(&l) {
            let ((ax, az), (bx, bz)) = (centre_m(&l, a), centre_m(&l, b));
            let st = state_at(ax, az);
            let dest = [bx as f32, 0.0, bz as f32];
            let land = (MoveRules { rules_epoch: CURRENT_RULES_EPOCH }).plain_move(&st, &t, 0, dest, 24.0, false, true, crate::mv::FAST_PLANNER_GUARD).expect("a landing");
            let trail = &land.trails[0];
            let from = t.to_inch([ax as f32, 0.0, az as f32]);
            assert!(trail.len() >= 2 && (trail[0][0] - from[0]).hypot(trail[0][1] - from[1]) < 0.5, "the route must start at the model (frame check): {trail:?} vs {from:?}");
            asked += 1;
            let end = t.to_inch(land.end[0]);
            let end_in_roof = l.cell((end[0] / 3.0) as usize, (end[1] / 3.0) as usize).lot_kind == LotKind::Roofed;
            let class = |p: [f32; 3]| t.type_at(p);
            if enters_a_roof(&l, trail) || end_in_roof {
                crossed.push(format!("seed {seed}, house at cell ({lx},{lz}): lane {a:?} -> {b:?}, route {trail:?}, ends at {end:?}{} (terrain class at the end {}, at the far cell {})", if end_in_roof { " IN the house" } else { "" }, class(land.end[0]), class(dest)));
            }
        }
    }
    (asked, crossed)
}

#[test]
fn no_move_passes_through_a_roofed_house() {
    let (asked, crossed) = crossings(true);
    assert!(asked >= 10, "the seeds must give lanes, or the run proves nothing: {asked}");
    assert!(crossed.is_empty(), "{} of {asked} lanes cross a roofed house:\n{}", crossed.len(), crossed.join("\n"));
}

#[test]
fn the_crossing_check_sees_a_house_when_its_terrain_class_is_removed() {
    let (asked, crossed) = crossings(false);
    assert!(asked >= 10 && !crossed.is_empty(), "with no CONTAINER class the same lanes must cross a house, or the check cannot fail: {} of {asked}", crossed.len());
}

/// L-RF1 corner graze: a leg exactly through a grid vertex of a 2 x 2 house touches the END of two cliff runs. Every
/// diagonal lane through such a house on seeds 1..=60 must stay out; the twin without the house class must cross.
#[test]
fn no_move_cuts_a_house_corner_to_corner() {
    let seeds: Vec<i64> = (1..=60).collect();
    let (asked, crossed) = crossings_on(&seeds, true, diagonals);
    assert!(asked >= 4, "the seeds must give 2 x 2 houses with open corners: {asked}");
    assert!(crossed.is_empty(), "{} of {asked} diagonal lanes cut a house:\n{}", crossed.len(), crossed.join("\n"));
    let (open_asked, open) = crossings_on(&seeds, false, diagonals);
    assert!(!open.is_empty(), "planted: with no house class the diagonals must cut a house: 0 of {open_asked}");
}
