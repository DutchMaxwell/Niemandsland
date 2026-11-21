//! Free solids (organic plan C1): an intact house of a town board as ONE box in board-centred inches instead of its
//! painted cells. `to_plain` emits each box twice - a `sandbox` piece (movement, `type_at`) and a `containers` box
//! (sight) - with the same centre, half extents and yaw; the table draws and collides exactly these boxes.
use serde::{Deserialize, Serialize};
use super::levels::LotKind;
use super::Layout;

/// One free solid: centre and half extents in inches about the board centre, `yaw` in radians as `terrain::Obb`
/// (local +X -> (cos, -sin)), `lot` the lot it stands on.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FreeSolid { pub c_in: [f64; 2], pub he_in: [f64; 2], pub yaw: f64, pub lot: u16 }

/// The intact houses of `l` as free boxes (empty unless the theme has `free_solids`). A house whose cells are not one
/// rectangle (never seen; kept as a guard) gives one box per cell.
pub fn free_solids(l: &Layout) -> Vec<FreeSolid> {
    if !l.theme.budgets().free_solids { return Vec::new(); }
    let cell = f64::from(l.cell_in);
    let (ox, oz) = (f64::from(l.board_in[0]) * 0.5, f64::from(l.board_in[1]) * 0.5);
    let rect = |x0: usize, z0: usize, w: usize, h: usize, lot: u16| FreeSolid {
        c_in: [(x0 as f64 + w as f64 * 0.5) * cell - ox, (z0 as f64 + h as f64 * 0.5) * cell - oz],
        he_in: [w as f64 * cell * 0.5, h as f64 * cell * 0.5], yaw: 0.0, lot,
    };
    let mut lots: Vec<u16> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).map(|c| c.lot_id).collect();
    lots.sort_unstable();
    lots.dedup();
    let mut out = Vec::new();
    for id in lots {
        let cs: Vec<_> = l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed && c.lot_id == id).collect();
        let (x0, z0) = (cs.iter().map(|c| c.x).min().unwrap_or(0), cs.iter().map(|c| c.z).min().unwrap_or(0));
        let (x1, z1) = (cs.iter().map(|c| c.x).max().unwrap_or(0), cs.iter().map(|c| c.z).max().unwrap_or(0));
        if cs.len() == (x1 - x0 + 1) * (z1 - z0 + 1) {
            out.push(rect(x0, z0, x1 - x0 + 1, z1 - z0 + 1, id));
        } else {
            out.extend(cs.iter().map(|c| rect(c.x, c.z, 1, 1, id)));
        }
    }
    out
}
