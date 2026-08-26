//! NML-1073 M4-3 — `MovementPlanner.string_pull` (movement_planner.gd:1464),
//! `_walk_offset` (:1497) and `_furthest_clear` (:1537), a LITERAL transcription.
//!
//! THE FUNNEL. `string_pull` is greedy, not optimal, and its `farthest`
//! DEFAULTS to `anchor + 1` — that leg is never visibility-checked, so a taut
//! path may still carry a leg `_cspace_blocked` would reject. That is why
//! `_walk_offset` has a blocked branch at all even when it walks a path the
//! pull just produced with the SAME options.
//!
//! THE WALK'S ANCHOR is `out.back()`, the last point actually APPENDED — not
//! `taut[i-1]`. With a zero offset and an in-board route the two coincide, but
//! once a leg is clipped the loop breaks anyway, so the distinction only shows
//! up if that ever changes. Ported as written.
//!
//! A KNOWN QUIRK, PORTED AS IS: `spent` is not incremented on the leg that ends
//! the walk (the clipped/fractional branch and the `_furthest_clear` branch both
//! append and then `break`), so the variable understates the arc actually
//! consumed. Nothing reads it after the break, so the returned polyline is
//! unaffected — do not "fix" it. The trace's `walk_spent` is recomputed from the
//! returned polyline's arc length, which is what a gate may compare against.
//!
//! PRECISION. `spent`, `allowance`, every leg length and both fractions are
//! GDScript `float` = f64; the points and `lerp`'s weight are f32.

use super::cost::{cspace_blocked, legs_cost, segment_cost, Grid, StepOpts, Wall};
use super::geom2::{add, distance_to, lerp, to_f32, V2};
use super::{COHERENCY_BISECT_STEPS, EPS};

/// `MovementPlanner._board_clamp` — movement_planner.gd:1554. `clampf` is f64
/// over widened f32 components; the narrowing back is exact because the result
/// is always one of the three inputs.
#[inline]
pub fn board_clamp(p: V2, board: V2) -> V2 {
    to_f32([
        (p[0] as f64).clamp(0.0, board[0] as f64),
        (p[1] as f64).clamp(0.0, board[1] as f64),
    ])
}

/// DELIBERATE DAMAGE, for the red proofs — every field at its shipped value is
/// the shipped walk, byte for byte.
#[derive(Clone, Copy, Debug)]
pub struct WalkBend {
    /// `COHERENCY_BISECT_STEPS` — movement_planner.gd:347. Shipped: 14.
    pub bisect_steps: i64,
    /// RED: move EPS to the other side of the allowance comparisons —
    /// `spent + leg + EPS <= allowance` instead of `spent + leg <= allowance + EPS`
    /// (movement_planner.gd:1513 and :1522). Same epsilon, opposite sign: the
    /// shipped order lets a leg that overshoots by a hair through WHOLE, the
    /// swapped one clips it.
    pub eps_swapped: bool,
}

impl Default for WalkBend {
    fn default() -> Self {
        WalkBend { bisect_steps: COHERENCY_BISECT_STEPS, eps_swapped: false }
    }
}

/// DELIBERATE DAMAGE, for the red proof.
#[derive(Clone, Copy, Debug, Default)]
pub struct PullBend {
    /// RED: `break` on a too-dear shortcut instead of `continue`
    /// (movement_planner.gd:1476-1479). The asymmetry is the whole point of the
    /// scan: a candidate that is merely EXPENSIVE must not stop the search for a
    /// cheaper farther one, only an invisible candidate may.
    pub cost_break: bool,
}

/// `MovementPlanner.string_pull` — movement_planner.gd:1464. From each anchor,
/// advance to the FARTHEST later point still visible in a straight
/// configuration-space line AND no dearer than the legs it replaces. Note the
/// asymmetry: a visibility failure `break`s the scan, a cost failure only
/// `continue`s it.
pub fn string_pull(path: &[V2], walls: &[Wall], grid: &Grid, opts: &StepOpts) -> Vec<V2> {
    string_pull_bent(path, walls, grid, opts, PullBend::default())
}

