//! D8a (NML-1073 M5) — the rulebook-LEGAL objective layout, seeded, identical on
//! table and twin. A draw-for-draw mirror of `scripts/solo/objective_layout.gd`;
//! that file carries the long-form rationale and the book quotation.
//!
//! THE RULE (GF Advanced Rules v3.5.1, "PLACING OBJECTIVES", restated identically
//! in the Advanced Missions "MISSION OBJECTIVES" block): D3+2 markers; the players
//! roll-off and the winner picks who places the first; then they alternate placing
//! one marker each OUTSIDE the deployment zones and over 9" from other markers,
//! never in an unreachable position.
//!
//! WHAT THIS IS NOT: the book BOUNDS the placement, it never says WHERE the players
//! place. This is therefore a layout LEGAL BY THE RULES, not one PLACED BY THE
//! PLAYERS — candidates are drawn from a dedicated seeded stream and illegal ones
//! rejected. `first_placer`/`placed_by` are still rolled and carried so a real
//! placement doctrine can replace `draw` alone, leaving the stream and stamp intact.
//!
//! THE STREAM: one `GodotRng` seeded with the LAYOUT seed, drawn in the pinned order
//! `count -> roll-off -> placements`. NOT the table's global RNG (the terrain
//! layouter consumes it a data-dependent number of times, which is why D2 banked the
//! boards instead of porting it) and NOT `SoloController._rng` (extra draws there
//! would shift every recorded roll-off).
//!
//! ALL LEGALITY MATHS IS INTEGER — a 1" lattice against integer zone polygons — so
//! no float tie can make the two sides disagree.

use std::collections::HashMap;

use serde_json::Value;

use crate::rng::GodotRng;
use crate::terrain::{Terrain, CELL_IN, CONTAINER};

/// Book: "over 9 inches away from other markers".
pub const MARKER_GAP_IN: i64 = 9;
/// OURS, NOT THE BOOK'S — the book names an edge distance only for King of the Hill
/// / Mosh Pit, none for the generic alternate placement. Stamped so a reader sees it
/// was a choice. `objective_layout.gd:EDGE_MARGIN_IN`.
pub const EDGE_MARGIN_IN: i64 = 3;
/// Random attempts per marker before the deterministic sweep takes over.
pub const DRAW_CAP: usize = 1000;
/// `SoloController.roll_off`'s own tie cap.
pub const ROLL_OFF_CAP: usize = 100;

/// The stamp the recorder writes and this module re-derives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout {
    pub count_roll: i64,
    pub first_placer: i64,
    pub layout_seed: i64,
    pub edge_margin_in: i64,
    pub positions: Vec<(i64, i64)>,
    pub placed_by: Vec<i64>,
    pub swept: i64,
}

/// One polygon of a deployment zone, integer table-centred inches.
pub type Poly = Vec<[i64; 2]>;

/// The board as the legality test needs it: painted cells in the RECORDED 0-based
/// grid index, plus the grid dimension. `from_terrain` is the normal way in.
pub struct Cells {
    map: HashMap<(i64, i64), i32>,
    n: i64,
}

impl Cells {
    pub fn from_terrain(t: &Terrain) -> Cells {
        Cells { map: t.painted_cells().collect(), n: t.n() }
    }

    pub fn from_pairs(pairs: &[((i64, i64), i32)], n: i64) -> Cells {
        Cells { map: pairs.iter().copied().collect(), n }
    }

    /// `SchoolTerrain.cell_of` school_terrain.gd:52-53 — `int(floor(...))`.
    #[inline]
    fn type_at_in(&self, x_in: i64, z_in: i64) -> i32 {
        let cx = (x_in as f64 / CELL_IN + self.n as f64 / 2.0).floor() as i64;
        let cz = (z_in as f64 / CELL_IN + self.n as f64 / 2.0).floor() as i64;
        *self.map.get(&(cx, cz)).unwrap_or(&0)
    }
}

/// `ObjectiveLayout.generate`. `count` is the mission's raw catalog value, taken as
/// the JSON `Value` so the GDScript type test (`spec is float or spec is int` FIRST,
/// only then the "d3+N" string) is mirrored exactly — a number never draws.
pub fn generate(
    layout_seed: i64,
    count: &Value,
    zones: &[Poly],
    cells: &Cells,
    table_w_in: f64,
    table_d_in: f64,
) -> Layout {
    let mut rng = GodotRng::new(layout_seed);
    // Draw order, pinned: count, then the roll-off, then the placements.
    let count_roll = count_of(count, &mut rng);
    let first_placer = roll_off(&mut rng);
    let hx = (table_w_in / 2.0) as i64 - EDGE_MARGIN_IN;
    let hz = (table_d_in / 2.0) as i64 - EDGE_MARGIN_IN;
    let mut positions: Vec<(i64, i64)> = Vec::new();
    let mut swept = 0i64;
    for _ in 0..count_roll {
        match draw(&mut rng, hx, hz, &positions, zones, cells) {
            Some(p) => positions.push(p),
            None => match sweep(hx, hz, &positions, zones, cells) {
                Some(p) => {
                    swept += 1;
                    positions.push(p);
                }
                // No legal cell left at all: fewer markers, stamped honestly.
                None => break,
            },
        }
    }
    let placed_by = (0..positions.len() as i64)
        .map(|i| if i % 2 == 0 { first_placer } else { 3 - first_placer })
        .collect();
    Layout {
        count_roll,
        first_placer,
        layout_seed,
        edge_margin_in: EDGE_MARGIN_IN,
        positions,
        placed_by,
        swept,
    }
}

