//! ONNX leaf hook (M1a-2): the `LeafValue` face of the tract loader. Builds one
//! token per leaf with the same call `brain::Hook` makes, runs them through
//! `Brain` in static batches, and answers the mean values only — member heads
//! stay reachable through `run_tokens` for the later seams.

use nml_core::plan::LeafValue;
use nml_core::rows::RowEncoder;
use nml_core::sim::Unsupported;
use nml_core::state::State;
use nml_core::terrain::Terrain;
use nml_core::tokens::{self, Tokens, DESIGN_FIELDS, F_G, F_O, F_T, N_OBJ, N_TERR, V1_UNITS};
use nml_core::unit::UnitStatic;
use std::cell::RefCell;
use super::onnx::{Batch, Brain};

pub struct OnnxHook<'a> {
    pub brain: &'a Brain,
    pub statics: &'a [UnitStatic],
    pub terrain: &'a Terrain,
    pub rows: RefCell<RowEncoder>,
    pub hero_attach: bool,
    pub opener_seat: bool,
}

impl OnnxHook<'_> {
    /// One `Brain::run` per `static_batch`-wide chunk; the last chunk is
    /// zero-padded to the full width and its padding rows are discarded. The
    /// width comes from the brain, never a hardcoded number.
    pub fn run_tokens(&self, tokens: &[Tokens]) -> Result<(Vec<f32>, Vec<f32>), Unsupported> {
        let wide = self.brain.static_batch();
        let members = self.brain.members();
        // The unit window comes from the model's token_schema (`Brain::rows/width`):
        // the v1 stand-in is 24 × 90 (each 91-wide core row is fed as its first 88
        // design fields; t[88]/t[89] stay the trained-zero pads, t[90] drops), the
        // vocab-3 export is the core's own 32 × 91 window and takes the row whole.
        // A token set with more live units than the model has rows is REFUSED —
        // the caller falls back to the hand planner. Never truncate a board.
        let (rows, width) = (self.brain.rows(), self.brain.width());
        let mut values = Vec::with_capacity(tokens.len());
        let mut member_values = Vec::with_capacity(tokens.len() * members);
        for chunk in tokens.chunks(wide) {
            for t in chunk {
                let live = t.units_mask.iter().map(|&m| usize::from(m)).sum::<usize>();
                if live > rows {
                    return Err(Unsupported::TooManyUnits(live));
                }
            }
            let mut batch = Batch {
                units: vec![0.0; wide * rows * width], units_mask: vec![0.0; wide * rows],
                objs: vec![0.0; wide * N_OBJ * F_O], objs_mask: vec![0.0; wide * N_OBJ],
                terr: vec![0.0; wide * N_TERR * F_T], glob: vec![0.0; wide * F_G],
            };
            for (i, t) in chunk.iter().enumerate() {
                for (j, row) in t.units.iter().take(rows).enumerate() {
                    let d = i * rows * width + j * width;
                    let take = if width == V1_UNITS { DESIGN_FIELDS } else { width };
                    batch.units[d..d + take].copy_from_slice(&row[..take]);
                }
                let units_mask = i * rows..(i + 1) * rows;
                for (dst, &src) in batch.units_mask[units_mask].iter_mut().zip(t.units_mask.iter().take(rows)) {
                    *dst = f32::from(src);
                }
                let objs = i * N_OBJ * F_O..(i + 1) * N_OBJ * F_O;
                batch.objs[objs].copy_from_slice(t.objs.as_flattened());
                let objs_mask = i * N_OBJ..(i + 1) * N_OBJ;
                for (dst, &src) in batch.objs_mask[objs_mask].iter_mut().zip(&t.objs_mask) {
                    *dst = f32::from(src);
                }
                let terr = i * N_TERR * F_T..(i + 1) * N_TERR * F_T;
                batch.terr[terr].copy_from_slice(t.terr.as_flattened());
                batch.glob[i * F_G..(i + 1) * F_G].copy_from_slice(&t.glob);
            }
            let (chunk_values, chunk_members) = self.brain.run(&batch)?;
            let rows = chunk.len();
            values.extend_from_slice(&chunk_values[..rows]);
            member_values.extend_from_slice(&chunk_members[..rows * members]);
        }
        Ok((values, member_values))
    }
}

impl LeafValue for OnnxHook<'_> {
    fn value(&self, leaves: &[&State], side: i64) -> Result<Vec<f64>, Unsupported> {
        let mut rows = self.rows.borrow_mut();
        let tokens = leaves.iter().map(|state| {
            tokens::build(state, side, self.statics, self.terrain, &mut rows,
                &[], -1, self.hero_attach, self.opener_seat,
                nml_core::acts::CURRENT_RULES_EPOCH)
        }).collect::<Result<Vec<_>, _>>()?;
        Ok(self.run_tokens(&tokens)?.0.into_iter().map(f64::from).collect())
    }
}
