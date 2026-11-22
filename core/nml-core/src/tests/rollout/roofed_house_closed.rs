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
        && { let c = l.cell(x as usize, z as usize); c.level == 0 && !matches!(c.lot_kind, LotKind::Roofed | LotKind::Hazard | LotKind::Tower) };
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
        && { let c = l.cell(x as usize, z as usize); c.level == 0 && !matches!(c.lot_kind, LotKind::Roofed | LotKind::Hazard | LotKind::Tower) };
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
        if !classed {   // planted "no house": everything that makes a cell a house goes - its class, its solid listing and (sight plan S2) its 4.5 in height
            plain.cells.retain(|c| c[2] as i32 != CONTAINER);
            let tiers = plain.tiers.as_mut().expect("tiers");
            for &i in &plain.solid_cells { tiers.level_in[usize::from(i)] = f64::from(crate::boardgen::LEVEL_IN[usize::from(l.cells[usize::from(i)].level)]); }
            plain.solid_cells.clear();
        }
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
    eprintln!("planted no-house twin: {} of {asked} lanes cross", crossed.len());
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
    eprintln!("planted no-house twin: {} of {open_asked} diagonals cut a house", open.len());
    assert!(!open.is_empty(), "planted: with no house class the diagonals must cut a house: 0 of {open_asked}");
}

/// L-RF1 F5: every reader agrees that an intact house is closed, on town seeds 1..=60 - per house cell: class CONTAINER,
/// no rest (`gate::rest_forbidden`), deployment refuses it for a walker and a flier (`cell_blocked`), every border to open
/// ground is a deployment wall (`wall_blocked`), no objective marker, no ladder touches it, sight across it is blocked.
/// Returns the readers found OPEN as lines. Not covered here (logged in the plan): the charge reach index (its CONTAINER
/// cost is infinite, read) and the solid landmarks (wells, crane feet: D-F2's own step).
fn open_readers(seeds: std::ops::RangeInclusive<i64>, solid: bool) -> (usize, Vec<String>) {
    use crate::deployment::{cell_blocked, wall_blocked};
    let (mut cells, mut open) = (0, Vec::new());
    for seed in seeds {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let mut plain = to_plain(&l);
        if !solid {   // planted: the house is no longer solid - its listing and (sight plan S2) its 4.5 in height go, the class stays
            let tiers = plain.tiers.as_mut().expect("tiers");
            for &i in &plain.solid_cells { tiers.level_in[usize::from(i)] = f64::from(crate::boardgen::LEVEL_IN[usize::from(l.cells[usize::from(i)].level)]); }
            plain.solid_cells.clear();
        }
        let t = Terrain::build(&plain);
        let marks = crate::objectives::Cells::from_terrain(&t);
        let ladders = &plain.tiers.as_ref().unwrap().ladders;
        let half = [l.nx as f64 * 1.5, l.nz as f64 * 1.5];
        for c in l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed) {
            cells += 1;
            let (x, z) = (c.x as f64 * 3.0 + 1.5, c.z as f64 * 3.0 + 1.5); // planner inch frame
            let m = |px: f64, pz: f64| ((px - half[0]) * crate::IN2M, (pz - half[1]) * crate::IN2M);
            let mut say = |what: &str| open.push(format!("seed {seed} cell ({},{}): {what}", c.x, c.z));
            let w = m(x, z);
            if t.type_at([w.0 as f32, 0.0, w.1 as f32]) != CONTAINER { say("class"); }
            if !crate::mv::gate::rest_forbidden([x, z], 0.5, &t) { say("rest"); }
            if !cell_blocked(&t, w, false) || !cell_blocked(&t, w, true) { say("deployment cell"); }
            if crate::objectives::is_legal((x - half[0] - 0.5) as i64, (z - half[1] - 0.5) as i64, &[], &[], &marks) { say("marker"); }
            let i = (c.z * l.nx + c.x) as u16;
            if ladders.iter().any(|p| p.contains(&i)) { say("ladder"); }
            for (dx, dz) in [(-1i64, 0i64), (1, 0), (0, -1), (0, 1)] {
                let (nx, nz) = (c.x as i64 + dx, c.z as i64 + dz);
                if !(0..l.nx as i64).contains(&nx) || !(0..l.nz as i64).contains(&nz) { continue; }
                let n = l.cell(nx as usize, nz as usize);
                if n.level != 0 || matches!(n.lot_kind, LotKind::Roofed | LotKind::Tower) { continue; }   // (towers plan T2: a tall tower is no open ground either)
                if !wall_blocked(&t, m(x + dx as f64 * 1.5, z + dz as f64 * 1.5)) { say("border wall"); }
                let (a, b) = (m(x + dx as f64 * 3.0, z + dz as f64 * 3.0), m(x - dx as f64 * 3.0, z - dz as f64 * 3.0));
                let lifted = |p: (f64, f64)| [p.0 as f32, 0.02, p.1 as f32];
                if !t.los_blocked_at(lifted(a), lifted(b), CURRENT_RULES_EPOCH) { say("sight"); }
            }
        }
    }
    (cells, open)
}

#[test]
fn every_reader_agrees_a_house_is_closed() {
    let (cells, open) = open_readers(1..=60, true);
    assert!(cells > 300, "the seeds must give houses: {cells}");
    assert!(open.is_empty(), "{} readers open over {cells} house cells:\n{}", open.len(), open.join("\n"));
    let (_, planted) = open_readers(1..=60, false);
    assert!(planted.iter().any(|s| s.ends_with("border wall")), "planted: without solid_cells the border walls must be open, or the check proves nothing");
}

/// L-RF1 F5: a Flying model may cross a house but never ends on it (the K1 lanes, seeds 7 / 25 / 41).
#[test]
fn a_flier_crosses_a_house_but_never_ends_on_it() {
    let (mut asked, mut inside) = (0, Vec::new());
    for seed in [7, 25, 41] {
        let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
        let t = Terrain::build(&to_plain(&l));
        for (lx, lz, a, b) in lanes(&l).into_iter().chain(diagonals(&l)) {
            let ((ax, az), (bx, bz)) = (centre_m(&l, a), centre_m(&l, b));
            let mut st = state_at(ax, az);
            std::rc::Rc::get_mut(&mut st.profiles).expect("owned").list[0].special_rules.push("Flying".into());
            let land = (MoveRules { rules_epoch: CURRENT_RULES_EPOCH }).plain_move(&st, &t, 0, [bx as f32, 0.0, bz as f32], 24.0, false, true, crate::mv::FAST_PLANNER_GUARD).expect("a landing");
            let end = t.to_inch(land.end[0]);
            asked += 1;
            if l.cell((end[0] / 3.0) as usize, (end[1] / 3.0) as usize).lot_kind == LotKind::Roofed {
                inside.push(format!("seed {seed} house ({lx},{lz}) lane {a:?} -> {b:?} ends at {end:?}"));
            }
        }
    }
    assert!(asked >= 16);
    assert!(inside.is_empty(), "{} of {asked} flights end on a house:\n{}", inside.len(), inside.join("\n"));
}
