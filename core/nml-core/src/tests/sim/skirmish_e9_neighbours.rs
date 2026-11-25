//! The skirmish Blast(X) spread's neighbours (`sim::blast_neighbours`): the target's own side, base edge to base edge
//! within the spread distance (3 in in the Firefight / AoF: Skirmish books), with their living models.
use super::*;

/// Unit 0 = the target (two models at x 20 / 21.5 in), unit 1 its side at 2.9 in edge gap, unit 2 its side at 3.1 in,
/// unit 3 the shooter's side at 0.5 in. 32 mm bases (0.63 in radius): centre distance = gap + 1.26 in.
fn spread_line() -> State {
    let mut st = four_unit_line();
    let r = 0.63 * IN2M;
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![
        vec![at(20.0, 20.0), at(21.5, 20.0)],
        vec![at(21.5, 20.0 + 2.9 + 1.26)],
        vec![at(20.0 - 3.1 - 1.26, 20.0)],
        vec![at(20.0, 20.0 - 0.5 - 1.26)],
    ];
    st.radii = Rc::new(vec![vec![r, r], vec![r], vec![r], vec![r]]);
    st.player = vec![1, 1, 1, 0];
    st.alive = vec![2, 1, 1, 1];
    st
}

#[test]
fn only_the_targets_side_within_the_spread_counts() {
    let st = spread_line();
    assert_eq!(blast_neighbours(&st, 0, 3.0), vec![(1, 1)], "2.9 in in, 3.1 in out, the shooter's side never");
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(1, 1), (2, 1)]);
    assert_eq!(blast_neighbours(&st, 0, 2.8), vec![]);
}

/// A destroyed unit, or one off the table (in reserve: no models placed), takes no share.
#[test]
fn a_dead_or_reserved_unit_is_no_neighbour() {
    let mut st = spread_line();
    st.alive[1] = 0;
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(2, 1)]);
    let mut st = spread_line();
    st.positions[2].clear();
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(1, 1)]);
}
