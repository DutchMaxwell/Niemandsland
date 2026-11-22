//! L-RF1 (PLAN_RUINTOWN_ROOFS) - a solid tier cell (an intact house) is closed by Cliff edges on every border, so every
//! reader of the tier edges (planner walls, rest clearance, deployment, `check_move`) sees a wall round it.
use crate::mv::tier::{HighSide, TierEdge, TierKind};
use crate::terrain::{PlainTerrain, Terrain, TierGrid, SOLID_TOP_IN};

/// 4 x 4 cells of 3 in, board-centred: vertex (i, j) = (-6 + 3i, -6 + 3j); cell index = z * 4 + x.
fn grid(level_in: Vec<f64>) -> TierGrid {
    TierGrid { nx: 4, nz: 4, cell_in: 3.0, level_in, ladders: vec![], stairs: vec![] }
}

fn cliff(a: [f64; 2], b: [f64; 2], dy_in: f64, high: HighSide) -> TierEdge {
    TierEdge { a, b, dy_in, high, kind: TierKind::Cliff }
}

fn board(level_in: Vec<f64>, solid: Vec<u16>) -> Terrain {
    painted(level_in, solid, false)
}

/// `board`, with `container` painting the type cell under tier cell 5 CONTAINER (a 1 ft table: type cell = tier cell + 1).
fn painted(level_in: Vec<f64>, solid: Vec<u16>, container: bool) -> Terrain {
    let cells = if container { serde_json::json!([[2.0, 2.0, crate::terrain::CONTAINER as f64]]) } else { serde_json::json!([]) };
    let mut p: PlainTerrain = serde_json::from_value(serde_json::json!({"cells": cells, "sandbox": [],
        "cell_params": {"table_size_feet": [1.0, 1.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0,
            "inches_to_meters": crate::IN2M}})).unwrap();
    p.tiers = Some(grid(level_in));
    p.solid_cells = solid;
    Terrain::build(&p)
}

/// Red before F1: `edges_with` / `solid_cells` did not exist. The planted variant (no solid cell) keeps 0 edges.
#[test]
fn a_solid_cell_is_closed_by_four_cliffs_with_the_cell_on_the_high_side() {
    use HighSide::{Left, Right};
    let flat = grid(vec![0.0; 16]);
    assert!(flat.edges_with(&[]).is_empty(), "planted: no solid cell, a flat grid has no edge");
    assert_eq!(flat.edges_with(&[5]), vec![
        cliff([-3.0, -3.0], [-3.0, 0.0], SOLID_TOP_IN, Right), // west face of cell (1,1)
        cliff([0.0, -3.0], [0.0, 0.0], SOLID_TOP_IN, Left),    // east face
        cliff([-3.0, -3.0], [0.0, -3.0], SOLID_TOP_IN, Left),  // north face, high side south
        cliff([-3.0, 0.0], [0.0, 0.0], SOLID_TOP_IN, Right),   // south face, high side north
    ]);
    let t = board(vec![0.0; 16], vec![5]);
    assert_eq!(t.tier_walls_in().len(), 4);
    assert!(t.solid_at(-1.5, -1.5) && !t.solid_at(1.5, -1.5) && !t.solid_at(-1.5, 1.5));
    assert!(!board(vec![0.0; 16], vec![]).solid_at(-1.5, -1.5), "planted: not listed = not solid");
}

#[test]
fn a_two_cell_house_has_no_inner_edge_and_a_solid_beside_a_block_still_has_a_cliff() {
    let pair = grid(vec![0.0; 16]).edges_with(&[5, 6]);
    assert_eq!(pair.len(), 4, "one run per face: {pair:?}");
    assert!(!pair.iter().any(|e| e.a[0] == 0.0 && e.b[0] == 0.0), "no edge between the two solid cells");
    let mut levels = vec![0.0; 16];
    levels[6] = 3.0;
    let beside = grid(levels).edges_with(&[5]);
    assert!(beside.contains(&cliff([0.0, -3.0], [0.0, 0.0], SOLID_TOP_IN - 3.0, HighSide::Left)), "{beside:?}");
}

/// Deepworks pins depend on this: an empty list never reaches the header.
#[test]
fn an_empty_solid_list_does_not_serialise_and_a_written_one_comes_back() {
    let mut p = PlainTerrain::default();
    assert!(!serde_json::to_string(&p).unwrap().contains("solid_cells"));
    p.solid_cells = vec![5, 6];
    let back: PlainTerrain = serde_json::from_str(&serde_json::to_string(&p).unwrap()).unwrap();
    assert_eq!(back.solid_cells, vec![5, 6]);
}

/// L-RF1 F2: a base whose centre is over a solid CONTAINER cell is NOT "on the roof" - it overlaps a block and the end cut
/// walks it out past the cliff; the same cell unlisted stays today's climbable container roof. Red before F2: the first
/// assert (the roof exemption ignored `solid_cells`).
#[test]
fn nobody_stands_on_a_solid_cell_but_a_container_roof_stays() {
    let (house, roof) = (painted(vec![0.0; 16], vec![5], true), painted(vec![0.0; 16], vec![], true));
    let centre = [4.5, 4.5]; // tier cell 5 in the planner's 0-origin inch frame (board 12 x 12 in)
    assert!(crate::mv::gate::overlaps_block(centre, 0.5, &house), "a solid cell is no roof");
    assert!(!crate::mv::gate::overlaps_block(centre, 0.5, &roof), "planted: an unlisted container is a roof to stand on");
    let cut = crate::mv::gate::rest_legal_cut(&[[4.5, 10.5], [4.5, 4.5]], 0.5, &house).expect("a legal spot on the route");
    let end = cut.last().unwrap();
    assert!(end[1] >= 6.5, "the base ends outside the house and off its cliff: {end:?}");
    let w = [-1.5 * crate::IN2M, -1.5 * crate::IN2M];
    let epoch = crate::acts::CURRENT_RULES_EPOCH;
    assert_eq!(crate::sight::surface_y_m(&house, w, epoch), 0.0, "no model height on a house");
    assert!(crate::sight::surface_y_m(&roof, w, epoch) > 0.0, "planted: a container roof keeps its 2.5 in");
}

/// L-RF1 F4: the human drop check (`activation::check_move`) on a 2 x 2 house (cells 5, 6, 9, 10 of the 4 x 4 board).
/// Unit "a" starts at the centre of cell (0,1), world (-4.5, -1.5) in. Measured on the parent of F4: the straight
/// crossing was refused only as a cliff, the end inside by Flying and the corner-to-corner trail were Ok (red).
mod human_drop {
    use super::painted;
    use crate::activation::{check_move, Check, Drop};
    use crate::io::Seams;
    use crate::sim::RUSH;
    use crate::unit::UnitStatic;
    use std::rc::Rc;

    fn w(x_in: f64, z_in: f64) -> [f64; 2] {
        [x_in * crate::IN2M, z_in * crate::IN2M]
    }

    fn go(flying: bool, start: [f64; 2], trail: Vec<[f64; 2]>) -> Check {
        let mut st = crate::sim::tests::four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(crate::state::Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
        if flying {
            Rc::get_mut(&mut st.profiles).expect("owned").list[0].special_rules.push("Flying".into());
        }
        st.positions[0] = vec![[start[0], 0.0, start[1]]];
        let end = *trail.last().unwrap();
        let statics = vec![UnitStatic { name: "Squad".into(), ..Default::default() }];
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        let t = painted(vec![0.0; 16], vec![5, 6, 9, 10], true);
        check_move(&statics, &st, 0, seams, &t, &Drop { mode: RUSH, placed: vec![[end[0], 0.0, end[1]]], trails: vec![trail] }, true)
    }

    fn refused() -> Check {
        Check::Refused { reason: "Squad: a building is impassable".into() }
    }

    #[test]
    fn a_drop_through_into_or_across_the_corner_of_a_house_is_refused() {
        let a = w(-4.5, -1.5);
        assert_eq!(go(false, a, vec![a, w(4.5, -1.5)]), refused(), "straight through");
        assert_eq!(go(false, a, vec![a, w(-1.5, -1.5)]), refused(), "ends inside");
        assert_eq!(go(true, a, vec![a, w(-1.5, -1.5)]), refused(), "Flying ends inside");
        // the diagonal runs exactly through the house's grid vertices (-3,-3), (0,0), (3,3): 9.9 in, inside the Rush band
        let c = w(-3.5, -3.5);
        assert_eq!(go(false, c, vec![c, w(3.5, 3.5)]), refused(), "corner to corner through the 2 x 2 house");
        // lead review: a leg exactly through a house corner into the house (the corner vertex (-3,-3) is where the north
        // and west cliff runs END, so the segment test sees no crossing) is refused
        assert_eq!(go(false, w(-4.5, -4.5), vec![w(-4.5, -4.5), w(-1.5, -1.5)]), refused(), "through the exact corner, into the house");
        assert!(matches!(go(true, a, vec![a, w(4.5, -1.5)]), Check::Ok { .. }), "Flying crosses a house");
        assert!(matches!(go(false, a, vec![a, w(-4.5, 4.5)]), Check::Ok { .. }), "planted: a drop beside the house is Ok");
    }

    /// Lead review: a leg through the point where two cliff pieces meet. Cell 5 is a house, cell 6 east of it a 3 in block,
    /// so the border z = -3 is two runs (house x -3..0, block x 0..3) joined at (0,-3); the leg from cell (2,0) into the
    /// house passes exactly through that joint, where the segment test sees neither run.
    #[test]
    fn a_leg_through_a_cliff_joint_into_a_house_is_refused() {
        let mut levels = vec![0.0; 16];
        levels[6] = 3.0;
        let mut st = crate::sim::tests::four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(crate::state::Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
        let (a, b) = (w(1.5, -4.5), w(-1.5, -1.5));
        st.positions[0] = vec![[a[0], 0.0, a[1]]];
        let statics = vec![UnitStatic { name: "Squad".into(), ..Default::default() }];
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        let t = painted(levels, vec![5], true);
        let drop = Drop { mode: RUSH, placed: vec![[b[0], 0.0, b[1]]], trails: vec![vec![a, b]] };
        assert_eq!(check_move(&statics, &st, 0, seams, &t, &drop, true), refused());
    }
}

/// Lead review 22.11.: the floor under a solid tier cell is the ground, not its height - `surface_y_m` (the end-of-activation settle of
/// models and moved markers) skips the tier term on a solid cell, for a tall tower (12 in) and a house at its ridge (4.5 in). Planted:
/// the same cells unlisted are tier tops at their height. Red before: the settle put a model 12 in up, on top of a tower.
#[test]
fn nobody_settles_on_top_of_a_tower_or_a_house() {
    let epoch = crate::acts::CURRENT_RULES_EPOCH;
    let w = [-1.5 * crate::IN2M, -1.5 * crate::IN2M]; // the centre of tier cell 5 (world, board-centred)
    for top in [crate::boardgen::plain::TOWER_IN, 4.5] {
        let mut level = vec![0.0; 16];
        level[5] = top;
        let (solid, open) = (board(level.clone(), vec![5]), board(level, vec![]));
        assert_eq!(crate::sight::surface_y_m(&solid, w, epoch), 0.0, "a model settles on top of a {top} in solid cell");
        assert!((crate::sight::surface_y_m(&open, w, epoch) - top * crate::IN2M).abs() < 1e-9, "planted: an unlisted {top} in cell is a floor at its height");
        let mut models = vec![[w[0], 1.0, w[1]]];
        crate::sim::settle_models(&solid, &mut models, epoch);
        assert_eq!(models[0][1], 0.0, "the settle leaves a model on a {top} in solid cell");
    }
}

/// Sight plan S2: an intact house blocks sight to its drawn ridge (`HOUSE_TOP_IN` 4.5 in) and no higher, a tall tower to `TOWER_IN`. One row of an 8 x 8 board:
/// the viewer stands on cell 0 on a floor of 0 / 3 / 6 / 9 in, the house is cell 1, the target stands on the ground of cell 5 (four cells beyond the house).
/// Red before S2: a house read 2.5 in in `level_in` was not a tier block at all, so the 3 in viewer saw over it.
#[test]
fn a_house_blocks_sight_to_its_ridge_and_no_higher() {
    use crate::boardgen::plain::{HOUSE_TOP_IN, TOWER_IN};
    use crate::sight::{has_los, zones_of_at, Cyl};
    let sees = |floor_in: f64, block_in: f64, solid: bool| {
        let mut level_in = vec![0.0; 64];
        level_in[8 * 3] = floor_in;   // the viewer's cell (0, 3)
        level_in[8 * 3 + 1] = block_in;   // the house / tower cell (1, 3)
        let mut p: PlainTerrain = serde_json::from_value(serde_json::json!({"cells": [], "sandbox": [],
            "cell_params": {"table_size_feet": [2.0, 2.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0,
                "inches_to_meters": crate::IN2M}})).unwrap();
        p.tiers = Some(TierGrid { nx: 8, nz: 8, cell_in: 3.0, level_in, ladders: vec![], stairs: vec![] });
        p.solid_cells = if solid { vec![8 * 3 + 1] } else { vec![] };
        let t = Terrain::build(&p);
        let zones = zones_of_at(&t, crate::acts::CURRENT_RULES_EPOCH);
        let m = crate::IN2M;
        let cyl = |x_in: f64, y_in: f64| Cyl { c: [x_in * m, -1.5 * m], r: 0.4 * m, y0: y_in * m, y1: (y_in + 1.25) * m };
        has_los(&cyl(-10.5, floor_in), &cyl(4.5, 0.0), false, &zones, &[])
    };
    assert!(!sees(0.0, HOUSE_TOP_IN, true), "a ground viewer sees over a house");
    assert!(!sees(3.0, HOUSE_TOP_IN, true), "a viewer on a 3 in floor (eye 4.25 in) sees over a 4.5 in ridge");
    assert!(sees(6.0, HOUSE_TOP_IN, true), "a viewer on a 6 in floor must see over a house");
    assert!(sees(9.0, HOUSE_TOP_IN, true), "a viewer on a 9 in floor must see over a house");
    assert!(!sees(9.0, TOWER_IN, true), "a viewer on a 9 in floor sees over a tall tower");
    assert!(sees(0.0, 0.0, false) && sees(3.0, 0.0, false), "planted: without the house every viewer sees");
}

/// Sight plan S2 (lead 22.11.): now that a house cell carries its 4.5 in height, F2 must still hold - a base whose centre is over it overlaps a block and the end cut
/// walks it out. Planted: the same 4.5 in cell NOT listed solid is a plain tier top a model may rest on (the check can fail).
#[test]
fn nobody_rests_on_a_house_that_has_its_ridge_height() {
    let mut level = vec![0.0; 16];
    level[5] = crate::boardgen::plain::HOUSE_TOP_IN;
    let (house, tier) = (painted(level.clone(), vec![5], true), painted(level, vec![], false));
    let centre = [4.5, 4.5];
    assert!(crate::mv::gate::overlaps_block(centre, 0.5, &house), "a 4.5 in house cell is a roof to rest on");
    let cut = crate::mv::gate::rest_legal_cut(&[[4.5, 10.5], [4.5, 4.5]], 0.5, &house).expect("a legal spot on the route");
    assert!(cut.last().unwrap()[1] >= 6.5, "the base ends outside the house: {cut:?}");
    assert!(!crate::mv::gate::overlaps_block(centre, 0.5, &tier), "planted: an unlisted 4.5 in tier top is standing room");
}
