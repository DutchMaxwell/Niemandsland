//! FALL-REPLACE (3.6 p.15, D-27c): after a fall the others stand within 1 in of the fallen model - the table's lock asks
//! `fall_replace_needed`, its "Place for me" button takes `regroup_around`.
use super::*;
use crate::sim::{fall_replace_needed, regroup_around};
use crate::terrain::Terrain;

/// Unit "a" as three 1 in radius models on the x axis: model 1 at 0, model 2 `gap2` in and model 3 `gap3` in base to base
/// from it; the other units far away.
fn three(gap2: f64, gap3: f64) -> State {
    let mut st = four_unit_line();
    st.positions = vec![
        vec![[0.0, 0.0, 0.0], [(2.0 + gap2) * IN2M, 0.0, 0.0], [-(2.0 + gap3) * IN2M, 0.0, 0.0]],
        vec![[30.0 * IN2M, 0.0, 0.0]],
        vec![[40.0 * IN2M, 0.0, 0.0]],
        vec![[50.0 * IN2M, 0.0, 0.0]],
    ];
    st.wounds[0] = vec![1; 3];
    st.radii = Rc::new(vec![vec![IN2M; 3], vec![IN2M], vec![IN2M], vec![IN2M]]);
    st
}

fn gap_in(p: &[[f64; 3]], a: usize, b: usize) -> f64 {
    (p[a][0] - p[b][0]).hypot(p[a][2] - p[b][2]) / IN2M - 2.0
}

#[test]
fn a_model_3_in_off_the_fallen_one_is_placed_within_1_in() {
    let st = three(0.5, 3.0);
    assert!(fall_replace_needed(&st, 0, 0));
    let (pos, line) = regroup_around(&st, 0, 0, &Terrain::absent());
    assert_eq!(pos[1], st.positions[0][1], "model 2 already stands within 1 in");
    assert!((gap_in(&pos, 0, 2) - 1.0).abs() < 1e-6, "model 3 ends 1 in off: {}", gap_in(&pos, 0, 2));
    assert_eq!(line, "Fall: model 1 fell; model 3 placed within 1 in of it");
    assert_eq!(st.positions[0][2][0], -5.0 * IN2M, "pure: the handed state is not written");
}

#[test]
fn all_within_1_in_needs_no_move() {
    let st = three(0.5, 1.0);
    assert!(!fall_replace_needed(&st, 0, 0));
    let (pos, line) = regroup_around(&st, 0, 0, &Terrain::absent());
    assert_eq!(pos, st.positions[0]);
    assert_eq!(line, "");
    assert!(!fall_replace_needed(&st, 0, 3), "an unknown slot needs nothing");
    assert!(!fall_replace_needed(&st, 9, 0), "an unknown unit needs nothing");
}

/// The placer's spot after the f32 round trip of the table still counts as within 1 in; a millimetre beyond does not.
#[test]
fn the_placer_spot_read_back_through_f32_is_within_1_in() {
    let mut st = three(0.5, 3.0);
    for p in st.positions[0].iter_mut() {
        *p = [p[0] - 0.3657, p[1] + 0.1524, p[2] - 0.2667];   // where the table's ledge test stands (world metres)
    }
    let (pos, _) = regroup_around(&st, 0, 0, &Terrain::absent());
    let mut back = st.clone();
    back.positions[0] = pos.iter().map(|p| p.map(|v| f64::from(v as f32))).collect();
    assert!(!fall_replace_needed(&back, 0, 0), "f32 read-back: {}", gap_in(&back.positions[0], 0, 2));
    assert!(fall_replace_needed(&three(0.5, 1.0 + 0.001 / IN2M), 0, 0), "1 mm beyond 1 in still needs a re-place");
}