/// `ObjectiveLayout._count` — D3+2, or the mission's fixed int (which draws nothing).
pub fn count_of(spec: &Value, rng: &mut GodotRng) -> i64 {
    if spec.is_number() {
        let v = spec.as_i64().unwrap_or_else(|| spec.as_f64().map(|f| f as i64).unwrap_or(0));
        return v.max(1);
    }
    let s = spec.as_str().unwrap_or("d3+2").trim().to_lowercase();
    if let Some(rest) = s.strip_prefix("d3+") {
        if let Ok(add) = rest.parse::<i64>() {
            return rng.randi_range(1, 3) + add;
        }
    }
    rng.randi_range(1, 3) + 2
}

/// `ObjectiveLayout._roll_off` — with no doctrine to model the winner's CHOICE of who
/// places first, the winner places first.
pub fn roll_off(rng: &mut GodotRng) -> i64 {
    for _ in 0..ROLL_OFF_CAP {
        let d1 = rng.randi_range(1, 6);
        let d2 = rng.randi_range(1, 6);
        if d1 != d2 {
            return if d1 > d2 { 1 } else { 2 };
        }
    }
    1
}

fn draw(
    rng: &mut GodotRng,
    hx: i64,
    hz: i64,
    pos: &[(i64, i64)],
    zones: &[Poly],
    cells: &Cells,
) -> Option<(i64, i64)> {
    for _ in 0..DRAW_CAP {
        let x = rng.randi_range(-hx, hx);
        let z = rng.randi_range(-hz, hz);
        if is_legal(x, z, pos, zones, cells) {
            return Some((x, z));
        }
    }
    None
}

/// `ObjectiveLayout._sweep` — the deterministic fall-back, x ascending outermost.
/// Public: the doctrine modes keep this last resort (design 1) instead of a copy.
pub fn sweep(
    hx: i64,
    hz: i64,
    pos: &[(i64, i64)],
    zones: &[Poly],
    cells: &Cells,
) -> Option<(i64, i64)> {
    for x in -hx..=hx {
        for z in -hz..=hz {
            if is_legal(x, z, pos, zones, cells) {
                return Some((x, z));
            }
        }
    }
    None
}

/// The book's three constraints, exact in integers. Public: the gate's legality
/// self-test calls it, so one definition answers for both the rule and the check.
pub fn is_legal(x: i64, z: i64, pos: &[(i64, i64)], zones: &[Poly], cells: &Cells) -> bool {
    for &(qx, qz) in pos {
        let (dx, dz) = (x - qx, z - qz);
        // "over 9 inches" — exactly 9.0 is NOT over.
        if dx * dx + dz * dz <= MARKER_GAP_IN * MARKER_GAP_IN {
            return false;
        }
    }
    for poly in zones {
        if in_poly(x, z, poly) {
            return false;
        }
    }
    cells.type_at_in(x, z) != CONTAINER
}

/// `ObjectiveLayout._in_poly` — even-odd crossing in pure integers; a point ON the
/// boundary counts as INSIDE, so "outside the deployment zones" is strict.
pub fn in_poly(px: i64, pz: i64, poly: &Poly) -> bool {
    let m = poly.len();
    let mut inside = false;
    for i in 0..m {
        let a = poly[i];
        let b = poly[(i + m - 1) % m];
        let (ax, az, bx, bz) = (a[0], a[1], b[0], b[1]);
        if (bx - ax) * (pz - az) - (bz - az) * (px - ax) == 0
            && ax.min(bx) <= px
            && px <= ax.max(bx)
            && az.min(bz) <= pz
            && pz <= az.max(bz)
        {
            return true;
        }
        if (az > pz) != (bz > pz) {
            let d = bz - az;
            let lhs = (px - ax) * d;
            let rhs = (pz - az) * (bx - ax);
            if (d > 0 && lhs < rhs) || (d < 0 && lhs > rhs) {
                inside = !inside;
            }
        }
    }
    inside
}

/// The two players' zone polygons out of a `DeploymentCatalog` style, flattened —
/// the legality test does not care which side a polygon belongs to.
pub fn zones_of_style(style: &Value) -> Vec<Poly> {
    let mut out: Vec<Poly> = Vec::new();
    for pk in ["1", "2"] {
        let Some(polys) = style.get("zones").and_then(|z| z.get(pk)).and_then(|v| v.as_array())
        else {
            continue;
        };
        for poly in polys {
            let Some(pts) = poly.as_array() else { continue };
            out.push(
                pts.iter()
                    .filter_map(|p| p.as_array())
                    .filter(|p| p.len() >= 2)
                    .map(|p| {
                        [
                            p[0].as_f64().unwrap_or(0.0) as i64,
                            p[1].as_f64().unwrap_or(0.0) as i64,
                        ]
                    })
                    .collect(),
            );
        }
    }
    out
}
