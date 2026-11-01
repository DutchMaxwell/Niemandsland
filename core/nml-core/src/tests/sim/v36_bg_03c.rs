//! Rules 3.6 row BG-03c tests (unstable ruins, AI move cost) for the sim module; owned by lane ux.
use super::*;

use crate::mv::cost::{segment_cost, terrain_cost_at, Grid, StepOpts};
use crate::mv::T_RUINS;

/// The planner grid with ONE Unstable RUINS coarse cell (3"): cell (1, 0) covers x in [3", 6"),
/// y in [0", 3"). Every other cell is open ground.
fn ruin_grid() -> Grid {
    let mut grid = Grid::default();
    grid.insert((1, 0), T_RUINS);
    grid
}

fn step_opts(unstable_danger: bool) -> StepOpts<'static> {
    let mut o = StepOpts::new(0.0, &[]);
    o.unstable_danger = unstable_danger;
    o
}

/// rules 3.6: a leg longer than 6" through a ruin prices the ruin ground as Dangerous, so 3" of
/// ruin plus 7" of open ground costs 7 * 1 + 3 * 6 = 25.
#[test]
fn a_long_leg_through_a_ruin_prices_it_as_dangerous_at_rules_36() {
    let grid = ruin_grid();
    let cost = segment_cost([0.0, 1.5], [10.0, 1.5], &grid, &step_opts(true));
    assert!((cost - 25.0).abs() < 1e-6, "cost was {cost}");
}

/// The same 10" leg below the gate (epoch 72) keeps the ruin as open ground: 10.
#[test]
fn the_same_leg_below_the_gate_stays_open_ground() {
    let grid = ruin_grid();
    let cost = segment_cost([0.0, 1.5], [10.0, 1.5], &grid, &step_opts(false));
    assert!((cost - 10.0).abs() < 1e-6, "cost was {cost}");
}

/// A leg of 6" or less through the ruin does NOT risk the test: 4" prices 4 at both settings.
#[test]
fn a_short_leg_through_a_ruin_stays_open_ground_at_both_settings() {
    let grid = ruin_grid();
    for unstable in [false, true] {
        let cost = segment_cost([3.5, 1.5], [7.5, 1.5], &grid, &step_opts(unstable));
        assert!((cost - 4.0).abs() < 1e-6, "unstable={unstable} cost was {cost}");
    }
}

/// Point-wise pricing is untouched: one ruin point still costs 1.0 at both settings.
#[test]
fn point_wise_ruin_pricing_is_unchanged() {
    let grid = ruin_grid();
    for unstable in [false, true] {
        let cost = terrain_cost_at([4.5, 1.5], &grid, &step_opts(unstable));
        assert!((cost - 1.0).abs() < 1e-6, "unstable={unstable} cost was {cost}");
    }
}
