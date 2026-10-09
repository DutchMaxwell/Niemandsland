use super::*;
use crate::terrain::{CellParams, PlainTerrain, Terrain, CONTAINER};
use crate::IN2M;

/// The school table (6x4 ft on the 3" grid), built through the public terrain API as
/// `terrain.rs`'s own test fixture does.
fn school(cells: &[(i64, i64, i32)]) -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: cells.iter().map(|c| [c.0 as f64, c.1 as f64, c.2 as f64]).collect(),
        sandbox: vec![],
        pieces: vec![],
        walls: vec![],
        cell_params: CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: IN2M,
        },
    })
}

#[test]
fn cell_and_centre_round_trip_over_the_whole_table() {
    let t = school(&[]);
    let (nx, ny) = (72u16, 48u16);
    assert_eq!((nx_of(&t), ny_of(&t)), (nx as i64, ny as i64));
    for id in 0..(nx as u32 * ny as u32) {
        let id = id as u16;
        let c = cell_centre(&t, id, 0.0);
        assert_eq!(cell_of(&t, c), Some(id), "id {id}");
    }
    // a point past the table edge is off the grid
    assert_eq!(cell_of(&t, t.from_inch([-0.5f32, 10.0], 0.0)), None);
}

#[test]
fn mirror_cell_is_an_involution() {
    let (nx, ny) = (72u16, 48u16);
    for id in [0u16, 1, 71, 72, 1728, 3455] {
        assert_eq!(mirror_cell(mirror_cell(id, nx, ny), nx, ny), id, "id {id}");
    }
}

#[test]
fn reachable_cells_stay_in_band_and_clear_of_edges_and_containers() {
    let mut st = crate::sim::tests::four_unit_line();
    // move unit 0 to (1", 1") — one inch from the table's near corner — so the base-radius edge
    // exclusion actually bites within the 6" band
    st.positions[0] = vec![[-35.0 * IN2M, 0.0, -23.0 * IN2M]];
    let centre = crate::geom::centre(&st.positions[0]);
    // a CONTAINER three inches to the unit's +x side
    let t0 = school(&[]);
    let pin = t0.to_inch(centre);
    let sc = t0.school_cell_of((pin[0] + 3.0) as f64, pin[1] as f64);
    let t = school(&[(sc.0, sc.1, CONTAINER)]);
    let reach = crate::sim::reach_index_for_state(&st, &t).unwrap();
    let cells = reachable_cells(&st, &[], &t, &reach, 0, 6.0);
    assert!(!cells.is_empty());
    for &id in &cells {
        let p = cell_centre(&t, id, centre[1]);
        let q = t.to_inch(p);
        let d = (((p[0] - centre[0]) as f64).hypot((p[2] - centre[2]) as f64)) / IN2M;
        assert!(d <= 6.0 + 1e-6, "cell {id} at {d} in is outside the band");
        // inside the table by at least the base radius (unit 0's is 1")
        assert!(q[0] as f64 >= 1.0 - 1e-6 && q[1] as f64 >= 1.0 - 1e-6, "cell {id} too close to an edge");
        assert!(q[0] as f64 <= 72.0 - 1.0 + 1e-6 && q[1] as f64 <= 48.0 - 1.0 + 1e-6);
        assert_ne!(t.type_at(p), CONTAINER, "cell {id} lands in a container");
    }
}
