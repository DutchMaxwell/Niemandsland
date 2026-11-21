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