/// `string_pull` with the red-proof knob.
pub fn string_pull_bent(
    path: &[V2],
    walls: &[Wall],
    grid: &Grid,
    opts: &StepOpts,
    bend: PullBend,
) -> Vec<V2> {
    if path.len() <= 2 {
        return path.to_vec();
    }
    let mut out: Vec<V2> = vec![path[0]];
    let mut anchor = 0usize;
    while anchor < path.len() - 1 {
        let mut farthest = anchor + 1;
        for j in (anchor + 2)..path.len() {
            if cspace_blocked(path[anchor], path[j], walls, grid, opts) {
                break;
            }
            if segment_cost(path[anchor], path[j], grid, opts)
                > legs_cost(path, anchor, j, grid, opts) + EPS
            {
                if bend.cost_break {
                    break;
                }
                continue;
            }
            farthest = j;
        }
        out.push(path[farthest]);
        anchor = farthest;
    }
    out
}

/// `MovementPlanner._walk_offset` — movement_planner.gd:1497.
pub fn walk_offset(
    start_pt: V2,
    taut: &[V2],
    offset: V2,
    allowance: f64,
    walls: &[Wall],
    grid: &Grid,
    opts: &StepOpts,
    board: V2,
) -> Vec<V2> {
    walk_offset_bent(start_pt, taut, offset, allowance, walls, grid, opts, board, WalkBend::default())
}

/// `_walk_offset` with the red-proof knobs.
#[allow(clippy::too_many_arguments)]
pub fn walk_offset_bent(
    start_pt: V2,
    taut: &[V2],
    offset: V2,
    allowance: f64,
    walls: &[Wall],
    grid: &Grid,
    opts: &StepOpts,
    board: V2,
    bend: WalkBend,
) -> Vec<V2> {
    if taut.len() <= 1 {
        return vec![start_pt];
    }
    let mut out: Vec<V2> = vec![start_pt];
    let mut spent = 0.0f64;
    // The shipped comparison is `spent + d <= allowance + EPS` (:1513, :1522).
    let fits = |spent: f64, d: f64| -> bool {
        if bend.eps_swapped {
            spent + d + EPS <= allowance
        } else {
            spent + d <= allowance + EPS
        }
    };
    for i in 1..taut.len() {
        let a = *out.last().unwrap();
        let b = board_clamp(add(taut[i], offset), board);
        let leg = distance_to(a, b);
        if leg < EPS {
            continue;
        }
        if cspace_blocked(a, b, walls, grid, opts) {
            // :1509-1518 — the offset shifted this leg into an obstacle the
            // anchor cleared (or the pull left an unchecked `anchor+1` leg):
            // advance to the furthest clear point and stop.
            let stop = furthest_clear_steps(a, b, walls, grid, opts, bend.bisect_steps);
            let slen = distance_to(a, stop);
            if slen > EPS {
                if fits(spent, slen) {
                    out.push(stop);
                } else {
                    let f = (allowance - spent) / slen;
                    if f > EPS {
                        out.push(lerp(a, stop, f));
                    }
                }
            }
            break;
        }
        if fits(spent, leg) {
            out.push(b);
            spent += leg;
        } else {
            let frac = (allowance - spent) / leg;
            if frac > EPS {
                out.push(lerp(a, b, frac));
            }
            break;
        }
    }
    out
}

/// `MovementPlanner._furthest_clear` — movement_planner.gd:1537. `a` is assumed
/// clear; the bisection converges on `lo`, the last parameter proven clear, so
/// the returned point sits just INSIDE the free side of the boundary.
pub fn furthest_clear(a: V2, b: V2, walls: &[Wall], grid: &Grid, opts: &StepOpts) -> V2 {
    furthest_clear_steps(a, b, walls, grid, opts, COHERENCY_BISECT_STEPS)
}

/// `_furthest_clear` with the bisection count as a parameter — the shipped call
/// passes `COHERENCY_BISECT_STEPS` = 14. The parameter exists so the gate can
/// prove the count is load-bearing (RED PROOF).
pub fn furthest_clear_steps(
    a: V2,
    b: V2,
    walls: &[Wall],
    grid: &Grid,
    opts: &StepOpts,
    steps: i64,
) -> V2 {
    if !cspace_blocked(a, b, walls, grid, opts) {
        return b;
    }
    let mut lo = 0.0f64;
    let mut hi = 1.0f64;
    for _ in 0..steps {
        let mid = (lo + hi) * 0.5;
        if cspace_blocked(a, lerp(a, b, mid), walls, grid, opts) {
            hi = mid;
        } else {
            lo = mid;
        }
    }
    lerp(a, b, lo)
}
