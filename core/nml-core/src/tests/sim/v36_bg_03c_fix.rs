//! Rules 3.6 row BG-03c-fix (audit A): the Rust core and the GDScript planner must price a long
//! leg through ruin ground the same way — the long-ruin Dangerous price outranks the Difficult
//! debuff, and a Flying unit is exempt from the ruin price.
use super::*;

use crate::mv::cost::{segment_cost, terrain_cost_at, Grid, StepOpts};
use crate::mv::{T_DANGEROUS, T_RUINS};
use crate::terrain::{CellParams, PlainTerrain, Terrain};

/// ONE coarse (3") cell at (1, 0): x in [3", 6"), y in [0", 3").
fn cell_grid(kind: i64) -> Grid {
    let mut grid = Grid::default();
    grid.insert((1, 0), kind);
    grid
}

fn cost_opts(difficult_debuff: bool, unstable_danger: bool) -> StepOpts<'static> {
    let mut o = StepOpts::new(0.0, &[]);
    o.difficult_debuff = difficult_debuff;
    o.unstable_danger = unstable_danger;
    o
}

/// A long leg through a ruin keeps the Difficult price everywhere EXCEPT the ruin samples, which
/// the rules 3.6 ruin override prices as Dangerous: 7" open * 2 + 3" ruin * 6 = 32.
#[test]
fn long_ruin_leg_with_difficult_debuff_prices_the_ruin_as_dangerous() {
    let cost = segment_cost([0.0, 1.5], [10.0, 1.5], &cell_grid(T_RUINS), &cost_opts(true, true));
    assert!((cost - 32.0).abs() < 1e-6, "cost was {cost}");
}

/// A leg of 6" or less does not risk the ruin test, so the Difficult debuff keeps every sample
/// at 2: 4" * 2 = 8.
#[test]
fn short_ruin_leg_keeps_the_difficult_price() {
    let cost = segment_cost([3.5, 1.5], [7.5, 1.5], &cell_grid(T_RUINS), &cost_opts(true, true));
    assert!((cost - 8.0).abs() < 1e-6, "cost was {cost}");
}

/// A Dangerous cell outranks the Difficult debuff: 6.
#[test]
fn dangerous_cell_with_difficult_debuff_prices_as_dangerous() {
    let cost = terrain_cost_at([4.5, 1.5], &cell_grid(T_DANGEROUS), &cost_opts(true, false));
    assert!((cost - 6.0).abs() < 1e-6, "cost was {cost}");
}

/// The school table (6x4 ft, 3" grid) with ONE painted cell.
fn one_cell_board(kind: i32) -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: vec![[14.0, 15.0, kind as f64]],
        sandbox: Vec::new(),
        pieces: Vec::new(),
        walls: vec![],
        cell_params: CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: IN2M,
        },
    })
}

fn at(x_in: f64, z_in: f64) -> [f64; 3] {
    [x_in * IN2M, 0.0, z_in * IN2M]
}

/// ONE four-model unit (host only) standing in a column inside the painted cell's z band.
fn solo_line() -> (State, Vec<UnitStatic>) {
    let (mut st, statics) = dangerous_line();
    Rc::make_mut(&mut st.attached)[0].clear();
    Rc::make_mut(&mut st.attached_to)[1] = None;
    for u in 1..4 {
        st.positions[u].clear();
        Rc::make_mut(&mut st.radii)[u].clear();
        st.alive[u] = 0;
    }
    st.positions[0] = (0..4).map(|k| at(-5.0, 1.0 + 0.5 * k as f64)).collect();
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 4];
    (st, statics)
}

fn set_flying(st: &mut State) {
    let mut p = st.profiles.list[0].clone();
    p.special_rules.push("Flying".into());
    st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
}

/// The landing the unit gets when ordered `run_in` inches along +x through the painted cell.
fn run(st: &State, t: &Terrain, run_in: f64, epoch: u32) -> crate::mv::step::Landing {
    let start = crate::geom::centre(&st.positions[0]);
    let dest = [start[0] + (run_in * IN2M) as f32, 0.0, start[2]];
    (crate::mv::step::MoveRules { rules_epoch: epoch })
        .plain_move(st, t, 0, dest, run_in, false, true, crate::mv::FAST_PLANNER_GUARD)
        .expect("the board is real and the unit has models")
}

/// A Flying unit flies over the ruin: the plan call must not switch the ruin price on.
#[test]
fn flying_unit_skips_the_ruin_price_at_epoch_73() {
    let (mut st, _) = solo_line();
    set_flying(&mut st);
    let land = run(&st, &one_cell_board(crate::terrain::RUINS), 8.0, crate::acts::EPOCH_73_V36);
    let call = land.call.expect("a plan call");
    assert!(!call.opts.unstable_danger, "flying must skip the ruin price");
}

/// Control: the same unit on foot keeps the ruin price.
#[test]
fn non_flying_unit_keeps_the_ruin_price_at_epoch_73() {
    let (st, _) = solo_line();
    let land = run(&st, &one_cell_board(crate::terrain::RUINS), 8.0, crate::acts::EPOCH_73_V36);
    let call = land.call.expect("a plan call");
    assert!(call.opts.unstable_danger, "a walking unit keeps the ruin price");
}
