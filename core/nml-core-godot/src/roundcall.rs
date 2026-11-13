//! One-core P3 step 46 (N3 b): `NmlCore.round_end` / `round_begin`, marshalling only - `nml_core::round` rules. The table's
//! words go in as a plain dictionary, the answer comes out as one. Neither call hands Seams to the core.
use crate::{actcall, plain};
use godot::prelude::*;
use nml_core::logline::LogLine;
use nml_core::mission::vp_of;
use nml_core::round::RoundWords;
use nml_core::state::State;

/// `{"labels": {player id: label}, "cite": String, "placed_by": {unit key: rule}}`; an absent key reads empty.
pub fn words_of(d: &VarDictionary) -> RoundWords {
    let pairs = |k: &str| plain::sub_dict(d, k).iter_shared().collect::<Vec<_>>();
    RoundWords {
        labels: pairs("labels").iter().map(|(k, v)| (plain::int(k), plain::text(v))).collect(),
        cite: d.get("cite").map(|v| plain::text(&v)).unwrap_or_default(),
        placed_by: pairs("placed_by").iter().map(|(k, v)| (plain::text(k), plain::text(v))).collect(),
    }
}

/// The round end's answer: every objective's owner, the VP ledger (`[0, 0]` without one) and its memo, the lines.
pub fn end_of(state: &State, lines: &[LogLine]) -> VarDictionary {
    let mut out = VarDictionary::new();
    let owners: VarArray = state.objectives.iter().map(|o| o.owner.to_variant()).collect();
    let vp = vp_of(state.vp.as_deref());
    out.set("owners", &owners);
    out.set("vp", &varray![vp[0], vp[1]]);
    out.set("vp_memo", &state.vp_memo.as_deref().map_or_else(|| VarDictionary::new().to_variant(), plain::variant_of));
    out.set("lines", &actcall::lines_of(lines));
    out
}

/// The round begin's answer: the opener and the "Round %d begins" line.
pub fn begin_of(opener: i64, lines: &[LogLine]) -> VarDictionary {
    let mut out = VarDictionary::new();
    out.set("opener", opener);
    out.set("lines", &actcall::lines_of(lines));
    out
}

/// A call the core did not take: the reason, no handle.
pub fn refused(reason: &str) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("refused", reason);
    d
}
